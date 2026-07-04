//
//  CurioChatScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioChatScreen.kt
//         (CurioChatScreen, ChatBubble, CitationStrip, SourceChipRow).
//
//  DESIGN §10 (Screens): RAG chat — header/clear, empty suggestions, bubbles+citations, typing,
//  composer+source chips. `struct CurioChatView`; `ScrollViewReader` auto-scroll; `ChatBubbleView`
//  (asymmetric corners, long-press copy, markdown); `CitationStrip` (FlowLayout, host parse,
//  openURL); `SourceChipRow`.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": the Kotlin `collectAsStateWithLifecycle()` reads collapse to plain
//    property reads on the injected `@Bindable BookmarkViewModel`. `textInput` is local `@State`.
//  - §4 "exact user-facing strings": every label/placeholder/suggestion is carried verbatim.
//  - §8 "Glass": chips/bubbles/composer use `glassSurface(tier:shape:tint:borderColor:)`; the send
//    button + AI avatars use `curioAccentBrush(primary:tertiary:)`. The threaded `tier` is the
//    resolved `GlassTier` handed down from `BookmarkApp`.
//  - §8 "Motion": the Compose `pressBounce { … }` taps map to `Button { } .buttonStyle(.curioPressBounce)`.
//  - §8 "Layout/insets": the Box `.imePadding()` + bottom composer become a `.safeAreaInset(.bottom)`
//    pinned composer; SwiftUI handles keyboard avoidance natively (CONVENTIONS §8 "chat composer pins
//    via .safeAreaInset(edge:.bottom)").
//  - §10 "Markdown": bubbles render through the ported `MarkdownText`.
//  - The Compose `lazyListState.animateScrollToItem(target)` auto-scroll is a `ScrollViewReader`
//    `proxy.scrollTo(...)` keyed off `messages.count` + `isLoading` (the `target` index logic
//    preserved: last message + 1 while loading).
//
//  `ChatMessage`/`ChatSender`/`ChatSource`/`OrderedChatSourceSet` are owned by `ChatController`
//  (Platform); this screen consumes their declared API surface (CONVENTIONS §1 single definition).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Research Assistant (RAG chat) screen. Direct port of the `@Composable fun CurioChatScreen(...)`.
///
/// Renders the AI header (with a clear-conversation action once a conversation exists), either the
/// welcome + suggestion grid (empty state) or the message list (asymmetric bubbles + citation strips +
/// a typing indicator while loading), and the pinned source-chip + composer at the bottom.
struct CurioChatView: View {
    /// Central library view model. Injected, owned by `BookmarkApp`; `@Bindable` so chat state
    /// (messages, loading, sources) drives the UI reactively.
    @Bindable var viewModel: BookmarkViewModel
    /// The resolved glass tier threaded from `BookmarkApp`.
    let tier: GlassTier
    var onNavigateToBookmarks: () -> Void = {}
    var onNavigateToSettings: () -> Void = {}

    @Environment(\.curioColors) private var colors

    // MARK: - Local UI state (Compose `remember { mutableStateOf(...) }`)

    /// The composer text. Port of `var textInput by remember { mutableStateOf("") }`.
    @State private var textInput: String = ""

    // MARK: - Suggestions (Compose `val suggestions = listOf(...)`)

    /// The four empty-state suggestion prompts. Carried verbatim.
    private let suggestions: [String] = [
        "Summarize my recent bookmarks",
        "What topics am I reading most?",
        "Find papers about attention",
        "Suggest a paper to read next"
    ]

    /// Scroll-anchor id appended after the typing indicator so the list always scrolls to the very
    /// bottom (covering both the last message and the loading row).
    private enum ScrollAnchor: Hashable { case bottom }

    /// Contextual label under the typing dots while Grok is working.
    private var chatLoadingLabel: String {
        let sources = viewModel.chatSources
        if sources.contains(.library) && sources.count == 1 {
            return "Searching your library…"
        }
        if sources.contains(where: { $0 != .library }) {
            return "Searching live sources…"
        }
        return "Thinking…"
    }

