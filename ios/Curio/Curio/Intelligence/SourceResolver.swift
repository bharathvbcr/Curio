import Foundation
import os

/// Resolved primary-source metadata. Port of `data class SourceInfo`.
struct SourceInfo: Sendable, Equatable {
    let sourceType: SourceType
    let sourceId: String
    let sourceTitle: String
    let sourceAuthors: String?
    let sourceAbstract: String?
    let sourceExtra: String?
}

/// Resolves a bookmark's text + url to a primary research source (arXiv / GitHub / HuggingFace /
/// Crossref DOI). Ports `class SourceResolver` from `data/source/SourceResolver.kt`.
///
/// Fixed resolution priority (preserved exactly — CONVENTIONS Repository cross-cutting / DESIGN §6):
///   arXiv > HuggingFace papers page > GitHub > HuggingFace model/dataset > bare-arXiv-in-text >
///   DOI-in-url > DOI-in-text.
///
/// `withRetry` mirrors the Kotlin retry/backoff: a `429`/`503` honours `Retry-After` (else `2^attempt`
/// seconds); a `4xx` client error → `nil` (no retry); any other error backs off `delayMs * 2^attempt`
/// and gives up on the last attempt; `CancellationError` is rethrown. The underlying networking
/// clients are already resilient (log + return `nil`) so the retry shape is preserved for the rare
/// case a block surfaces an `APIError`.
struct SourceResolver: Sendable {

    private let arxivClient: ArxivClient
    private let githubApi: GithubApiClient
    private let huggingFaceApi: HuggingFaceApiClient
    private let crossrefClient: CrossrefClient
    private static let logger = Logger(subsystem: "com.curio.app", category: "SourceResolver")

    init(
        arxivClient: ArxivClient,
        githubApi: GithubApiClient,
        huggingFaceApi: HuggingFaceApiClient,
        crossrefClient: CrossrefClient
    ) {
        self.arxivClient = arxivClient
        self.githubApi = githubApi
        self.huggingFaceApi = huggingFaceApi
        self.crossrefClient = crossrefClient
    }

    // MARK: - Retry

    /// Port of `private suspend fun <T> withRetry(maxAttempts, delayMs, block)`.
    private func withRetry<T: Sendable>(
        maxAttempts: Int = 3,
        delayMs: Int = 1000,
        _ block: () async throws -> T?
    ) async -> T? {
        for attempt in 0..<maxAttempts {
            do {
                return try await block()
            } catch let apiError as APIError {
                if let code = apiError.statusCode, code == 429 || code == 503 {
                    let retryAfter = apiError.headers["retry-after"].flatMap { Int64($0) } ?? (Int64(1) << attempt)
                    let retryAfterMs = retryAfter * 1000
                    try? await Task.sleep(for: .milliseconds(retryAfterMs))
                } else if let code = apiError.statusCode, (400..<500).contains(code) {
                    return nil  // client errors: don't retry
                }
                // Other status codes fall through to the next attempt.
            } catch is CancellationError {
                // Rethrow-cancel parity: stop retrying (callers treat a nil as "unresolved").
                return nil
            } catch {
                if attempt == maxAttempts - 1 { return nil }
                try? await Task.sleep(for: .milliseconds(Int64(delayMs) * (Int64(1) << attempt)))
            }
        }
        return nil
    }

    // MARK: - Resolve

    /// Port of `suspend fun resolve(text, url)`. Tries each resolver in fixed priority order over all
    /// extracted URLs, then the bare-arXiv and DOI text fallbacks.
    func resolve(text: String, url: String?) async -> SourceInfo? {
        var allUrls = extractAllUrls(text)
        if let url { allUrls.append(url) }

        // Priority: arXiv > HuggingFace papers page > GitHub > HuggingFace model/dataset > DOI
        for u in allUrls {
            if let info = await resolveArxiv(u) { return info }
        }
        for u in allUrls {
            if let info = await resolveHfPaper(u) { return info }
        }
        for u in allUrls {
            if let info = await resolveGithub(u) { return info }
        }
        for u in allUrls {
            if let info = await resolveHuggingFace(u) { return info }
        }
        // Fallback: bare arXiv IDs mentioned in text without a URL (e.g. "2312.00752").
        if let match = text.firstMatch(of: ArxivClient.arxivBareRegex) {
            let bareId = String(match.1)
            if let info = await resolveArxiv("https://arxiv.org/abs/\(bareId)") { return info }
        }
        // Fallback: a DOI in a doi.org URL or bare "10.xxxx/..." token anywhere in the text.
        for u in allUrls {
            if let match = u.firstMatch(of: CrossrefClient.doiRegex) {
                let doi = String(match.1)
                if let info = await resolveDoi(doi) { return info }
            }
        }
        if let match = text.firstMatch(of: CrossrefClient.doiRegex) {
            let doi = String(match.1)
            if let info = await resolveDoi(doi) { return info }
        }
        return nil
    }

