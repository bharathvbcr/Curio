# Curio iOS — DESIGN

Full-parity native iOS 26 SwiftUI port of the Curio Android app (X-bookmarks research index; dual AI = offline keyword classifier + xAI Grok; Vision OCR; on-device embeddings RAG; BibTeX/JSON/CSV/RIS/CSL export; App Intents; BGTaskScheduler background sync; OAuth2 PKCE via ASWebAuthenticationSession; Keychain/CryptoKit token store; Firestore via Firebase-iOS SPM; Liquid Glass UI).

- **Target:** iOS 26+, latest SDK, Swift 6 strict concurrency.
- **Root:** every module is a folder under `ios/Curio/Curio/`.
- **Companion doc:** `CONVENTIONS.md` (DI, error enums, `@Observable` VM pattern, concurrency rules, theme tokens, SwiftData `@Model` rules, DTO↔domain mapping). The two are mutually consistent; this doc references conventions by name.

Implementers write Swift from **this doc + the original Android file only**. Each file row gives: Swift file → responsibility → Android source(s) ported → key types/functions.

---

## Top-level tech mapping (Android lib → iOS framework)

| Android lib / concept | iOS framework / API | Notes |
|---|---|---|
| Room (`@Database`, `@Entity`, `@Dao`, migrations) | **SwiftData** (`@Model`, `ModelContainer`, `#Index`, `FetchDescriptor`, `SchemaMigrationPlan`) | Default. Store file `curio_database` in Application Support. `@ModelActor` for background writes. GRDB is the documented fidelity fallback for exact LIKE/COLLATE NOCASE/atomic-increment SQL — not used unless a predicate cannot be expressed. |
| Kotlin `Flow` (Room live queries) | `AsyncStream` / Combine `AnyPublisher` / SwiftData `@Query` | Repository-level reactivity via an `AsyncStream` fed by SwiftData change tracking; SwiftUI views may also use `@Query`. Hot/continuous, re-emit on every DB change. |
| Kotlin `suspend` + `Result<T>` | `async throws` (Result collapses to throwing) | Plain `suspend` (no Result) → `async` (no throws). See CONVENTIONS §Concurrency. |
| Retrofit + Moshi + OkHttp | **URLSession** (`async/await`) + `Codable` + `URLComponents` | One protocol per API, backed by an `actor`. `encodeIfPresent` everywhere to mirror Moshi null-omission. Two `URLSessionConfiguration`s (primary 120s read, metadata 15s). |
| Koin DI (constructor + `by viewModel()`) | Manual `AppEnvironment` container (`@Observable`), constructor injection, `.environment(_:)` | No DI lib. ViewModels built by factory methods on the container. App Intents use `@Dependency` + `AppDependencyManager`. |
| AndroidKeyStore AES-GCM + DataStore | **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) + CryptoKit `AES.GCM` (optional envelope) | Path A (direct Keychain) recommended; Path B (CryptoKit envelope) only for Android-backup interop. |
| Gemini Nano via AICore (on-device text) | **Foundation Models** (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`) | Availability gate replaces reflective AICore probe. Degrades to offline keyword classifier / cloud. |
| ML Kit GenAI FeatureStatus | `SystemLanguageModel.availability` | `.available`→AVAILABLE; `.unavailable(...)`→other states. |
| EmbeddingGemma LiteRT (`GeckoEmbeddingModel`) | **Core ML** `MLModel`/`MLTensor` (CPU compute units) OR `NLContextualEmbedding` | Convert `.tflite`→`.mlpackage`. Serialize inference behind an `actor`. CPU only (GPU emits zero vectors unless FP32). |
| ML Kit Latin text recognition | **Vision** `RecognizeTextRequest` (iOS 18+ async) | `.accurate`, languages `[en]`. Never throws — returns fallback strings. |
| Chrome Custom Tabs (OAuth) | **ASWebAuthenticationSession** | Callback scheme = registered redirect URI. Validates state. |
| WorkManager (`PeriodicWorkRequest`, constraints) | **BGTaskScheduler** (`BGProcessingTaskRequest`) | `requiresExternalPower`=charging. No true periodic — self-resubmit at end of run (de-dupes by identifier = KEEP semantics). |
| Foreground `Service` (6h URL sweep) | `BGProcessingTaskRequest` (`requiresNetworkConnectivity`) | iOS has no indefinite foreground service; self-reschedule earliestBeginDate=+6h. |
| AppFunctions (`@AppFunctionSerializable`, allowlist) | **App Intents** (`AppIntent`, `AppEntity`, `@Dependency`, `authenticationPolicy`) | Caller allowlist not portable → `.requiresAuthentication` on write/detail intents; search/export discoverable. |
| Firebase Firestore (Android SDK) | **FirebaseFirestore** (firebase-ios-sdk via SPM) | Native `async/await` (`setData(merge:)`, `getDocuments()`, `batch.commit()`), wrapped in an `actor`. `GoogleService-Info.plist`. |
| `org.json` JSONObject/JSONArray | `JSONSerialization` (lenient) or `Codable` | For tolerant parsers (SpaceRules, sourceExtra, Crossref) use `JSONSerialization` + optional chaining. |
| Java `Regex` / `Pattern` | Swift `Regex` / `NSRegularExpression` | Keep patterns byte-identical. |
| `java.time.Instant` / RFC3339 | `ISO8601DateFormatter` (`.withFractionalSeconds`) | Returns 0 on failure (epoch millis). |
| `Calendar` (year from epoch) | `Calendar.current.component(.year,...)` | >1e12 = ms else seconds heuristic preserved. |
| Compose `GlassScaffold` + Haze blur | iOS 26 **Liquid Glass** (`.glassEffect`, `GlassEffectContainer`) | Native glass samples backdrop automatically — Haze machinery dropped. Solid tier = Reduce Transparency fallback. |
| Material3 ColorScheme + Material You | Custom `CurioColorScheme` (`@Environment`) | No dynamic color on iOS; static Cosmic palette is canonical. |
| Compose `Modifier.pressBounce`/`bounceScale` | `ButtonStyle` + `.scaleEffect`/`.sensoryFeedback` | One shared `CurioPressBounceStyle`. |
| `ByteArray` (embedding blob) | `Data` (explicit little-endian Float32) | `@Attribute(.externalStorage)`. |
| `Long` (epoch millis / ARGB color) | `Int64` | createdAt is ms and the reorder key. ARGB→`Color` only at UI boundary. |
| `PhotosPicker` for OCR image | **PhotosUI** `PhotosPicker` | Replaces `GetContent()`. |
| Clipboard / Share / Open URL | `UIPasteboard`, `ShareLink`/`UIActivityViewController`, `openURL`/`UIApplication.open` | Toasts → transient SwiftUI overlay. |
| Android share-receive (ACTION_SEND) | **Share Extension** + App Group + `NSItemProvider.loadTransferable` | Queue to App-Group `UserDefaults`; main app drains on `.active`. |

---

## Feature-parity checklist (ALL Android features)

- [ ] X OAuth2 **PKCE** login (verifier/challenge S256, state CSRF, scope `tweet.read users.read bookmark.read offline.access`), browser handoff, redirect validation, token refresh rotation.
- [ ] X **bookmarks sync**: 3-phase (Firebase pull → X paginated fetch → Firebase push); cursor "load more"; per-page durability; 401 refresh; 429 rate-limit countdown; merge-bias asymmetry (cloud=fresh, X=local-wins); X-authoritative result precedence.
- [ ] Bookmark **CRUD**: manual add (`manual_` prefix), delete, search (keyword across 4 fields, COLLATE-NOCASE semantics), reorder via atomic `swapCreatedAt`.
- [ ] **AI analysis** (summary/tags/category/entities) with backend selection: on-device (Foundation Models) → cloud xAI → offline keyword; image→vision (cloud); LanguageGate (EN/JA/KO, ≤3000 words).
- [ ] **OCR** (Vision) from picked image; scheduled flag; fallback strings.
- [ ] **Primary-source resolution** (arXiv Atom XML / GitHub / HuggingFace / Crossref DOI) with fixed priority + dedupe-on-resolve + reference counting.
- [ ] **Deep analysis** (deepSummary, isDeepAnalyzed).
- [ ] **On-device embeddings RAG**: EmbeddingGemma download manager (gated, ~180MB, HF token); shared `EmbeddingText` assembly/chunk/mean-pool; on-device + cloud providers + selector; cosine top-K vector search; little-endian blob serialization; charging-gated backfill.
- [ ] **Spaces**: CRUD, pin, sort, color/icon, count (derived); assign/unfile; no FK cascade (manual clearSpace).
- [ ] **Smart Spaces**: rule builder (field/op/value, ANY/ALL, autoFile), case-insensitive matching, `fileByRules` (first auto-file match, unfiled only), `applySpaceRules` (ignores autoFile), `applyRulesToLibrary`, JSON `m/a/r`+`f/o/v` wire format (byte-compatible).
- [ ] **Category→Space seeding** (`CategorySpaces.forCategory`, `ensureCategorySpace`, `backfillCategorySpaces`); category never surfaces in UI.
- [ ] **Curation**: favorite, save-for-later, notes (local-only, blank clears).
- [ ] **Chat (RAG)**: grounding sources (Library/Web/X/News), Live Search params, query embedding→top-K context, citation strip, prompt builder, markdown render.
- [ ] **Weekly AI Digest** (7-day window, ≤40 items, state machine).
- [ ] **Rediscover** (older un-starred, 14-day min, batch 3, shuffle).
- [ ] **Insights** dashboard (stats, curated %, distribution bars, hot topics).
- [ ] **Export**: BibTeX (+single), RIS, CSL-JSON, Markdown, JSON backup, CSV backup — all byte-faithful (LaTeX escape, cite keys, RIS tag spacing).
- [ ] **Grok image generation** (with procedural fallback).
- [ ] **xAI key** management (Keychain, async-configured gate → forceLocal).
- [ ] **App Intents** (6): search/add/detail/note/favorite/exportCitation + 2 AppEntities.
- [ ] **Background**: link sweep (404/410 only), charging embedding backfill, scheduler (index-while-charging pref).
- [ ] **Share-in** ingestion (queue when signed out, flush on login).
- [ ] **Liquid Glass UI**: feed, chat, insights, spaces, reader, settings, login; glass tiers; press/selection springs; theme (system/light/dark); accessibility (Reduce Transparency/Motion).
- [ ] **Secrets/log hygiene**: never log Authorization or bodies; secrets in Keychain only.
- [ ] **Privacy rule**: no cloud AI/enrichment in background — maintenance + on-device embedding only.

---

# Modules

Dependency order (low→high): **Domain → Persistence → Networking → Auth → AI → Intelligence → Repository → Theme → Components → Screens → Platform → App**. (Networking/Auth are siblings; Repository depends on Persistence+Networking+AI+Intelligence.)

---

## 1. Domain — `ios/Curio/Curio/Domain`

Pure Foundation-only core: value models, enums (String raw == Kotlin `.name`), repository protocols (`async throws` / `AnyPublisher`), one use case, and the only behavior-bearing file `SpaceRule` (matching + tolerant JSON). No Apple framework beyond Foundation.

**dependsOn:** (none)

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `Bookmark.swift` | Central aggregate value model (AI/OCR/source/entities/deep/curation/space fields). UI must never display `category`. | `domain/model/Bookmark.kt` | `struct Bookmark: Identifiable, Hashable, Codable, Sendable`; all fields exact names/nullability; `tags: [String] = []`; `createdAt: Int64` (epoch ms, sort key); `referenceCount: Int = 1`; explicit memberwise init with Kotlin defaults; opaque `entities/sourceExtra/deepSummary: String?`. |
| `SourceType.swift` | Source enum; rawValue == Kotlin `.name`. | `domain/model/Bookmark.kt` (SourceType) | `enum SourceType: String, Codable, Sendable { case ARXIV, GITHUB, HUGGING_FACE, TWEET, DOI }`. |
| `Space.swift` | User collection; promotable to Smart Space. | `domain/model/Space.kt` | `struct Space: Identifiable, Hashable, Sendable`; `color: Int64` (ARGB), `createdAt: Int64`, `count: Int = 0` (derived/transient), `description = ""`, `isPinned = false`, `sortIndex = 0`, `rules: SpaceRules = .empty`; computed `var isSmart: Bool { rules.isActive }`. |
| `SpaceRule.swift` | Smart-Space rules, case-insensitive matching engine, tolerant JSON (short keys). | `domain/model/SpaceRule.kt` | `enum RuleField: String { KEYWORD,TAG,CATEGORY,SOURCE,AUTHOR,URL; var label }`; `enum RuleOp: String {CONTAINS,EQUALS,STARTS_WITH; label}`; `enum RuleMatch: String {ANY,ALL}`; `struct SpaceRule { field,op,value; func matches(_:Bookmark)->Bool; private func test }`; `struct SpaceRules { match=.ANY, autoFile=true, rules=[]; var effective; var isActive; func matches; func toJson()->String; static func fromJson(_:String?)->SpaceRules; static let empty }`. Manual `JSONSerialization` encode/decode (keys `m/a/r`,`f/o/v`); never throws; STARTS_WITH lowercases both sides. |
| `CategorySpaces.swift` | Static AI-category→default-Space lookup (10 entries) + fabricating fallback. | `domain/model/CategorySpaces.kt` | `struct CategorySpaceMeta: Hashable, Sendable { name; color: Int64; icon }`; `enum CategorySpaces { static let defaults: [String:CategorySpaceMeta]; static func forCategory(_:String)->CategorySpaceMeta }`. Replicate trim+lowercase, split on `[-_ ]`, title-case, fallback name `Uncategorized`, color `0xFF607D8B`, icon `label`. |
| `AuthModels.swift` | Auth state machine + PKCE challenge payload. | `domain/model/Models.kt` | `enum AuthState: Equatable, Sendable { case signedOut; case signingIn; case signedIn(userId:String, username:String?=nil, name:String?=nil) }`; `struct AuthChallenge: Sendable { authorizationUrl; codeVerifier; state }`. (No AppError here.) |
| `AuthRepository.swift` | Auth lifecycle protocol. | `domain/repo/AuthRepository.kt` | `protocol AuthRepository: Sendable { func authState() -> AnyPublisher<AuthState,Never>; func beginLogin() async throws -> AuthChallenge; func completeLogin(code:String, codeVerifier:String) async throws; func currentUserId() async -> String?; func logout() async }`. |
| `BookmarkRepository.swift` | Full bookmark + Space lifecycle protocol (reads/sync/CRUD/analysis/source/embeddings/deep/curation/spaces/smart-spaces). | `domain/repo/BookmarkRepository.kt` | `protocol BookmarkRepository: Sendable` — flows→`AnyPublisher<[Bookmark],Never>`/`[Space]`; every `suspend`→`async`, every `Result<T>`→`async throws -> T`; default params preserved; `ByteArray`→`Data`; `[(String,Data)]` for bulk embeddings. Doc-comment the contracts: `swapCreatedAt`/bulk-embeddings single transaction; `fileByRules` first-match/unfiled-only; `applySpaceRules` ignores autoFile; backfills idempotent. |
| `LoginUseCase.swift` | Stateless pass-through to AuthRepository. | `domain/usecase/LoginUseCase.kt` | `struct LoginUseCase { let authRepository: AuthRepository; func beginLogin() async throws -> AuthChallenge; func completeLogin(code:,codeVerifier:) async throws }`. |
| `CurioError.swift` | Root sealed error + cross-domain error glue (see CONVENTIONS §Errors). | (new; consolidates `RateLimitException` concept) | `enum CurioError: Error`; `struct RateLimitError: Error { let resetTimeSeconds: Int64 }`. Per-domain enums live in their modules but conform to a shared protocol. |

**Cross-cutting invariants (preserve):** persistence-key stability (enum rawValues uppercase; JSON short keys); case-insensitivity in matching; draft-rule semantics (blank value never matches but `toJson` serializes ALL incl. drafts); tolerant `fromJson` (`.empty` on nil/blank/error, skip malformed elements); Result→throws vs plain async; ARGB `Int64` until UI; `createdAt` ms + reorder key.

---

## 2. Persistence — `ios/Curio/Curio/Persistence`

SwiftData layer: one container (`curio_database`), two `@Model`s, repository **actors** mirroring Room DAOs, migration plan. Empty/null sentinels and transactional atomicity preserved.

**dependsOn:** Domain

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `CurioDatabase.swift` | Single `ModelContainer` singleton; store in Application Support named `curio_database`; migration plan; DEBUG destructive fallback / RELEASE fatalError. | `data/local/AppDatabase.kt` | `final class CurioDatabase { static let shared; let container: ModelContainer }`. `Schema([BookmarkModel.self, SpaceModel.self])`, `ModelConfiguration(url:)`. `#if DEBUG` delete-store-and-rebuild on incompatible store; RELEASE propagate. |
| `CurioMigrationPlan.swift` | `SchemaMigrationPlan` mirroring Room v6→v11 (additive cols + index declarations). | `data/local/AppDatabase.kt` (MIGRATION_6_7…10_11) | `enum SchemaV6…V11: VersionedSchema`; `enum CurioMigrationPlan: SchemaMigrationPlan`; lightweight stages; indices declared on final models (no raw CREATE INDEX). Preserve defaults (`description=""`, `isPinned=false`, `sortIndex=0`, `rulesJson=""`, `spaceId=nil`, `notes=nil`). |
| `BookmarkModel.swift` | `@Model` for `bookmarks` table; 6 composite indices; identity by id. | `data/local/BookmarkEntity.kt` | `@Model final class BookmarkModel`; `@Attribute(.unique) var id`; `tags` stays CSV `String?` (do NOT model `[String]`); `embedding: Data?` (`@Attribute(.externalStorage)`); `#Index<BookmarkModel>([\.userId,\.createdAt],[\.userId,\.sourceId],[\.spaceId],[\.userId,\.category],[\.isAnalyzed],[\.userId,\.isAnalyzed])`; `Identifiable`/`==` by id. |
| `SpaceModel.swift` | `@Model` for `spaces` table. | `data/local/SpaceEntity.kt` | `@Model final class SpaceModel`; `@Attribute(.unique) var id`; `colorValue: Int64` (packed ARGB, kept exact); `iconKey: String`; `rulesJson: String = ""` (empty-string sentinel, NOT optional); `#Index<SpaceModel>([\.userId])`. |
| `BookmarkStore.swift` | `@ModelActor` mirroring every `BookmarkDao` method (reactive→AsyncStream, writes→save). | `data/local/BookmarkDao.kt` | `@ModelActor actor BookmarkStore`. Methods: `getBookmarks`, `observeAll`, `search` (case-insensitive 4-field OR, ASCII semantics — `FetchDescriptor`+closure filter), `byCategory`, `categories` (fetch non-nil→Set→sort), `unenriched` (`summary == nil \|\| summary == ""`), `insertBookmarks` (upsert by unique id), `clearBookmarks`, `getBookmarkById`, `getBookmarkBySourceId`, `updateAnalysis`, `updateOcr`, `deleteBookmarks` (`ids.contains`), `updateCategoryForIds`, `updateSpaceForIds`, `clearSpace`, `updateCreatedAt`, `swapCreatedAt` (both mutations + ONE save), `updateSourceInfo`, `incrementReferenceCount` (fetch+increment+save), `updateEmbedding`, `updateEmbeddings`/`batchUpdateEmbeddings` (ONE save), `getIdsAndEmbeddings` (`propertiesToFetch:[\.id,\.embedding]`→`IdEmbeddingRow`), `getUnembedded` (`fetchLimit=200`), `getUnfiledBookmarks` (`spaceId==nil\|\|""`), `clearAllEmbeddings`, `updateDeepSummary`, `updateFavorite`, `updateSavedForLater`, `updateNotes`. `struct IdEmbeddingRow { id; embedding: Data? }`. |
| `SpaceStore.swift` | `@ModelActor` mirroring `SpaceDao`. | `data/local/SpaceDao.kt` | `@ModelActor actor SpaceStore`; `getSpaces`/`getSpacesDirect` (sort `[isPinned .reverse, sortIndex .forward, createdAt .reverse]`), `upsertSpace`, `deleteSpace` (NO cascade), `getSpaceById`, `setPinned`, `setSortIndex`. |
| `ModelMappers.swift` | `BookmarkModel`↔`Bookmark`, `SpaceModel`↔`Space` (`rules()` via `SpaceRules.fromJson`). | (cross-cutting in DAO/Repo) | `func toDomain() -> Bookmark/Space`; `func apply(_ domain:)`; tags CSV split/join; `count` filled by query. See CONVENTIONS §DTO mapping. |

**Cross-cutting (preserve):** actor serialization replaces Mutex/ConcurrentHashMap; ONE `save()` for atomic batches; REPLACE upsert (whole-row); userId scoping vs device-wide sweeps; no FK cascade (manual `clearSpace`); ASCII case-insensitive search (not `localizedStandardContains`); `'' vs nil` sentinels kept distinct; opaque little-endian embedding blob; `createdAt` dual-purpose.

---

## 3. Networking — `ios/Curio/Curio/Networking`

URLSession+Codable port of the xAI Grok contract, X bookmarks/auth APIs, scholarly clients (arXiv/Crossref/GitHub/HF), and Firestore sync. Per-call `Bearer` headers; Moshi null-omission via `encodeIfPresent`; hand-rolled retry/backoff.

**dependsOn:** Domain

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `HTTPClient.swift` | Shared URLSession layer; two configs (primary 120s, metadata 15s); status/header helpers; never logs Authorization/bodies. | `di/AppContainer.kt` (OkHttp/Retrofit wiring) | `actor HTTPClient`; `func send<T:Decodable>(...)`; `APIError` `enum { case http(Int, headers:[String:String]); case transport(URLError); case decoding(Error) }`; redacting logger. |
| `JSONValue.swift` | `AnyCodable`/`JSONValue` for raw JSON-Schema `Map<String,Any?>` fields. | `data/remote/XAiApi.kt` (schema/params maps) | `enum JSONValue: Codable` encodable as raw JSON object. |
| `GrokModels.swift` | Model-id/reasoning/search-mode constant registry. | `data/remote/GrokModels.kt` | `enum GrokModels { static let flagship="grok-4.3"; analysis/deepAnalysis/chat/vision=flagship; embedding="grok-embedding-small" }`; `GrokReasoning`, `GrokSearchMode` caseless namespaces. |
| `XAiDTOs.swift` | All xAI Codable DTOs (chat/vision/search/tools/embeddings/image) w/ CodingKeys + `encodeIfPresent`. | `data/remote/XAiApi.kt` | `XAiMessage`, `XAiContentPart`(+`.text`/`.image`), `XAiVisionMessage/Request`, `XAiJsonSchema`, `XAiResponseFormat`, `XAiFunctionDef`, `XAiTool`(+`webSearch`/`xSearch`/`function`), `XAiToolFunctionCall`(`arguments:String`), `XAiToolCall`, `XAiSearchSource`(+`web/x/news/rss`), `XAiSearchParameters`(mode=.auto, returnCitations=true), `XAiRequest`, `XAiUsage`(+details), `XAiChoice`, `XAiResponse`(top-level `citations:[String]?`), `XAiEmbeddingRequest/Data/Response`, `XAiImageRequest/Data/Response`. |
| `XAiApi.swift` | xAI endpoints (chat/vision/embeddings/images) actor. | `data/remote/XAiApi.kt` (interface) | `protocol XAiApi`; `actor XAiApiClient`; `chatCompletions`/`visionCompletions`/`createEmbeddings`/`generateImages` — POST to `https://api.x.ai/v1/...`, `Authorization: <Bearer key>` passed per-call. |
| `XAiAnalyzer.swift` | Cloud bookmark analysis + image vision + chat response + weekly digest generation (consumes XAiApi). | (referenced by `data/ai/*`, repo) | `final class XAiAnalyzer`; `func analyzeBookmark`, `analyzeImageBookmark`, `generateChatResponse(contextPrompt:systemInstruction:searchParameters:)`, `generateWeeklyDigest(_:count:)`. `AnalysisResult`/`AnalysisConfig` structs. |
| `XBookmarksDTOs.swift` | X v2 bookmarks DTOs (note_tweet, url entities, media/users includes, meta). | `data/remote/XBookmarksApi.kt` | `BookmarkDto`, `NoteTweetDto`, `UrlEntityDto`, `TweetEntitiesDto`, `MediaDto`, `UserDto`, `BookmarksIncludesDto`, `BookmarksMetaDto`, `BookmarksResponse`. CodingKeys for snake_case. |
| `XBookmarksApi.swift` | Paginated bookmarks GET with fixed expansions/fields. | `data/remote/XBookmarksApi.kt` (interface) | `actor XBookmarksApiClient`; `getBookmarks(...)` → `https://api.twitter.com/2/users/{id}/bookmarks` with exact `tweet.fields`/`expansions`/`media.fields`/`user.fields` constants. |
| `XAuthDTOs.swift` | Token + /users/me DTOs. | `data/remote/XAuthStructures.kt` | `TokenResponse`, `UserResponse`, `UserData`. |
| `XAuthApi.swift` | OAuth token exchange/refresh (form-urlencoded) + getUserMe. | `data/remote/XAuthStructures.kt` (interface) | `actor XAuthApiClient`; `exchangeToken`, `refreshToken` (`application/x-www-form-urlencoded` body), `getUserMe`. base `https://api.twitter.com/`. |
| `ArxivClient.swift` | arXiv Atom XML fetch + XMLParser state machine + 503 retry + ID regexes. | `data/remote/ArxivClient.kt` | `struct ArxivMeta`; `actor ArxivClient`; `fetchPaper(_:) async -> ArxivMeta?`; `XMLParserDelegate` (inEntry/inAuthor/tagStack); retry 3× (503→2000ms*(n+1), other→1000ms*(n+1)); `static let ARXIV_ID_REGEX`, `ARXIV_BARE_REGEX`. Rethrow `CancellationError`. |
| `CrossrefClient.swift` | DOI→metadata; JATS strip; polite User-Agent; date assembly. | `data/remote/CrossrefClient.kt` | `struct CrossrefMeta`; `actor CrossrefClient`; `fetchWork(_:) async -> CrossrefMeta?`; exact `User-Agent`; `JSONSerialization` lenient nav; `extractPublished` via `String(format:"%04d-%02d-%02d")`; `DOI_REGEX`. |
| `GithubApi.swift` | GitHub repo metadata (fixed headers). | `data/remote/GithubApi.kt` | `GithubRepoResponse` (`stars` default 0, `topics` default []), `GithubOwner`; `actor GithubApiClient`; `getRepo(owner:repo:)` GET `https://api.github.com/repos/...` + `Accept`/`X-GitHub-Api-Version` headers. |
| `HuggingFaceApi.swift` | HF model/dataset metadata; 404→nil; non-encoded slash path. | `data/remote/HuggingFaceApi.kt` | `HfModelResponse`/`HfDatasetResponse` (tags default []); `actor HuggingFaceApiClient`; `getModel`/`getDataset` GET `https://huggingface.co/api/models|datasets/{id}` (id slashes NOT encoded), 404→nil. |
| `FirebaseSyncManager.swift` | Anonymous-auth-gated push/pull/delete; 500/batch; minimal-push vs richer-pull; serverTimestamp; 15s timeouts. | `data/remote/FirebaseSyncManager.kt` | `actor FirebaseSyncManager`; `FirebaseApp.configure()`; `ensureAuthenticated() async -> Bool`; `userBookmarks(userId:)` path; `buildMinimalMap`; `pushBookmark`/`pushBookmarks` (chunk 500, `setData(merge:)`); `pullBookmarks` (full mapping, CSV tags, `SourceType(rawValue:)` guarded, defaults); `deleteBookmarks` (chunk 500). |

**Cross-cutting (preserve):** per-call `Bearer` header (not interceptor); Moshi null-omission → `encodeIfPresent`; `citations` top-level; `arguments` is JSON string; hand-rolled retry delays; rethrow cancellation; resilient (log+nil/empty) except auth completeLogin; TokenStore `clear()` keeps HF+xAI; Firestore anonymous-auth gate + path-scoped + minimal/rich asymmetry + 500 chunking; embedding endpoint best-effort (nil-tolerant); authorize host `twitter.com` exact.

---

## 4. Auth — `ios/Curio/Curio/Auth`

PKCE handshake driver + session state + Keychain token store. ASWebAuthenticationSession replaces Custom Tabs.

**dependsOn:** Domain, Networking

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `TokenStore.swift` | Keychain-backed secure store; observable identity; semantics (clear keeps HF+xAI; blank xAI deletes; nil username/name removes). | `data/remote/TokenStore.kt` | `actor TokenStore`; Path A Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); `userIdSubject`/`usernameSubject`/`nameSubject` (`CurrentValueSubject` → publishers); `getUserId`, `hasTokens`, `getAccessToken`/`getRefreshToken`, `saveTokens`, `get/saveHuggingFaceToken`, `get/saveXaiKey` (blank deletes), `clear()` (X-session only). Account strings mirror Android keys (`access_token_surface`, …). |
| `XaiKeyStore.swift` | Runtime xAI key resolver + configured check. | (referenced by `EmbeddingService`, VM) | `struct XaiKeyStore`; `resolve()`/`isConfigured()` (non-empty && != `MY_XAI_API_KEY`); reads TokenStore + build-time secret. |
| `PKCE.swift` | Verifier/challenge (S256) via CryptoKit. | `data/repo/AuthRepositoryImpl.kt` (generate*) | `enum PKCE { static func makeCodeVerifier() -> String; static func codeChallengeS256(for:) -> String }`; 32 secure-random bytes → base64url (no pad); SHA256(ASCII). |
| `WebAuthSession.swift` | ASWebAuthenticationSession wrapper (presentation anchor, ephemeral, callback scheme). | (replaces Custom Tabs handoff) | `final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding`; `func authenticate(url:callbackScheme:) async throws -> URL`; retain session strong-ref; `.canceledLogin` detection. |
| `AuthRepositoryImpl.swift` | Drives PKCE flow; owns `AuthState` subject; boot restore; build authorize URL; exchange; persist; logout. | `data/repo/AuthRepositoryImpl.kt` | `final class AuthRepositoryImpl: AuthRepository`; `CurrentValueSubject<AuthState,Never>` (initial `.signedOut`); boot `Task` restore (off main); `beginLogin` builds authorize URL (host `twitter.com`, scope spaces→%20, S256); `completeLogin` via XAuthApi; `currentUserId`; `logout`. Config via `CurioConfig` (CLIENT_ID/X_CLIENT_ID fallback, X_REDIRECT_URI). |
| `AuthError.swift` | Per-domain auth errors. | (new) | `enum AuthError: Error, LocalizedError { case stateMismatch, cancelled, missingCode, exchangeFailed(Error) }`. |

