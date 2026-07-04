# Curio iOS — CONVENTIONS

Shared conventions ALL modules MUST follow. These are binding rules; `DESIGN.md` references them by name. When in doubt, prefer the rule here over an ad-hoc choice. Target: iOS 26+, latest SDK, Swift 6 strict concurrency.

---

## 1. Project layout & naming

- Root for all source: `ios/Curio/Curio/`. One folder per module (see DESIGN §Modules): `Domain, Persistence, Networking, Auth, AI, Intelligence, Repository, Theme, Components, Screens, Platform, App`.
- **Types:** `UpperCamelCase`. **Files:** named after their primary type (`BookmarkViewModel.swift`). A file may host one primary type + tightly-coupled small helper types (e.g. `SpaceRule.swift` holds `RuleField/RuleOp/RuleMatch/SpaceRule/SpaceRules`).
- **Protocols:** noun or `-ing`/`-able` (`BookmarkRepository`, `EmbeddingProvider`). Concrete impls add `Impl` ONLY where the protocol name is the public surface (`AuthRepositoryImpl`, `BookmarkRepositoryImpl`); networking actors use `…Client` (`XAiApiClient`).
- **Enums as namespaces** (no cases) for pure-static collections: `enum GrokModels`, `enum BibtexExporter`, `enum CurioFormat`, `enum ChatPromptBuilder`, `enum VectorSearch`, `enum CategorySpaces`, `enum LanguageGate`. Caseless namespaces are never instantiated.
- **No abbreviations** in public API except established ones (`url`, `id`, `json`, `ocr`, `ai`, `csv`, `ris`).
- **Persistence-key stability is sacred:** any enum whose rawValue is written to storage/JSON/Firestore (`SourceType`, `RuleField`, `RuleOp`, `RuleMatch`) keeps the **exact uppercase Kotlin `.name`** as `String` rawValue. JSON wire keys (`m/a/r`, `f/o/v`) are literal. Never rename.

---

## 2. Dependency injection — composition root

- **One container:** `@Observable final class AppEnvironment` in `Platform/AppEnvironment.swift`. It is the single place every graph node is built, using `lazy var` (the direct analogue of Kotlin `by lazy` — once-only; not thread-safe, which is fine because the graph is built/read on the main actor at launch).
- **Constructor injection everywhere.** Every type takes its dependencies via `init`. No service locators, no globals (except `CurioDatabase.shared` and `XaiKeyStore` static resolution, mirroring Android singletons).
- **Protocol-typed storage:** the container stores `bookmarkRepository: BookmarkRepository`, `authRepository: AuthRepository`, `embeddingProvider: EmbeddingProvider`, `textGenerator: TextGenerator` behind their **protocol** types so call sites depend on abstractions (mirrors Koin `single<Interface>`).
- **Injection into SwiftUI:** `.environment(appEnvironment)` at the root; read with `@Environment(AppEnvironment.self) private var env`. ViewModels are built by **factory methods** on the container (`env.makeBookmarkViewModel()`), then held by the owning view as `@State private var vm = …` (see §4).
- **App Intents** cannot read `@Environment`; they use App Intents' own `@Dependency` mechanism. Register all intent dependencies at launch: `AppDependencyManager.shared.add { … }` in `CurioApp.init`.
- **Two URLSession configs** are built in the container: primary (`timeoutIntervalForRequest = 120`, `waitsForConnectivity = true`) for xAI long calls; metadata (`timeoutIntervalForRequest = 15`) for arXiv/Crossref/GitHub/HF. No DI library (no Factory/Swinject) — a hand-rolled container matches the Android `AppContainer` 1:1.
- **Teardown:** `AppEnvironment.close()` cancels the repository's long-lived background `Task` tree; called from `CurioApp` scene teardown / `deinit`.

---

## 3. Error model — sealed enums

- **Root error** in `Domain/CurioError.swift`:
  ```swift
  enum CurioError: Error { case notSignedIn; case decoding(Error); case unknown(Error?) }
  ```
