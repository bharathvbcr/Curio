//
//  CurioApp.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/CurioApplication.kt  (Application bootstrap:
//         DI graph wiring, charging-gated embedding-index scheduling, runtime xAI-key load,
//         App-Function configuration provider)
//      +  app/src/main/java/com/example/MainActivity.kt       (entry Activity: background
//         sweeper start, edge-to-edge, share-receive (ACTION_SEND) ingestion, OAuth deep-link
//         redirect, setContent → BookmarkApp)
//
//  DESIGN §12 (App): `@main App` — configure Firebase, build `AppEnvironment`, register BGTasks,
//  inject the environment, host `BookmarkApp`; drain shares + ensureScheduled on `.active`;
//  `close()` on teardown. The Android split across `CurioApplication` (process bootstrap) and
//  `MainActivity` (UI entry + intent handling) collapses into one SwiftUI `App`, because the
//  SwiftUI lifecycle has no separate `Application` object — the composition root, scene wiring,
//  container lifecycle, Firebase configure, BGTask registration, and share-drain all live here.
//
//  CONVENTIONS mapping (by name):
//  - §2 "DI / composition root": the single `AppEnvironment` is built once and owned by the app
//    scene (`@State private var env = AppEnvironment()`), injected via `.environment(env)` and read
//    downstream with `@Environment(AppEnvironment.self)`. The two ViewModels are built by the
//    container's factory methods (`makeBookmarkViewModel()` / `makeAuthViewModel()`) and held as
//    `@State` by this scene — the direct analogue of Koin `by viewModel()` resolved in
//    `MainActivity`. App Intents cannot read `@Environment`, so their dependencies
//    (`BookmarkRepository`, `TokenStore`, `ChronosFlowBridge`) are registered at launch via `AppDependencyManager`
//    (replaces the Android `AppFunctionConfiguration.Provider` / `addEnclosingClassFactory`).
//  - §2 "Teardown": `env.close()` cancels the repository's long-lived mirror Task tree; called from
//    scene teardown (`.background` phase) — matching Android `AppContainer.close()`.
//  - §9 "BGTask": the `BackgroundTaskCoordinator` `register`s its handlers in `init` **before the
//    app finishes launching** (the `BGTaskScheduler` contract), and `ensureScheduled()` re-arms the
//    charging-gated embedding backfill + link sweep on every foreground (`.active`) — mirroring
//    `CurioApplication.onCreate` → `EmbeddingIndexScheduler.ensureScheduled` and
//    `BookmarkSweeperScheduler.ensureScheduled` (WorkManager). PRIVACY RULE preserved: only
//    offline maintenance (link sweep) + on-device-only embedding run in the background.
//  - §9 "Secrets": the user-supplied xAI key is loaded from the Keychain into the process-wide
//    `XaiKeyStore` runtime slot **asynchronously** at launch and again on foreground (matching the
//    Android `CoroutineScope(Dispatchers.IO).launch { XaiKeyStore.setRuntimeKey(...) }`), so the app
//    uses the user's own key instead of a build-time key baked into the bundle.
//  - §8 "Theme": the root `BookmarkApp` owns the System/Light/Dark resolution and `.curioTheme(...)`
//    wrapper internally (it reads `bookmarkViewModel.themeSetting`), so this scene simply hosts it;
//    the brand seed stays the canonical Cosmic palette (no `brandSeed` override).
//
//  Share-drain (Android `MainActivity.handleSendIntent`): the iOS Share Extension queues payloads
//  into the App-Group `UserDefaults` (`pendingShares`); this scene drains that FIFO on every
//  `.active` transition and on first launch, feeding each entry through
//  `BookmarkViewModel.captureSharedText(_:)` (which ingests immediately when signed in, else queues
//  until `setUserId`). The "fresh launch vs config-change recreate" guard the Android Activity used
//  (`savedInstanceState == null`) has no SwiftUI analogue — draining is idempotent because each
//  drained payload is removed from the queue, so re-entry never re-processes an item.
//
//  OAuth redirect (Android `MainActivity.handleDeepLink`): on iOS the entire browser round-trip is
//  owned by `ASWebAuthenticationSession` inside `AuthViewModel.onLoginClick`, so there is NO custom
//  `curio-oauth://callback` deep-link entry point to wire here — the callback URL is delivered
//  directly to the session. `CFBundleURLTypes` still registers the scheme (so the session's callback
//  matcher resolves it), but the app never receives it via `onOpenURL`.
//

