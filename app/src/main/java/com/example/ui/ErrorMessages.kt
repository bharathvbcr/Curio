package com.example.ui

import com.example.data.repo.RateLimitException
import retrofit2.HttpException
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * Which remote service an error came from. Determines the remedy we suggest — the same HTTP code
 * means different things depending on who returned it (a 401 from X means "re-login"; a 401 from
 * the AI backend means "the API key is bad").
 */
enum class ErrorContext(
    /** Human name of the service, used in the middle of a sentence. */
    val service: String,
    /** What the user should do when the service rejects our credentials (401/403). */
    val authRemedy: String
) {
    SYNC("X", "Sign out and sign back in to reconnect your X account."),
    AI("the AI service", "Check that a valid xAI (Grok) API key is configured in Settings."),
    SOURCE("the source database", "This is usually temporary — try again shortly."),
    GENERIC("the server", "Try again, and re-authenticate if the problem continues.")
}

/**
 * Translates a raw [Throwable] into a clear, user-facing sentence that says *what went wrong* and
 * *what to do about it*, instead of leaking cryptic strings like "HTTP 401" — which is what
 * Retrofit's [HttpException.getLocalizedMessage] returns verbatim.
 *
 * Pass the [context] so the remedy matches the service that failed.
 */
fun humanReadableError(throwable: Throwable, context: ErrorContext = ErrorContext.GENERIC): String =
    when (throwable) {
        is RateLimitException ->
            "Rate limit reached. ${context.service} limits how often Curio can make requests — " +
                "wait for the countdown to finish, then try again."

        is HttpException -> when (val code = throwable.code()) {
            400 -> "Bad request (HTTP 400): ${context.service} rejected the request. This is likely a bug in Curio — please report it."
            401 -> "Authentication failed (HTTP 401): ${context.service} no longer accepts the saved credentials. ${context.authRemedy}"
            403 -> "Access denied (HTTP 403): ${context.service} refused this request. The required permission may not be granted, or your access tier doesn't allow it. ${context.authRemedy}"
            404 -> "Not found (HTTP 404): the requested data doesn't exist on ${context.service}. It may have been deleted or moved."
            429 -> "Too many requests (HTTP 429): you've hit ${context.service}'s rate limit. Wait a few minutes before trying again."
            in 500..599 -> "Server error (HTTP $code): ${context.service} is having trouble right now. This is on their end — try again in a little while."
            else -> "Unexpected response (HTTP $code) from ${context.service}. Try again, and report it if it keeps happening."
        }

        is UnknownHostException ->
            "No internet connection. Check your network and try again."

        is SocketTimeoutException ->
            "The connection to ${context.service} timed out. Your network may be slow, or the service is unresponsive — try again."

        is IOException ->
            "Network error: couldn't reach ${context.service}. Check your connection and try again."

        else ->
            throwable.localizedMessage?.takeIf { it.isNotBlank() }
                ?: "Something went wrong with ${context.service}. Please try again."
    }