    var body: some View {
        let messages = viewModel.chatMessages
        let isLoading = viewModel.isChatLoading

        // Box(fillMaxSize().imePadding().padding(horizontal = 16)). The bottom composer pins above the
        // keyboard via `.safeAreaInset(.bottom)`; the message column scrolls under it.
        messageColumn(messages: messages, isLoading: isLoading)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Source chips + liquid-glass composer — sits flush above the keyboard (no buffer).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
                    .padding(.horizontal, 16)
            }
    }

    // MARK: - Header + message list

    @ViewBuilder
    private func messageColumn(messages: [ChatMessage], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: 4)

            // Header row: brand mark + title/subtitle + clear-conversation action.
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(curioAccentBrush(primary: colors.primary, tertiary: colors.tertiary))
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Curio AI")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(colors.onSurface)
                    Text("Grounded in your saved research")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.onSurface.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // `AnimatedVisibility(visible = messages.isNotEmpty())` — fade in/out with the conversation.
                if !messages.isEmpty {
                    Button {
                        viewModel.clearChat()
                    } label: {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 18))
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Clear conversation")
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("chat_clear_button")
                    .transition(.opacity)
                }
            }

            if messages.isEmpty {
                welcomeState
            } else {
                conversationList(messages: messages, isLoading: isLoading)
            }
        }
    }

    // MARK: - Welcome / suggestions (empty state)

    private var welcomeState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle().fill(colors.primary.opacity(0.12))
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 38))
                    .foregroundStyle(colors.primary)
            }
            .frame(width: 76, height: 76)

            Spacer().frame(height: 16)

            if !viewModel.xaiKeyConfigured {
                Text("Connect your xAI key")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(colors.onSurface)
                    .multilineTextAlignment(.center)
                Text("Add your API key in Settings to chat with Grok about your saved research.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Spacer().frame(height: 16)
                Button(action: onNavigateToSettings) {
                    Text("OPEN SETTINGS")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            } else if viewModel.stats.totalCount == 0 {
                Text("Your index is empty")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(colors.onSurface)
                    .multilineTextAlignment(.center)
                Text("Sync bookmarks from X first, then ask Curio to summarize or explore them.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Spacer().frame(height: 16)
                Button(action: onNavigateToBookmarks) {
                    Text("GO TO BOOKMARKS")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(colors.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            } else {
            Text("Ask anything about your index")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(colors.onSurface)
                .multilineTextAlignment(.center)
            Text("I read across everything you've saved.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 20)

            // FlowRow(maxItemsInEachRow = 2) — a fixed 2-column grid of suggestion chips.
            let columns = [
                GridItem(.flexible(), spacing: 8, alignment: .leading),
                GridItem(.flexible(), spacing: 8, alignment: .leading)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        viewModel.sendChatMessage(s)
                    } label: {
                        Text(s)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.curioPressBounce)
                    .disabled(viewModel.isChatLoading)
                    .opacity(viewModel.isChatLoading ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversation list

    @ViewBuilder
    private func conversationList(messages: [ChatMessage], isLoading: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                            .accessibilityIdentifier("chat_msg_bubble_\(msg.id)")
                    }

                    if isLoading {
                        let loadingLabel = chatLoadingLabel
                        HStack(alignment: .center, spacing: 8) {
                            aiAvatar(size: 28, glyph: 15)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    TypingDots(color: colors.primary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Text(loadingLabel)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(colors.onSurface.opacity(0.55))
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    // Invisible scroll anchor that always sits at the very bottom.
                    Color.clear
                        .frame(height: 1)
                        .id(ScrollAnchor.bottom)
                }
                // Keep the list clear of the pinned composer (Compose `padding(bottom = 132.dp)`).
                .padding(.bottom, 132)
            }
            // `LaunchedEffect(messages.size) { animateScrollToItem(target) }`: scroll to the bottom
            // whenever the message count changes OR loading toggles (so the typing row reveals).
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
        }
    }

    /// Scrolls the conversation to its bottom anchor. Mirrors the Kotlin
    /// `runCatching { lazyListState.animateScrollToItem(target) }` (failures swallowed). The Kotlin
    /// `target = messages.size - 1 + (isLoading ? 1 : 0)` is the last visible row; the bottom anchor
    /// is equivalent and robust to the loading row.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard !viewModel.chatMessages.isEmpty else { return }
        withAnimation(CurioMotion.liquid) {
            proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
        }
    }

    /// A single chat row: AI replies are leading (with an avatar) + an optional citation strip;
    /// user messages are trailing. Port of the `items(messages) { msg -> Row(...) }` body.
    @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        let isAi = msg.sender == .ai
        let isError = msg.isError
        HStack(alignment: .top, spacing: 0) {
            if isAi {
                if isError {
                    ZStack {
                        Circle().fill(colors.error.opacity(0.2))
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.error)
                    }
                    .frame(width: 28, height: 28)
                } else {
                    aiAvatar(size: 28, glyph: 15)
                }
                Spacer().frame(width: 8)
            } else {
                Spacer(minLength: 0)
            }
            VStack(alignment: isAi ? .leading : .trailing, spacing: 6) {
                ChatBubbleView(
                    text: msg.text,
                    isAi: isAi,
                    isError: isError,
                    tier: tier
                )
                if isError, msg.retryPrompt != nil {
                    Button {
                        viewModel.retryChatMessage(msg.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(colors.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 12, style: .continuous), tint: colors.errorContainer.opacity(0.2))
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("chat_retry_\(msg.id)")
                }
                if isAi && !isError && !msg.citations.isEmpty {
                    CitationStrip(citations: msg.citations)
                }
            }
            .frame(maxWidth: 300, alignment: isAi ? .leading : .trailing)
            if isAi {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isAi ? .leading : .trailing)
    }

    /// The accent-gradient circular AI avatar (sparkles glyph). `size` is the circle diameter,
    /// `glyph` the icon point size.
    private func aiAvatar(size: CGFloat, glyph: CGFloat) -> some View {
        ZStack {
            Circle().fill(curioAccentBrush(primary: colors.primary, tertiary: colors.tertiary))
            Image(systemName: "sparkles")
                .font(.system(size: glyph))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Composer (source chips + text field + send)

    private var composer: some View {
        VStack(spacing: 8) {
            SourceChipRow(
                activeSources: viewModel.chatSources,
                onToggle: { viewModel.toggleChatSource($0) },
                tier: tier,
                enabled: !viewModel.isChatLoading
            )

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $textInput,
                    prompt: Text("Ask Curio anything…")
                        .foregroundColor(colors.onSurface.opacity(0.4))
                )
                .font(.system(size: 14))
                .foregroundStyle(colors.onSurface)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit(sendIfPossible)
                .disabled(viewModel.isChatLoading)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("chatbot_text_input")

                Button {
                    sendIfPossible()
                } label: {
                    sendButtonBackground
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(textInput.isBlankChatScreen ? colors.onSurface.opacity(0.4) : Color.white)
                                .accessibilityLabel("Send")
                        }
                }
                .buttonStyle(.curioPressBounce)
                .disabled(textInput.isBlankChatScreen || viewModel.isChatLoading)
                .accessibilityIdentifier("chatbot_send_button")
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    /// The send-button background: a neutral disc when blank, the accent brush otherwise.
    @ViewBuilder
    private var sendButtonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if textInput.isBlankChatScreen {
            shape.fill(colors.onSurface.opacity(0.12))
        } else {
            shape.fill(curioAccentBrush(primary: colors.primary, tertiary: colors.tertiary))
        }
    }

    /// Sends the composer text when non-blank, then clears it. Port of
    /// `if (textInput.isNotBlank()) { viewModel.sendChatMessage(textInput); textInput = "" }`.
    private func sendIfPossible() {
        guard !textInput.isBlankChatScreen else { return }
        viewModel.sendChatMessage(textInput)
        textInput = ""
    }
}

// MARK: - ChatBubbleView

/// A tappable chat bubble with markdown rendering and long-press-to-copy. Direct port of the private
/// `@Composable ChatBubble(...)`.
///
/// AI bubbles use a surface tint with a flat bottom-leading corner; user bubbles use a primary tint
/// with a primary border and a flat bottom-trailing corner. Long-press copies the raw text to the
/// pasteboard (the Compose `combinedClickable(onLongClick = { clipboard.setText(...) })`).
private struct ChatBubbleView: View {
    let text: String
    let isAi: Bool
    var isError: Bool = false
    let tier: GlassTier

    @Environment(\.curioColors) private var colors

    /// Asymmetric corners: AI flattens bottom-leading (4pt), user flattens bottom-trailing (4pt).
    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isAi ? 4 : 18,
            bottomTrailingRadius: isAi ? 18 : 4,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    /// AI: surface@0.55; user: primary@0.2. (Matches the Compose `tint`.)
    private var bubbleTint: Color {
        if isError { return colors.errorContainer.opacity(0.35) }
        return isAi ? colors.surface.opacity(0.55) : colors.primary.opacity(0.2)
    }

    /// AI: transparent border; user: primary@0.35.
    private var bubbleBorder: Color {
        if isError { return colors.error.opacity(0.35) }
        return isAi ? Color.clear : colors.primary.opacity(0.35)
    }

    var body: some View {
        MarkdownText(
            markdown: text,
            style: CurioFont.bodyMediumLineHeight21,
            color: colors.onSurface,
            accent: colors.primary
        )
        .padding(13)
        .glassSurface(
            tier: tier,
            shape: bubbleShape,
            tint: bubbleTint,
            borderColor: bubbleBorder
        )
        // Long-press to copy the message text (Compose `onLongClick`).
        .onLongPressGesture {
            #if canImport(UIKit)
            if CurioFormat.copyToClipboard(text) {
                CurioNotifier.notify("Copied to clipboard")
            } else {
                CurioNotifier.notify("Failed to copy")
            }
            #endif
        }
    }
}

// MARK: - CitationStrip

/// Tappable source citations rendered under a grounded AI reply. Direct port of the private
/// `@Composable CitationStrip(citations)`.
///
/// Shows up to 8 citations as `"<index>. <host>"` chips; the host is the URL host stripped of a
/// leading `www.` (falling back to `"source"` on a parse failure). Tapping opens the URL.
private struct CitationStrip: View {
    let citations: [String]

    @Environment(\.curioColors) private var colors

    var body: some View {
        // FlowRow(spacedBy 6) — a wrapping row of citation chips.
        ChatFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(citations.prefix(8).enumerated()), id: \.offset) { index, url in
                Button {
                    // `runCatching { uriHandler.openUri(url) }` — open the URL with user feedback.
                    switch CurioFormat.openUrl(url) {
                    case .opened: break
                    case .noLink: CurioNotifier.notify("No link on this bookmark")
                    case .failed: CurioNotifier.notify("Couldn't open link")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.primary)
                        Text("\(index + 1). \(host(of: url))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colors.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(colors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
            }
        }
    }

    /// `runCatching { Uri.parse(url).host?.removePrefix("www.") }.getOrNull() ?: "source"`.
    private func host(of url: String) -> String {
        guard let comps = URLComponents(string: url), let h = comps.host, !h.isEmpty else { return "source" }
        if h.hasPrefix("www.") { return String(h.dropFirst("www.".count)) }
        return h
    }
}

// MARK: - SourceChipRow

/// Horizontally scrollable grounding-source toggles shown above the composer. Direct port of the
/// private `@Composable SourceChipRow(...)`.
///
/// Iterates `ChatSource.allCases` (Library / Web / X / News), rendering each as a toggle pill that
/// tints + outlines + shows a checkmark when active.
private struct SourceChipRow: View {
    let activeSources: OrderedChatSourceSet
    let onToggle: (ChatSource) -> Void
    let tier: GlassTier
    var enabled: Bool = true

    @Environment(\.curioColors) private var colors

    /// SF-Symbol substitutions for the Compose source icons:
    ///   LIBRARY → Icons.Default.Bookmarks        → "bookmark.fill"
    ///   WEB     → Icons.Default.Public            → "globe"
    ///   X       → Icons.Default.AlternateEmail    → "at"
    ///   NEWS    → Icons.AutoMirrored.Filled.Article → "newspaper"
    private func icon(for source: ChatSource) -> String {
        switch source {
        case .library: return "bookmark.fill"
        case .web: return "globe"
        case .x: return "at"
        case .news: return "newspaper"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatSource.allCases, id: \.self) { source in
                    let selected = activeSources.contains(source)
                    Button {
                        onToggle(source)
                    } label: {
                        chip(source: source, selected: selected)
                    }
                    .buttonStyle(.curioPressBounce)
                    .disabled(!enabled)
                    .accessibilityIdentifier("chat_source_\(source.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func chip(source: ChatSource, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: icon(for: source))
                .font(.system(size: 15))
                .foregroundStyle(selected ? colors.primary : colors.onSurface.opacity(0.6))
            Text(source.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? colors.primary : colors.onSurface.opacity(0.75))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.primary)
                    .accessibilityLabel("Active")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            // Selected: a flat primary@0.18 fill. Unselected: the glass surface.
            if selected {
                shape.fill(colors.primary.opacity(0.18))
            } else {
                Color.clear.glassSurface(tier: tier, shape: shape)
            }
        }
        .overlay {
            shape.stroke(selected ? colors.primary.opacity(0.5) : Color.clear, lineWidth: 1)
        }
        .clipShape(shape)
    }
}

// MARK: - ChatFlowLayout
//
// A wrapping flow layout (the Compose `FlowRow` analogue) used by the citation strip. iOS 16+ ships
// `Layout`; this lays out subviews left→right, wrapping when the row width is exceeded, with the
// supplied horizontal/vertical spacing.

private struct ChatFlowLayout: Layout {
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

// MARK: - CurioFont chat-bubble role

extension CurioFont {
    /// `MaterialTheme.typography.bodyMedium.copy(lineHeight = 21.sp)` — the chat-bubble body role
    /// (bodyMedium is 14pt; line height bumped to 21 to match the Compose copy).
    static let bodyMediumLineHeight21 = CurioTextStyle(size: 14, weight: .medium, tracking: 0.25, lineHeight: 21)
}

// MARK: - String.isBlank parity

private extension String {
    /// Kotlin `String.isBlank()`: empty or whitespace-only. Named distinctly to avoid colliding with
    /// blank helpers in sibling files.
    var isBlankChatScreen: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
