import Foundation
import Observation
import SwiftData

// ---------------------------------------------------------------------------
// XaiKeyStore → XaiKeyResolving conformance
//
// `XAiAnalyzer`, `GrokImageService` (Networking/Platform) and the AI selector take a
// `keyResolver: XaiKeyResolving` (the `resolve()`/`isConfigured()` pair). The Auth module's
// `XaiKeyStore` already declares both methods with the exact signatures `XaiKeyResolving`
// requires but does NOT spell the conformance (its declaration is `struct XaiKeyStore: Sendable`).
// The doc comments on those types say "the Auth module's `XaiKeyStore` conforms"; this retroactive
// extension makes that true without re-declaring any method (mirrors how the Kotlin `object
// XaiKeyStore` was passed directly to constructors expecting the resolver contract). Declared once,
// at the composition root, so the conformance lives with the wiring rather than leaking into Auth.
// ---------------------------------------------------------------------------

extension XaiKeyStore: XaiKeyResolving {}

/// **Single composition root** for the entire object graph. Direct port of
/// `di/AppContainer.kt` (the hand-rolled DI container) **+** `di/KoinModules.kt` (the Koin module
/// that exposed that graph to ViewModels). Ports both because iOS uses no DI library — CONVENTIONS
/// §2 mandates a hand-rolled container that matches `AppContainer` 1:1, with ViewModels built by
/// **factory methods** on the container instead of Koin's `by viewModel()`.
///
/// ## Mapping to the Android container (CONVENTIONS §2)
/// - **`by lazy` → `lazy var`:** every node is a `lazy var`, the direct analogue of Kotlin
///   `val x by lazy { … }` — once-only, computed on first access. Not thread-safe, which is fine:
///   the graph is built/read on the **main actor** at launch (this class is `@MainActor`), so there
///   is no concurrent first-touch. This is the "lazy-var graph (thread-safety caveat)" called out in
///   DESIGN §11 cross-cutting.
/// - **Protocol-typed storage:** `bookmarkRepository`, `authRepository`, `embeddingProvider`,
///   `textGenerator` are stored behind their **protocol** types (Koin `single<Interface>`) so call
///   sites depend on abstractions. The concrete selector chains (Text/Embedding) are assembled from
///   private `lazy var`s exactly as `AppContainer` did.
/// - **Two `URLSession` configs:** `AppContainer` built two OkHttp clients (primary 120 s read for
///   xAI/X; metadata 15 s for arXiv/Crossref/HF). Here the single `HTTPClient` actor owns BOTH
///   sessions (primary 120 s + metadata 15 s) and routes per call via `SessionKind`; that one
///   `HTTPClient` is shared by every API client, mirroring how `AppContainer` shared the two OkHttp
///   instances across Retrofit builders. No DI library (no Factory/Swinject).
/// - **Singletons:** `CurioDatabase.shared` (Room `@Volatile INSTANCE` analogue) and the
///   `XaiKeyStore` static slot are the two sanctioned globals (CONVENTIONS §2); everything else is
///   constructor-injected through this container.
/// - **`@Dependency` for App Intents:** App Intents cannot read `@Environment`, so they use App
///   Intents' own `@Dependency`. `CurioApp.init` registers them via `AppDependencyManager` from the
///   instances this container exposes (`bookmarkRepository`, `tokenStore`); this container is the
///   source of truth for those registrations.
///
/// ## Teardown
/// `close()` cancels the repository's long-lived background mirror `Task` tree (port of
/// `AppContainer.close()` → `BookmarkRepositoryImpl.close()`); called from `CurioApp` scene teardown
/// and `deinit`.
///
/// `@MainActor @Observable final class` (CONVENTIONS §2/§4): it is injected into SwiftUI via
/// `.environment(_:)` and read with `@Environment(AppEnvironment.self)`; the `@Observable` conformance
/// lets views observe it directly, and `@MainActor` matches the "graph built/read on the main actor at
/// launch" guarantee that justifies the non-thread-safe `lazy var`s.
@MainActor
@Observable
final class AppEnvironment {

    // ========================================================================
    // Networking — shared HTTP layer (two URLSession configs live inside HTTPClient)
    // ========================================================================

    /// Shared URLSession layer. Owns BOTH the primary (120 s read, `waitsForConnectivity`) and the
    /// metadata (15 s read) sessions and routes per call via `SessionKind` — the iOS consolidation of
    /// `AppContainer`'s two OkHttp clients (`okHttpClient` + `metadataClient`). The redacting logger
    /// never logs the `Authorization` header or bodies (CONVENTIONS §3 / DESIGN §11 secret hygiene),
    /// matching the Android `redactHeader("Authorization")` + headers-only logging.
    @ObservationIgnored lazy var http: HTTPClient = HTTPClient()

