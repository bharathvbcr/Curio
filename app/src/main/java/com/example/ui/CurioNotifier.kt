package com.example.ui

import android.content.Context
import android.widget.Toast

/**
 * App-wide transient feedback channel. [BookmarkApp] registers [showMessage] so copy/share/settings
 * actions can surface glass-style snackbars instead of system toasts when the shell is active.
 */
object CurioNotifier {
    var showMessage: ((String) -> Unit)? = null

    fun notify(context: Context, message: String) {
        val handler = showMessage
        if (handler != null) {
            handler(message)
        } else {
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
        }
    }
}