- **Per-domain error enums**, each `Error` (and `LocalizedError` where surfaced to UI/App Intents):
  - `AuthError` (Auth): `.stateMismatch, .cancelled, .missingCode, .exchangeFailed(Error)`.
  - `RateLimitError` (Domain, used by Repository): `struct RateLimitError: Error { let resetTimeSeconds: Int64 }` — `Int64` to avoid 2038 overflow.
  - `APIError` (Networking): `case http(status: Int, headers: [String:String], body: Data); case transport(URLError); case decoding(Error)`.
  - `SyncError`, `RepositoryError` (Repository) wrap/forward the above.
  - `NanoUnavailable` (AI): `enum NanoUnavailable: Error { … }` — caught inside the selector, never surfaced.
- **Result→throws collapse:** Kotlin `suspend …: Result<Unit>` → Swift `func … async throws` (no return). Kotlin `suspend …: Result<Bookmark>` → `async throws -> Bookmark`. Plain `suspend` (no Result) → `async` (NO throws) — do **not** add throwing to `currentUserId`, `getBookmarkById`, `logout`, DAO reads, etc.
- **Resilience contract:** all network clients (Arxiv/Crossref/GitHub/HF/Firebase/TokenStore decrypt) and OCR **log + return `nil`/empty/fallback-string instead of throwing**. The ONLY path that surfaces a typed failure to the UI is `AuthRepository.completeLogin` (throws) and `syncBookmarks` (throws `RateLimitError`). Never force-unwrap a network/JSON result.
- **Never log secrets:** error messages and any logging must omit the `Authorization` header value and request/response bodies.

---

## 4. ViewModels & `@Observable` / `@MainActor`

- **ViewModels and UI controllers** are `@MainActor @Observable final class` (Observation framework; replaces `ObservableObject`/`@Published`/StateFlow). Plain stored `var`s are auto-tracked — no `@Published`.
- **Ownership:** a view that creates a VM uses `@State private var vm = env.makeX()`. A child that receives but does not own a VM/observable model and needs two-way bindings uses `@Bindable`. Read an injected observable via `@Environment(Type.self)`. (Never `@StateObject`/`@ObservedObject`/`@EnvironmentObject` — those are for `ObservableObject`.)
- **Derived state = computed properties.** Kotlin `combine(...)` flows (`bookmarks`, `spaces`, `stats`, `rediscoverPicks`) become computed `var`s recomputed from source arrays. The 5-input feed filter predicate is ported **verbatim** as a computed property.
- **Eager source stream:** `rawBookmarks` (Kotlin `SharingStarted.Eagerly`) is a stored property continuously fed by an `AsyncStream`/Combine subscription started in the VM `init` and kept alive for the VM lifetime — background tasks read it with no view subscriber. Do NOT lazily start it on view appear.
- **`@ObservationIgnored`** for injected services/dependencies and cancellable `Task`s that must never invalidate views.
- **Async pattern:** every `viewModelScope.launch` → `Task { … }` on the main actor. Heavy work (network, embedding, source resolution) is performed by **actor-isolated services** or `await Task.detached`, then results assigned back on the main actor (the `await` hop returns to `@MainActor`). Never block the main actor.
- **Cancellation:** the ubiquitous Kotlin `if (e is CancellationException) throw e` becomes `try Task.checkCancellation()` at loop heads and `catch is CancellationError { throw … }` / rethrow. Never swallow `CancellationError`.
- **Countdown/timers:** the rate-limit `CountDownTimer` → a cancellable `Task` loop with `try await Task.sleep(for: .seconds(1))`; cancel in `deinit`/teardown.
- **Sealed UI states** (`SyncUiState`, `AnalysisUiState`, `DigestUiState`, `ModelState`, `AuthState`) are Swift `enum`s with associated values; views switch over them exhaustively. **Preserve exact user-facing strings** (e.g. `"X Rate Limited. Resume syncing in {n}s"`, `"No Summary available…"`, `"Untitled Curio"`).

---

## 5. Swift 6 concurrency (Sendable, actors)

