import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Hands Curio bookmarks off to the ChronosFlow productivity app. Port of
/// `interop/ChronosFlowBridge.kt` — this is the "remind me to read later" / watch-later
/// integration: a Curio bookmark becomes a ChronosFlow reading-list item (optionally with a
/// scheduled reminder), an inbox capture, or a follow-up task.
///
/// **Transport (iOS substitution, see `ChronosInteropContract`):** instead of inserting into
/// ChronosFlow's exported ContentProvider, each call appends one `ChronosHandoffEntry` to the JSON
/// queue file in the shared App-Group container. ChronosFlow drains the queue with its interop
/// import pipeline (the same shape as its Meridian `InteropSync`).
///
/// Every call is best-effort. When ChronosFlow isn't installed, the shared container is missing,
/// or the write fails, the call throws and Curio carries on standalone — nothing here is allowed
/// to crash a bookmark action (the callers wrap in `do/catch`, CONVENTIONS §3).
///
/// The type is an `actor` (CONVENTIONS §5: owns a non-reentrant resource — the queue file). Actor
/// isolation serializes Curio-side appends; `NSFileCoordinator` guards the cross-process
/// read-modify-write against ChronosFlow's drain.
actor ChronosFlowBridge {

    private static let logger = Logger(subsystem: "com.curio.app", category: "ChronosFlowBridge")

    /// Cross-process handoff failures (`LocalizedError` so the VM can surface `error.message`
    /// analogues verbatim).
    enum HandoffError: Error, LocalizedError {
        /// ChronosFlow isn't installed (or the shared container is unreachable).
        case notInstalled
        /// The queue file could not be read/written.
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "ChronosFlow is not installed"
            case .writeFailed(let detail): return "ChronosFlow handoff failed: \(detail)"
            }
        }
    }

    init() {}

    // MARK: - Availability

    /// True when ChronosFlow is installed and the shared handoff container is reachable from this
    /// app — the iOS analogue of resolving the Android provider's owner package. `@MainActor`
    /// because `UIApplication.canOpenURL` is main-actor-isolated; the check is cheap, so callers
    /// (the VM) cache it once per session exactly as Android does.
    @MainActor
    static func isAvailable() -> Bool {
        guard ChronosInteropContract.handoffFileURL != nil else { return false }
        #if canImport(UIKit)
        guard let probe = URL(string: "\(ChronosInteropContract.chronosFlowScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
        #else
        return false
        #endif
    }

    // MARK: - Handoffs (Kotlin `sendToReadingList` / `captureToInbox` / `createTask`)

    /// Saves `url` to ChronosFlow's reading list ("read later"). When `reminderAtEpochMillis` is
    /// non-nil, ChronosFlow also schedules a "remind me to read later" notification at that time.
    func sendToReadingList(
        url: String,
        title: String? = nil,
        reminderAtEpochMillis: Int64? = nil,
        notes: String? = nil
    ) async throws {
        try append(entry: makeEntry(
            kind: ChronosInteropContract.kindReading,
            url: url,
            title: title.nonBlank,
            notes: notes.nonBlank,
            reminderAtEpochMillis: reminderAtEpochMillis
        ))
    }

    /// Captures `text` (a note or a link) into ChronosFlow's quick-capture inbox for later triage.
    func captureToInbox(_ text: String) async throws {
        try append(entry: makeEntry(kind: ChronosInteropContract.kindInbox, text: text))
    }

    /// Creates a follow-up task in ChronosFlow from `title` (with optional `notes` and `url`).
    func createTask(title: String, notes: String? = nil, url: String? = nil) async throws {
        try append(entry: makeEntry(
            kind: ChronosInteropContract.kindTask,
            url: url.nonBlank,
            title: title,
            text: notes.nonBlank
        ))
    }

    // MARK: - Queue append (Kotlin `insert`)

    private func makeEntry(
        kind: String,
        url: String? = nil,
        title: String? = nil,
        text: String? = nil,
        notes: String? = nil,
        reminderAtEpochMillis: Int64? = nil
    ) -> ChronosHandoffEntry {
        ChronosHandoffEntry(
            id: UUID().uuidString,
            kind: kind,
            createdAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000),
            url: url,
            title: title,
            text: text,
            notes: notes,
            reminderAtEpochMillis: reminderAtEpochMillis
        )
    }

    /// Read-modify-write of the queue file under `NSFileCoordinator` (the shared container is
    /// written by this app and drained by ChronosFlow — coordination prevents a torn read on
    /// either side). A malformed/missing existing file starts a fresh queue rather than failing:
    /// losing a stale queue beats blocking new handoffs.
    private func append(entry: ChronosHandoffEntry) throws {
        guard let fileURL = ChronosInteropContract.handoffFileURL else {
            throw HandoffError.notInstalled
        }
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            do {
                var payload: ChronosHandoffPayload
                if let data = try? Data(contentsOf: url),
                   let existing = try? JSONDecoder().decode(ChronosHandoffPayload.self, from: data),
                   existing.peer == ChronosInteropContract.curioPeer {
                    payload = existing
                } else {
                    payload = ChronosHandoffPayload(handoffs: [])
                }
                payload.handoffs.append(entry)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(payload).write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinatorError {
            Self.logger.warning("ChronosFlow \(entry.kind, privacy: .public) handoff coordination failed: \(coordinatorError.localizedDescription, privacy: .public)")
            throw HandoffError.writeFailed(coordinatorError.localizedDescription)
        }
        if let writeError {
            Self.logger.warning("ChronosFlow \(entry.kind, privacy: .public) handoff failed: \(writeError.localizedDescription, privacy: .public)")
            throw HandoffError.writeFailed(writeError.localizedDescription)
        }
    }
}

// MARK: - Blank helpers (Kotlin `takeIf { it.isNotBlank() }`)

private extension Optional where Wrapped == String {
    /// `nil` when absent or whitespace-only, else the value — Kotlin `?.takeIf { it.isNotBlank() }`.
    var nonBlank: String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return self
    }
}
