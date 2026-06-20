package com.example.domain.model

/**
 * Core authentication states for Curio.
 */
sealed interface AuthState {
    object SignedOut : AuthState
    object SigningIn : AuthState
    data class SignedIn(
        val userId: String,
        val username: String? = null,
        val name: String? = null
    ) : AuthState
}

/**
 * Representation of an OAuth PKCE Authorization details.
 */
data class AuthChallenge(
    val authorizationUrl: String,
    val codeVerifier: String,
    val state: String
)

// Note: typed error handling lives in the layers that surface it — [com.example.data.repo.RateLimitException]
// and the sealed UI states (SyncUiState/AnalysisUiState/DigestUiState). A separate unused AppError
// hierarchy was removed to avoid dead, drifting code.
