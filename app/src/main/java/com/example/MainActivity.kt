package com.example

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.example.ui.BookmarkApp
import com.example.ui.BookmarkViewModel
import com.example.ui.screens.auth.AuthViewModel
import org.koin.androidx.viewmodel.ext.android.viewModel

class MainActivity : ComponentActivity() {

    // ViewModels resolved by Koin (see CurioApplication.startKoin / appModule).
    private val authViewModel: AuthViewModel by viewModel()
    private val bookmarkViewModel: BookmarkViewModel by viewModel()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Launch background diagnostic/sweeper service
        try {
            val serviceIntent = Intent(this, com.example.background.BookmarkSweeperService::class.java)
            startService(serviceIntent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to start BookmarkSweeperService: ${e.message}")
        }

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
            Toast.makeText(this, "Nothing to save", Toast.LENGTH_SHORT).show()
            return
        }

        val ingestedNow = bookmarkViewModel.captureSharedText(payload)
        val message = if (ingestedNow) "Saved to Curio" else "Sign in to Curio to finish saving"
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun handleDeepLink(uri: Uri) {
        if (uri.scheme == "curio-oauth" && uri.host == "callback") {
            authViewModel.handleRedirect(uri) { result ->
                result.fold(
                    onSuccess = {
                        Toast.makeText(this, "Logged in successfully to X!", Toast.LENGTH_SHORT).show()
                    },
                    onFailure = { error ->
                        Toast.makeText(this, "Login connection failed: ${error.localizedMessage}", Toast.LENGTH_LONG).show()
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
            Toast.makeText(this, "Could not open browser. Please check details.", Toast.LENGTH_SHORT).show()
        }
    }
}