import SwiftUI
import SwiftData
import Observation
import AppIntents
import BackgroundTasks
import UserNotifications
import FirebaseCore

/// Curio's SwiftUI application entry point. Consolidates the Android `CurioApplication`
/// (process bootstrap) and `MainActivity` (UI entry + intent handling) into one `@main App`.
@main
struct CurioApp: App {

    // MARK: - Composition root (CONVENTIONS §2)

    /// Single object graph, built once and owned by the app scene. Injected into SwiftUI via
    /// `.environment(_:)` and read downstream with `@Environment(AppEnvironment.self)`. Direct port
    /// of `CurioApplication.appContainer` (the hand-rolled DI container) — `@MainActor @Observable`,
    /// so holding it as `@State` keeps it alive for the whole app lifetime.
    @State private var env: AppEnvironment

    // MARK: - Owned ViewModels (replace Koin `by viewModel()` in `MainActivity`)

    /// Central library view model. Built by the container's factory (Koin
    /// `viewModel { BookmarkViewModel(...) }`) and owned by the scene for its lifetime. The whole
    /// shell observes it, so it must outlive any single view (it feeds background streams eagerly —
    /// CONVENTIONS §4 "Eager source stream").
    @State private var bookmarkViewModel: BookmarkViewModel

    /// OAuth-PKCE controller. Built by the container's factory; owned by the scene so the
    /// `ASWebAuthenticationSession` it drives stays retained for the whole login round-trip.
    @State private var authViewModel: AuthViewModel

    // MARK: - Background coordinator (BGTask registration + scheduling)

    /// Schedules + routes the charging-gated on-device embedding backfill and the 404/410 link
    /// sweep. Built from container nodes (the `EmbeddingIndexer` / `LinkSweeper` are not part of the
    /// foreground graph in `AppEnvironment`, so they are assembled here). Its `registerHandlers()`
    /// runs in `init` (before launch finishes) per the `BGTaskScheduler` contract; `ensureScheduled`
    /// re-arms on every foreground. Ports `CurioApplication` → `EmbeddingIndexScheduler.ensureScheduled`
    /// and `BookmarkSweeperScheduler.ensureScheduled` (WorkManager).
    @State private var background: BackgroundTaskCoordinator

    // MARK: - Scene phase (for foreground drain / scheduling / teardown)

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - App-Group share hand-off contract (mirrors `ShareViewController`)

    /// App Group suite that the Share Extension writes pending payloads into. MUST match
    /// `ShareViewController.appGroupIdentifier` and the entitlements on both targets.
    private static let appGroupIdentifier = "group.com.curio.app"
    /// FIFO key the Share Extension appends to; drained + cleared here on `.active`. MUST match
    /// `ShareViewController.pendingSharesKey`.
    private static let pendingSharesKey = "pendingShares"

    // MARK: - Init (process bootstrap — CurioApplication.onCreate + MainActivity.onCreate)

