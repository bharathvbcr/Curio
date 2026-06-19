package com.example.domain.repo

import com.example.domain.model.AuthState
import com.example.domain.model.AuthChallenge
import kotlinx.coroutines.flow.Flow

/**
 * Interface safeguarding X OAuth 2.0 PKCE authentication lifecycle and session credentials.
 */
interface AuthRepository {
    /**
     * Observable stream representing current authentication credentials and session status.
     */
    fun authState(): Flow<AuthState>

    /**
     * Initializes a PKCE challenge state, returning details required for launching the login sheet.
     */
    suspend fun beginLogin(): AuthChallenge

    /**
     * Exchanges auth code using original code verifier from previous flow.
     */
    suspend fun completeLogin(code: String, codeVerifier: String): Result<Unit>

    /**
     * Resolves currently active user's numeric ID (for retrieving bookmarks safely).
     */
    suspend fun currentUserId(): String?

    /**
     * Purges auth credentials silently, notifying all sessions.
     */
    suspend fun logout()
}
