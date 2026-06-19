package com.example.domain.model

/**
 * A user-created collection that bookmarks can be filed into. [color] is a packed ARGB value and
 * [icon] is a stable key resolved to a Material icon at the UI boundary. [count] is the number of
 * bookmarks currently filed here; it is computed at read time (not persisted).
 *
 * [description] is an optional one-line note shown under the name. [isPinned] floats the Space to
 * the top of the list and [sortIndex] gives manual ordering within each pinned/unpinned group.
 * [rules] is the auto-filing configuration that turns a Space into a "Smart Space" (see
 * [SpaceRules]); an empty rule set means it's a plain manual collection.
 */
data class Space(
    val id: String,
    val userId: String,
    val name: String,
    val color: Long,
    val icon: String,
    val createdAt: Long,
    val count: Int = 0,
    val description: String = "",
    val isPinned: Boolean = false,
    val sortIndex: Int = 0,
    val rules: SpaceRules = SpaceRules.EMPTY
) {
    /** True when this Space auto-files bookmarks via [rules] — surfaced as a "Smart" badge. */
    val isSmart: Boolean get() = rules.isActive
}
