package com.example.domain.usecase

import com.example.domain.model.AuthChallenge
import com.example.domain.repo.AuthRepository

/**
 * Orchestrates login actions and session handshakes for the presentation layer.
 */
class LoginUseCase(private val authRepository: AuthRepository) {

    /**
     * Prepares authentication challenge properties to kickstart Custom Tabs display.
     */
    suspend fun beginLogin(): AuthChallenge {
        return authRepository.beginLogin()
    }

    /**
     * Executes official endpoint code resolution handshake.
     */
    suspend fun completeLogin(code: String, codeVerifier: String): Result<Unit> {
        return authRepository.completeLogin(code, codeVerifier)
    }
}
