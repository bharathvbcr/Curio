//
//  CurioInsightsScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioInsightsScreen.kt
//         (CurioInsightsScreen, WeeklyDigestCard, RediscoverCard, DigestActionButton).
//
//  DESIGN §10 (Screens): Analytics dashboard — hero %, stat tiles, digest card, rediscover,
//  distribution bars, hot topics. `struct CurioInsightsView`; animated progress on appear;
//  `WeeklyDigestCard` (5-state switch), `RediscoverCard`, distribution capsules
//  (tap→filter+navigate), `FlowLayout` topics.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": `collectAsStateWithLifecycle()` reads collapse to plain property
//    reads on the injected `@Bindable BookmarkViewModel` (`stats`, `spaces`, `digestState`,
//    `rediscoverPicks`). `play` is local `@State` flipped on appear (the `LaunchedEffect(Unit){play=true}`).
//  - §4 "Sealed UI states": `DigestUiState` is switched exhaustively; EXACT user-facing strings are
//    surfaced from the controller and rendered verbatim.
//  - §8 "Glass / Motion": cards use `glassSurface(tier:)`; bars/hero animate with `CurioMotion.liquid`.
//    Compose `pressBounce { … }` taps → `Button { } .buttonStyle(.curioPressBounce)`.
//  - §8 "ARGB": `space.color` (Int64 packed ARGB) is unpacked to `Color(packedARGB:)` ONLY here at the
//    UI boundary; `spaceIcon(_:)` resolves the stored icon key to an SF Symbol.
//  - §10 "Markdown": the digest body renders through the ported `MarkdownText`.
//  - The Kotlin `animateFloatAsState(if (play) pct else 0f, CurioMotion.liquid())` becomes a stored
//    target driven on `.onAppear` with `withAnimation(CurioMotion.liquid)` so progress/bars animate in.
//
//  Cross-module helpers consumed (DESIGN "Notes for implementers"): `CurioFormat.sourceDisplayName`,
//  `CurioFormat.relativeTime`, `CurioFormat.openUrl` (Screens); `spaceIcon(_:)` (CurioSpacesScreen).
//  `DigestUiState` / `CurioStats` are owned by DigestController / BookmarkViewModel respectively.
//

import SwiftUI

/// The Insights analytics dashboard. Direct port of the `@Composable fun CurioInsightsScreen(...)`.
///
/// A scrolling column of: a gradient hero (total count + curated %), a three-up stat tile row, the
/// on-demand weekly AI digest card, the rediscover card (older un-starred saves), the Space
/// distribution bars (tap → scope the feed to that Space), and the hot-topics tag cloud.
struct CurioInsightsView: View {
    /// Central library view model. Injected, owned by `BookmarkApp`; `@Bindable` so the derived stats
    /// / spaces / digest / rediscover state drive the dashboard reactively.
    @Bindable var viewModel: BookmarkViewModel
    /// The resolved glass tier threaded from `BookmarkApp`.
    let tier: GlassTier
    /// Navigates back to the feed (used by the distribution bars + tag chips after applying a filter).
    let onNavigateToFeed: () -> Void
    var onNavigateToSettings: () -> Void = {}

    @Environment(\.curioColors) private var colors

