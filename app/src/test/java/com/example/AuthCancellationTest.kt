package com.example

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.data.remote.TokenResponse
import com.example.data.remote.TokenStore
import com.example.data.remote.UserData
import com.example.data.remote.UserResponse
import com.example.data.remote.XAuthApi
import com.example.data.repo.AuthRepositoryImpl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A cancelled login attempt (user backs out mid token-exchange) must propagate cancellation —
 * the old catch-all converted CancellationException into Result.failure + SignedOut,
 * breaking structured concurrency and clobbering any prior signed-in state.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class AuthCancellationTest {

    /** Auth API whose token exchange surfaces cancellation, as an aborted Retrofit call does. */
    private val cancellingApi = object : XAuthApi {
        override suspend fun exchangeToken(
            grantType: String, clientId: String, redirectUri: String, code: String, codeVerifier: String
        ): TokenResponse = throw CancellationException("login cancelled")

        override suspend fun refreshToken(grantType: String, clientId: String, refreshToken: String): TokenResponse =
            TokenResponse("x", null, null, null)

        override suspend fun getUserMe(authorization: String, userFields: String): UserResponse =
            UserResponse(UserData("1", "n", "h"))
    }

    @Test
    fun `completeLogin rethrows cancellation`() = runTest {
        val repo = AuthRepositoryImpl(
            cancellingApi,
            TokenStore(ApplicationProvider.getApplicationContext<Context>())
        )
        var thrown: Throwable? = null
        try {
            repo.completeLogin(code = "c", codeVerifier = "v")
        } catch (e: Throwable) {
            thrown = e
        }
        assertTrue(
            "expected CancellationException to propagate, got $thrown",
            thrown is CancellationException
        )
    }
}
