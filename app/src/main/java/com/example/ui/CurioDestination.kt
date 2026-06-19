package com.example.ui

/**
 * Type-safe top-level destinations. Using an enum (instead of raw route strings) gives the
 * navigation `when` blocks compile-time exhaustiveness and removes stringly-typed comparisons.
 * The [id] is only used at the reusable [com.example.ui.components.GlassBottomBar] boundary,
 * which stays route-string based so it remains app-agnostic.
 */
enum class CurioDestination(val id: String, val title: String) {
    Bookmarks("bookmarks", "My Bookmarks"),
    Spaces("spaces", "Spaces"),
    Insights("insights", "Curio Insights"),
    Chat("chatbot", "Curio AI Chat"),
    Settings("settings", "Settings Hub");

    companion object {
        fun fromId(id: String): CurioDestination = entries.firstOrNull { it.id == id } ?: Bookmarks
    }
}
