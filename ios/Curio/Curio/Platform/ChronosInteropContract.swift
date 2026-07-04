import Foundation

/// Curio's mirror of ChronosFlow's iOS interop handoff contract. Port of
/// `interop/ChronosInteropContract.kt`, with the platform substitution the two apps already use for
/// their other integrations (Meridian → ChronosFlow):
///
/// **Android:** ChronosFlow exposes a write-only ContentProvider path
/// (`content://com.ChronosFlow.VBCR.share/handoff`) and Curio inserts one row per handoff.
///
/// **iOS:** there is no ContentProvider, so the handoff travels through the SHARED App-Group
/// container both apps are entitled to (`group.com.chronosflow.shared` — the same group
/// ChronosFlow's `ChronosStore.appGroup` declares). Curio appends one entry per handoff to a JSON
/// queue file (`curio-handoff.json`) inside that container; ChronosFlow drains the queue on launch /
/// background refresh (the same import pipeline shape as its `InteropSync`). The App-Group
/// entitlement IS the trust boundary on iOS (team-scoped sandbox) — there is no certificate-pinning
/// API, exactly as ChronosFlow's own interop notes.
///
/// There is no shared package between the two apps, so the file name and JSON keys below MUST stay
/// byte-for-byte equal to the reader on the ChronosFlow side. The wire keys reuse Android's
/// handoff column names (`kind` / `url` / `title` / `text` / `notes` / `reminder_at_epoch_ms`) so
/// the cross-platform contract stays aligned.
enum ChronosInteropContract {

    /// ChronosFlow's iOS URL scheme (declared in its Info.plist `CFBundleURLSchemes`). Used by
    /// `ChronosFlowBridge.isAvailable()` via `canOpenURL` — the iOS analogue of resolving the
    /// Android provider's owner package. Requires `chronosflow` in Curio's
    /// `LSApplicationQueriesSchemes`.
    static let chronosFlowScheme = "chronosflow"

    /// The shared App-Group both apps are entitled to (== ChronosFlow `ChronosStore.appGroup`).
    static let appGroup = "group.com.chronosflow.shared"

    /// Queue file Curio appends handoffs to, inside the shared container. ChronosFlow's reader
    /// drains and truncates it.
    static let handoffFileName = "curio-handoff.json"

    /// Curio's bundle id — self-identifies the payload author so ChronosFlow can reject a payload
    /// that doesn't name the expected companion app (a cheap sanity check; the App-Group
    /// entitlement is the real trust boundary).
    static let curioPeer = "com.curio.app"

    // MARK: - Handoff kinds (Android `KIND_*`, byte-identical)

    static let kindReading = "reading"
    static let kindInbox = "inbox"
    static let kindTask = "task"

    /// The queue file URL inside the shared container, or `nil` when the App-Group entitlement is
    /// missing (e.g. an unconfigured dev build) — callers treat that as "ChronosFlow unavailable".
    static var handoffFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(handoffFileName)
    }
}

// MARK: - Wire types

/// Top-level payload Curio writes into the shared container: the author id plus the pending handoff
/// queue. Mirrors the envelope shape of ChronosFlow's `InteropPeerPayload` (peer self-identification
/// + rows) so the reader on the ChronosFlow side stays uniform across its integrations.
struct ChronosHandoffPayload: Codable, Equatable, Sendable {
    /// The author bundle id — must equal `ChronosInteropContract.curioPeer` to be trusted.
    var peer: String
    /// Pending handoffs, oldest first. ChronosFlow drains and truncates.
    var handoffs: [ChronosHandoffEntry]

    init(peer: String = ChronosInteropContract.curioPeer, handoffs: [ChronosHandoffEntry]) {
        self.peer = peer
        self.handoffs = handoffs
    }
}

/// One handoff row — the iOS analogue of the Android `ContentValues` insert. Field names on the
/// wire reuse the Android handoff column names; `id`/`created_at_epoch_ms` are added so
/// ChronosFlow's drain pass can deduplicate deterministically (same role as its `InteropDedup`
/// external ids).
struct ChronosHandoffEntry: Codable, Equatable, Sendable {
    /// Stable unique id for deduplication on the ChronosFlow side.
    var id: String
    /// Discriminator: one of `ChronosInteropContract.kindReading` / `kindInbox` / `kindTask`.
    var kind: String
    /// Wall-clock instant (epoch millis) Curio wrote this entry.
    var createdAtEpochMillis: Int64
    var url: String?
    var title: String?
    var text: String?
    var notes: String?
    /// Absolute reminder instant (epoch millis) for "remind me to read later", or nil for none.
    var reminderAtEpochMillis: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAtEpochMillis = "created_at_epoch_ms"
        case url
        case title
        case text
        case notes
        case reminderAtEpochMillis = "reminder_at_epoch_ms"
    }
}