    // ========================================================================
    // Secure store + auth
    // ========================================================================

    /// Keychain-backed secure store. Port of `AppContainer.tokenStore`.
    @ObservationIgnored lazy var tokenStore: TokenStore = TokenStore()

    /// X OAuth token exchange / refresh / `users/me` client. Was `retrofit.create(XAuthApi)` against
    /// base `https://api.twitter.com/` in `AppContainer`; here the actor wraps the shared `HTTPClient`
    /// with that same base host.
    @ObservationIgnored lazy var xAuthApi: XAuthApi = XAuthApiClient(http: http)

    /// Auth lifecycle (PKCE flow, session stream, boot restore). Port of `AppContainer.authRepository`
    /// (`AuthRepositoryImpl(xAuthApi, tokenStore)`). Stored behind the `AuthRepository` protocol
    /// (Koin `single<AuthRepository>`).
    @ObservationIgnored lazy var authRepository: AuthRepository =
        AuthRepositoryImpl(api: xAuthApi, tokenStore: tokenStore)

    /// Stateless login pass-through. Port of `AppContainer.loginUseCase`.
    @ObservationIgnored lazy var loginUseCase: LoginUseCase =
        LoginUseCase(authRepository: authRepository)

    /// Synchronous resolver for the runtime xAI key (user-supplied via Keychain, else build-time
    /// secret). Mirrors the Kotlin `object XaiKeyStore` passed to `XAiAnalyzer` / `GrokImageService` /
    /// `EmbeddingService`. A value type — re-created cheaply; the mutable runtime slot is a static
    /// inside `XaiKeyStore` (the genuinely app-global key, lock-guarded).
    @ObservationIgnored lazy var xaiKeyStore: XaiKeyStore = XaiKeyStore()

    // ========================================================================
    // xAI Grok API + analyzers
    // ========================================================================

    /// xAI Grok endpoints (chat/vision/embeddings/images). Was `xAiRetrofit.create(XAiApi)` against
    /// base `https://api.x.ai/` in `AppContainer`. Stored behind the `XAiApi` protocol.
    @ObservationIgnored lazy var xAiApi: XAiApi = XAiApiClient(http: http)

    /// OCR engine (Vision). Port of `AppContainer.ocrAnalyzer`. No deps (matches `OcrAnalyzer()`).
    @ObservationIgnored lazy var ocrAnalyzer: OcrAnalyzer = OcrAnalyzer()

    /// Cloud bookmark analysis / vision / chat / digest. Port of `AppContainer.aiAnalyzer`
    /// (`XAiAnalyzer(xAiApi)`). The Kotlin analyzer read the global `XaiKeyStore`; the iOS port takes
    /// the resolver explicitly (constructor injection) — `xaiKeyStore` conforms to `XaiKeyResolving`.
    @ObservationIgnored lazy var aiAnalyzer: XAiAnalyzer =
        XAiAnalyzer(xAiApi: xAiApi, keyResolver: xaiKeyStore)

    /// Grok image generation client (used by the VM, which owns the procedural fallback). Port of
    /// `AppContainer.grokImageService` (`GrokImageService(xAiApi)`), resolver injected as above.
    @ObservationIgnored lazy var grokImageService: GrokImageService =
        GrokImageService(xAiApi: xAiApi, keyResolver: xaiKeyStore)

    // ========================================================================
    // Text-generation selector (on-device → cloud → offline keyword)
    //
    // Mirrors `AppContainer`'s private chain:
    //   genAiAvailability → cloudTextGenerator → localTextGenerator → nanoTextGenerator → selector
    // Android's `NanoTextGenerator(genAiAvailability, localTextGenerator)` maps to the iOS
    // `OnDeviceTextGenerator(availability:localFallback:)` (Foundation Models replaces AICore/Nano).
    // ========================================================================

    /// On-device availability gate (Foundation Models). Port of `AppContainer.genAiAvailability`.
    @ObservationIgnored lazy var genAiAvailability: GenAiAvailability = GenAiAvailability()

    /// Cloud backend wrapper. Port of `AppContainer.cloudTextGenerator`.
    @ObservationIgnored lazy var cloudTextGenerator: CloudTextGenerator =
        CloudTextGenerator(xAiAnalyzer: aiAnalyzer)

    /// Offline keyword backend wrapper. Port of `AppContainer.localTextGenerator`.
    @ObservationIgnored lazy var localTextGenerator: LocalKeywordTextGenerator =
        LocalKeywordTextGenerator(xAiAnalyzer: aiAnalyzer)

