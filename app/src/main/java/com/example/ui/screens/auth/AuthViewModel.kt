package com.example.ui.screens.auth

import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.domain.model.AuthChallenge
import com.example.domain.model.AuthState
import com.example.domain.usecase.LoginUseCase
import com.example.domain.repo.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Handles active session states and PKCE code exchange redirects.
 */
class AuthViewModel(
    private val loginUseCase: LoginUseCase,
    private val authRepository: AuthRepository
) : ViewModel() {

    // TODO sec-5: Persist activeChallenge to SavedStateHandle to survive process death.
    // Requires injecting SavedStateHandle into this ViewModel. See AUDIT.md #6.
    // When adding SavedStateHandle support, also annotate AuthChallenge with
    // @kotlinx.parcelize.Parcelize and make it implement android.os.Parcelable.
    private var activeChallenge: AuthChallenge? = null

    init {
        // Backfill the profile photo for sessions that signed in before it was fetched at login.
        // Best-effort and self-limiting (no-op once cached) — see AuthRepository.refreshProfile.
        viewModelScope.launch { authRepository.refreshProfile() }
    }

    val authState: StateFlow<AuthState> = authRepository.authState()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = AuthState.SignedOut
        )

    private val _loginError = MutableStateFlow<String?>(null)
    val loginError: StateFlow<String?> = _loginError.asStateFlow()

    private val _loginSuccessMessage = MutableStateFlow<String?>(null)
    val loginSuccessMessage: StateFlow<String?> = _loginSuccessMessage.asStateFlow()

    fun clearLoginError() {
        _loginError.value = null
    }

    fun reportLoginSuccess() {
        _loginSuccessMessage.value = "Logged in successfully to X!"
    }

    fun clearLoginSuccess() {
        _loginSuccessMessage.value = null
    }

    fun reportLoginFailure(message: String) {
        _loginError.value = message
    }

    /**
     * Prepares PKCE parameters and triggers Custom Tabs navigation.
     */
    fun onLoginClick(onLaunchBrowser: (String) -> Unit) {
        viewModelScope.launch {
            _loginError.value = null
            try {
                val challenge = loginUseCase.beginLogin()
                activeChallenge = challenge
                onLaunchBrowser(challenge.authorizationUrl)
            } catch (e: Exception) {
                Log.e("AuthVM", "Failed to construct PKCE login redirect URL", e)
                _loginError.value = "Could not start sign-in. Check your connection and try again."
            }
        }
    }

    /**
     * Processes custom tabs redirect custom scheme callback URL.
     */
    fun handleRedirect(uri: Uri, onResult: (Result<Unit>) -> Unit) {
        val code = uri.getQueryParameter("code")
        val stateParam = uri.getQueryParameter("state")
        val challenge = activeChallenge

        if (code == null) {
            val error = uri.getQueryParameter("error") ?: "Authentication cancelled"
            onResult(Result.failure(Exception(error)))
            return
        }

        if (challenge == null || challenge.state != stateParam) {
            onResult(Result.failure(Exception("State parameters do not match of active security transaction")))
            return
        }

        viewModelScope.launch {
            val result = loginUseCase.completeLogin(code, challenge.codeVerifier)
            onResult(result)
        }
    }

    fun onLogout() {
        viewModelScope.launch {
            authRepository.logout()
        }
    }

    /**
     * Simple VM factory mapping dependency containers manually.
     */
    class Factory(
        private val loginUseCase: LoginUseCase,
        private val authRepository: AuthRepository
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return AuthViewModel(loginUseCase, authRepository) as T
        }
    }
}
