import Foundation

// Direct port of `ui/ErrorMessages.kt` — translates raw errors into clear, user-facing sentences
// that say *what went wrong* and *what to do about it*, instead of leaking cryptic strings like
// "HTTP 401" (which is what a bare `localizedDescription` of a transport error often amounts to).
//
// iOS error mapping (the Android `when` arms → the Swift error surface, CONVENTIONS §3):
//   - `RateLimitException`      → `RateLimitError` (Domain)
//   - `HttpException.code()`    → `APIError.http(status:…)` (Networking)
//   - `UnknownHostException`    → `URLError` host/connectivity codes
//   - `SocketTimeoutException`  → `URLError.timedOut`
//   - `IOException`             → any other `URLError` (transport-level failure)
//   - anything else             → `errorDescription` / `localizedDescription` fallback
// `APIError.transport` is unwrapped to its underlying `URLError` so both the wrapped and the bare
// form take the same arm. All user-facing sentences are carried verbatim from Android
// (CONVENTIONS §4 "Preserve exact user-facing strings").

/// Which remote service an error came from. Determines the remedy we suggest — the same HTTP code
/// means different things depending on who returned it (a 401 from X means "re-login"; a 401 from
/// the AI backend means "the API key is bad"). Port of `enum class ErrorContext`.
enum ErrorContext {
    case sync
    case ai
    case source
    case generic

    /// Human name of the service, used in the middle of a sentence.
    var service: String {
        switch self {
        case .sync: return "X"
        case .ai: return "the AI service"
        case .source: return "the source database"
        case .generic: return "the server"
        }
    }

    /// What the user should do when the service rejects our credentials (401/403).
    var authRemedy: String {
        switch self {
        case .sync: return "Sign out and sign back in to reconnect your X account."
        case .ai: return "Check that a valid xAI (Grok) API key is configured in Settings."
        case .source: return "This is usually temporary — try again shortly."
        case .generic: return "Try again, and re-authenticate if the problem continues."
        }
    }
}

/// Translates a raw `Error` into a clear, user-facing sentence. Pass the `context` so the remedy
/// matches the service that failed. Port of `humanReadableError(throwable, context)`.
func humanReadableError(_ error: Error, context: ErrorContext = .generic) -> String {
    // Unwrap `APIError.transport` so the underlying URLError takes the connectivity arms below.
    let unwrapped: Error
    if case APIError.transport(let urlError) = error {
        unwrapped = urlError
    } else {
        unwrapped = error
    }

    switch unwrapped {
    case is RateLimitError:
        return "Rate limit reached. \(context.service) limits how often Curio can make requests — "
            + "wait for the countdown to finish, then try again."

    case APIError.http(let code, _, _):
        switch code {
        case 400:
            return "Bad request (HTTP 400): \(context.service) rejected the request. This is likely a bug in Curio — please report it."
        case 401:
            return "Authentication failed (HTTP 401): \(context.service) no longer accepts the saved credentials. \(context.authRemedy)"
        case 403:
            return "Access denied (HTTP 403): \(context.service) refused this request. The required permission may not be granted, or your access tier doesn't allow it. \(context.authRemedy)"
        case 404:
            return "Not found (HTTP 404): the requested data doesn't exist on \(context.service). It may have been deleted or moved."
        case 429:
            return "Too many requests (HTTP 429): you've hit \(context.service)'s rate limit. Wait a few minutes before trying again."
        case 500...599:
            return "Server error (HTTP \(code)): \(context.service) is having trouble right now. This is on their end — try again in a little while."
        default:
            return "Unexpected response (HTTP \(code)) from \(context.service). Try again, and report it if it keeps happening."
        }

    case let urlError as URLError:
        switch urlError.code {
        // The `UnknownHostException` analogues: no route to the named host / offline.
        case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            return "No internet connection. Check your network and try again."
        case .timedOut:
            return "The connection to \(context.service) timed out. Your network may be slow, or the service is unresponsive — try again."
        default:
            // Any other transport-level failure (the Kotlin `IOException` arm).
            return "Network error: couldn't reach \(context.service). Check your connection and try again."
        }

    default:
        let message = (unwrapped as? LocalizedError)?.errorDescription
            ?? (unwrapped as NSError).localizedDescription
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Something went wrong with \(context.service). Please try again."
            : message
    }
}