    /// On-device (Foundation Models) backend with offline-keyword fallback. Port of
    /// `AppContainer.nanoTextGenerator` (`NanoTextGenerator(genAiAvailability, localTextGenerator)`).
    @ObservationIgnored lazy var onDeviceTextGenerator: OnDeviceTextGenerator =
        OnDeviceTextGenerator(availability: genAiAvailability, localFallback: localTextGenerator)

    /// Device-gated selector — the concrete `TextGeneratorSelector` is what gets injected (the
    /// `BookmarkViewModel` constructor takes the concrete `TextGeneratorSelector`, mirroring Koin
    /// `get<TextGeneratorSelector>()`). Port of `AppContainer.textGenerator`.
    @ObservationIgnored lazy var textGenerator: TextGeneratorSelector =
        TextGeneratorSelector(
            nano: onDeviceTextGenerator,
            cloud: cloudTextGenerator,
            local: localTextGenerator,
            availability: genAiAvailability
        )

    // ========================================================================
    // Embeddings (cloud fallback + on-device gated + selector)
    // ========================================================================

    /// Cloud (xAI) embedding provider. Port of `AppContainer.embeddingService` (`EmbeddingService(xAiApi)`).
    /// Uses the default `XaiKeyStore()` resolver inside (matching Android's global-object read).
    @ObservationIgnored lazy var embeddingService: EmbeddingService =
        EmbeddingService(xAiApi: xAiApi)

    /// On-device EmbeddingGemma download/manager (gated, ~180 MB, HF token). Port of
    /// `AppContainer.embeddingModelManager` (`EmbeddingModelManager(context, tokenStore)`). `@Observable
    /// @MainActor` so the Settings UI tracks its `ModelState` directly; safe to hold here since this
    /// container is `@MainActor`.
    @ObservationIgnored lazy var embeddingModelManager: EmbeddingModelManager =
        EmbeddingModelManager(tokenStore: tokenStore)

    /// On-device availability gate (model files present on disk). Port of `AppContainer.embeddingAvailability`.
    @ObservationIgnored lazy var embeddingAvailability: EmbeddingAvailability =
        EmbeddingAvailability(modelManager: embeddingModelManager)

    /// On-device-ONLY embedding provider, **exposed directly** so the charging-gated index worker can
    /// embed on-device with no cloud fallback (CONVENTIONS §9 PRIVACY RULE: background = on-device
    /// embedding only). Port of `AppContainer.onDeviceEmbeddingProvider`.
    @ObservationIgnored lazy var onDeviceEmbeddingProvider: OnDeviceEmbeddingProvider =
        OnDeviceEmbeddingProvider(availability: embeddingAvailability, modelManager: embeddingModelManager)

    /// Foreground embedding provider: on-device when available, else cloud. Port of
    /// `AppContainer.embeddingProvider` (`EmbeddingProviderSelector(onDeviceEmbeddingProvider, embeddingService)`).
    /// Stored behind the `EmbeddingProvider` protocol (Koin `single<EmbeddingProvider>`).
    @ObservationIgnored lazy var embeddingProvider: EmbeddingProvider =
        EmbeddingProviderSelector(onDevice: onDeviceEmbeddingProvider, cloud: embeddingService)

    // ========================================================================
    // Scholarly metadata clients + source resolver
    // (metadata session: 15 s — routed inside HTTPClient via SessionKind.metadata)
    // ========================================================================

    /// arXiv Atom client. Was `ArxivClient(metadataClient)`; here the actor wraps the shared
    /// `HTTPClient` (which carries the 15 s metadata session). Port of `AppContainer.arxivClient`.
    @ObservationIgnored lazy var arxivClient: ArxivClient = ArxivClient(http: http)

    /// Crossref DOI client. Port of `AppContainer.crossrefClient` (`CrossrefClient(metadataClient)`).
    @ObservationIgnored lazy var crossrefClient: CrossrefClient = CrossrefClient(http: http)

    /// GitHub repo metadata client. Was `githubRetrofit.create(GithubApi)` against base
    /// `https://api.github.com/`; the actor uses the shared `HTTPClient` with that base.
    @ObservationIgnored lazy var githubApi: GithubApiClient = GithubApiClient(http: http)

    /// Hugging Face model/dataset metadata client. Was `huggingFaceRetrofit.create(HuggingFaceApi)`
    /// against base `https://huggingface.co/api/` on the metadata client.
    @ObservationIgnored lazy var huggingFaceApi: HuggingFaceApiClient = HuggingFaceApiClient(http: http)

