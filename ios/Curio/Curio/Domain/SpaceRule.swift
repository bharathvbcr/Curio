import Foundation

/// Which field of a `Bookmark` a `SpaceRule` inspects. Ports `enum class RuleField` from
/// `domain/model/SpaceRule.kt`.
///
/// The raw value is the persisted/serialized name (Kotlin `.name`) and MUST keep its exact
/// uppercase spelling (CONVENTIONS §"Persistence-key stability"). `label` is the user-facing name
/// shown in the rule builder — exact strings preserved.
enum RuleField: String, Codable, Sendable, CaseIterable, Hashable {
    /// raw text, title, summary, OCR, source title/abstract
    case KEYWORD
    case TAG
    /// AI-assigned category
    case CATEGORY
    /// resolved primary source type (ARXIV, GITHUB, …)
    case SOURCE
    /// tweet author or resolved paper authors
    case AUTHOR
    case URL

    var label: String {
        switch self {
        case .KEYWORD: return "Text"
        case .TAG: return "Tag"
        case .CATEGORY: return "Category"
        case .SOURCE: return "Source"
        case .AUTHOR: return "Author"
        case .URL: return "Link"
        }
    }
}

/// How a `SpaceRule` compares its `value` against the chosen `RuleField`. Ports `enum class RuleOp`.
/// Raw value is persisted; `label` is user-facing.
enum RuleOp: String, Codable, Sendable, CaseIterable, Hashable {
    case CONTAINS
    case EQUALS
    case STARTS_WITH

    var label: String {
        switch self {
        case .CONTAINS: return "contains"
        case .EQUALS: return "is"
        case .STARTS_WITH: return "starts with"
        }
    }
}

/// Whether a Space's rule set fires when ANY rule matches or only when ALL of them do. Ports
/// `enum class RuleMatch`. Raw value is persisted.
enum RuleMatch: String, Codable, Sendable, CaseIterable, Hashable {
    case ANY
    case ALL
}

/// A single auto-filing condition: "`field` `op` `value`", e.g. KEYWORD CONTAINS "diffusion".
/// Ports `data class SpaceRule`.
///
/// Matching is always **case-insensitive**; a blank `value` never matches (and is treated as a
/// draft). Case-insensitivity uses ASCII/non-localized semantics to mirror Kotlin's
/// `ignoreCase = true` default (which compares by lowercasing, not locale-aware folding).
struct SpaceRule: Hashable, Sendable {
    let field: RuleField
    let op: RuleOp
    let value: String

    init(field: RuleField, op: RuleOp, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    func matches(_ b: Bookmark) -> Bool {
        let needle = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return false }
        switch field {
        case .KEYWORD:
            // listOfNotNull(text, title, summary, ocrText, sourceTitle, sourceAbstract)
            let haystacks = [b.text, b.title, b.summary, b.ocrText, b.sourceTitle, b.sourceAbstract]
                .compactMap { $0 }
            return haystacks.contains { test($0, needle) }
        case .TAG:
            return b.tags.contains { test($0, needle) }
        case .CATEGORY:
            return b.category.map { test($0, needle) } ?? false
        case .SOURCE:
            return b.sourceType.map { test($0.rawValue, needle) } ?? false
        case .AUTHOR:
            let haystacks = [b.authorName, b.authorUsername, b.sourceAuthors].compactMap { $0 }
            return haystacks.contains { test($0, needle) }
        case .URL:
            return b.url.map { test($0, needle) } ?? false
        }
    }

    /// Mirrors Kotlin's `contains/equals/startsWith(needle, ignoreCase = true)`.
    /// `STARTS_WITH` lowercases both sides explicitly (CONVENTIONS §Domain invariants).
    private func test(_ haystack: String, _ needle: String) -> Bool {
        switch op {
        case .CONTAINS:
            return haystack.range(of: needle, options: .caseInsensitive) != nil
        case .EQUALS:
            return haystack.compare(needle, options: .caseInsensitive) == .orderedSame
        case .STARTS_WITH:
            return haystack.lowercased().hasPrefix(needle.lowercased())
        }
    }
}

/// The full rule configuration attached to a Space ("Smart Space"). Ports `data class SpaceRules`.
///
/// `autoFile` gates whether matching bookmarks are filed automatically (on analysis / sync / login
/// backfill); when off the rules are inert until the user taps "Apply rules". Persisted as a compact
/// JSON blob (short keys `m`/`a`/`r` and `f`/`o`/`v`) via `toJson`/`fromJson` so no extra table or
/// per-rule migration is needed.
///
/// DRAFT-RULE SEMANTICS (preserved): a rule with a blank value never *matches* but `toJson`
/// serializes **all** rules including drafts. `fromJson` is tolerant — any malformed/blank input
/// yields `.empty` rather than throwing, and malformed array elements are skipped.
struct SpaceRules: Hashable, Sendable {
    let match: RuleMatch
    let autoFile: Bool
    let rules: [SpaceRule]

