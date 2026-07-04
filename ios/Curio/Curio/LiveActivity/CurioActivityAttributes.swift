import ActivityKit
import Foundation

// ============================================================================
// Shared Live Activity contract — COMPILED INTO BOTH the Curio app target AND
// the CurioActivityWidget extension (see ios/project.yml). ActivityKit requires
// the attributes/ContentState types to be identical on both sides, so this file
// must stay dependency-free (Foundation + ActivityKit only) — no app-only types.
//
// This is the iOS twin of Android's `com.example.notifications.CurioActivity`:
// Curio shows EXACTLY ONE Live Activity that collapses every concurrent
// background operation (sync, link-sweep, embedding index, digest) into one
// live-updating item, plus a terminal "digest ready" / error state.
// ============================================================================

/// A background/async operation Curio can surface in its single Live Activity.
enum CurioActivityTask: String, Codable, Hashable, Sendable, CaseIterable {
    case sync
    case sweep
    case index
    case digest

    /// Full label for the lock-screen / expanded presentation.
    var label: String {
        switch self {
        case .sync: return "Syncing bookmarks"
        case .sweep: return "Tidying links"
        case .index: return "Building search index"
        case .digest: return "Preparing your digest"
        }
    }

    /// Compact label for the Dynamic Island chip.
    var shortLabel: String {
        switch self {
        case .sync: return "Sync"
        case .sweep: return "Tidy"
        case .index: return "Index"
        case .digest: return "Digest"
        }
    }

    /// SF Symbol used per task in the expanded presentation.
    var symbol: String {
        switch self {
        case .sync: return "arrow.triangle.2.circlepath"
        case .sweep: return "sparkles"
        case .index: return "magnifyingglass"
        case .digest: return "doc.text"
        }
    }
}

/// A momentary state that needs the user's attention; shown in place of the "working" headline.
enum CurioAttention: Codable, Hashable, Sendable {
    case none
    /// The weekly digest finished generating and is ready to read.
    case digestReady(itemCount: Int)
    /// A sync (or handoff) failed; carries a short, human-readable reason.
    case error(message: String)
}

/// The single Live Activity Curio ever runs. It has no static attributes — everything the UI needs
/// lives in the live-updating `ContentState`.
struct CurioActivityAttributes: ActivityAttributes {

    /// The live-updating state pushed to the Live Activity. Mirrors Android's `CurioActivityState`,
    /// including the pure derived/reducer helpers so both the app and the widget compute identically.
    struct ContentState: Codable, Hashable, Sendable {
        /// Running tasks, in insertion order (nicer to render than a set).
        var activeTasks: [CurioActivityTask] = []
        /// Fractional progress (0...1) per task that reports counts, keyed by `task.rawValue`
        /// (dictionaries need String keys to stay `Codable`).
        var progressByTask: [String: Double] = [:]
        var attention: CurioAttention = .none

        // MARK: Derived

        /// Aggregate progress across running tasks, or nil when nothing reports a determinate count.
        var progress: Double? {
            let known = activeTasks.compactMap { progressByTask[$0.rawValue] }
            guard !known.isEmpty else { return nil }
            return min(max(known.reduce(0, +) / Double(known.count), 0), 1)
        }

        /// No running work and nothing awaiting attention → the Live Activity should end.
        var isEmpty: Bool { activeTasks.isEmpty && attention == .none }

        /// True while representing in-progress work (progress ring / bar shown).
        var isOngoing: Bool { !activeTasks.isEmpty && attention == .none }

        /// The headline shown as the Live Activity title.
        var headline: String {
            switch attention {
            case .digestReady:
                return "Your weekly digest is ready"
            case .error:
                return "Sync failed"
            case .none:
                if activeTasks.isEmpty { return "Curio" }
                if activeTasks.count == 1 { return activeTasks[0].label + "…" }
                return "Curio is tidying up…"
            }
        }

        /// Secondary line, or nil when there's nothing useful to add.
        var detail: String? {
            switch attention {
            case let .digestReady(itemCount):
                return "\(itemCount) \(itemCount == 1 ? "save" : "saves") from the last 7 days"
            case let .error(message):
                return message
            case .none:
                return activeTasks.count > 1 ? activeTasks.map(\.label).joined(separator: " · ") : nil
            }
        }

        /// The tiny label the Dynamic Island chip shows: a percentage when known, else the lead task.
        var shortStatus: String {
            if let p = progress { return "\(Int(p * 100))%" }
            return activeTasks.first?.shortLabel ?? "Curio"
        }

        // MARK: Pure reducers (mirror Android CurioActivityState)

        func taskStarted(_ task: CurioActivityTask) -> ContentState {
            guard !activeTasks.contains(task) else { return self }
            var copy = self
            copy.activeTasks.append(task)
            return copy
        }

        func taskProgress(_ task: CurioActivityTask, done: Int, total: Int) -> ContentState {
            guard total > 0 else { return taskStarted(task) }
            var copy = taskStarted(task)
            copy.progressByTask[task.rawValue] = min(max(Double(done) / Double(total), 0), 1)
            return copy
        }

        func taskFinished(_ task: CurioActivityTask) -> ContentState {
            var copy = self
            copy.activeTasks.removeAll { $0 == task }
            copy.progressByTask[task.rawValue] = nil
            return copy
        }

        func withDigestReady(itemCount: Int) -> ContentState {
            var copy = self
            copy.attention = .digestReady(itemCount: itemCount)
            return copy
        }

        func withError(_ message: String) -> ContentState {
            var copy = self
            copy.attention = .error(message: message)
            return copy
        }

        func clearedAttention() -> ContentState {
            var copy = self
            copy.attention = .none
            return copy
        }
    }
}
