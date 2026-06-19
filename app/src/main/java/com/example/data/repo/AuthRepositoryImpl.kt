package com.example.data.repo

import android.util.Base64
import android.util.Log
import com.example.BuildConfig
import com.example.data.remote.TokenStore
import com.example.data.remote.XAuthApi
import com.example.domain.model.AuthChallenge
import com.example.domain.model.AuthState
import com.example.domain.repo.AuthRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

class AuthRepositoryImpl(
    private val api: XAuthApi,
    private val tokenStore: TokenStore
) : AuthRepository {

    private val _authState = MutableStateFlow<AuthState>(AuthState.SignedOut)
    // IO, not Main: the boot block below reads the encrypted token DataStore (disk I/O +
    // Keystore decrypt). On Main that read can stall the UI thread during app launch.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val TAG = "AuthRepo"
    }

    init {
        // Automatically check token status during boot and map authState
        scope.launch {
            try {
                val hasToken = tokenStore.hasTokens()
                val userId = tokenStore.userIdFlow.firstOrNull()
                if (hasToken && userId != null) {
                    _authState.value = AuthState.SignedIn(
                        userId = userId,
                        username = tokenStore.usernameFlow.firstOrNull(),
                        name = tokenStore.nameFlow.firstOrNull()
                    )
                } else {
                    _authState.value = AuthState.SignedOut
                }
            } catch (e: Exception) {
                Log.e(TAG, "Boot token retrieval failed", e)
                _authState.value = AuthState.SignedOut
            }
        }
    }

    override fun authState(): Flow<AuthState> = _authState.asStateFlow()

    override suspend fun beginLogin(): AuthChallenge {
        val verifier = generateCodeVerifier()
        val challenge = generateCodeChallenge(verifier)
        val state = UUID.randomUUID().toString()

        val clientId = BuildConfig.CLIENT_ID.takeIf { it.isNotEmpty() } ?: BuildConfig.X_CLIENT_ID
        val redirectUri = BuildConfig.X_REDIRECT_URI
        val scope = "tweet.read users.read bookmark.read offline.access"

        val authUrl = "https://twitter.com/i/oauth2/authorize" +
                "?response_type=code" +
                "&client_id=$clientId" +
                "&redirect_uri=$redirectUri" +
                "&scope=${scope.replace(" ", "%20")}" +
                "&state=$state" +
                "&code_challenge=$challenge" +
                "&code_challenge_method=S256"

        return AuthChallenge(
            authorizationUrl = authUrl,
            codeVerifier = verifier,
            state = state
        )
    }

    override suspend fun completeLogin(code: String, codeVerifier: String): Result<Unit> {
        return try {
            _authState.value = AuthState.SigningIn
            val clientId = BuildConfig.CLIENT_ID.takeIf { it.isNotEmpty() } ?: BuildConfig.X_CLIENT_ID
            val redirectUri = BuildConfig.X_REDIRECT_URI

            // Exchange token
            val response = api.exchangeToken(
                grantType = "authorization_code",
                clientId = clientId,
                redirectUri = redirectUri,
                code = code,
                codeVerifier = codeVerifier
            )

            // Query profile credentials to obtain numeric user id and X handle
            val userResponse = api.getUserMe("Bearer ${response.accessToken}")
            val userId = userResponse.data.id
            val username = userResponse.data.username
            val name = userResponse.data.name

            tokenStore.saveTokens(
                accessToken = response.accessToken,
                refreshToken = response.refreshToken,
                userId = userId,
                username = username,
                name = name
            )

            _authState.value = AuthState.SignedIn(userId = userId, username = username, name = name)
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Token exchange failed", e)
            _authState.value = AuthState.SignedOut
            Result.failure(e)
        }
    }

    override suspend fun currentUserId(): String? {
        return tokenStore.userIdFlow.map { it }.firstOrNull()
    }

    override suspend fun logout() {
        tokenStore.clear()
        _authState.value = AuthState.SignedOut
    }

    // --- HELPER CRYPTO GENERATORS ---

    private fun generateCodeVerifier(): String {
        val secureRandom = SecureRandom()
        val bytes = ByteArray(32)
        secureRandom.nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun generateCodeChallenge(verifier: String): String {
        val bytes = verifier.toByteArray(Charsets.US_ASCII)
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(bytes)
        return Base64.encodeToString(hash, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