    /// Primary-source resolver (arXiv > HF-paper > GitHub > HF model/dataset > bare-arXiv > DOI).
    /// Port of `AppContainer.sourceResolver`
    /// (`SourceResolver(arxivClient, githubApi, huggingFaceApi, crossrefClient)`).
    @ObservationIgnored lazy var sourceResolver: SourceResolver =
        SourceResolver(
            arxivClient: arxivClient,
            githubApi: githubApi,
            huggingFaceApi: huggingFaceApi,
            crossrefClient: crossrefClient
        )

    // ========================================================================
    // Persistence + Firestore mirror
    // ========================================================================

    /// The single `ModelContainer` (store `curio_database` in Application Support). Port of
    /// `AppContainer.database` (`AppDatabase.getDatabase(context)`); `CurioDatabase.shared` is the
    /// sanctioned singleton (Room `INSTANCE` analogue).
    @ObservationIgnored lazy var database: CurioDatabase = CurioDatabase.shared

    /// Bookmarks DAO equivalent (`@ModelActor` off-main store). Built from the shared container —
    /// the iOS analogue of `database.bookmarkDao()`. `@ModelActor` synthesises
    /// `init(modelContainer:)`.
    @ObservationIgnored lazy var bookmarkStore: BookmarkStore =
        BookmarkStore(modelContainer: database.container)

    /// Spaces DAO equivalent (`@ModelActor`). Analogue of `database.spaceDao()`.
    @ObservationIgnored lazy var spaceStore: SpaceStore =
        SpaceStore(modelContainer: database.container)

    /// Anonymous-auth-gated Firestore mirror. Port of `AppContainer.firebaseSyncManager`
    /// (`FirebaseSyncManager(context)`). `FirebaseApp.configure()` is invoked by `CurioApp.init`
    /// before this is touched (the manager self-configures defensively if not).
    @ObservationIgnored lazy var firebaseSyncManager: FirebaseSyncManager = FirebaseSyncManager()

    /// ChronosFlow handoff bridge ("remind me to read later" / inbox / task). Port of
    /// `AppContainer.chronosFlowBridge` (`ChronosFlowBridge(context)`).
    @ObservationIgnored lazy var chronosFlowBridge: ChronosFlowBridge = ChronosFlowBridge()

    // ========================================================================
    // Unified Live Activity + in-house reminders (no Android AppContainer node —
    // Android wires these in CurioApplication; here they live in the graph)
    // ========================================================================

    /// Drives Curio's single unified Live Activity (sync / sweep / index / digest). Shared between the
    /// `BackgroundTaskCoordinator` (assembled in `CurioApp.init`) and the ViewModel/digest paths.
    @ObservationIgnored lazy var liveActivityManager: LiveActivityManager = LiveActivityManager()

    /// Schedules Curio-owned read-later reminders in-house (twin of Android `ReminderScheduler`).
    @ObservationIgnored lazy var reminderScheduler: ReminderScheduler = ReminderScheduler()

    /// Off-main store for the on-device semantic response cache (`@ModelActor`), analogue of
    /// `database.semanticCacheDao()`.
    @ObservationIgnored lazy var semanticCacheStore: SemanticCacheStore =
        SemanticCacheStore(modelContainer: database.container)

    /// On-device semantic layer: response cache + RAG compression + complexity routing. Replaces
    /// the former Python sidecar client; fully local, single-user.
    @ObservationIgnored lazy var onDeviceSemanticLayer: OnDeviceSemanticLayer =
        OnDeviceSemanticLayer(cacheStore: semanticCacheStore)

    /// Retained notification-center delegate (banner-while-foreground + tap-opens-link). Set as the
    /// `UNUserNotificationCenter` delegate in `CurioApp.init`.
    @ObservationIgnored lazy var reminderNotificationDelegate: ReminderNotificationCenterDelegate =
        ReminderNotificationCenterDelegate()

    /// Paginated X v2 bookmarks client. Was `retrofit.create(XBookmarksApi)` against base
    /// `https://api.twitter.com/`; the actor wraps the shared `HTTPClient`.
    @ObservationIgnored lazy var xBookmarksApi: XBookmarksApi = XBookmarksApiClient(http: http)

    // ========================================================================
    // Repository (single source of truth) — depends on everything above
    // ========================================================================