    init(match: RuleMatch = .ANY, autoFile: Bool = true, rules: [SpaceRule] = []) {
        self.match = match
        self.autoFile = autoFile
        self.rules = rules
    }

    /// Rules that actually carry a value — drafts with an empty value are ignored when matching.
    private var effective: [SpaceRule] {
        rules.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// True when this Space has at least one usable rule (i.e. it's a "smart" Space).
    var isActive: Bool { !effective.isEmpty }

    /// Whether `b` should be filed here. Always false for an empty/inactive rule set.
    func matches(_ b: Bookmark) -> Bool { matchScore(b) > 0 }

    /// How many rules matched `b`; 0 when the set doesn't match. Used to pick the best Smart Space
    /// when several qualify (more matching rules = more specific intent).
    func matchScore(_ b: Bookmark) -> Int {
        let active = effective
        if active.isEmpty { return 0 }
        let hits = active.filter { $0.matches(b) }.count
        switch match {
        case .ANY: return hits > 0 ? hits : 0
        case .ALL: return hits == active.count ? active.count : 0
        }
    }

    /// Serializes ALL rules (including drafts) to the compact short-key JSON wire format.
    /// Returns `""` when there are no rules (byte-compatible with the Kotlin `org.json` output:
    /// `{"m":..,"a":..,"r":[{"f":..,"o":..,"v":..}, …]}`).
    func toJson() -> String {
        if rules.isEmpty { return "" }
        let ruleObjs: [[String: Any]] = rules.map { r in
            [
                "f": r.field.rawValue,
                "o": r.op.rawValue,
                "v": r.value
            ]
        }
        let root: [String: Any] = [
            "m": match.rawValue,
            "a": autoFile,
            "r": ruleObjs
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    static let empty = SpaceRules()

    /// Tolerant parser — any malformed/blank input yields `.empty` rather than throwing. Mirrors the
    /// Kotlin `org.json` reader: unknown/missing `m` → `.ANY`, missing `a` → `true`, missing `r` →
    /// empty array, and any rule element missing/invalid `f` or `o` is skipped (`mapNotNull`).
    static func fromJson(_ raw: String?) -> SpaceRules {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let obj = parsed as? [String: Any] else {
            return .empty
        }

        // match = runCatching { RuleMatch.valueOf(obj.optString("m", "ANY")) }.getOrDefault(.ANY)
        let matchName = (obj["m"] as? String) ?? "ANY"
        let match = RuleMatch(rawValue: matchName) ?? .ANY

        // autoFile = obj.optBoolean("a", true) — org.json coerces "true"/"false" strings too.
        let autoFile = optBoolean(obj["a"], default: true)

        // arr = obj.optJSONArray("r") ?: JSONArray()
        let arr = (obj["r"] as? [Any]) ?? []
        let rules: [SpaceRule] = arr.compactMap { element -> SpaceRule? in
            guard let o = element as? [String: Any] else { return nil }
            // field = RuleField.valueOf(o.optString("f")) ?: return null
            guard let fieldName = o["f"] as? String, let field = RuleField(rawValue: fieldName) else {
                return nil
            }
            // op = RuleOp.valueOf(o.optString("o")) ?: return null
            guard let opName = o["o"] as? String, let op = RuleOp(rawValue: opName) else {
                return nil
            }
            // value = o.optString("v") — org.json optString returns "" when absent/null.
            let value = (o["v"] as? String) ?? ""
            return SpaceRule(field: field, op: op, value: value)
        }

        return SpaceRules(match: match, autoFile: autoFile, rules: rules)
    }

    /// Mirrors `JSONObject.optBoolean(key, default)`: accepts a real Bool, or the strings
    /// "true"/"false" (case-insensitively), otherwise the supplied default.
    private static func optBoolean(_ value: Any?, default fallback: Bool) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber {
            // org.json treats only the literal Boolean true/false; numbers fall back. NSNumber from
            // JSONSerialization for a JSON bool bridges to Bool above, so a numeric here is a number.
            // org.json.optBoolean returns the default for non-boolean numbers.
            _ = n
            return fallback
        }
        if let s = value as? String {
            if s.caseInsensitiveCompare("true") == .orderedSame { return true }
            if s.caseInsensitiveCompare("false") == .orderedSame { return false }
        }
        return fallback
    }
}
