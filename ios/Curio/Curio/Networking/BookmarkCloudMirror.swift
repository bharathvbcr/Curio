import Foundation

/// Best-effort cloud mirror for bookmarks. Firestore is one implementation; the Mac
/// target ships a no-op because that mirror is keyed by a per-device anonymous uid
/// and is not a cross-device library.
protocol BookmarkCloudMirror: Sendable {
    func pushBookmark(userId: String, bookmark: Bookmark) async
    func pushBookmarks(userId: String, bookmarks: [Bookmark]) async
    func pullBookmarks(userId: String) async -> [Bookmark]
    func deleteBookmarks(ids: [String]) async
}

/// Used when Firebase is not linked (the Mac target). Every call succeeds as an empty mirror.
struct NoOpBookmarkCloudMirror: BookmarkCloudMirror {
    func pushBookmark(userId: String, bookmark: Bookmark) async {}
    func pushBookmarks(userId: String, bookmarks: [Bookmark]) async {}
    func pullBookmarks(userId: String) async -> [Bookmark] { [] }
    func deleteBookmarks(ids: [String]) async {}
}