- **Stores/caches/clients that own mutable state or a non-reentrant resource are `actor`s:**
  - Persistence: `BookmarkStore`/`SpaceStore` are `@ModelActor` (serialized, off-main — replaces Room's IO dispatcher).
  - Networking: each API client is an `actor` (`XAiApiClient`, `XBookmarksApiClient`, …); `HTTPClient`, `FirebaseSyncManager`, `ArxivClient`, `CrossrefClient` are actors.
  - Repository: `BookmarkRepositoryImpl` is an `actor` — its isolation replaces `Mutex` (OAuth refresh) and `ConcurrentHashMap` (`cursors`). The single LiteRT/Core ML interpreter in `OnDeviceEmbeddingProvider` is serialized by making it an `actor`.
  - Background: `EmbeddingIndexer` is an `actor`.
- **`Sendable`:** all domain value types (`Bookmark`, `Space`, `SpaceRule(s)`, `AuthState`, `AuthChallenge`, `SourceType`, DTOs) are `struct`/`enum` and conform to `Sendable`. Protocols that cross actor boundaries (`BookmarkRepository`, `AuthRepository`, `EmbeddingProvider`, `TextGenerator`) declare `: Sendable`.
- **`@Model` is NOT `Sendable`:** never pass a SwiftData model across actor/context boundaries. Hand off `persistentModelID` (`PersistentIdentifier`) and re-fetch with `context.model(for:)`. Stores convert `@Model` → domain `struct` before returning across boundaries (mappers in `ModelMappers.swift`).
- **Transaction atomicity:** `swapCreatedAt` and bulk `updateEmbeddings`/`batchUpdateEmbeddings` perform all mutations then **exactly one** `try modelContext.save()` (SwiftData save is atomic — preserves the TOCTOU guarantee and O(1) WAL flush). Never save per item.
- **Bounded calls:** Firebase pull/push (15s) use a `withTimeout` helper (`withThrowingTaskGroup` racing `Task.sleep`) returning `nil` on timeout (never a hard failure).
- **Fire-and-forget mirror:** detached `Task { try? await … }` not awaited by the writer; tracked for cancellation in `close()`/`deinit`. A timed-out/failed mirror must never mask a real X error (X-authoritative precedence).
- **Main-actor boundary only at SwiftUI/VM:** data-layer methods are `nonisolated async` or actor-isolated; only VMs/controllers and views are `@MainActor`.

---

## 6. SwiftData `@Model` conventions

- `@Model final class …Model` (suffix `Model`); domain type is the un-suffixed `struct` (`BookmarkModel` ↔ `Bookmark`).
- **Primary key:** `@Attribute(.unique) var id: String`. Unique-id insert = upsert (REPLACE semantics) — fetch-or-insert then `save()`.
- **Type mapping:** `String?`→`String?`; Kotlin `Long`→`Int64` (epoch ms / packed ARGB); `Boolean`→`Bool`; `Int`→`Int`; `ByteArray?`→`Data?` with `@Attribute(.externalStorage)` for the embedding blob.
- **Preserve serialization shapes:** `tags` stays a single CSV `String?` (do NOT model `[String]`); `entities`/`sourceExtra`/`rulesJson` stay opaque `String` (decoded by Domain). Empty-string sentinels (`rulesJson = ""`, `description = ""`) are NOT optionals — keep the `'' vs nil` distinction exactly (predicates check `summary == nil || summary == ""`, `spaceId == nil || spaceId == ""`).
- **Indices** via `#Index<Model>([...])` declared on the model, matching Room's composite indices (no raw CREATE INDEX). SwiftData recreates them from the model definition.
- **Defaults** mirror Kotlin defaults exactly (`isOcrScheduled=false`, `isAnalyzed=false`, `referenceCount=1`, `isFavorite=false`, `isPinned=false`, `sortIndex=0`, `count=0` transient on domain).
- **No relationships / no cascade:** `spaceId` is a loose `String?`, NOT a SwiftData `@Relationship`. Deleting a Space does NOT cascade — the caller manually nulls membership (`clearSpace`) in the same actor op. Do not add a `.cascade` rule.
- **Migrations:** `VersionedSchema` per Room version (6→11), `SchemaMigrationPlan` with `.lightweight` stages (additive columns with defaults + index declarations). Store file `curio_database` in Application Support. DEBUG: delete-store-and-rebuild on incompatible store; RELEASE: propagate/`fatalError` (never silently wipe).
- **Search semantics:** Room `LIKE … COLLATE NOCASE` is ASCII-only. Use a non-localized case-insensitive `range(of:options:.caseInsensitive)` over a `FetchDescriptor` + closure filter (NOT `localizedStandardContains`) across `text/title/summary/ocrText` OR'd. `categories` distinct = fetch non-nil → `Set` → sort. `fetchLimit = 200` for `getUnembedded`; `propertiesToFetch` projection for `getIdsAndEmbeddings`.
- **userId scoping** on nearly every query; device-wide sweeps (`observeAll`, `getAllBookmarksDirect`, `clearAllEmbeddings`) deliberately span all users — keep that distinction.

---

## 7. DTO / Codable ↔ domain mapping

- **Wire DTOs are `Codable` structs** with explicit `CodingKeys` for snake_case (or `keyDecodingStrategy = .convertFromSnakeCase` on a shared decoder — prefer explicit `CodingKeys` for hot/ambiguous paths). A single shared `JSONDecoder`/`JSONEncoder` is reused (`.iso8601` dates).
- **Moshi null-omission is load-bearing:** every optional DTO field is encoded with `encodeIfPresent` (or a custom `encode(to:)`) so unset fields never hit the wire. A naive Codable emitting `null` will change xAI tool/search semantics. The xAI `XAiTool`/`XAiSearchSource`/`XAiSearchParameters`/`XAiRequest` rely on this.
- **Raw JSON-Schema fields** (`Map<String,Any?>`) → a `JSONValue`/`AnyCodable` wrapper that round-trips as a raw JSON object.
- **String-not-object fields:** `XAiToolFunctionCall.arguments` stays a `String` (JSON-encoded), decoded separately by the caller. `XAiResponse.citations` is a **top-level** `[String]?` sibling of `choices`/`usage`.
- **Tolerant parsers** (`SpaceRules.fromJson`, `sourceExtra`, Crossref) use `JSONSerialization` + optional chaining (mirrors `org.json` `optString`/`optJSONObject`); never throw — return `.empty`/`nil`/defaults, skip malformed elements. Manual encoder for short-key wire formats (`m/a/r`, `f/o/v`) — do NOT use synthesized Codable for those.
- **DTO → domain mappers** live next to the data layer (`ModelMappers.swift`, Firebase `pull` mapping, X tweet mapping). They apply: prefer `noteTweet.text` over `text`; `t.co expandedUrl` resolution; CSV tag split/trim/filter; `SourceType(rawValue:)` guarded; numeric/bool defaults. **Domain models never carry DTO/CodingKeys** — keep wire and domain separate.
- **Firestore asymmetry preserved:** minimal push map (id/userId/createdAt/updatedAt/flags/spaceId/sourceType/sourceId/title/url) vs richer pull (full mapping with safe defaults). `serverTimestamp()` on push; `@DocumentID` not used for the loose-id scheme — map dictionaries manually under `users/{userId}/bookmarks`.

---

## 8. Theme tokens & Liquid Glass

- **Color:** a custom `CurioColorScheme` struct mirrors every Material3 role (primary, onPrimary, primaryContainer, …, surfaceVariant, outline, error). `static dark`/`static light` carry the exact Cosmic Slate hex values. Injected via `@Environment(\.curioColors)` resolved from `@Environment(\.colorScheme)`. **No Material You / dynamic color** — the static palette is canonical; `brandSeed` may override `primary`. Do NOT use SwiftUI semantic system colors for these roles — use literal `Color(hex:)`.
- **ARGB:** `Space.color` / `CategorySpaceMeta.color` stay `Int64` packed ARGB through domain/persistence; convert to `Color(.sRGB, …)` by unpacking A/R/G/B bytes **only at the SwiftUI boundary**.
- **Icons:** stored `iconKey`/`icon` strings stay unchanged; resolved to SF Symbols via a single `spaceIcon(_:)` lookup in the UI layer (document any Material→SF-Symbol substitutions). Centralize **source-type → color/glyph** in one helper to avoid drift.
- **Typography:** `CurioFont` role factories return `(Font, tracking, lineSpacing)`; apply `.font()` + `.tracking()` + `.lineSpacing()` together via a `.curioText(_:)` modifier. Heavy weights (Black/ExtraBold) and ALL-CAPS + wide tracking are intentional — apply `.textCase(.uppercase)` + `.tracking()` explicitly.
- **Glass:** `GlassTier { full, blur, solid }`. Full/Blur use native iOS 26 `.glassEffect(_:in:)` (samples backdrop automatically, keeps children crisp — Haze machinery is dropped). Solid (and Reduce Transparency) uses an opaque manual recipe (translucent fill, no specular/blur). The `glassSurface(...)` ViewModifier carries the exact per-mode alphas/hex (tint, specular, top light line, hairline border) verbatim. Combine adjacent glass shapes in a `GlassEffectContainer`. Every native-glass API is behind `#available(iOS 26, *)` with a `.ultraThinMaterial` fallback.
- **Motion:** `CurioMotion` springs map Compose damping→SwiftUI (`bouncy/liquid/snappy/gentle` + `fade`). `CurioPressBounceStyle: ButtonStyle` (scale to pressedScale on `isPressed`, `.sensoryFeedback(.impact(weight:.light))`, `.accessibilityAddTraits(.isButton)`) replaces ripple **everywhere**. `bounceScale(active:)` is a non-hit-testing `.scaleEffect` modifier (must not steal taps).
- **Accessibility:** honor `accessibilityReduceTransparency` (→ Solid/opaque) and `accessibilityReduceMotion` (damp/disable springs and infinite animations). 44pt minimum touch targets; mirror Compose `testTag` as `.accessibilityIdentifier`; carry `contentDescription` → `.accessibilityLabel`.
- **Layout/insets:** rely on native safe-area + keyboard avoidance. Bars use `.safeAreaInset(edge:)`; chat composer pins via `.safeAreaInset(edge:.bottom)`. Full-screen modals via `.fullScreenCover`; slide-up dialogs via `.sheet` + `.presentationDetents`.

---

## 9. Background, App Intents, secrets (binding rules)

- **PRIVACY RULE (load-bearing):** no third-party cloud AI/enrichment (xAI Grok, cloud embedder) runs in the background — only foreground with the user present. Background = offline maintenance (link sweep) + **on-device-only** embedding. `onDeviceEmbeddingProvider` is exposed as a distinct injectable so the backfill never falls back to cloud.
- **Definitive-vs-transient deletion:** the link sweep deletes a bookmark ONLY on HTTP 404/410. Any thrown error / other status → leave intact (prevents offline data loss).
- **BGTask:** identifiers in `BGTaskSchedulerPermittedIdentifiers`; charging = `requiresExternalPower`; no true periodic — self-resubmit `earliestBeginDate = +6h` at end of each run (de-dup by identifier ≈ WorkManager KEEP). "Run now" = an immediate `Task`, not a BGTask. Always set `expirationHandler` first and call `setTaskCompleted` once.
- **App Intents:** signed-in gate (`requireUserId()` throwing `LocalizedError`) on all six. The Android caller allowlist is NOT portable → approximate with `authenticationPolicy = .requiresAuthentication` on write/detail intents; `searchBookmarks` and `exportCitation` stay freely discoverable. Preserve summary 300-char truncation, ISO-8601 UTC `createdAt`, blank-note-clears, null-on-not-found, addBookmark error wrapping.
- **Secrets:** OAuth tokens, HF token, xAI key live in the **Keychain** only (`TokenStore`). Never in `UserDefaults`/`@State`. `SecureField` for entry; key input is transient. `clear()` removes X-session items only (HF + xAI survive). Blank xAI key deletes the item. The `forceLocalNano` gate is set **asynchronously** after an `XaiKeyStore.isConfigured()` check (never read synchronously at construction).
- **Config** (`CurioConfig`) sources `CLIENT_ID`/`X_CLIENT_ID` fallback, `X_REDIRECT_URI`, `HF_TOKEN`, `XAI_API_KEY` from Info.plist/xcconfig (Android `BuildConfig` analogue). The redirect URI is registered as the ASWebAuthenticationSession callback scheme.

---

## 10. Determinism & faithful-output rules

- **Java `String.hashCode` reimplementation** is REQUIRED wherever Kotlin hashed for a deterministic result (`getCategoryColor` fallback palette): Swift `String.hashValue` is randomized per run. Use `s.unicodeScalars.reduce(0) { 31 &* $0 &+ Int($1.value) }` (Int32 overflow semantics) so colors stay stable.
- **Char-count semantics:** Kotlin `take(n)` counts UTF-16 code units. Swift `prefix(n)` on `Character` is acceptable for the texts involved but document the slight difference; for byte-format-sensitive paths operate on the same unit.
- **Export byte-fidelity:** BibTeX LaTeX escaping (`& % $ # _`), double-braced GitHub/HF titles, RIS two-space-dash tags (`"TY  - "`), CSL-JSON family/given split, deterministic cite keys (cleaned-lastname[a-z0-9,≤12] + year + first significant title word). Year from `sourceExtra.published` regex else `Calendar` year from `createdAt` (epoch-ms vs epoch-s disambiguated by the `1e12` threshold). Match output byte-for-byte (downstream LaTeX/Zotero parsers are whitespace-sensitive).
- **Vector blob format:** explicit little-endian Float32 (`UInt32(bitPattern:).littleEndian`) for `[Float] ↔ Data`, byte-stable and consistent across read/write. Cosine on L2-normalized vectors; differing-dimension vectors score 0; `meanPool` returns the first vector (not a malformed average) on dim mismatch.
- **Regexes** (URL extraction, arXiv/DOI IDs, JATS strip, month/year) ported with **identical patterns**. URL trailing-punctuation strip is a `while`-loop over `.,)]!?;`, not `trimmingCharacters` (which trims both ends).
- **Markdown parser** edge cases preserved: unmatched inline markers appended literally; italic requires a later matching marker (`end > i+1`); autolink terminator set `)]},`; heading font multipliers `1.0/1.05/1.12/1.2`.

---

## 11. Streams / reactivity mapping

- Kotlin hot `Flow` (Room live queries, `authState`) → Combine `AnyPublisher` (preferred for SwiftUI binding) or `AsyncStream`. Must re-emit on every underlying DB/session change.
- `StateFlow` → `CurrentValueSubject` (carries current value) exposed as a publisher, or an `@Observable` stored property.
- `SharedFlow` (one-shot errors, e.g. `curationError`) → `AsyncStream` continuation or a published `String?` that the view observes and clears.
- `WhileSubscribed(5000)` (auth) → keep the subscription/Task alive while the relevant view is on screen (`.task`/`.onDisappear`); `SharingStarted.Eagerly` (rawBookmarks) → keep alive for the VM lifetime regardless of view presence.

---

## 12. Testing & purity

- Pure helpers (`relativeTime`, `readingTime`, `getCategoryColor`, `cleanSnippet`, `sourceDisplayName`, `SpaceRule.matches`, `SpaceRules.toJson/fromJson`, `CategorySpaces.forCategory`, `VectorSearch`, `BibtexExporter`, `LanguageGate`, the markdown parser) are deterministic and Foundation-only — write unit tests covering the documented edge cases (Java-hashCode stability, tolerant JSON, byte-faithful export, dim-mismatch guards).
- Protocols (`BookmarkRepository`, `AuthRepository`, `EmbeddingProvider`, `TextGenerator`) enable mock conformances; `LoginUseCase` stays a stateless pass-through for trivial mocking.
- In-memory `ModelContainer` (`isStoredInMemoryOnly: true`) for persistence tests/previews.
