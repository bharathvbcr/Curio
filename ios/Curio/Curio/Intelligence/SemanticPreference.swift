import Foundation

/// User preference for the on-device semantic layer (response cache + RAG compression +
/// complexity routing). When enabled, chat consults the local cache before calling xAI, compresses
/// retrieved context, and routes reasoning effort by query complexity. Everything runs on-device.
enum SemanticPreference {
    private static let enabledKey = "semantic_layer_enabled"
    private static let thresholdKey = "semantic_cache_threshold"

    static let thresholdInitial: Float = 0.90
    static let thresholdMin: Float = 0.85
    static let thresholdMax: Float = 0.97

    /// Default ON. Disable in Settings to skip the semantic layer entirely.
    static func isEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    /// Adaptive cosine threshold for a semantic cache hit. Nudged up on thumbs-down feedback so a
    /// bad match isn't repeated; persisted so tuning survives restarts. Clamped to [min, max].
    static func cacheThreshold() -> Float {
        if UserDefaults.standard.object(forKey: thresholdKey) == nil { return thresholdInitial }
        let v = UserDefaults.standard.float(forKey: thresholdKey)
        return min(max(v, thresholdMin), thresholdMax)
    }

    static func setCacheThreshold(_ value: Float) {
        UserDefaults.standard.set(min(max(value, thresholdMin), thresholdMax), forKey: thresholdKey)
    }
}