    init() {
        // ── Firebase ──────────────────────────────────────────────────────────────────────────
        // Configure Firebase once at launch (reads `GoogleService-Info.plist` from the app target).
        // `FirebaseSyncManager` self-configures defensively if it touches Firestore before this, but
        // doing it here matches the Android `FirebaseApp.initializeApp` happening at process start
        // and guarantees a single configuration. Guarded against a double-configure (e.g. across
        // SwiftUI previews / test harnesses re-instantiating the App) the same way the Android Koin
        // start was guarded by `GlobalContext.getOrNull() == null`.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // ── Composition root ──────────────────────────────────────────────────────────────────
        // Build the single object graph (Android `appContainer = AppContainer(this)`). `@MainActor`;
        // `CurioApp.init` runs on the main actor, so constructing it here is sound.
        let environment = AppEnvironment()
        _env = State(initialValue: environment)

        // ── ViewModels (Koin `by viewModel()` in MainActivity) ──────────────────────────────────
        _bookmarkViewModel = State(initialValue: environment.makeBookmarkViewModel())
        _authViewModel = State(initialValue: environment.makeAuthViewModel())

        // ── App Intent dependencies (replace AppFunctionConfiguration.Provider) ─────────────────
        // App Intents cannot read `@Environment`, so they resolve their dependencies through App
        // Intents' own `@Dependency` mechanism. Register the three the intents declare
        // (`BookmarkRepository`, `TokenStore`, `ChronosFlowBridge`) from the live graph nodes — the iOS analogue of the
        // Android `AppFunctionConfiguration.Builder().addEnclosingClassFactory(CurioFunctions…)`.
        // Registered with the protocol-typed repository so `@Dependency private var
        // bookmarkRepository: any BookmarkRepository` resolves the same single instance the UI uses.
        // The closure form `add { … }` is the form CONVENTIONS §2 prescribes; the closure returns the
        // already-built graph node so the resolved dependency is the SAME instance the UI graph uses
        // (App Intents caches the closure result per type).
        let repository: any BookmarkRepository = environment.bookmarkRepository
        let tokenStore = environment.tokenStore
        let chronosFlowBridge = environment.chronosFlowBridge
        AppDependencyManager.shared.add { repository }
        AppDependencyManager.shared.add { tokenStore }
        AppDependencyManager.shared.add { chronosFlowBridge }

        // ── Background coordinator ──────────────────────────────────────────────────────────────
        // Assemble the on-device-only embedding backfill + link sweep from container nodes. The
        // indexer takes the **on-device-only** provider (never the cloud selector) so the background
        // backfill can't fall back to cloud (CONVENTIONS §9 PRIVACY RULE). The sweeper reads the
        // device-wide store directly and mirrors deletions to Firestore.
        let indexer = EmbeddingIndexer(
            onDeviceEmbeddingProvider: environment.onDeviceEmbeddingProvider,
            bookmarkRepository: repository,
            tokenStore: tokenStore
        )
        let sweeper = LinkSweeper(
            store: environment.bookmarkStore,
            firebaseSyncManager: environment.firebaseSyncManager
        )
        // The coordinator surfaces sweep/index runs in the ONE unified Live Activity shared with the
        // rest of the graph (sync/digest feed the same manager from the ViewModel).
        let coordinator = BackgroundTaskCoordinator(
            indexer: indexer,
            sweeper: sweeper,
            liveActivityManager: environment.liveActivityManager
        )
        _background = State(initialValue: coordinator)

        // Route reminder banners (foreground) + taps (open the saved link) through Curio's delegate.
        UNUserNotificationCenter.current().delegate = environment.reminderNotificationDelegate

        // BGTask handlers MUST be registered before `application(_:didFinishLaunchingWithOptions:)`
        // returns — i.e. during App `init` (CONVENTIONS §9 / `BGTaskScheduler` contract). Doing it
        // here (not lazily) guarantees the identifiers are claimed before the OS may launch a task.
        coordinator.registerHandlers()
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            // The root container owns the auth gate, theme wrapper, drawer, routed screens, the
            // manual-add sheet and the reader cover. Both ViewModels are passed in (Koin-resolved in
            // the Android `setContent { BookmarkApp(authViewModel, bookmarkViewModel) }`).
            BookmarkApp(
                authViewModel: authViewModel,
                bookmarkViewModel: bookmarkViewModel
            )
            // Make the whole object graph readable by any descendant via
            // `@Environment(AppEnvironment.self)` (CONVENTIONS §2).
            .environment(env)
            // Bind the shared SwiftData container so `@Query`/`@Environment(\.modelContext)` resolve
            // the same store the `@ModelActor` stores write to (DESIGN §12).
            .modelContainer(env.database.container)
            // First-launch share drain + xAI-key load + BGTask arming. `.task` runs once when the
            // root view appears; the scene-phase handler below covers every subsequent foreground.
            .task {
                await onForeground()
            }
        }
        // React to lifecycle transitions: drain shares + re-arm BGTasks + reload the xAI key on
        // every foreground; cancel long-lived background work when the scene is fully backgrounded
        // (CONVENTIONS §2 teardown). Ports `MainActivity.onNewIntent` (share/redirect re-entry) and
        // `AppContainer.close()`.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await onForeground() }
            case .background:
                // Releases the repository's detached mirror Task tree and any in-flight "run now"
                // background work. The repository / coordinator also cancel in their own `deinit`,
                // so this is the explicit, prompt teardown for a backgrounded scene.
                env.close()
                background.close()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - Foreground entry (drain shares, arm BGTasks, reload xAI key)

