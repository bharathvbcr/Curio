import Foundation

/// Language + length gate for on-device summarization. The on-device model is reliable only for
/// English / Japanese / Korean and short inputs (~3k words); everything else must route to the
/// cloud fallback.
///
/// Direct port of the Android `object LanguageGate`. Caseless namespace enum (CONVENTIONS §1).
///
/// Determinism note (CONVENTIONS §10 "char-count semantics"): the Kotlin code iterates `for (ch in
/// text)` over UTF-16 code units and tests `ch.code`. We iterate `text.unicodeScalars` and test
/// `scalar.value`. For every character in the gated ranges (all within the BMP) a `Character` is a
/// single scalar, so the two counts are identical. Supplementary-plane characters (which Kotlin
/// would split into surrogate pairs whose code units fall in 0xD800..0xDFFF — outside every range
/// below) match neither pathway, so the behaviour is preserved exactly.
enum LanguageGate {
    static let MAX_WORDS = 3_000

    enum Lang: Sendable {
        case EN
        case JA
        case KO
        case OTHER
    }

    /// Cheap script-based language detection (no model/dependency needed). Ports the Kotlin
    /// counting loop and decision ladder verbatim.
    static func detect(_ text: String) -> Lang {
        var hangul = 0
        var kana = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            let code = scalar.value
            switch code {
            case 0xAC00...0xD7A3, 0x1100...0x11FF: // Hangul syllables / Jamo
                hangul += 1
            case 0x3040...0x30FF:                  // Hiragana + Katakana
                kana += 1
            case 0x0041...0x007A:                  // Basic Latin letters (incl. 0x5B..0x60, as in Kotlin)
                latin += 1
            default:
                break
            }
        }
        if hangul > 0 && hangul >= kana { return .KO }
        if kana > 0 { return .JA }
        if latin > 0 && hangul == 0 && kana == 0 { return .EN }
        return .OTHER
    }

    /// True when the input's detected language is one the on-device model supports.
    static func isSupported(_ text: String) -> Bool {
        detect(text) != .OTHER
    }

    /// True when the input is within the on-device word cap.
    ///
    /// Mirrors Kotlin `text.split(Regex("\\s+")).size <= MAX_WORDS`. Kotlin's `split` on a regex
    /// does NOT drop empty trailing/leading tokens, so a leading-whitespace string yields a leading
    /// empty token (counted). We replicate that by splitting on the `\s+` regex with empty
    /// subsequences retained.
    static func withinCap(_ text: String) -> Bool {
        wordCount(text) <= MAX_WORDS
    }

    /// Replicates Kotlin `text.split(Regex("\\s+")).size` exactly (empty leading/trailing tokens kept).
    private static func wordCount(_ text: String) -> Int {
        // Java/Kotlin `String.split(Regex)` semantics: split on each non-empty `\s+` run; a match at
        // the very start produces a leading empty string; trailing empty strings are NOT removed
        // (only `split(regex, limit)` with default limit 0 removes *trailing* empties in Java —
        // Kotlin's `String.split(Regex)` keeps them). So we count: (number of `\s+` separators) + 1.
        let separators = whitespaceRunCount(text)
        return separators + 1
    }

    /// Counts the number of maximal `\s+` (one-or-more Unicode whitespace) runs in `text`, matching
    /// the count of separators Java's `Pattern.split` would use.
    private static func whitespaceRunCount(_ text: String) -> Int {
        var runs = 0
        var inRun = false
        for scalar in text.unicodeScalars {
            if isJavaWhitespace(scalar) {
                if !inRun {
                    runs += 1
                    inRun = true
                }
            } else {
                inRun = false
            }
        }
        return runs
    }

    /// Java regex `\s` = `[ \t\n\x0B\f\r]` (ASCII-only by default — the pattern is `"\\s+"` without
    /// the UNICODE_CHARACTER_CLASS flag, so only these six characters count as whitespace).
    private static func isJavaWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
            return true
        default:
            return false
        }
    }
}
