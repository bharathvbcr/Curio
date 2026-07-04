import Foundation
import SwiftData
import Testing
@testable import Curio

/// In-memory persistence-layer test covering the query surface added for the checklist
/// (search / byCategory / categories / unenriched) plus upsert + round-trip.
///
/// Port of `app/src/test/java/com/example/BookmarkDaoTest.kt` (JUnit + Robolectric + in-memory
/// Room). The mapping:
/// - `Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)` becomes a `ModelContainer`
///   over the SAME schema the app uses (`Schema([BookmarkModel.self, SpaceModel.self])`, the exact
///   pair `CurioDatabase` builds) with `ModelConfiguration(isStoredInMemoryOnly: true)`.
/// - `db.bookmarkDao()` becomes the `BookmarkStore` `@ModelActor`, instantiated with the in-memory
///   container via its generated `init(modelContainer:)`.
/// - Kotlin `dao.getBookmarks(uid).first()` (first Flow emission) becomes a direct `await` actor
///   read — the store returns the current rows; the hot re-emission lives in the repository layer.
/// - `BookmarkEntity` becomes the domain `Bookmark` (the store converts at the actor boundary);
///   the `entity(...)` factory mirrors the Kotlin one field-for-field, including the
///   `createdAt = id.hashCode().toLong()` default (Java `String.hashCode` reimplemented below so
///   the ordering inputs stay byte-identical).
@Suite("BookmarkStore (mirrors BookmarkDaoTest.kt)")
struct BookmarkStoreTests {

    private let store: BookmarkStore

    private let uid = "u1"

    /// Kotlin `@Before setup()`: fresh in-memory database per test (Swift Testing instantiates the
    /// suite struct — and therefore a fresh container — for every `@Test`). No `@After teardown` is
    /// needed: the in-memory container dies with the suite value.
    init() throws {
        let schema = Schema([BookmarkModel.self, SpaceModel.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        store = BookmarkStore(modelContainer: container)
    }

    /// Java `String.hashCode()` (31-based, overflow-wrapping over UTF-16 units) so the
    /// `createdAt = id.hashCode().toLong()` default matches the Kotlin factory byte-for-byte.
    private static func javaHashCode(_ s: String) -> Int32 {
        var hash: Int32 = 0
        for unit in s.utf16 {
            hash = 31 &* hash &+ Int32(unit)
        }
        return hash
    }

    /// Mirrors the Kotlin `entity(...)` factory (defaults included). `text` uses a nil sentinel
    /// because a Swift default argument cannot reference another parameter (`"text $id"`).
    private func entity(
        _ id: String,
        text: String? = nil,
        category: String? = nil,
        summary: String? = nil,
        ocrText: String? = nil,
        isAnalyzed: Bool = false,
        createdAt: Int64? = nil
    ) -> Bookmark {
        Bookmark(
            id: id,
            text: text ?? "text \(id)",
            createdAt: createdAt ?? Int64(Self.javaHashCode(id)),
            userId: uid,
            summary: summary,
            category: category,
            ocrText: ocrText,
            isAnalyzed: isAnalyzed
        )
    }

    /// Kotlin: `upsert and observe round-trip`. Upsert (REPLACE) updates the existing row rather
    /// than duplicating — the store's fetch-by-unique-`id`-then-overwrite path.
    @Test("upsert and observe round-trip")
    func upsertAndObserveRoundTrip() async {
        await store.insertBookmarks([entity("1"), entity("2")])
        // Upsert (REPLACE) updates the existing row rather than duplicating.
        await store.insertBookmarks([entity("1", text: "updated")])
        let all = await store.getBookmarks(userId: uid)
        #expect(all.count == 2)
        #expect(all.first(where: { $0.id == "1" })?.text == "updated")
    }

    /// Kotlin: `search matches text, ocr and summary`.
    @Test("search matches text, ocr and summary")
    func searchMatchesTextOcrAndSummary() async {
        await store.insertBookmarks([
            entity("1", text: "Mamba selective state spaces"),
            entity("2", text: "unrelated", ocrText: "FlashAttention kernel"),
            entity("3", text: "unrelated", summary: "About PagedAttention serving")
        ])
        #expect(await store.search(userId: uid, query: "Mamba").map(\.id) == ["1"])
        #expect(await store.search(userId: uid, query: "FlashAttention").map(\.id) == ["2"])
        #expect(await store.search(userId: uid, query: "PagedAttention").map(\.id) == ["3"])
    }

    /// Kotlin: `byCategory and categories`.
    @Test("byCategory and categories")
    func byCategoryAndCategories() async {
        await store.insertBookmarks([
            entity("1", category: "training"),
            entity("2", category: "training"),
            entity("3", category: "inference-opt"),
            entity("4", category: nil)
        ])
        #expect(await store.byCategory(userId: uid, category: "training").count == 2)
        #expect(await store.categories(userId: uid) == ["inference-opt", "training"])
    }

    /// Kotlin: `unenriched returns only un-analyzed or un-summarized`.
    @Test("unenriched returns only un-analyzed or un-summarized")
    func unenrichedReturnsOnlyUnAnalyzedOrUnSummarized() async {
        await store.insertBookmarks([
            entity("1", summary: "done", isAnalyzed: true),
            entity("2", isAnalyzed: false),
            entity("3", summary: nil, isAnalyzed: true)
        ])
        let ids = Set(await store.unenriched(userId: uid).map(\.id))
        #expect(ids == Set(["2", "3"]))
        #expect(!ids.contains("1"))
    }
}