    /// Offline-first bookmark + Space repository (3-phase sync, smart-spaces, embeddings, curation).
    /// Port of `AppContainer.bookmarkRepository`:
    /// `BookmarkRepositoryImpl(xBookmarksApi, bookmarkDao, spaceDao, tokenStore, firebaseSyncManager, xAuthApi)`.
    /// Stored behind the `BookmarkRepository` protocol (Koin `single<BookmarkRepository>`); the
    /// concrete actor is recovered in `close()` to cancel its mirror tasks.
    @ObservationIgnored lazy var bookmarkRepository: BookmarkRepository =
        BookmarkRepositoryImpl(
            api: xBookmarksApi,
            store: bookmarkStore,
            spaceStore: spaceStore,
            tokenStore: tokenStore,
            firebaseSyncManager: firebaseSyncManager,
            authApi: xAuthApi
        )

    // ========================================================================
    // Init / teardown
    // ========================================================================

    /// Builds the empty container; nodes are constructed lazily on first access (mirrors `by lazy`).
    init() {}

    /// Releases resources held by long-lived components. Port of `AppContainer.close()` →
    /// `(bookmarkRepository as? BookmarkRepositoryImpl)?.close()`: cancels the repository's detached
    /// background mirror `Task` tree. Called from `CurioApp` scene teardown / `deinit` (CONVENTIONS §2).
    ///
    /// Only acts if the repository was actually built (touching the `lazy var` would otherwise
    /// force-construct the whole graph during teardown). `BookmarkRepository` is a `Sendable`
    /// protocol; the concrete `close()` is on the `actor`, so the call hops onto the actor.
    func close() {
        if let impl = builtRepository as? BookmarkRepositoryImpl {
            Task { await impl.close() }
        }
    }

    deinit {
        // `deinit` cannot `await`; fire-and-forget the actor cancellation. The repository's own
        // `deinit` also cancels its tasks, so this is belt-and-suspenders for an explicit teardown
        // that did not call `close()`. Reads the recorded slot (NOT the `lazy var`) so teardown never
        // force-constructs the entire graph just to tear it down.
        if let impl = builtRepository as? BookmarkRepositoryImpl {
            Task { await impl.close() }
        }
    }

    /// Records whether the repository was actually constructed, so `close()`/`deinit` can tear it
    /// down **without** touching the `lazy var bookmarkRepository` (which would otherwise force-build
    /// the whole graph during teardown). Swift has no built-in "is this lazy var initialized?"
    /// query, so this slot is set the first time the live repository is needed
    /// (`makeBookmarkViewModel()`). In practice the repository is always built at launch — this is a
    /// safety valve for unusual teardown ordering only.
    @ObservationIgnored private var builtRepository: BookmarkRepository?

    // ========================================================================
    // ViewModel factories (replace Koin `by viewModel()` — CONVENTIONS §2)
    //
    // Held by the owning view as `@State private var vm = env.makeX()`. The 9-dependency
    // `BookmarkViewModel` constructor matches Koin's `viewModel { BookmarkViewModel(get(), …) }`
    // exactly (repository, ocrAnalyzer, aiAnalyzer, embeddingProvider, sourceResolver,
    // textGeneratorSelector, grokImageService, embeddingModelManager, tokenStore).
    // ========================================================================

    /// Builds the central feed/library view model. Port of the Koin
    /// `viewModel { BookmarkViewModel(...) }`. `embeddingService` is the **selector** provider
    /// (`embeddingProvider`), matching Koin `get<EmbeddingProvider>()`; `textGenerator` is the
    /// concrete `TextGeneratorSelector` (`get<TextGeneratorSelector>()`).
    func makeBookmarkViewModel() -> BookmarkViewModel {
        // Mark the repository as built so teardown can find it (it's constructed here regardless).
        builtRepository = bookmarkRepository
        return BookmarkViewModel(
            repository: bookmarkRepository,
            ocrAnalyzer: ocrAnalyzer,
            aiAnalyzer: aiAnalyzer,
            embeddingService: embeddingProvider,
            sourceResolver: sourceResolver,
            textGenerator: textGenerator,
            grokImageService: grokImageService,
            embeddingModelManager: embeddingModelManager,
            tokenStore: tokenStore,
            chronosFlowBridge: chronosFlowBridge,
            liveActivityManager: liveActivityManager,
            reminderScheduler: reminderScheduler,
            semanticLayer: onDeviceSemanticLayer
        )
    }

    /// Builds the OAuth-PKCE auth controller. Port of the Koin
    /// `viewModel { AuthViewModel(get<LoginUseCase>(), get<AuthRepository>()) }`.
    ///
    /// `AuthViewModel` is a Screens-module type (`@MainActor @Observable final class`, ported in
    /// `Screens/AuthViewModel.swift`); its initializer takes `(loginUseCase:authRepository:)` per
    /// DESIGN §10. This factory wires the two graph nodes Koin resolved.
    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(loginUseCase: loginUseCase, authRepository: authRepository)
    }
}