**Cross-cutting (preserve):** session refresh single-use/rotated (serialize via actor, re-read stored token, persist rotated refresh); PKCE scope string incl. `offline.access`; state CSRF validation in presentation layer; secrets only in Keychain; boot restore off main actor.

---

## 5. AI — `ios/Curio/Curio/AI`

Backend-selection chain (on-device Foundation Models / cloud xAI / offline keyword), language gate, prompt builder.

**dependsOn:** Domain, Networking

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `TextGenerator.swift` | Provider protocol + cloud/local/on-device backends + selector. | `data/ai/TextGenerator.kt` | `protocol TextGenerator { var name:String { get }; func analyze(text:,ocrText:,sourceAbstract:,imageUrl:) async throws -> AnalysisResult }`; `CloudTextGenerator`, `LocalKeywordTextGenerator`, `OnDeviceTextGenerator` (Foundation Models; `enum NanoUnavailable: Error`), `TextGeneratorSelector` (forceLocal→local; image→cloud; on-device gated→try then catch→cloud). |
| `GenAiAvailability.swift` | On-device availability gate (Foundation Models). | `data/ai/TextGenerator.kt` (GenAiAvailability, FeatureStatus) | `struct GenAiAvailability { func status() -> FeatureStatus; func isNanoUsable() -> Bool }` via `SystemLanguageModel.default.availability`; `enum FeatureStatus { UNAVAILABLE, DOWNLOADABLE, DOWNLOADING, AVAILABLE }`. |
| `LanguageGate.swift` | EN/JA/KO + ≤3000-word gate via unicode-scalar counting. | `data/ai/TextGenerator.kt` (LanguageGate) | `enum LanguageGate { static let MAX_WORDS=3000; enum Lang {EN,JA,KO,OTHER}; static func detect(_:)->Lang; static func isSupported(_:)->Bool; static func withinCap(_:)->Bool }`. Same hex ranges (hangul/kana/latin). |
| `ChatPromptBuilder.swift` | Assemble (contextPrompt, systemInstruction, searchParameters) triple. | `data/ai/ChatPromptBuilder.kt` | `enum ChatPromptBuilder { struct Parts { contextPrompt; systemInstruction; searchParameters: XAiSearchParameters? }; static func build(userQuery:contextItems:useLibrary:liveSourceApiTypes:liveLabels:) -> Parts }`. `compactMap` sources; `prefix(4)` tags; `prefix(200)` deep; mode `.on`, maxSearchResults 12. |

