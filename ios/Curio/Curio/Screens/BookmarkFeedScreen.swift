//
//  BookmarkFeedScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/BookmarkFeedScreen.kt
//         (BookmarkFeedScreen, BulkActionTile).
//
//  DESIGN §10 (Screens): the primary feed. A merged header (brand-less menu + search pill with a
//  3-way AI toggle + live count + sync/overflow controls + quick filters + Space chips + active-
//  Space / active-filter banners), a sync-status banner, the bookmark list (or empty / no-match
//  state), a floating bulk-operations action bar (multi-select, two-step delete), and four sheets:
//  export, model download, assign-to-space, and new-space.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": the Kotlin `collectAsStateWithLifecycle()` reads collapse to
//    plain `@Bindable` property reads off the injected `BookmarkViewModel`. The Compose
//    `remember { mutableStateOf(...) }` local UI flags become `@State`.
//  - §4 "Sealed UI states": `SyncUiState` / `AnalysisUiState` / `EmbeddingModelManager.ModelState`
//    are switched over exhaustively; EXACT user-facing strings are preserved verbatim (including
//    "X Rate Limited. Resume syncing in {n}s", "Synchronizing bookmarks feed from X.com...").
//  - §8 "Theme": colors via `@Environment(\.curioColors)`; glass via `glassSurface(tier:...)`;
//    press feedback via `.curioPressBounce`; non-hit-testing selection bounce via `.bounceScale`.
//  - §10 "stable id keys": the list iterates `bookmark.id`; the bulk selection is a `Set<String>`.
//  - The Compose `PullToRefreshBox` becomes SwiftUI `.refreshable`; the `DropdownMenu` overflow
//    becomes a SwiftUI `Menu`; the `LazyColumn` header items collapse into a single `ScrollView`
//    + `LazyVStack`. The merged search `TextField`'s AI toggle keeps the EXACT 3-way logic:
//    turning AI off is always allowed; turning it on requires the on-device model (else prompt).
//
//  The leaf widgets this screen composes (`CurioPostCard`, `CurioCardActions`, `QuickFilterPill`,
//  `FeedIconAction`, `CurioEmptyState`, `SlideUpCard`, `AssignToSpaceDialog`, `SpaceEditorDialog`,
//  `spaceIcon`, `CurioFormat.*`) live in the Components / Screens modules and are treated as the
//  documented API surface (DESIGN "Notes for implementers").
//

import SwiftUI

// MARK: - BookmarkFeedView

/// The flagship bookmarks feed. Direct port of `@Composable fun BookmarkFeedScreen(...)`.
struct BookmarkFeedView: View {
    /// Central library view model. Injected, owned upstream; `@Bindable` so its derived feed /
    /// sync / analysis state drives the view reactively.
    @Bindable var viewModel: BookmarkViewModel
    let tier: GlassTier
    let onBookmarkClick: (Bookmark) -> Void
    var onOpenMenu: () -> Void = {}
    /// Opens the Settings screen (the BYOK setup banner's tap target). Port of `onNavigateToSettings`.
    var onNavigateToSettings: () -> Unit = {}
    var loginSuccessMessage: String? = nil
    var onDismissLoginSuccess: () -> Void = {}

    @Environment(\.curioColors) private var colors

    // MARK: - Local UI state (Compose `remember { mutableStateOf(...) }`)

    /// Multi-select set (bulk operations). Port of `var selectedIds by remember { … emptySet() }`.
    @State private var selectedIds: Set<String> = []
    @State private var showBulkSpaceDialog = false
    @State private var showBulkNewSpace = false
    @State private var isReorderMode = false
    @State private var showExportDialog = false
    @State private var showModelDialog = false
    /// Two-step bulk-delete arming. Port of `var confirmingBulkDelete by remember { … false }`.
    @State private var confirmingBulkDelete = false

    // MARK: - Derived reads (mirror the Kotlin `collectAsState` snapshots)

    private var bookmarks: [Bookmark] { viewModel.bookmarks }
    private var stats: CurioStats { viewModel.stats }
    private var spaces: [Space] { viewModel.spaces }
    private var searchQuery: String { viewModel.searchQuery }
    private var selectedTag: String? { viewModel.selectedTag }
    private var searchMode: SearchMode { viewModel.searchMode }
    private var quickFilter: QuickFilter { viewModel.quickFilter }
    private var selectedSpaceId: String? { viewModel.selectedSpaceId }
    private var forceLocalNano: Bool { viewModel.forceLocalNano }
    private var isSemanticLoading: Bool { viewModel.isSemanticLoading }
    private var embeddingModelState: EmbeddingModelManager.ModelState { viewModel.embeddingModelState }