    // MARK: - DOI (Crossref)

    private func resolveDoi(_ doi: String) async -> SourceInfo? {
        let meta = await withRetry { await crossrefClient.fetchWork(doi) }
        guard let meta else { return nil }
        // arXiv DOIs (10.48550/arXiv.*) are better served by the arXiv resolver; skip them here.
        if meta.doi.range(of: "arxiv", options: .caseInsensitive) != nil { return nil }
        let extra = buildExtraJson([
            ("doi", meta.doi),
            ("published", meta.published),
            ("container", meta.containerTitle),
            ("type", meta.type)
        ])
        let authors = meta.authors.joined(separator: ", ")
        return SourceInfo(
            sourceType: .DOI,
            sourceId: meta.doi,
            sourceTitle: meta.title,
            sourceAuthors: authors.isBlank ? nil : authors,
            sourceAbstract: meta.abstract,
            sourceExtra: extra
        )
    }

    // MARK: - URL extraction

    /// Port of `extractAllUrls(text)`. Matches full URLs including query strings (`?k=v`) and
    /// fragments (`#anchor`); trailing punctuation that is syntactically part of the surrounding
    /// sentence is stripped after extraction. CONVENTIONS §10: the trailing-punctuation strip is a
    /// `while`-loop over `.,)]!?;` (not `trimmingCharacters`, which trims both ends).
    private func extractAllUrls(_ text: String) -> [String] {
        var results: [String] = []
        for match in text.matches(of: Self.urlRegex) {
            var value = String(match.0)
            let trailing: Set<Character> = [".", ",", ")", "]", "!", "?", ";"]
            while let last = value.last, trailing.contains(last) {
                value.removeLast()
            }
            results.append(value)
        }
        return results
    }

    // MARK: - arXiv

    private func resolveArxiv(_ url: String) async -> SourceInfo? {
        guard let match = url.firstMatch(of: ArxivClient.arxivIdRegex) else { return nil }
        let id = String(match.1).replacing(Self.versionSuffixRegex, with: "")

        let meta = await withRetry { await arxivClient.fetchPaper(id) }
        guard let meta else { return nil }
        let extra = buildExtraJson([
            ("published", meta.published),
            ("categories", meta.categories)
        ])
        return SourceInfo(
            sourceType: .ARXIV,
            sourceId: meta.id,
            sourceTitle: meta.title,
            sourceAuthors: meta.authors.joined(separator: ", "),
            sourceAbstract: meta.abstract,
            sourceExtra: extra
        )
    }

    /// HuggingFace papers links embed arXiv IDs. Port of `resolveHfPaper(url)`.
    private func resolveHfPaper(_ url: String) async -> SourceInfo? {
        guard let match = url.firstMatch(of: Self.hfPaperRegex) else { return nil }
        let id = String(match.1)
        return await resolveArxiv("https://arxiv.org/abs/\(id)")
    }

    // MARK: - GitHub

    private func resolveGithub(_ url: String) async -> SourceInfo? {
        guard let match = url.firstMatch(of: Self.githubRegex) else { return nil }
        let owner = String(match.1)
        var repo = String(match.2)
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        if owner.isBlank || repo.isBlank { return nil }

        let r = await withRetry { await githubApi.getRepo(owner: owner, repo: repo) }
        guard let r else { return nil }
        let extra = buildExtraJson([
            ("stars", r.stars),
            ("language", r.language),
            ("topics", r.topics),
            ("pushedAt", r.pushedAt)
        ])
        return SourceInfo(
            sourceType: .GITHUB,
            sourceId: r.fullName,
            sourceTitle: r.fullName,
            sourceAuthors: r.owner.login,
            sourceAbstract: r.description,
            sourceExtra: extra
        )
    }

    // MARK: - HuggingFace

    private func resolveHuggingFace(_ url: String) async -> SourceInfo? {
        // Exclude known non-model paths.
        if url.contains("/spaces/") || url.contains("/papers/") || url.contains("/docs/") {
            return nil
        }
        if let datasetMatch = url.firstMatch(of: Self.hfDatasetRegex) {
            return await resolveHfDataset(String(datasetMatch.1))
        }
        if let modelMatch = url.firstMatch(of: Self.hfModelRegex) {
            return await resolveHfModel(String(modelMatch.1))
        }
        return nil
    }