**Cross-cutting (preserve):** image→cloud precedes on-device gate; on-device failure silently→cloud (caught in selector); identical EmbeddingText not here but referenced; AnalysisResult/Config structs shared.

---

## 6. Intelligence — `ios/Curio/Curio/Intelligence`

Embeddings (download manager + providers + selector + cloud), OCR (Vision), vector math, source resolver, exporter. (Embeddings + OCR + RAG math + source resolution + citation export grouped per brief.)

**dependsOn:** Domain, Networking, Auth (XaiKeyStore)

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `EmbeddingModelManager.swift` | Download/manage on-device EmbeddingGemma (~180MB, gated, HF token); `@Observable` state; Application Support; size-floor sanity; tokenizer-first. | `data/embedding/EmbeddingModelManager.kt` | `@Observable final class EmbeddingModelManager`; `enum ModelState { absent; downloading(fraction:Double,label:String); ready; failed(String) }`; `download(overrideToken:) async -> Bool` (`URLSession.bytes`, `.part`→atomic move); token order (pasted>saved>build>none); `MIN_MODEL_BYTES=1_000_000`; `delete`, `refresh`; 401/403→gated hint; `APPROX_SIZE_LABEL="~180 MB"`. |
| `EmbeddingProvider.swift` | Provider protocol + shared text assembly + on-device provider + availability + selector. | `data/embedding/EmbeddingProvider.kt` | `protocol EmbeddingProvider { func embedDocument(_:Bookmark) async -> [Float]?; func embedQuery(_:String) async -> [Float]?; func isOnDevice() -> Bool }`; `enum EmbeddingText { CHUNK_CHARS=800, MAX_CHUNKS=4; forDocument; chunksForDocument; meanPool }`; `actor OnDeviceEmbeddingProvider` (Core ML, serialized; CPU-only; task prefixes RETRIEVAL_DOCUMENT/QUERY; `release()`); `struct EmbeddingAvailability`; `EmbeddingProviderSelector` (`await onDevice ?? cloud`). |
| `EmbeddingService.swift` | Cloud (xAI) fallback provider; best-effort nil-tolerant. | `data/embedding/EmbeddingService.kt` | `final class EmbeddingService: EmbeddingProvider`; `isOnDevice()=false`; `embed(_:)` reads XaiKeyStore, `prefix(8000)`, POST `/v1/embeddings`, nil on any error; reuses `EmbeddingText`. |
| `VectorSearch.swift` | Cosine, top-K (min-heap + floor), little-endian Float32↔Data. | `data/embedding/VectorSearch.kt` | `enum VectorSearch { static func cosineSimilarity(_:_:)->Float (size guard, denom<1e-10→0); DEFAULT_MIN_SIMILARITY:Float=0.30; static func topK(query:candidates:k:minSimilarity:)->[String]; topKScored(...)->[(String,Float)] }`; `Accelerate` vDSP for dot/norm; `[Float]<->Data` explicit little-endian (`UInt32(bitPattern).littleEndian`); differing-dim→0. |
| `OcrAnalyzer.swift` | Vision text recognition; never throws; exact fallback strings. | `data/ocr/OcrAnalyzer.kt` | `final class OcrAnalyzer`; `func analyze(_ image: UIImage) async -> String`; `RecognizeTextRequest` (.accurate, `[en]`); blank→`"No text detected in selected image."`, failure→`"OCR failed to process: <desc>"`, no cgImage→`"Bitmap load error: <msg>"`. |
| `SourceResolver.swift` | Resolve text+url→primary source (priority arXiv>HF-paper>GitHub>HF model/dataset>bare-arXiv>DOI-url>DOI-text); retry/backoff; extra-JSON build. | `data/source/SourceResolver.kt` | `struct SourceResolver`; `struct SourceInfo`; `func withRetry<T>(maxAttempts:delayMs:_:) async -> T?` (429/503 retry honoring Retry-After, 4xx→nil, rethrow cancel); `resolve(text:url:) async -> SourceInfo?`; per-type resolvers; `extractAllUrls` (regex + trailing-punct strip loop); `buildExtraJson`; arXiv-DOI skip in DOI path. |
| `BibtexExporter.swift` | BibTeX/RIS/CSL-JSON/Markdown (+ list variants); byte-faithful. | `data/export/BibtexExporter.kt` | `enum BibtexExporter`; `toBibtex/toRis/toCslJson/toMarkdown` + `*List`; helpers `sourceUrl`, `isPaper`, `cslName`, `extra`, `extractDoi/PrimaryClass/Month/Year`, `generateKey`/`buildKey`, `formatAuthors`, `escapeLatex` (& % $ # _), `MONTHS`. `Calendar` year (>1e12 ms heuristic); exact RIS tag spacing `"TY  - "`, double-braced GitHub/HF titles. |

**Cross-cutting (preserve):** off-main work; single-interpreter serialized via actor; CPU compute (no zero vectors); cloud+on-device embed identical `EmbeddingText`; dim-mixing guards (meanPool returns first, cosine 0); non-throwing fallback-first contract; fixed little-endian blob; opt-in resumable download + size floor + gated 401/403 hint + token order; reactive state via `@Observable`; Application Support storage.

---

## 7. Repository — `ios/Curio/Curio/Repository`

The offline-first `BookmarkRepository` implementation (actor): Room↔SwiftData, X sync, cloud mirror, smart-spaces, source persistence, embeddings, curation. The heaviest data-layer file.

**dependsOn:** Domain, Persistence, Networking, Auth, AI, Intelligence

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `BookmarkRepositoryImpl.swift` | Single source of truth: streams, 3-phase sync, refresh lock, 429 backoff, mirror, spaces/smart-spaces, dedupe, embeddings, deep, curation. | `data/repo/BookmarkRepositoryImpl.kt` | `actor BookmarkRepositoryImpl: BookmarkRepository`; deps injected; `cursors:[String:String]` (actor-isolated); detached mirror `Task` tree (`close()`/deinit cancel); constants (`X_PAGE_SIZE=100`, `MAX_PAGES_PER_SYNC=10`, `MAX_RATE_LIMIT_RETRIES=3`, backoff base 1000 / max 30000, `FIREBASE_TIMEOUT_MS=15000`, prefixes `manual_`/`space_`/`space_cat_`); `getBookmarksFlow`→`AnyPublisher`; `syncBookmarks` (3-phase, merge-bias asymmetry, X-authoritative precedence, per-page durability, 429→`RateLimitError`); all writes + `mirrorToCloud` (notes/embeddings/incrementRef/applyRules NOT mirrored); `addBookmark`, `deleteBookmarks`, `deduplicateBySource`, embeddings, `fileByRules`/`applySpaceRules`/`applyRulesToLibrary`/`ensureCategorySpace`/`backfillCategorySpaces`; private `getBookmarksWithAuthRetry`, `refreshAccessTokenSafely` (serialized re-check), `parseRfc3339ToEpoch` (`ISO8601DateFormatter`), `extractUrlAndTitle`. |
| `RepositoryError.swift` | Repo errors (rate limit etc.). | (RateLimitException) | re-exports `RateLimitError` (Domain) + `enum SyncError: Error`. |
| `TimeoutSupport.swift` | `withTimeout` helper for bounded Firebase calls (15s→nil). | `data/repo/BookmarkRepositoryImpl.kt` (withTimeoutOrNull) | `func withTimeout<T>(_ ms:Int, _ op:) async -> T?` via `withThrowingTaskGroup` racing `Task.sleep`. |

**Cross-cutting (preserve):** merge-bias asymmetry; X-authoritative result; best-effort non-blocking mirror; single-use rotated refresh (serialize + re-read + persist rotated); 429 epoch-seconds in two places (Int64, >1_000_000 absolute else relative, fallback 900s); per-page durability + cursor resume; resolution priority; withRetry 4xx-nonretry; rethrow cancellation; threading (async off main; actor-isolated state; AsyncStream/Combine flows; cancel in close/deinit).

---

## 8. Theme — `ios/Curio/Curio/Theme`

Liquid-glass design system: Cosmic color scheme, bold typography, motion springs, glass modifier + tier ladder, accent gradient.

**dependsOn:** (none beyond SwiftUI)

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `CurioColorScheme.swift` | Cosmic Slate palette (dark+light) mirroring every M3 role; `@Environment` injection. | `theme/Theme.kt` | `struct CurioColorScheme` (primary…outline,error); `static dark`/`static light` exact hex; `EnvironmentKey` `\.curioColors` resolved from `colorScheme`. No Material You. |
| `CurioTypography.swift` | Bold type scale (Black/ExtraBold, tracking). | `theme/Type.kt` | `enum CurioFont`/role factories returning `(Font, tracking, lineSpacing)`; `.curioText(_:)` ViewModifier; sizes/weights/tracking exact. |
| `CurioMotion.swift` | Named springs + press/selection modifiers. | `theme/Motion.kt` | `enum CurioMotion { bouncy/liquid/snappy/gentle/fade }` Animations; `CurioPressBounceStyle: ButtonStyle` (scale + `.sensoryFeedback(.impact(.light))` + `.isButton`); `bounceScale(active:)` ViewModifier (non-hit-testing). |
| `GlassHelpers.swift` | `GlassTier` ladder + `glassSurface` modifier (native `.glassEffect` for Full/Blur, manual recipe for Solid) + accent gradient + tokens. | `theme/GlassHelpers.kt` | `enum GlassTier { full, blur, solid }`; `enum GlassTokens { containerShape=24, cardShape=22 }`; `func resolveGlassTier(override:) -> GlassTier` (Reduce Transparency→solid); `glassSurface(tier:shape:tint:borderColor:edgeSheenColor:highlight:)` ViewModifier; `curioAccentBrush(primary:tertiary:)` LinearGradient (0.6 lerp). |
| `CurioTheme.swift` | Root theme wrapper (preferredColorScheme + env injection + brandSeed). | `theme/Theme.kt` (BookmarkTheme) | `struct CurioTheme<Content>: View` or `.curioTheme(darkTheme:brandSeed:)` modifier; injects colors/typography; drops dynamicColor. |

**Cross-cutting (preserve):** carry every alpha/hex verbatim per mode; ALL-CAPS+tracking explicit; honor Reduce Transparency (→Solid, opaque, no specular/blur) and Reduce Motion (damp springs); glass keeps children crisp; press feedback centralized.

---

## 9. Components — `ios/Curio/Curio/Components`

Reusable widgets + brand logo + chrome (top bar/bottom nav/FAB/scaffold) + post card + dialogs + procedural art + markdown renderer.

**dependsOn:** Domain, Theme

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `CurioLogo.swift` | Brand mark as `Shape`/`Canvas` (even-odd spark hole). | `components/CurioLogo.kt` | `struct CurioMarkShape: Shape` (108-viewport math, quad curves, `eoFill`); `CurioLogoMark`. |
| `GlassTopBar.swift` | Glass top app bar (64pt, leading/title/actions). | `components/GlassTopBar.kt` | `struct GlassTopBar`; safe-area top; glassSurface(surface@0.55, border onSurface@0.08). |
| `GlassBottomBar.swift` | Glass bottom nav with animated pill selected tab. | `components/GlassBottomBar.kt` | `struct GlassNavigationItem`; `GlassBottomBar`; `.safeAreaInset(.bottom)`; selected pill `.background(primary@0.15, Capsule)` + scale 1.06 + label transition. |
| `LiquidGlassFab.swift` | Circular glass FAB (0.86 press). | `components/LiquidGlassFab.kt` | `struct LiquidGlassFab`; Circle + glassSurface/`.glassEffect`(primary@0.24); default SF Symbol `arrow.triangle.2.circlepath`. |
| `GlassScaffold.swift` | App shell (content under glass bars via safeAreaInset; FAB overlay). Haze dropped. | `components/GlassScaffold.kt` | `struct GlassScaffold<TopBar,BottomBar,FAB,Content>`; native glass auto-samples; Solid→opaque bars. |
| `CurioComponents.swift` | Chips/pills/panels/tiles/cover/icon-buttons/typing dots. | `ui/CurioComponents.kt` | `TagChip`, `DetailPanel`, `MarkdownDetailPanel`, `StatTile`, `CurioFallbackCover` (SF-symbol watermark by sourceType), `FeedIconAction` (spin via repeatForever), `QuickFilterPill` (count badge), `TypingDots` (3 staggered). |
| `ImagenBookmarkArt.swift` | 3-state cover (real Grok image / CTA / procedural Canvas by category). | `ui/ImagenBookmarkArt.kt` | `struct ImagenBookmarkArt`; `AsyncImage`; `Canvas` per-category gradient+shapes (exact color map/offsets/radii/alphas); badges. |
| `CurioPostCard.swift` | Flagship feed card (header/title/snippet/media/tags/footer/expandable detail) + options sheet + child dialogs. | `ui/CurioPostCard.kt` | `struct CurioPostCard`; `struct CurioCardActions` (closures incl. `exportBibtex()->String?`); `CardOptionsSheet` (`.sheet`+`.presentationDetents([.large])`, animate-then-run, 2-col grid, two-step delete); `SheetToggleRow`, `SheetActionTile`, `SheetDivider`; `PhotosPicker` for OCR; long-press copy. |
| `CurioDialogs.swift` | Slide-up card pattern + add/notes dialogs + empty state. | `ui/CurioDialogs.kt` | `SlideUpCard` (`.sheet` detents `.fraction(0.92)`, drag indicator, corner 28, glass background) or custom overlay; `LocalSlideUpDismiss` via closure/Environment; `ManualAddBookmarkDialog` (instant preview), `NotesEditorDialog` (trim→nil clear, CLEAR/SAVE flip), `CurioEmptyState`. |
| `CurioMarkdown.swift` | Hand-rolled markdown renderer (headings/bullets/numbered/quote/code/blank; inline bold/italic/strike/code/links/autolinks). | `ui/CurioMarkdown.kt` | `struct MarkdownText: View`; block state machine; `parseInline(...) -> AttributedString` (link via `.link`, accent headings, `NUMBERED` regex, unmatched-marker-literal + italic-end edge cases preserved). |

**Cross-cutting (preserve):** uniform pressBounce + selection bounceScale (non-hit-testing); GlassTier perf/accessibility ladder; glass keeps children crisp; per-mode alphas/hex; heavy typography; centralized source-type→color/glyph; child-dialog close on collapse; two-step destructive confirm + empty-save-clears-note; lenient image fallbacks; helpers injected from data/domain.

---

## 10. Screens — `ios/Curio/Curio/Screens`

Eight screens/dialogs + auth slice + nav enum + pure helpers (CurioFormat) reading one shared `@Observable BookmarkViewModel`.

**dependsOn:** Domain, Theme, Components, Repository (via ViewModels — see Platform for VM wiring), AI, Intelligence, Auth

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `CurioDestination.swift` | Nav enum (id rawValues, titles). | `ui/CurioDestination.kt` | `enum CurioDestination: String, CaseIterable { case bookmarks="bookmarks", spaces, insights, chat="chatbot", settings; var title }`; `init(rawValue:) ?? .bookmarks`. |
| `BookmarkApp.swift` | Root: auth gate, theme, drawer (NavigationSplitView/TabView), routed screens, manual-add sheet, reader cover, setUserId. | `ui/BookmarkApp.kt` | `struct BookmarkApp`; `@State` flags; `if case .signedIn`→shell else `LoginView`; `DrawerNavRow`, `XAccountCard`; `.task(id:userId){ setUserId }`; FAB on bookmarks; bottom bar hidden on keyboard; reader via `.fullScreenCover(item:)`. |
| `CurioFormat.swift` | Pure formatting + clipboard/share/open/url + tweetUrl + JSON/CSV backup. | `ui/CurioFormat.kt` | `enum CurioFormat`: `relativeTime`, `readingTime`, `displayAuthor`, `authorInitial`, `sourceDisplayName`, `cleanSnippet`, `formatEpoch`, `getCategoryColor` (**stable Java-hashCode reimpl** for fallback), `copyToClipboard`, `tweetUrl`, `openUrl`, `shareBookmark`, `exportBackupJson`, `exportBackupCsv`. |
| `BookmarkFeedScreen.swift` | Primary feed (merged header/search/AI toggle, stat strip, quick filters, space chips, banners, list, bulk bar, 4 sheets). | `ui/BookmarkFeedScreen.kt` | `struct BookmarkFeedView`; `.refreshable`; search pill 3-way AI toggle; `Menu` overflow; bulk selection (`Set<String>`, two-step delete); export/model/assign/new-space `.sheet`s. |
| `CurioChatScreen.swift` | RAG chat (header/clear, empty suggestions, bubbles+citations, typing, composer+source chips). | `ui/CurioChatScreen.kt` | `struct CurioChatView`; `ScrollViewReader` auto-scroll; `ChatBubbleView` (asymmetric corners, long-press copy, markdown); `CitationStrip` (FlowLayout, host parse, openURL); `SourceChipRow`. |
| `CurioInsightsScreen.swift` | Analytics (hero %, stat tiles, digest card, rediscover, distribution bars, hot topics). | `ui/CurioInsightsScreen.kt` | `struct CurioInsightsView`; animated progress on appear; `WeeklyDigestCard` (5-state switch), `RediscoverCard`, distribution capsules (tap→filter+navigate), `FlowLayout` topics. |
| `CurioSpacesScreen.swift` | Spaces home + editor/delete/assign dialogs + icon/color registry + rule builder. | `ui/CurioSpacesScreen.kt` | `struct CurioSpacesView`; `spaceIconKeys` (21), `spacePalette` (18 ARGB), `spaceIcon(_:)`→SF Symbols (document substitutions); `SpaceCard`, `SmartBadge`; `SpaceEditorDialog` (color/icon grids, `SpaceRulesEditor` tap-to-cycle pills, ANY/ALL, autoFile), `DeleteSpaceDialog`, `AssignToSpaceDialog`, `rulePlaceholder`. |
| `ReaderViewScreen.swift` | Full-screen reader (font scale, metadata, source/deep/summary/tags/OCR blocks, 600pt cap). | `ui/ReaderViewScreen.kt` | `struct ReaderView`; `.fullScreenCover`; slide-up transition; `@State fontScale` (0.85/1.0/1.25); serif body; source-type colors; date `MMM dd, yyyy - HH:mm`; openURL. |
| `SettingsScreen.swift` | Settings (theme, xAI key, session, backup, research-intelligence, embedding model, glass tier). | `ui/SettingsScreen.kt` | `struct SettingsView` (`Form`/`List`); theme Picker; `SecureField` xAI key (Keychain); logout/purge/backup; embed/resolve/dedup buttons; embedding `switch` + `ProgressView`; index-while-charging Toggle (UserDefaults→BGTask); glass-tier picker. |
| `AuthViewModel.swift` | OAuth-PKCE controller (authState, login→browser, redirect handle, logout). | `ui/screens/auth/AuthViewModel.kt` | `@MainActor @Observable final class AuthViewModel`; `authState` fed by AuthRepository publisher; `onLoginClick` builds challenge → `WebAuthSession`; `handleRedirect` (extract code/state/error, validate state) → `completeLogin`; `onLogout`. |
| `LoginScreen.swift` | Liquid-glass login landing (logo, privacy card, connect button spinner, trust row). | `ui/screens/auth/LoginScreen.kt` | `struct LoginView`; `state is .signingIn` disables button; `ASWebAuthenticationSession` via AuthViewModel; exact labels. |

**Cross-cutting (preserve):** single shared `@Observable` VM injected; stable `id` keys; glass tiers/press springs; sealed-state switches with exact labels; rate-limit countdown; auto-org precedence; dedupe-on-resolve; share capture; xAI-key async gate; citation URL templates; semantic search debounce 300ms / k=20 feed, k=15 RAG; atomic reorder; granular UI states; theme resolution; pure helpers + Java-hashCode caveat + markdown edge cases; safe-area/keyboard native; accessibility identifiers/labels/44pt targets.

---

## 11. Platform — `ios/Curio/Curio/Platform`

DI composition root, ViewModels (BookmarkViewModel + controllers), background tasks, App Intents, share extension glue, config/secrets.

**dependsOn:** all data + Screens (constructs VMs); App Intents depend on Repository/Auth

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `AppEnvironment.swift` | Single composition root (`lazy var` graph; two URLSession configs; protocol-typed impls; `close()`); VM factories. | `di/AppContainer.kt` + `di/KoinModules.kt` | `@Observable final class AppEnvironment`; `lazy var` tokenStore/authRepository/loginUseCase/xAiApi/ocrAnalyzer/aiAnalyzer/grokImageService/textGenerator/embeddingService/embeddingModelManager/onDeviceEmbeddingProvider/embeddingProvider/arxivClient/crossrefClient/sourceResolver/database/firebaseSyncManager/bookmarkRepository; selector chains; `makeBookmarkViewModel()`, `makeAuthViewModel()`; `close()`/deinit cancels repo Task. Injected via `.environment`. |
| `CurioConfig.swift` | Secrets/config (CLIENT_ID/X_CLIENT_ID fallback, X_REDIRECT_URI, HF_TOKEN, XAI_API_KEY) from Info.plist/xcconfig. | `BuildConfig.*` references | `enum CurioConfig { static let clientID, xRedirectURI, hfToken, xaiApiKey }`. |
| `BookmarkViewModel.swift` | Central `@MainActor @Observable` VM: reactive arrays + computed filtered list, sync/analysis/OCR/source/embedding/deep pipelines, spaces+auto-filing, exports, image gen, xAI key, controller facades, shared enums + UI-state types + ChatMessage. | `ui/BookmarkViewModel.kt` | `@MainActor @Observable final class BookmarkViewModel`; enums `AppThemeSetting`, `SearchMode`, `QuickFilter`; sealed `SyncUiState`/`AnalysisUiState`/`DigestUiState`; `CurioStats`; `ChatMessage`/`ChatSender`/`ChatSource(label,apiType)`; `rawBookmarks` fed eagerly by repo publisher; computed `bookmarks` (5-input filter verbatim), `spaces` (inject count), `stats`, `rediscoverPicks`; all methods (`setUserId`→flush+applyRules+backfill+sync, `syncBookmarks` guard, `startRateLimitCountdown` Task loop, OCR/analysis/deep/resolve/embeddings, exports, spaces CRUD, curation, digest, chat, shuffle); `REDISCOVER_MIN_AGE_MS=14d`, `REDISCOVER_BATCH=3`. |
| `SearchController.swift` | Feed search/filter input state + 300ms-debounced semantic search. | `ui/SearchController.kt` | `@MainActor @Observable final class SearchController`; cancellable `Task` debounce; `updateQuery`/`setMode`/`runSemanticSearch` (embedQuery→top-K k=20); `setQuickFilter` toggle, `clearSpaceIf`, `clearAll`; `close()`. |
| `ChatController.swift` | Chat messages/sources + RAG retrieval + Live-Search send + citation URL templates. | `ui/ChatController.kt` | `@MainActor @Observable final class ChatController`; `send` (`Task`, UUID); `toggleSource` (never empty→Library); `citationUrl(_:)` switch (exact templates); `retrieveRagContext` (k=15, take(15) fallbacks). |
| `CurationController.swift` | Per-bookmark mutations + error stream. | `ui/CurationController.kt` | `@MainActor @Observable final class CurationController`; `curationError: String?` (or AsyncStream); toggleFavorite/SavedForLater/updateNotes/assignToSpace(empty no-op)/delete/updateCategory; catch CancellationError. |
| `DigestController.swift` | Weekly digest state + Grok generation over 7 days. | `ui/DigestController.kt` | `@MainActor @Observable final class DigestController`; `digestState: DigestUiState`; `generate()` (cutoff -7d, ≤40 items, itemsBlock build, `generateWeeklyDigest`); `dismiss()`. |
| `BackgroundTasks.swift` | Registration + scheduling for link sweep + embedding backfill; identifiers; Info.plist note. | `background/EmbeddingIndexScheduler.kt` | `enum BGID`; `registerBackgroundTasks()`; `scheduleLinkSweep()`/`scheduleEmbeddingBackfill()` (`BGProcessingTaskRequest`, `requiresExternalPower` for backfill, `requiresNetworkConnectivity` for sweep; self-resubmit earliestBeginDate+6h); `EmbeddingIndexScheduler` (UserDefaults suite `curio_embedding_prefs`, key `index_while_charging` default true; `runNow`→immediate Task). |
| `LinkSweeper.swift` | 404/410-only link deletion sweep (HEAD checks, 50 cap, 250ms pace, 5s timeout). | `background/BookmarkSweeperService.kt` | `func handleLinkSweep(_ task: BGProcessingTask)`; HEAD via 5s-config URLSession; delete + Firestore delete ONLY on 404/410; pace 250ms; expirationHandler cancels; reschedule. NO AI/cloud enrichment. |
| `EmbeddingIndexer.swift` | Charging-gated on-device-only embedding backfill (≤200/run, single-transaction write, resubmit if more). | `background/EmbeddingIndexWorker.kt` | `actor EmbeddingIndexer { func run() async -> Outcome }`; guard on-device model + signed-in; `getUnembeddedAnalyzed`; embed ≤200 (cancellation each iter); accumulate `(id,Data)`→ONE `updateEmbeddings`; resubmit if >200; transient→resubmit, unrecoverable→complete. On-device only. |
| `CurioFunctionModels.swift` | App Intent value types (summary 300-char vs full detail). | `appfunctions/CurioFunctionModels.kt` | `struct BookmarkSummary: AppEntity`, `struct BookmarkDetail: AppEntity`; `@Property` per field; `DisplayRepresentation`; createdAt ISO-8601 UTC; sourceType raw name; tags `[String]` default []; text truncation 300 on summary. |
| `CurioIntents.swift` | 6 App Intents (search/add/detail/note/favorite/exportCitation) + dependency injection + auth gating. | `appfunctions/CurioFunctions.kt` | `SearchBookmarksIntent` (limit clamp 1...50, no auth req), `AddBookmarkIntent`, `GetBookmarkDetailIntent`, `AddNoteToBookmarkIntent` (blank clears), `ToggleFavoriteIntent`, `ExportCitationIntent` (BibTeX, no auth req); `@Dependency` repo/tokenStore; `requireUserId()` throws `LocalizedError`; write/detail intents `authenticationPolicy = .requiresAuthentication` (allowlist approximation); `BookmarkEntity`/`BookmarkQuery` (`EntityStringQuery`); `CurioShortcuts: AppShortcutsProvider`. |
| `GrokImageService.swift` | Grok image generation client (used by VM, procedural fallback in VM). | (referenced by AppContainer/VM) | `final class GrokImageService`; `func generate(prompt:) async -> String?` (URL); consumes XAiApi images endpoint. |
| `ShareViewController.swift` | Share Extension: extract shared url/text → App-Group queue. (Lives in extension target.) | (Android ACTION_SEND receive) | `final class ShareViewController: UIViewController`; `NSItemProvider.loadTransferable` (URL+plainText, re-parse text→URL); write `pendingShares` to App-Group `UserDefaults`; `completeRequest`. Main app drains in `BookmarkApp`/`AppEnvironment` on `.active` → `captureSharedText`. |

**Cross-cutting (preserve):** PRIVACY RULE (no cloud AI in background); definitive-vs-transient deletion (404/410 only); secret/log hygiene (no Authorization/body logs); selector device-gating (on-device + on-device-only injectables both exposed); charging vs run-now; idempotent scheduling (BGTask de-dup); batched single-transaction embedding writes; cooperative cancellation; per-cycle bounds + pacing; App Intents signed-in gate + auth-policy allowlist approximation; exportCitation→BibtexExporter; `lazy var` graph (thread-safety caveat); 9-dep BookmarkViewModel constructor; `if e is CancellationError throw e` → `try Task.checkCancellation()`.

---

## 12. App — `ios/Curio/Curio/App`

App entry, scene wiring, container lifecycle, Firebase configure, BGTask registration, share-drain.

**dependsOn:** Platform (and transitively all)

| Swift file | Responsibility | Ports Android file(s) | Key types / functions |
|---|---|---|---|
| `CurioApp.swift` | `@main App`: configure Firebase, build `AppEnvironment`, register BGTasks, inject environment, host `BookmarkApp`; drain shares + ensureScheduled on `.active`; `close()` on teardown. | `CurioApplication` / `MainActivity` (Android entry) | `@main struct CurioApp: App`; `init { FirebaseApp.configure(); registerBackgroundTasks() }`; `@State env = AppEnvironment()`; `WindowGroup { BookmarkApp(...).environment(env).curioTheme(...) }`; `.onChange(of: scenePhase)` → drainShares + ensureScheduled; `.modelContainer(env.database.container)`. |
| `Info.plist notes` (doc only) | Required keys checklist. | (manifest/permissions) | `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes` (fetch/processing), `CFBundleURLTypes` (redirect scheme), `NSExtension` (share ext), App Group, `GoogleService-Info.plist`, Associated Domains (if https callback). |

---

## Notes for implementers

- **Filenames are names only** — full paths are the module folder + filename.
- Where a file is referenced by another module but its primary home is elsewhere (e.g. `XAiAnalyzer`, `GrokImageService`, `IdEmbeddingRow`), it appears once in its owning module's table.
- All domain helpers consumed by Components/Screens (e.g. `getCategoryColor`, `sourceDisplayName`, `spaceIcon`, `CategorySpaces.forCategory`) are concrete in Domain/Screens; treat as injected/static where the porter writes a widget before the data layer exists.
- Follow `CONVENTIONS.md` for every shared decision (DI, errors, `@Observable`+`@MainActor`, Sendable/actors, theme tokens, SwiftData `@Model`, DTO↔domain mapping). This doc and CONVENTIONS are mutually consistent.
