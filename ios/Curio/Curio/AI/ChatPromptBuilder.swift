import Foundation

/// Assembles the Curio Research Assistant chat request (context prompt, system instruction and xAI
/// Live Search parameters) from retrieved library items and the user's selected live sources.
///
/// Direct port of `object ChatPromptBuilder` in `data/ai/ChatPromptBuilder.kt`. Extracted out of the
/// view model so the presentation layer no longer builds prompts or constructs remote DTOs — the VM
/// just supplies data and forwards the result to the analyzer.
///
/// Caseless namespace enum (CONVENTIONS §1). All user-facing / wire strings are byte-identical to
/// the Kotlin original; `XAiSearchParameters` mode is `.on` and `maxSearchResults` is 12 to match.
enum ChatPromptBuilder {

    /// The assembled triple handed to ``XAiAnalyzer/generateChatResponse(contextPrompt:systemInstruction:searchParameters:)``.
    /// Port of the Kotlin `data class Parts`.
    struct Parts: Sendable, Equatable {
        let contextPrompt: String
        let systemInstruction: String
        let searchParameters: XAiSearchParameters?
    }

    /// - Parameters:
    ///   - userQuery: the raw user message.
    ///   - contextItems: semantically-retrieved library bookmarks (may be empty).
    ///   - useLibrary: whether the local library is being used as grounding context.
    ///   - liveSourceApiTypes: xAI source ids the user enabled (`"web"` / `"x"` / `"news"`); the
    ///     local library is handled via `useLibrary` and is never a live source.
    ///   - liveLabels: human labels of the live sources for the system instruction (e.g. `"Web/News"`).
    static func build(
        userQuery: String,
        contextItems: [Bookmark],
        useLibrary: Bool,
        liveSourceApiTypes: [String],
        liveLabels: String
    ) -> Parts {
        // --- contextPrompt: mirrors the Kotlin `buildString { ... }` (each appendLine adds "\n").
        var contextPrompt = ""
        if !contextItems.isEmpty {
            contextPrompt += "Research library context (semantically retrieved):\n"
            for b in contextItems {
                let sourceInfo: String
                if b.sourceType != nil {
                    // Kotlin: "[${b.sourceType?.name}:${b.sourceId}] " — sourceId may be nil, printed as "null".
                    sourceInfo = "[\(b.sourceType?.rawValue ?? "null"):\(stringify(b.sourceId))] "
                } else {
                    sourceInfo = ""
                }
                // Kotlin: b.sourceTitle ?: b.title ?: "Untitled"
                let titleLine = b.sourceTitle ?? b.title ?? "Untitled"
                contextPrompt += "- \(sourceInfo)\(titleLine)\n"
                if let authors = b.sourceAuthors, !authors.isBlankPrompt {
                    contextPrompt += "  Authors: \(authors)\n"
                }
                // Kotlin: "  Category: ${b.category ?: "?"} | Tags: ${b.tags.take(4).joinToString(",")}"
                let category = b.category ?? "?"
                let tags = b.tags.prefix(4).joined(separator: ",")
                contextPrompt += "  Category: \(category) | Tags: \(tags)\n"
                if let summary = b.summary, !summary.isBlankPrompt {
                    contextPrompt += "  Summary: \(summary)\n"
                }
                if let deep = b.deepSummary, !deep.isBlankPrompt {
                    // Kotlin: b.deepSummary?.take(200) — UTF-16 code-unit take; prefix on Character is
                    // acceptable here (CONVENTIONS §10 char-count note).
                    contextPrompt += "  Deep: \(String(deep.prefix(200)))\n"
                }
            }
        } else if useLibrary {
            contextPrompt += "Library is empty.\n"
        }
        // Kotlin: appendLine("\nUser query: \"$userQuery\"") → a blank line then the query line + "\n".
        contextPrompt += "\nUser query: \"\(userQuery)\"\n"

        // --- live sources: mapNotNull over the enabled api types.
        var liveSources: [XAiSearchSource] = []
        for apiType in liveSourceApiTypes {
            switch apiType {
            case "web": liveSources.append(XAiSearchSource.web())
            case "x": liveSources.append(XAiSearchSource.x())
            case "news": liveSources.append(XAiSearchSource.news())
            default: break
            }
        }
        let searchParameters: XAiSearchParameters? = liveSources.isEmpty ? nil : XAiSearchParameters(
            mode: GrokSearchMode.on,
            returnCitations: true,
            maxSearchResults: 12,
            sources: liveSources
        )

        // --- systemInstruction: buildString { appendLine(...) }.trimIndent().
        // The built lines carry no indentation, so trimIndent only strips the leading/trailing blank
        // lines — net effect is the lines joined by "\n" with NO trailing newline.
        var systemLines: [String] = []
        systemLines.append("You are Curio Research Assistant — a personal AI for an ML researcher's saved papers and repos.")
        if useLibrary {
            systemLines.append("Prefer the retrieved library context. Cite paper titles and arXiv IDs when relevant.")
        }
        if searchParameters != nil {
            systemLines.append("You also have live \(liveLabels) search — use it to ground claims and cite sources with markdown links.")
        }
        systemLines.append("Use markdown (headings, bold, bullets, links). Keep answers concise and formatted for mobile screens.")
        let systemInstruction = systemLines.joined(separator: "\n")

        return Parts(
            contextPrompt: contextPrompt,
            systemInstruction: systemInstruction,
            searchParameters: searchParameters
        )
    }

    /// Mirrors Kotlin string interpolation of a nullable: `${b.sourceId}` prints `"null"` when nil.
    private static func stringify(_ value: String?) -> String {
        value ?? "null"
    }
}

private extension String {
    /// Mirrors Kotlin `isNullOrBlank()` on a non-optional (whitespace-only ⇒ blank). Distinct name to
    /// avoid colliding with the `isBlank` extension defined in the Networking module.
    var isBlankPrompt: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
