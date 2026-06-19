package com.example.domain.model

/**
 * Default Space appearance for an AI-assigned category. [color] is a packed ARGB Long and [icon] is
 * a stable key the UI resolves to a Material glyph (see `spaceIcon`).
 */
data class CategorySpaceMeta(val name: String, val color: Long, val icon: String)

/**
 * The bridge that lets AI categories *seed* Spaces: each category in the curator taxonomy
 * (see `XAiAnalyzer`) maps to a canonical default Space (name + colour + icon). When a bookmark is
 * analysed, the repository ensures the matching Space exists and files the bookmark into it, so the
 * user gets an auto-organised library of Spaces without the parallel "category" concept ever
 * surfacing in the UI. Custom/unknown categories fall back to a title-cased generic Space.
 */
object CategorySpaces {
    val DEFAULTS: Map<String, CategorySpaceMeta> = mapOf(
        "architectures" to CategorySpaceMeta("Architectures", 0xFF1E88E5, "hub"),
        "training" to CategorySpaceMeta("Training", 0xFFFF9800, "bolt"),
        "inference-opt" to CategorySpaceMeta("Inference & Opt", 0xFFFF5722, "rocket"),
        "datasets" to CategorySpaceMeta("Datasets", 0xFF43A047, "folder"),
        "evals" to CategorySpaceMeta("Evals", 0xFF3F51B5, "label"),
        "agents" to CategorySpaceMeta("Agents", 0xFF8E24AA, "workspaces"),
        "multimodal" to CategorySpaceMeta("Multimodal", 0xFF00BCD4, "star"),
        "theory" to CategorySpaceMeta("Theory", 0xFF673AB7, "science"),
        "systems" to CategorySpaceMeta("Systems", 0xFF607D8B, "code"),
        "other" to CategorySpaceMeta("Other", 0xFF9E9E9E, "label")
    )

    /** Canonical default Space for [category]; falls back to a title-cased generic for custom values. */
    fun forCategory(category: String): CategorySpaceMeta {
        val key = category.trim().lowercase()
        return DEFAULTS[key] ?: CategorySpaceMeta(
            name = key.split(' ', '-', '_').filter { it.isNotBlank() }
                .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                .ifBlank { "Uncategorized" },
            color = 0xFF607D8B,
            icon = "label"
        )
    }
}