    /// Runs the on-foreground housekeeping shared by first launch (`.task`) and every `.active`
    /// transition. Idempotent: draining removes each payload from the queue, scheduling de-dupes by
    /// identifier (WorkManager `KEEP`), and the xAI-key reload simply re-reads the Keychain.
    @MainActor
    private func onForeground() async {
        // (1) Re-arm the charging-gated embedding backfill + link sweep (Android
        //     `EmbeddingIndexScheduler.ensureScheduled` + the sweeper's startup scheduling). Safe to
        //     call every foreground — already-pending requests are left unchanged.
        background.ensureScheduled()

        // (1a) Ask for notification permission once (for reminders + the Live Activity's alerts), and
        //      clear any "digest ready" / error attention now that the user is back in the app
        //      (mirrors Android `MainActivity.onResume` → `clearAttention()`).
        await env.reminderScheduler.requestAuthorizationIfNeeded()
        env.liveActivityManager.clearAttention()

        // (2) Load any user-supplied xAI key (Keychain) into the process-wide runtime slot, so the
        //     app prefers the user's own key over a build-time key. Mirrors
        //     `CurioApplication.onCreate` → `XaiKeyStore.setRuntimeKey(tokenStore.getXaiKey())`.
        //     `getXaiKey()` is a non-throwing actor read returning `nil` on any failure, so the
        //     Android `runCatching { … }.onFailure { … }` collapses to a plain `await` here.
        let key = await env.tokenStore.getXaiKey()
        XaiKeyStore.setRuntimeKey(key)

        // (3) Drain any payloads the Share Extension queued while we were backgrounded / not running
        //     (Android `MainActivity.handleSendIntent`). Each is fed through `captureSharedText`,
        //     which ingests immediately when signed in or queues until `setUserId` otherwise.
        drainPendingShares()

        // (4) Background embedding may have auto-filed cards; refresh medium-confidence suggestions.
        bookmarkViewModel.refreshSuggestionsOnForeground()
    }

    // MARK: - Share-drain (App-Group FIFO → captureSharedText)

    /// Drains the App-Group `pendingShares` FIFO written by the Share Extension and feeds each
    /// payload through `BookmarkViewModel.captureSharedText(_:)`, then clears the queue. Direct port
    /// of `MainActivity.handleSendIntent`'s capture path: a non-empty payload routes through the
    /// bookmark capture path; an empty queue is a no-op (the Android "Nothing to save" Toast has no
    /// place here — the extension already filtered empties before enqueuing).
    ///
    /// Order is preserved (FIFO) and the queue is cleared in one write so a payload is never
    /// processed twice. `captureSharedText` itself decides immediate-ingest vs queue-until-sign-in,
    /// so a share that arrives while signed out is held by the VM until `setUserId` runs (matching
    /// the Android "Sign in to Curio to finish saving" deferral).
    @MainActor
    private func drainPendingShares() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else { return }
        let queue = defaults.stringArray(forKey: Self.pendingSharesKey) ?? []
        guard !queue.isEmpty else { return }
        // Clear first so a re-entrant foreground (or a crash mid-drain) can't double-ingest the same
        // payloads; the VM owns the captured text from here on.
        defaults.removeObject(forKey: Self.pendingSharesKey)
        for payload in queue {
            bookmarkViewModel.captureSharedText(payload)
        }
    }
}