    /// Drives the entrance progress/bar animations. Port of `var play by remember { mutableStateOf(false) }`
    /// flipped by `LaunchedEffect(Unit) { play = true }`.
    @State private var play: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stats = viewModel.stats
        let spaces = viewModel.spaces
        let digest = viewModel.digestState
        let rediscover = viewModel.rediscoverPicks

        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 8)

                hero(stats: stats)
                statTiles(stats: stats)

                WeeklyDigestCard(
                    state: digest,
                    tier: tier,
                    onGenerate: { viewModel.generateWeeklyDigest() },
                    onDismiss: { viewModel.dismissDigest() },
                    onNavigateToFeed: onNavigateToFeed,
                    onNavigateToSettings: onNavigateToSettings
                )

                // REDISCOVER — resurface older, not-yet-starred saves worth revisiting.
                if !rediscover.isEmpty {
                    RediscoverCard(
                        picks: rediscover,
                        tier: tier,
                        onShuffle: { viewModel.shuffleRediscover() }
                    )
                }

                spaceDistribution(stats: stats, spaces: spaces)
                hotTopics(stats: stats)

                Spacer().frame(height: 80)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                play = true
            } else {
                withAnimation(CurioMotion.liquid) { play = true }
            }
        }
    }

    // MARK: - Hero

    private func hero(stats: CurioStats) -> some View {
        // `pct = curated / total` (0 when total == 0). The bar animates from 0 → pct on appear.
        let pct: CGFloat = stats.totalCount > 0
            ? CGFloat(stats.curatedCount) / CGFloat(stats.totalCount)
            : 0
        let animPct = play ? pct : 0

        return VStack(alignment: .leading, spacing: 4) {
            Text("YOUR RESEARCH INDEX")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.85))
            if stats.totalCount == 0 {
                Text("Start building your index")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color.white)
                Text("Sync bookmarks from X to unlock insights, digests, and AI chat.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer().frame(height: 8)
                Button(action: onNavigateToFeed) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                        Text("GO TO BOOKMARKS")
                            .font(.system(size: 12, weight: .black))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            } else {
            Text("\(stats.totalCount)")
                .font(.system(size: 72, weight: .black))
                .tracking(-3)
                .foregroundStyle(Color.white)
            Text("\(stats.curatedCount) AI-curated · \(Int(pct * 100))% complete")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer().frame(height: 6)
            // Progress track + animated fill (rounded-50 capsule).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * animPct)
                }
            }
            .frame(height: 8)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            curioAccentBrush(primary: colors.primary, tertiary: colors.tertiary),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    // MARK: - Stat tiles

    private func statTiles(stats: CurioStats) -> some View {
        HStack(spacing: 12) {
            StatTile(label: "OCR Syncs", value: "\(stats.ocrCount)", systemImage: "camera.viewfinder", color: colors.secondary, tier: tier) {
                viewModel.clearAllFilters()
                viewModel.setLibraryFilter(.hasOCR)
                onNavigateToFeed()
            }
            StatTile(label: "Sources", value: "\(stats.sourceCount)", systemImage: "point.3.connected.trianglepath.dotted", color: Color(argb: 0xFFE53935), tier: tier) {
                viewModel.clearAllFilters()
                viewModel.setLibraryFilter(.hasSource)
                onNavigateToFeed()
            }
            StatTile(label: "Deep", value: "\(stats.deepAnalyzedCount)", systemImage: "sparkles", color: colors.tertiary, tier: tier) {
                viewModel.clearAllFilters()
                viewModel.setLibraryFilter(.deepAnalyzed)
                onNavigateToFeed()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Space distribution

    @ViewBuilder
    private func spaceDistribution(stats: CurioStats, spaces: [Space]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                // Workspaces → "square.grid.2x2.fill".
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.primary)
                Text("SPACE DISTRIBUTION")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(colors.primary)
            }

            // `spaces.filter { it.count > 0 }.sortedByDescending { it.count }`.
            let populated = spaces.filter { $0.count > 0 }.sorted { $0.count > $1.count }
            if populated.isEmpty {
                Text("No filed bookmarks yet. Curate a bookmark or add it to a Space to populate this view.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                Button(action: onNavigateToFeed) {
                    Text("GO TO BOOKMARKS")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.curioPressBounce)
            } else {
                ForEach(populated) { space in
                    distributionRow(space: space, total: stats.totalCount)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(tier: tier)
    }

    @ViewBuilder
    private func distributionRow(space: Space, total: Int) -> some View {
        let pct: CGFloat = total > 0 ? CGFloat(space.count) / CGFloat(total) : 0
        let animW = play ? pct : 0
        let color = Color(packedARGB: space.color)

        Button {
            // Tap → clear filters, scope to this Space, navigate to the feed. Port of
            // `viewModel.clearAllFilters(); viewModel.selectSpace(space.id); onNavigateToFeed()`.
            viewModel.clearAllFilters()
            viewModel.selectSpace(space.id)
            onNavigateToFeed()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: spaceIcon(space.icon))
                            .font(.system(size: 13))
                            .foregroundStyle(color)
                        Text(space.name.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(space.count) · \(Int(pct * 100))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(colors.onSurface.opacity(0.65))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.onSurface.opacity(0.4))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.onSurface.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * animW)
                    }
                }
                .frame(height: 9)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }

    // MARK: - Hot topics

    @ViewBuilder
    private func hotTopics(stats: CurioStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // LocalFireDepartment → "flame.fill".
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.tertiary)
                Text("HOT TOPICS")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(colors.tertiary)
            }

            if stats.topTags.isEmpty {
                Text("No tags yet. Curate bookmarks to surface trending topics.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                Button(action: onNavigateToFeed) {
                    Text("GO TO BOOKMARKS")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.curioPressBounce)
            } else {
                // `(topTags.maxOfOrNull { it.second } ?: 1).coerceAtLeast(1)`.
                let maxCount = max(stats.topTags.map { $0.1 }.max() ?? 1, 1)
                InsightsFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stats.topTags.enumerated()), id: \.offset) { _, pair in
                        let tag = pair.0
                        let count = pair.1
                        let intensity = Double(count) / Double(maxCount)
                        Button {
                            viewModel.clearAllFilters()
                            viewModel.selectTag(tag)
                            onNavigateToFeed()
                        } label: {
                            HStack(spacing: 5) {
                                Text("#\(tag)")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(colors.primary)
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(colors.onSurface.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            // `primary.copy(alpha = 0.08 + intensity * 0.22)`.
                            .background(colors.primary.opacity(0.08 + intensity * 0.22), in: Capsule())
                        }
                        .buttonStyle(.curioPressBounce)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(tier: tier)
    }
}

// MARK: - WeeklyDigestCard

/// On-demand weekly AI digest card. Renders the [DigestUiState] machine: a generate prompt when idle,
/// a spinner while Grok works, the rendered markdown when ready, and explicit empty/error states.
/// Direct port of the private `@Composable WeeklyDigestCard(...)`.
private struct WeeklyDigestCard: View {
    let state: DigestUiState
    let tier: GlassTier
    let onGenerate: () -> Void
    let onDismiss: () -> Void
    var onNavigateToFeed: () -> Void = {}
    var onNavigateToSettings: () -> Void = {}

    @Environment(\.curioColors) private var colors

    /// `val accent = MaterialTheme.colorScheme.tertiary`.
    private var accent: Color { colors.tertiary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // AutoAwesome → "sparkles".
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                Text("WEEKLY DIGEST")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
                // `if (state is Ready) Text("${state.itemCount} saves")` — the count is the `.ready` payload.
                if case let .ready(_, count) = state {
                    Text("\(count) saves")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.onSurface.opacity(0.5))
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(tier: tier)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Text("Get a themed AI summary of what you saved this week — grouped by theme, with what's worth a closer look.")
                .font(.system(size: 12))
                .foregroundStyle(colors.onSurface.opacity(0.65))
            DigestActionButton(label: "GENERATE DIGEST", accent: accent, onClick: onGenerate)

        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(accent)
                    .frame(width: 18, height: 18)
                Text("Reading your week…")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.onSurface)
            }

        case let .ready(markdown, _):
            MarkdownText(
                markdown: markdown,
                style: CurioFont.bodySmallLineHeight19,
                color: colors.onSurface.opacity(0.92),
                accent: accent
            )
            HStack(spacing: 8) {
                DigestActionButton(label: "REGENERATE", accent: accent, onClick: onGenerate)
                    .frame(maxWidth: .infinity)
                DigestActionButton(label: "COPY", accent: accent, onClick: {
                    if CurioFormat.copyToClipboard(markdown, label: "Weekly Digest") {
                        CurioNotifier.notify("Copied to clipboard")
                    } else {
                        CurioNotifier.notify("Failed to copy")
                    }
                })
                    .frame(maxWidth: .infinity)
                DigestActionButton(label: "SHARE", accent: accent, onClick: {
                    if CurioFormat.shareBookmark(markdown) {
                        CurioNotifier.notify("Share sheet opened")
                    } else {
                        CurioNotifier.notify("Failed to share digest")
                    }
                })
                    .frame(maxWidth: .infinity)
            }
            DigestActionButton(label: "DISMISS", accent: colors.onSurface.opacity(0.5), onClick: onDismiss, filled: false)
                .frame(maxWidth: .infinity)

        case let .empty(reason):
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(colors.onSurface.opacity(0.65))
            HStack(spacing: 8) {
                DigestActionButton(label: "GO TO BOOKMARKS", accent: accent, onClick: onNavigateToFeed)
                    .frame(maxWidth: .infinity)
                DigestActionButton(label: "DISMISS", accent: colors.onSurface.opacity(0.5), onClick: onDismiss, filled: false)
                    .frame(maxWidth: .infinity)
            }

        case let .error(message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(colors.error)
            HStack(spacing: 8) {
                DigestActionButton(label: "TRY AGAIN", accent: accent, onClick: onGenerate)
                    .frame(maxWidth: .infinity)
                if message.localizedCaseInsensitiveContains("key")
                    || message.localizedCaseInsensitiveContains("auth")
                    || message.localizedCaseInsensitiveContains("sign in") {
                    DigestActionButton(label: "SETTINGS", accent: colors.onSurface.opacity(0.7), onClick: onNavigateToSettings, filled: false)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - RediscoverCard

/// Resurfacing card: shows a few older, un-starred saves (with a source link) to bring forgotten
/// research back into view. Tapping a row opens its link; the shuffle action rotates to the next batch.
/// Direct port of the private `@Composable RediscoverCard(...)`.
private struct RediscoverCard: View {
    let picks: [Bookmark]
    let tier: GlassTier
    let onShuffle: () -> Void

    @Environment(\.curioColors) private var colors

    /// `val accent = MaterialTheme.colorScheme.secondary`.
    private var accent: Color { colors.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // Refresh → "arrow.clockwise".
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                Text("REDISCOVER")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
                Button(action: onShuffle) {
                    Text("SHUFFLE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            }

            Text("Saves you haven't starred — worth a second look.")
                .font(.system(size: 12))
                .foregroundStyle(colors.onSurface.opacity(0.6))

            ForEach(picks) { b in
                rediscoverRow(b)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(tier: tier)
    }

    @ViewBuilder
    private func rediscoverRow(_ b: Bookmark) -> some View {
        Button {
            switch CurioFormat.openUrl(b.url) {
            case .opened: break
            case .noLink: CurioNotifier.notify("No link on this bookmark")
            case .failed: CurioNotifier.notify("Couldn't open link")
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    // `sourceTitle?.takeIf { isNotBlank } ?: title?.takeIf { isNotBlank } ?: text.take(80).trim()`.
                    Text(rediscoverTitle(b))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(CurioFormat.sourceDisplayName(b)) · saved \(CurioFormat.relativeTime(b.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(colors.onSurface.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Link → "link" + chevron affordance.
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                        .foregroundStyle(accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.4))
                }
                .accessibilityLabel("Open link")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }

    /// `b.sourceTitle?.takeIf { it.isNotBlank() } ?: b.title?.takeIf { it.isNotBlank() } ?: b.text.take(80).trim()`.
    private func rediscoverTitle(_ b: Bookmark) -> String {
        if let st = b.sourceTitle, !st.isBlankInsights { return st }
        if let t = b.title, !t.isBlankInsights { return t }
        // CONVENTIONS §10 char-count: Kotlin `take(80)` is UTF-16 code units; `prefix(80)` on Character
        // is acceptable for this short, non-byte-sensitive snippet.
        return String(b.text.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - DigestActionButton

/// A pill action button used by the digest card. `filled` flips it to a solid accent button; the
/// outlined variant uses the accent at 12% with accent-tinted text. Direct port of the private
/// `@Composable DigestActionButton(...)`.
private struct DigestActionButton: View {
    let label: String
    let accent: Color
    let onClick: () -> Void
    var filled: Bool = true

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(.system(size: 12, weight: .black))
                .tracking(0.5)
                // `if (filled) onTertiary else accent`.
                .foregroundStyle(filled ? colors.onTertiary : accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, 18)
                .background(
                    (filled ? accent : accent.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - InsightsFlowLayout
//
// A wrapping flow layout (the Compose `FlowRow` analogue) used by the hot-topics tag cloud. Lays out
// subviews left→right, wrapping when the row width is exceeded.

private struct InsightsFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? horizontalSpacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - String.isBlank parity

private extension String {
    /// Kotlin `String.isBlank()`: empty or whitespace-only. Named distinctly to avoid colliding with
    /// blank helpers in sibling files.
    var isBlankInsights: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
