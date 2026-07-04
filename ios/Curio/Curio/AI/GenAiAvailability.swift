import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device GenAI feature status, mirroring the Android `FeatureStatus` (which itself mirrored
/// ML Kit GenAI's `FeatureStatus`).
///
/// The on-device text model is only present on a subset of devices (Apple-Intelligence-capable
/// hardware where the system model has finished downloading). Per Curio's privacy model we must
/// NEVER assume the on-device model is available — every on-device AI path is gated through
/// ``GenAiAvailability`` and silently falls back to the cloud generator when the feature is not
/// ``FeatureStatus/AVAILABLE``.
///
/// Raw values are uppercase to match the Kotlin `.name` (persistence-key stability, CONVENTIONS §1):
/// even though these are not persisted today, keeping the exact names avoids drift if they are.
enum FeatureStatus: String, Sendable {
    case UNAVAILABLE
    case DOWNLOADABLE
    case DOWNLOADING
    case AVAILABLE
}

/// Detects whether the on-device text model (Apple Foundation Models) is usable on this device,
/// and is the single device-gate for all on-device AI.
///
/// Direct port of the Android `GenAiAvailability`. The reflective AICore class-probe + low-RAM
/// check is replaced by `SystemLanguageModel.default.availability` (DESIGN tech-mapping table:
/// "ML Kit GenAI FeatureStatus → SystemLanguageModel.availability"). On OS versions that predate
/// Foundation Models — or builds without the framework — the gate reports ``FeatureStatus/UNAVAILABLE``
/// so the pipeline degrades to the cloud / offline-keyword backend exactly like an AICore-less Android device.
struct GenAiAvailability: Sendable {

    init() {}

    /// Returns the on-device GenAI feature status.
    ///
    /// Mapping from `SystemLanguageModel.Availability` (DESIGN tech-mapping):
    /// - `.available`                       → ``FeatureStatus/AVAILABLE``
    /// - `.unavailable(.modelNotReady)`     → ``FeatureStatus/DOWNLOADING`` (model is still downloading/preparing)
    /// - `.unavailable(.deviceNotEligible)` → ``FeatureStatus/UNAVAILABLE`` (hardware can't host the model)
    /// - `.unavailable(.appleIntelligenceNotEnabled)` → ``FeatureStatus/DOWNLOADABLE`` (user can turn it on)
    /// - any other `.unavailable(...)`      → ``FeatureStatus/UNAVAILABLE``
    ///
    /// Like the Kotlin `runCatching { … }.getOrDefault(UNAVAILABLE)`, any failure to query the model
    /// degrades to ``FeatureStatus/UNAVAILABLE`` → cloud.
    func status() -> FeatureStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .AVAILABLE
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .UNAVAILABLE
                case .appleIntelligenceNotEnabled:
                    return .DOWNLOADABLE
                case .modelNotReady:
                    return .DOWNLOADING
                @unknown default:
                    return .UNAVAILABLE
                }
            @unknown default:
                return .UNAVAILABLE
            }
        }
        #endif
        return .UNAVAILABLE
    }

    /// True only when the on-device model is ready to run inference right now.
    /// Mirrors Kotlin `status() == FeatureStatus.AVAILABLE`.
    func isNanoUsable() -> Bool {
        status() == .AVAILABLE
    }
}
