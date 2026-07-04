package com.example

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.ui.BookmarkApp
import com.example.ui.CurioNotifier
import com.example.ui.BookmarkViewModel
import com.example.ui.screens.auth.AuthViewModel
import org.koin.androidx.viewmodel.ext.android.viewModel

class MainActivity : ComponentActivity() {

    // ViewModels resolved by Koin (see CurioApplication.startKoin / appModule).
    private val authViewModel: AuthViewModel by viewModel()
    private val bookmarkViewModel: BookmarkViewModel by viewModel()

    // POST_NOTIFICATIONS runtime prompt (Android 13+). Result ignored — a denial simply means the
    // unified live activity / reminders stay silent; the app carries on unaffected.
    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* no-op */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // The periodic stale-link sweep is scheduled via WorkManager in CurioApplication
        // (BookmarkSweeperScheduler) — no foreground service is started here.

        maybeRequestNotificationPermission()

        enableEdgeToEdge()

        // Only on a fresh launch — not on a config-change recreate, which re-delivers the same
        // intent and would otherwise re-process the OAuth redirect or re-save a shared item.
        if (savedInstanceState == null) {
            handleSendIntent(intent)
            intent?.data?.let { handleDeepLink(it) }
        }

        setContent {
            BookmarkApp(
                authViewModel = authViewModel,
                bookmarkViewModel = bookmarkViewModel
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSendIntent(intent)
        intent.data?.let { handleDeepLink(it) }
    }

    override fun onResume() {
        super.onResume()
        // The user is now in the app, so any "digest ready" / error banner in the live activity has
        // served its purpose — clear it so a stale notification doesn't linger.
        (application as? CurioApplication)?.appContainer?.curioActivityController?.clearAttention()
        // Background embedding may have auto-filed cards; refresh medium-confidence suggestions.
        bookmarkViewModel.refreshSuggestionsOnForeground()
    }

    /** Requests POST_NOTIFICATIONS once on Android 13+ if not already granted. */
    private fun maybeRequestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    /**
     * Handles a tweet / URL / text shared into Curio from another app's share sheet
     * ([Intent.ACTION_SEND], `text/plain`). Combines the optional subject (e.g. an article title)
     * with the shared body and routes it through the bookmark capture path.
     */
    private fun handleSendIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("text/") != true) return

        val body = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val payload = listOf(subject, body)
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString("\n")
            .trim()

        if (payload.isEmpty()) {
            CurioNotifier.notify(this, "Nothing to save")
            return
        }

        val ingestedNow = bookmarkViewModel.captureSharedText(payload)
        val message = if (ingestedNow) "Saved to Curio" else "Sign in to Curio to finish saving"
        CurioNotifier.notify(this, message)
    }

    private fun handleDeepLink(uri: Uri) {
        if (uri.scheme == "curio-oauth" && uri.host == "callback") {
            authViewModel.handleRedirect(uri) { result ->
                result.fold(
                    onSuccess = {
                        authViewModel.reportLoginSuccess()
                    },
                    onFailure = { error ->
                        authViewModel.reportLoginFailure(
                            "Login connection failed: ${error.localizedMessage ?: "Unknown error"}"
                        )
                    }
                )
            }
        }
    }

    /**
     * Helper action to trigger the native device browser or deep links for OAuth PKCE authorization
     */
    fun launchOAuthBrowser(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            CurioNotifier.notify(this, "Could not open browser. Please check details.")
        }
    }
}