    private func resolveHfModel(_ id: String) async -> SourceInfo? {
        let r = await withRetry { await huggingFaceApi.getModel(id) }
        guard let r else { return nil }
        let modelId = r.modelId ?? r.id ?? id
        let extra = buildExtraJson([
            ("downloads", r.downloads),
            ("likes", r.likes),
            ("pipelineTag", r.pipelineTag),
            ("tags", Array(r.tags.prefix(8)))
        ])
        return SourceInfo(
            sourceType: .HUGGING_FACE,
            sourceId: modelId,
            sourceTitle: modelId,
            sourceAuthors: r.author,
            sourceAbstract: r.description.map { String($0.prefix(500)) },
            sourceExtra: extra
        )
    }

    private func resolveHfDataset(_ id: String) async -> SourceInfo? {
        let r = await withRetry { await huggingFaceApi.getDataset(id) }
        guard let r else { return nil }
        let datasetId = r.id ?? id
        let extra = buildExtraJson([
            ("downloads", r.downloads),
            ("likes", r.likes),
            ("tags", Array(r.tags.prefix(8)))
        ])
        return SourceInfo(
            sourceType: .HUGGING_FACE,
            sourceId: datasetId,
            sourceTitle: datasetId,
            sourceAuthors: r.author,
            sourceAbstract: r.description.map { String($0.prefix(500)) },
            sourceExtra: extra
        )
    }

    // MARK: - Extra JSON

    /// Port of `buildExtraJson(data)`. Drops nil values, serializes lists as JSON arrays, everything
    /// else as its natural JSON value. Mirrors `org.json.JSONObject` insertion order via an ordered
    /// pair list (Swift `Dictionary` is unordered; the Kotlin `mapOf` preserved insertion order and
    /// `JSONObject` echoes it, so we serialize manually to keep key order stable).
    private func buildExtraJson(_ data: [(String, Any?)]) -> String {
        var obj: [String: Any] = [:]
        var orderedKeys: [String] = []
        for (k, v) in data {
            guard let v else { continue }
            if let list = v as? [String] {
                obj[k] = list
            } else {
                obj[k] = v
            }
            orderedKeys.append(k)
        }
        return Self.serializeOrdered(obj, order: orderedKeys)
    }

    /// Serializes a small flat object preserving `order`, escaping strings the way `org.json` does for
    /// the value kinds we emit (strings, ints, string arrays).
    private static func serializeOrdered(_ obj: [String: Any], order: [String]) -> String {
        var parts: [String] = []
        for key in order {
            guard let value = obj[key] else { continue }
            parts.append("\(jsonString(key)):\(jsonValue(value))")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func jsonValue(_ value: Any) -> String {
        switch value {
        case let s as String:
            return jsonString(s)
        case let arr as [String]:
            return "[" + arr.map { jsonString($0) }.joined(separator: ",") + "]"
        case let i as Int:
            return String(i)
        case let i as Int64:
            return String(i)
        case let d as Double:
            return String(d)
        case let b as Bool:
            return b ? "true" : "false"
        default:
            return jsonString("\(value)")
        }
    }

    /// JSON-escapes a string per RFC 8259 (mirrors `org.json` string quoting for the chars we emit).
    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    // MARK: - Regexes (byte-identical to the Kotlin patterns)

    /// `https?://[^\s<>"']+`
    private nonisolated(unsafe) static let urlRegex = /https?:\/\/[^\s<>"']+/
    /// `v\d+$`
    private nonisolated(unsafe) static let versionSuffixRegex = /v\d+$/
    /// `huggingface\.co/papers/([\d.]+)`
    private nonisolated(unsafe) static let hfPaperRegex = /huggingface\.co\/papers\/([\d.]+)/
    /// `github\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)`
    private nonisolated(unsafe) static let githubRegex = /github\.com\/([a-zA-Z0-9_.-]+)\/([a-zA-Z0-9_.-]+)/
    /// `huggingface\.co/datasets/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)`
    private nonisolated(unsafe) static let hfDatasetRegex = /huggingface\.co\/datasets\/([a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+)/
    /// `huggingface\.co/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)`
    private nonisolated(unsafe) static let hfModelRegex = /huggingface\.co\/([a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+)/
}