    /// `spaces.firstOrNull { it.id == selectedSpaceId }`.
    private var activeSpace: Space? {
        guard let id = selectedSpaceId else { return nil }
        return spaces.first { $0.id == id }
    }

    /// `syncState is SyncUiState.Loading`.
    private var isSyncing: Bool {
        if case .loading = viewModel.syncState { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // The Compose `PullToRefreshBox` → SwiftUI `.refreshable` on the scroll view.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerItem
                    loginSuccessBanner
                    byokSetupBanner
                    syncStatusBanner
                    analysisErrorBanner
                    listSection
                    // `item { Spacer(modifier = Modifier.height(80.dp)) }`.
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 16)
            }
            .refreshable {
                viewModel.syncBookmarks(fetchNextPage: false)
            }

            // Floating bulk operations action bar (overlaid at the bottom).
            if !selectedIds.isEmpty {
                bulkActionBar
                    .padding(.bottom, 24)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            for await message in viewModel.curationError {
                CurioNotifier.notify(message)
            }
        }
        .task(id: viewModel.syncState) {
            if case .success = viewModel.syncState {
                try? await Task.sleep(for: .seconds(5))
                if case .success = viewModel.syncState {
                    viewModel.dismissSyncBanner()
                }
            }
        }
        .animation(CurioMotion.liquid, value: selectedIds.isEmpty)
        // Reset the delete-confirm arming whenever the selection changes underneath it.
        // Port of `LaunchedEffect(selectedIds) { confirmingBulkDelete = false }`.
        .onChange(of: selectedIds) { _, _ in
            confirmingBulkDelete = false
        }
        .sheet(isPresented: $showExportDialog) { exportDialog }
        .sheet(isPresented: $showModelDialog) { modelDialog }
        .sheet(isPresented: $showBulkSpaceDialog) { bulkSpaceDialog }
        .sheet(isPresented: $showBulkNewSpace) { bulkNewSpaceDialog }
    }

    // ========================================================================
    // 0. MERGED HEADER — brand · search · controls · filters
    // ========================================================================

    private var headerItem: some View {
        VStack(alignment: .leading, spacing: 11) {
            searchRow          // Row 1
            statControlStrip   // Row 2
            quickFilterRow     // Row 3
            spaceChipsRow      // Row 4
            activeSpaceBanner
            activeFilterBanner
        }
        // `Modifier.statusBarsPadding().padding(top = 6.dp)` — the status-bar inset is provided by
        // the scroll view's safe area; the explicit top padding is carried.
        .padding(.top, 6)
    }

    // ── Row 1: hamburger · merged search pill (with AI toggle) · live count ──

    private var searchRow: some View {
        HStack(spacing: 8) {
            // Menu button (opens the workspace drawer).
            Button {
                onOpenMenu()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.onSurface)
                    .frame(width: 44, height: 44)
                    .glassSurface(tier: tier, shape: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")

            // Merged search pill (search field + clear + AI toggle).
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.onSurface.opacity(0.5))
                    .accessibilityHidden(true)

                TextField(
                    "",
                    text: Binding(
                        get: { searchQuery },
                        set: { viewModel.updateSearchQuery($0) }
                    )
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.onSurface)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .overlay(alignment: .leading) {
                    if searchQuery.isEmpty {
                        Text("Search your index…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("search_field_input")

                if !searchQuery.isEmpty {
                    Button {
                        viewModel.updateSearchQuery("")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(colors.onSurface.opacity(0.5))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear raw query")
                }

                aiToggle
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity)
            .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    /// The 3-way AI search toggle. Tapping it: turning AI OFF is always allowed; turning it ON
    /// needs the on-device model (else the model-download dialog is prompted).
    private var aiToggle: some View {
        let isSemantic = searchMode == .semantic
        return Button {
            // when { semantic -> KEYWORD; ready -> SEMANTIC; else -> prompt }.
            if isSemantic {
                viewModel.setSearchMode(.keyword)
            } else if case .ready = embeddingModelState {
                viewModel.setSearchMode(.semantic)
            } else {
                showModelDialog = true
            }
        } label: {
            Group {
                if isSemanticLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(isSemantic ? .white : colors.primary)
                        .frame(width: 13, height: 13)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSemantic ? .white : colors.onSurface.opacity(0.6))
                        Text("AI")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(isSemantic ? .white : colors.onSurface.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSemantic {
                    curioAccentBrush(primary: colors.primary, tertiary: colors.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    colors.onSurface.opacity(0.08)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
        .bounceScale(active: isSemantic)
        .accessibilityLabel(isSemantic ? "Disable AI semantic search" : "Enable AI semantic search")
    }

    // ── Row 2: compact stat + control strip ──

    private var statControlStrip: some View {
        HStack(alignment: .center) {
            // Stats.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    Text("\(bookmarks.count)")
                        .font(.system(size: 28, weight: .black))
                        .tracking(-1)
                        .foregroundStyle(colors.onSurface)
                    Text("bookmarks")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.onSurface.opacity(0.55))
                        .padding(.bottom, 3)
                }
                Text("\(stats.curatedCount) curated · \(stats.sourceCount) sources")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.5))
            }

            Spacer(minLength: 0)

            // Controls.
            HStack(spacing: 8) {
                syncPill
                overflowMenu
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Primary "Sync" labeled pill.
    private var syncPill: some View {
        Button {
            if !isSyncing { viewModel.syncBookmarks(fetchNextPage: false) }
        } label: {
            HStack(spacing: 6) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(colors.primary)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.primary)
                }
                Text(isSyncing ? "Syncing…" : "Sync")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(colors.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(colors.primary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.curioPressBounce)
        .accessibilityIdentifier("sync_button")
    }

    /// The overflow `Menu` — load older, AI engine switch, reorder. Port of the Compose
    /// `DropdownMenu` opened from the `MoreVert` `FeedIconAction`.
    private var overflowMenu: some View {
        Menu {
            Button {
                viewModel.syncBookmarks(fetchNextPage: true)
            } label: {
                Label("Load older bookmarks", systemImage: "arrow.triangle.2.circlepath.icloud")
            }
            // The engine switch is meaningless without a cloud key (BYOK) — hidden until one is
            // configured, mirroring the Android `if (xaiKeyConfigured)` gate.
            if viewModel.xaiKeyConfigured {
                Button {
                    viewModel.setForceLocalNano(!forceLocalNano)
                } label: {
                    Label(
                        forceLocalNano ? "AI engine: On-device" : "AI engine: Cloud",
                        systemImage: forceLocalNano ? "brain.head.profile" : "sparkles"
                    )
                }
            }
            Button {
                isReorderMode.toggle()
            } label: {
                Label(
                    isReorderMode ? "Done reordering" : "Reorder bookmarks",
                    systemImage: isReorderMode ? "checkmark" : "arrow.up.arrow.down"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.onSurface.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(colors.onSurface.opacity(0.06), in: Circle())
        }
        .accessibilityLabel("More actions")
    }

    // ── Row 3: quick filters (All · Favorites · Read later) ──

    private var quickFilterRow: some View {
        HStack(spacing: 8) {
            QuickFilterPill(
                label: "All",
                systemImage: "bookmark.fill",
                count: quickFilter == .all ? bookmarks.count : nil,
                active: quickFilter == .all,
                color: colors.primary
            ) { viewModel.setQuickFilter(.all) }

            QuickFilterPill(
                label: "Favorites",
                systemImage: "heart.fill",
                count: stats.favoriteCount,
                active: quickFilter == .favorites,
                color: Color(argb: 0xFFFF5A6E)
            ) { viewModel.setQuickFilter(.favorites) }

            // The Kotlin `READ_LATER` pill maps to the Swift enum's `.saved`.
            QuickFilterPill(
                label: "Read later",
                systemImage: "clock.fill",
                count: stats.readLaterCount,
                active: quickFilter == .saved,
                color: colors.secondary
            ) { viewModel.setQuickFilter(.saved) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Row 4: Space chips — quick-switch the feed between collections ──

    @ViewBuilder
    private var spaceChipsRow: some View {
        if !spaces.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" — clears the Space scope.
                    let allActive = selectedSpaceId == nil
                    Button {
                        viewModel.selectSpace(nil)
                    } label: {
                        Text("ALL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(allActive ? colors.primary : colors.onSurface.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                (allActive ? colors.primary.opacity(0.2) : colors.onSurface.opacity(0.05)),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(allActive ? colors.primary : .clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .bounceScale(active: allActive)

                    ForEach(spaces) { space in
                        spaceChip(space)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func spaceChip(_ space: Space) -> some View {
        let active = selectedSpaceId == space.id
        let chipColor = Color(packedARGB: space.color)
        return Button {
            viewModel.selectSpace(active ? nil : space.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: spaceIcon(space.icon))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chipColor)
                Text(space.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? chipColor : colors.onSurface.opacity(0.7))
                if space.count > 0 {
                    Text("\(space.count)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle((active ? chipColor : colors.onSurface).opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (active ? chipColor.opacity(0.2) : colors.onSurface.opacity(0.05)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? chipColor : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .bounceScale(active: active)
    }

    // ── Active Space banner — shown when the feed is scoped to a Space ──

    @ViewBuilder
    private var activeSpaceBanner: some View {
        if let space = activeSpace {
            let spaceColor = Color(packedARGB: space.color)
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(spaceColor.opacity(0.9))
                    Image(systemName: spaceIcon(space.icon))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("SPACE")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(spaceColor)
                        if space.isSmart {
                            Text("· SMART")
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.5)
                                .foregroundStyle(spaceColor.opacity(0.7))
                        }
                    }
                    Text(space.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !space.description.isBlank {
                        Text(space.description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.selectSpace(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(spaceColor)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit space")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(spaceColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(spaceColor.opacity(0.4), lineWidth: 1)
            }
            .accessibilityIdentifier("active_space_banner")
        }
    }

    // ── Active query / tag filter banner ──

    @ViewBuilder
    private var activeFilterBanner: some View {
        if selectedTag != nil || !searchQuery.isBlank {
            HStack {
                Text(filterBannerText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.primary.opacity(0.8))
                Spacer(minLength: 0)
                Button {
                    viewModel.clearAllFilters()
                } label: {
                    Text("CLEAR ALL")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(colors.error)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
    }

    /// `buildString { append("Filtering: "); if (query) "Query '$q' • "; if (tag) "Tag '#$t' " }
    /// .trimEnd(' ', '•')`.
    private var filterBannerText: String {
        var s = "Filtering: "
        if !searchQuery.isBlank { s += "Query '\(searchQuery)' • " }
        if let tag = selectedTag { s += "Tag '#\(tag)' " }
        // `trimEnd(' ', '•')` strips trailing spaces and bullets (NOT a both-ends trim).
        while let last = s.last, last == " " || last == "•" {
            s.removeLast()
        }
        return s
    }

    // ========================================================================
    // 0b. BYOK SETUP BANNER — shown until the user saves an xAI key in Settings
    // ========================================================================

    @ViewBuilder
    private var byokSetupBanner: some View {
        if !viewModel.xaiKeyConfigured {
            // NOT a Button: a Button label swallows every tap, which would make the console.x.ai
            // Markdown link dead (it would route to Settings). A container tap gesture reproduces
            // the Android `ClickableText` annotation split instead — the link region handles its
            // own tap (opens the browser); everywhere else bubbles to the gesture → Settings.
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.tertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add your xAI API key to enable AI features")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                        .multilineTextAlignment(.leading)
                    Text(.init(
                        "Auto-tagging, chat, and weekly digests need a key from " +
                        "[console.x.ai](https://console.x.ai). Tap to set up in Settings."
                    ))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.65))
                    .tint(colors.primary)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onNavigateToSettings)
            .glassSurface(tier: tier, tint: colors.tertiaryContainer.opacity(0.35))
            .accessibilityIdentifier("byok_setup_banner")
        }
    }

    // ========================================================================
    // 0.5 LOGIN SUCCESS BANNER
    // ========================================================================

    @ViewBuilder
    private var loginSuccessBanner: some View {
        if let loginSuccessMessage, !loginSuccessMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.primary)
                Text(loginSuccessMessage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismissLoginSuccess) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.primaryContainer.opacity(0.25))
            .task(id: loginSuccessMessage) {
                guard let msg = loginSuccessMessage, !msg.isEmpty else { return }
                try? await Task.sleep(for: .seconds(5))
                if loginSuccessMessage == msg {
                    onDismissLoginSuccess()
                }
            }
        }
    }

    // ========================================================================
    // 1. SYNC STATUS BANNER
    // ========================================================================

    @ViewBuilder
    private var syncStatusBanner: some View {
        switch viewModel.syncState {
        case let .loading(message):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(message ?? "Synchronizing bookmarks feed from X.com...")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.onSurface)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.primaryContainer.opacity(0.2))

        case let .success(message):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.primary)
                Text(message)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    viewModel.dismissSyncBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.primaryContainer.opacity(0.2))

        case let .rateLimited(secondsLeft):
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.error)
                    .accessibilityLabel("Rate limited lockout")
                Text("X Rate Limited. Resume syncing in \(secondsLeft)s")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(colors.error)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.errorContainer.opacity(0.25))

        case let .error(message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.error)
                Text(message)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    viewModel.syncBookmarks(fetchNextPage: false)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sync")
                Button {
                    viewModel.dismissSyncBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.errorContainer.opacity(0.15))

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var analysisErrorBanner: some View {
        if case let .error(message, bookmarkId) = viewModel.analysisState {
            let showGlobal = bookmarkId == nil || !bookmarks.contains(where: { $0.id == bookmarkId })
            if showGlobal {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.error)
                Text("AI analysis failed: \(message)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    viewModel.clearAnalysisError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, tint: colors.errorContainer.opacity(0.15))
            }
        }
    }

    // ========================================================================
    // 4. BOOKMARK ENTRY ROW LIST
    // ========================================================================

    @ViewBuilder
    private var listSection: some View {
        if bookmarks.isEmpty {
            emptyOrNoMatch
        } else {
            ForEach(bookmarks) { item in
                bookmarkRow(item)
            }
        }
    }

    /// Distinct "no matches" state vs the genuine "empty library" state — the latter's sync CTA
    /// would be the wrong action when a filter merely matched nothing.
    @ViewBuilder
    private var emptyOrNoMatch: some View {
        let isFiltering = !searchQuery.isBlank || selectedTag != nil ||
            quickFilter != .all || selectedSpaceId != nil
        if isFiltering && stats.totalCount > 0 {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.5))
                Text("No matches")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.onSurface)
                Text("Nothing in your index matches the current search and filters.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.65))
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.clearAllFilters()
                } label: {
                    Text("Clear filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(colors.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
        } else {
            CurioEmptyState(
                tier: tier,
                onActionClick: { viewModel.syncBookmarks(fetchNextPage: false) }
            )
        }
    }

    private func bookmarkRow(_ item: Bookmark) -> some View {
        // `(analysisState as? AnalysisUiState.Processing)?.bookmarkId == item.id`.
        let isProcessing: Bool = {
            if case let .processing(id) = viewModel.analysisState { return id == item.id }
            return false
        }()
        let isAnalysisError: Bool = {
            if case let .error(_, bookmarkId) = viewModel.analysisState { return bookmarkId == item.id }
            return false
        }()
        let analysisErrorMessage: String? = {
            if case let .error(message, bookmarkId) = viewModel.analysisState, bookmarkId == item.id { return message }
            return nil
        }()

        // Per-card actions
        // `CurioCardActions`). Swift closures capture `item` by value, so each row gets a fresh
        // action object reflecting the current field values (no stale `isFavorite` capture).
        let cardActions = CurioCardActions(
            onProcessOcr: { image in viewModel.processOcrForBookmark(bookmarkId: item.id, image: image) },
            onGenerateImagen: { viewModel.generateImagenImage(bookmarkId: item.id) },
            onSelectTag: { viewModel.selectTag($0) },
            onSelectSpace: { viewModel.selectSpace($0) },
            onAcceptCategory: { viewModel.acceptCategorySuggestion(item) },
            onToggleFavorite: { viewModel.toggleFavorite(item) },
            onToggleSavedForLater: { viewModel.toggleSavedForLater(item) },
            onUpdateNotes: { viewModel.updateNotes(bookmarkId: item.id, notes: $0) },
            onAssignToSpace: { viewModel.assignBookmarksToSpace(ids: [item.id], spaceId: $0) },
            onCreateSpaceAndAssign: { name, color, icon, description, rules, isPinned in
                viewModel.createSpaceAndAssign(
                    name: name, color: color, icon: icon, ids: [item.id],
                    description: description, rules: rules, isPinned: isPinned
                )
            },
            onRunAiAnalysis: { viewModel.runAiAnalysis(item) },
            onRunDeepAnalysis: { viewModel.runDeepAnalysis(item) },
            onResolveSource: { viewModel.resolveSource(item) },
            exportBibtex: { viewModel.exportSingleBibtex(item) },
            onDelete: { viewModel.deleteBookmarks(ids: [item.id]) },
            onRemindInChronosFlow: { choice in viewModel.remindToReadLaterInChronosFlow(item, choice: choice) },
            onCaptureToChronosFlow: { viewModel.captureToChronosFlowInbox(item) },
            onCreateChronosFlowTask: { viewModel.createChronosFlowTask(item) }
        )

        return CurioPostCard(
            bookmark: item,
            actions: cardActions,
            spaces: spaces,
            isProcessing: isProcessing,
            isAnalysisError: isAnalysisError,
            analysisErrorMessage: analysisErrorMessage,
            isImagenGenerated: viewModel.imagenGeneratedIds.contains(item.id),
            imagenUrl: viewModel.imagenUrls[item.id],
            tier: tier,
            isSelected: selectedIds.contains(item.id),
            onToggleSelect: {
                if selectedIds.contains(item.id) {
                    selectedIds.remove(item.id)
                } else {
                    selectedIds.insert(item.id)
                }
            },
            inSelectionMode: !selectedIds.isEmpty,
            isReorderMode: isReorderMode,
            onMoveUp: { viewModel.moveBookmarkUp(item) },
            onMoveDown: { viewModel.moveBookmarkDown(item) },
            onBookmarkClick: { onBookmarkClick(item) },
            chronosFlowInstalled: viewModel.isChronosFlowInstalled(),
            suggestedSpace: viewModel.spaceSuggestions[item.id].flatMap { s in
                spaces.first(where: { $0.id == s.spaceId })
            }
        )
    }

    // ========================================================================
    // Floating bulk operations action bar
    // ========================================================================

    /// `allIds` = every visible bookmark id; `allSelected` = the selection covers all of them.
    private var allIds: Set<String> { Set(bookmarks.map { $0.id }) }
    private var allSelected: Bool { !allIds.isEmpty && allIds.isSubset(of: selectedIds) }

    private var bulkActionBar: some View {
        VStack(spacing: 12) {
            bulkHeader
            if confirmingBulkDelete {
                bulkDeleteConfirm
            } else {
                bulkActionTiles
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassSurface(
            tier: tier,
            shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: colors.surface.opacity(0.94),
            borderColor: colors.primary.opacity(0.35)
        )
        .animation(CurioMotion.liquid, value: confirmingBulkDelete)
        .accessibilityIdentifier("bulk_actions_panel")
    }

    // ── HEADER: count badge · label · select-all · close ──

    private var bulkHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(colors.primary)
                Text("\(selectedIds.count)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(colors.onPrimary)
            }
            .frame(width: 36, height: 36)
            .bounceScale(active: true)

            VStack(alignment: .leading, spacing: 0) {
                Text(selectedIds.count == 1 ? "1 selected" : "\(selectedIds.count) selected")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(colors.onSurface)
                Text("Bulk index operations")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Select-all / clear-all quick toggle.
            Button {
                selectedIds = allSelected ? [] : allIds
            } label: {
                Text(allSelected ? "CLEAR" : "ALL")
                    .font(.system(size: 12, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(colors.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(colors.primary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityIdentifier("bulk_select_all_button")

            Button {
                selectedIds = []
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.onSurface.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(colors.onSurface.opacity(0.06), in: Circle())
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityLabel("Cancel bulk operation")
            .accessibilityIdentifier("bulk_cancel_button")
        }
        .frame(maxWidth: .infinity)
    }

    // ── ACTIONS ──

    private var bulkActionTiles: some View {
        HStack(spacing: 10) {
            BulkActionTile(
                label: "Space",
                systemImage: "square.grid.2x2.fill",
                tint: colors.tertiary,
                onClick: { showBulkSpaceDialog = true }
            )
            .accessibilityIdentifier("bulk_space_button")

            BulkActionTile(
                label: "Export",
                systemImage: "square.and.arrow.up",
                tint: colors.secondary,
                onClick: { showExportDialog = true }
            )
            .accessibilityIdentifier("bulk_export_button")

            BulkActionTile(
                label: "Delete",
                systemImage: "trash",
                tint: colors.error,
                onClick: { confirmingBulkDelete = true }
            )
            .accessibilityIdentifier("bulk_delete_button")
        }
        .frame(maxWidth: .infinity)
    }

    private var bulkDeleteConfirm: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.error)
            Text("Delete \(selectedIds.count)?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                confirmingBulkDelete = false
            } label: {
                Text("CANCEL")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.curioPressBounce)
            Button {
                viewModel.deleteBookmarks(ids: Array(selectedIds))
                selectedIds = []
            } label: {
                Text("DELETE")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(colors.error)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colors.error.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityIdentifier("bulk_delete_confirm_button")
        }
        .padding(.init(top: 8, leading: 14, bottom: 8, trailing: 8))
        .frame(maxWidth: .infinity)
        .background(colors.error.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.error.opacity(0.30), lineWidth: 1)
        }
    }

    // ========================================================================
    // Sheets — export / model / assign-space / new-space
    // ========================================================================

    /// EXPORT ARCHIVE sheet. Each format copies to the clipboard, shares, clears the selection, and
    /// dismisses. Mirrors the Compose `SlideUpCard` + the JSON/CSV/BibTeX/RIS/CSL/Markdown buttons.
    private var exportDialog: some View {
        let selectedBookmarks = bookmarks.filter { selectedIds.contains($0.id) }
        return SlideUpCard(
            tier: tier,
            spacing: 16,
            horizontalAlignment: .center
        ) {
            ExportArchiveContent(
                selectedCount: selectedIds.count,
                selectedBookmarks: selectedBookmarks,
                viewModel: viewModel,
                onCompleted: { selectedIds = [] }
            )
        }
    }

    /// AI SEMANTIC SEARCH model-download sheet. Drops into AI search + dismisses when the model
    /// finishes downloading.
    private var modelDialog: some View {
        SlideUpCard(
            tier: tier,
            spacing: 16,
            horizontalAlignment: .center
        ) {
            ModelDownloadContent(
                tier: tier,
                modelState: embeddingModelState,
                onDownload: { token in viewModel.downloadEmbeddingModel(token: token) },
                onReady: {
                    viewModel.setSearchMode(.semantic)
                    showModelDialog = false
                }
            )
        }
    }

    /// Bulk "assign to space" sheet. Highlights the common Space only when EVERY selected item
    /// shares it (`distinct().singleOrNull()`).
    private var bulkSpaceDialog: some View {
        let selected = bookmarks.filter { selectedIds.contains($0.id) }
        let distinctSpaceIds = Set(selected.map { $0.spaceId })
        let commonSpaceId: String? = distinctSpaceIds.count == 1 ? selected.first?.spaceId : nil
        return AssignToSpaceDialog(
            spaces: spaces,
            currentSpaceId: commonSpaceId,
            tier: tier,
            onAssign: { spaceId in
                viewModel.assignBookmarksToSpace(ids: Array(selectedIds), spaceId: spaceId)
                showBulkSpaceDialog = false
                selectedIds = []
            },
            onCreateSpace: {
                showBulkSpaceDialog = false
                showBulkNewSpace = true
            }
        )
    }

    /// Bulk "new space" editor — creates a Space and files the selection into it.
    private var bulkNewSpaceDialog: some View {
        SpaceEditorDialog(
            existing: nil,
            tier: tier,
            onConfirm: { name, color, icon, description, rules, isPinned in
                viewModel.createSpaceAndAssign(
                    name: name, color: color, icon: icon, ids: Array(selectedIds),
                    description: description, rules: rules, isPinned: isPinned
                )
                showBulkNewSpace = false
                selectedIds = []
            }
        )
    }
}

// MARK: - ExportArchiveContent

/// The body of the EXPORT ARCHIVE slide-up card. Hoisted into its own view so it can read the
/// `@Environment(\.slideUpDismiss)` provided by `SlideUpCard` (the Cancel/format buttons animate
/// the sheet closed). Every export path: build → copy → share → clear selection → dismiss.
private struct ExportArchiveContent: View {
    let selectedCount: Int
    let selectedBookmarks: [Bookmark]
    let viewModel: BookmarkViewModel
    let onCompleted: () -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    /// Run an export: copy to clipboard, share, clear selection, dismiss. Mirrors the Compose
    /// `copyToClipboard(...) ; shareBookmark(...) ; selectedIds = emptySet() ; dismiss()`.
    private func run(_ text: String, label: String? = nil) {
        if let label {
            CurioFormat.copyToClipboard(text, label: label)
        } else {
            CurioFormat.copyToClipboard(text)
        }
        CurioFormat.shareBookmark(text)
        CurioNotifier.notify("Copied & share sheet opened")
        onCompleted()
        dismissCard()
    }

    var body: some View {
        Text("EXPORT ARCHIVE")
            .font(.system(size: 16, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(colors.secondary)

        Text("Export \(selectedCount) bookmarks to JSON, CSV, or BibTeX citation format.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(colors.onSurface.opacity(0.6))
            .multilineTextAlignment(.center)

        // Primary row: JSON · CSV · BibTeX.
        HStack(spacing: 8) {
            exportButton("JSON", background: colors.primary, foreground: colors.onPrimary, height: 48) {
                run(CurioFormat.exportBackupJson(selectedBookmarks))
            }
            exportButton("CSV", background: colors.secondary, foreground: colors.onSecondary, height: 48) {
                run(CurioFormat.exportBackupCsv(selectedBookmarks))
            }
            exportButton("BIBTEX", background: Color(argb: 0xFFB71C1C), foreground: .white, height: 48) {
                run(viewModel.exportBibtex(selectedBookmarks), label: "BibTeX citations")
            }
        }
        .frame(maxWidth: .infinity)

        // Secondary row: RIS · CSL-JSON · MARKDOWN.
        HStack(spacing: 8) {
            exportButton("RIS", background: Color(argb: 0xFF455A64), foreground: .white, height: 44, small: true) {
                run(viewModel.exportRis(selectedBookmarks), label: "RIS citations")
            }
            exportButton("CSL-JSON", background: Color(argb: 0xFF5E35B1), foreground: .white, height: 44, small: true) {
                run(viewModel.exportCslJson(selectedBookmarks), label: "CSL-JSON citations")
            }
            exportButton("MARKDOWN", background: Color(argb: 0xFF00695C), foreground: .white, height: 44, small: true) {
                run(viewModel.exportMarkdown(selectedBookmarks), label: "MARKDOWN citations")
            }
        }
        .frame(maxWidth: .infinity)

        // Cancel.
        Button {
            dismissCard()
        } label: {
            Text("CANCEL")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(colors.onSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }

    private func exportButton(
        _ label: String,
        background: Color,
        foreground: Color,
        height: CGFloat,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: small ? 11 : 12, weight: .black))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - ModelDownloadContent

/// The body of the AI SEMANTIC SEARCH model-download slide-up card. Hoisted so it can read the
/// `@Environment(\.slideUpDismiss)` and host the local HF-token field + progress / failure states.
private struct ModelDownloadContent: View {
    let tier: GlassTier
    let modelState: EmbeddingModelManager.ModelState
    let onDownload: (String?) -> Void
    /// Invoked when the model reaches `.ready` (the caller flips to semantic + dismisses).
    let onReady: () -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    /// Local Hugging Face token entry (the model repo is Gemma-license-gated).
    @State private var hfToken: String = ""

    private var isDownloading: Bool {
        if case .downloading = modelState { return true }
        return false
    }

    private var isFailed: Bool {
        if case .failed = modelState { return true }
        return false
    }

    var body: some View {
        Text("AI SEMANTIC SEARCH")
            .font(.system(size: 16, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(colors.secondary)

        Text("Searches your index by meaning, not just keywords. Runs fully on-device with EmbeddingGemma — a one-time \(EmbeddingModelManager.APPROX_SIZE_LABEL) download, and nothing leaves your phone.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(colors.onSurface.opacity(0.6))
            .multilineTextAlignment(.center)

        switch modelState {
        case let .downloading(fraction, label):
            ProgressView(value: min(max(fraction, 0), 1))
                .frame(maxWidth: .infinity)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))

        default:
            if case let .failed(message) = modelState {
                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.error)
                    .multilineTextAlignment(.center)
            }
            // EmbeddingGemma is Gemma-license-gated on Hugging Face. Paste a token once (it's
            // stored encrypted and reused); tappable markdown link mirrors the Android
            // `ClickableText` annotation.
            Text(.init("Hugging Face token — get one at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .tint(colors.primary)
                .multilineTextAlignment(.center)
            SecureField("Paste token here", text: $hfToken)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Button {
                onDownload(hfToken)
            } label: {
                Text(isFailed
                    ? "RETRY DOWNLOAD"
                    : "DOWNLOAD (\(EmbeddingModelManager.APPROX_SIZE_LABEL))")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(colors.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
        }

        // Cancel / continue-in-background.
        Button {
            dismissCard()
        } label: {
            Text(isDownloading ? "CONTINUE IN BACKGROUND" : "CANCEL")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(colors.onSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
        // Once the download finishes, drop straight into AI search and dismiss the dialog.
        // Port of `LaunchedEffect(modelState) { if (Ready) { setSearchMode(SEMANTIC); dismiss } }`.
        .onChange(of: modelState) { _, newValue in
            if case .ready = newValue { onReady() }
        }
        .onAppear {
            if case .ready = modelState { onReady() }
        }
    }
}

// MARK: - BulkActionTile

/// A tinted, equally-weighted action tile in the bulk-selection bar (icon over label). Direct port
/// of the private `@Composable BulkActionTile(...)`.
private struct BulkActionTile: View {
    let label: String
    let systemImage: String
    let tint: Color
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }
}
