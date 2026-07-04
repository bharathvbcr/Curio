import Foundation

/// Which backend computes embeddings. Mirrors `EmbeddingBackend` / `EmbeddingPreference` from
/// `data/embedding/EmbeddingPreference.kt`.
enum EmbeddingBackend: String, CaseIterable, Sendable {
    /// On-device EmbeddingGemma when downloaded, else the xAI cloud fallback.
    case auto = "AUTO"
    /// Force on-device EmbeddingGemma; never falls back to the cloud.
    case onDevice = "ON_DEVICE"
    /// Force the xAI cloud embedder; never runs on-device.
    case xai = "XAI"

    var settingsLabel: String {
        switch self {
        case .auto: return "Auto"
        case .onDevice: return "On-device"
        case .xai: return "xAI"
        }
    }

    var settingsDescription: String {
        switch self {
        case .auto:
            return "On-device when the model is downloaded, otherwise xAI cloud."
        case .onDevice:
            return "Private, on-device only. Requires the EmbeddingGemma model (download below)."
        case .xai:
            return "xAI cloud. Note: xAI has no public embeddings endpoint yet, so this often returns nothing."
        }
    }
}

/// Persists the chosen `EmbeddingBackend`. Uses the same UserDefaults key as Android
/// (`embedding_backend` in `curio_embedding_prefs`).
enum EmbeddingPreference {
    private static let backendKey = "embedding_backend"

    static func get() -> EmbeddingBackend {
        guard let raw = UserDefaults.standard.string(forKey: backendKey),
              let backend = EmbeddingBackend(rawValue: raw) else {
            return .auto
        }
        return backend
    }

    static func set(_ backend: EmbeddingBackend) {
        UserDefaults.standard.set(backend.rawValue, forKey: backendKey)
    }
}
