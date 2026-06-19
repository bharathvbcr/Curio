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

/**
 * Typed application error representation mapping directly to visual presentation systems.
 */
sealed interface AppError {
    data class Network(val message: String) : AppError
    data class RateLimited(val retryAfterSeconds: Int) : AppError
    data class Auth(val message: String) : AppError
    data class GenAiUnavailable(val reason: String) : AppError
    data class Unknown(val throwable: Throwable) : AppError
}
