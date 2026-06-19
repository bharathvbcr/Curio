package com.example.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * A user-created Space — a named collection that bookmarks can be filed into. Distinct from the
 * AI-assigned [BookmarkEntity.category]: spaces are an explicit, user-driven way to organise the
 * research index (e.g. "Diffusion Models", "To Read", "Thesis").
 *
 * [colorValue] is an ARGB color packed into a Long; [iconKey] maps to a Material icon at the UI
 * boundary (see `spaceIcon`). Membership lives on [BookmarkEntity.spaceId].
 *
 * [description] is an optional subtitle, [isPinned]/[sortIndex] drive list ordering, and
 * [rulesJson] is the serialized [com.example.domain.model.SpaceRules] auto-filing config (empty
 * string = plain manual collection).
 */
@Entity(
    tableName = "spaces",
    indices = [Index(value = ["userId"])]
)
data class SpaceEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val name: String,
    val colorValue: Long,
    val iconKey: String,
    val createdAt: Long,
    val description: String = "",
    val isPinned: Boolean = false,
    val sortIndex: Int = 0,
    val rulesJson: String = ""
)
