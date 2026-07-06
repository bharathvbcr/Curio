//
//  SettingsScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/SettingsScreen.kt
//         (SettingsScreen — theme, xAI key, session, backup, research-intelligence, embedding model,
//          glass tier).
//
//  DESIGN §10 (Screens): `struct SettingsView`; theme radios; `SecureField` xAI key (Keychain via VM
//  → TokenStore); logout / purge / backup; embed/resolve/dedup buttons; embedding `switch` over the
//  model state + `ProgressView`; index-while-charging Toggle (UserDefaults → BGTask); glass-tier
//  picker. Wired against the shared `BookmarkViewModel` (CONVENTIONS §4).
//
//  CONVENTIONS mapping:
//  - §4 "exact user-facing strings": every card title, description, toggle/radio label, and button
//    caption is carried byte-for-byte from the Compose source.
//  - §4 "@Observable VM": the Android `collectAsStateWithLifecycle()` reads collapse to plain VM
//    property reads (`viewModel.themeSetting`, `.xaiKeyConfigured`, `.rawBookmarks`,
//    `.embeddingModelState`). The VM is passed as `@Bindable` so the radios/toggles drive it.
//  - §8 "Glass": every card uses `glassSurface(tier: resolvedTier)` (the Compose
//    `Modifier.glassSurface(tier = resolvedTier)`); the inner accent chips use the EXACT
//    container alphas (primary@0.15, secondary@0.15, error@0.12, onSurface@0.1, …).
//  - §8 "Theme tokens": colours from `@Environment(\.curioColors)` (Cosmic Slate), NOT system colors.
//  - §8 "Motion": every tappable chip/button is a `Button` with `.curioPressBounce`.
//  - §8/§13 "Material You DROPPED": iOS has no dynamic color; the Android `useDynamicColor` toggle is
//    kept verbatim (string + control) but wired to a no-op local flag — the static Cosmic palette is
//    canonical, so toggling it changes nothing about the colours (DESIGN §8, BookmarkApp note).
//  - §9 "Secrets": the xAI key uses a `SecureField`; the input is transient `@State` (never persisted
//    here — the VM saves it into the Keychain via `TokenStore`). A blank value clears it.
//  - §9 "BGTask / charging": the index-while-charging toggle and "build index now" drive the
//    `BackgroundTaskCoordinator` (the iOS analogue of Android's static `EmbeddingIndexScheduler`),
//    injected via `@Environment(\.backgroundTaskCoordinator)`. The toggle is backed by the SAME
//    `UserDefaults` key (`index_while_charging`, default ON) the coordinator persists, so the control
//    stays correct even before the coordinator is injected.
//  - §13 "Accessibility": Compose `testTag`s map to `.accessibilityIdentifier` verbatim
//    (`dynamic_color_switch`, `xai_key_input`, `xai_key_save`, `logout_button`,
//    `download_model_button`, `index_while_charging_switch`).
//  - "Clipboard / Share / Toast" → `CurioFormat.copyToClipboard`/`shareBookmark`; Android Toasts
//    become a transient SwiftUI overlay (`ToastOverlay`).
//

import SwiftUI

// MARK: - BackgroundTaskCoordinator environment injection
//
// The Android Settings screen drove `EmbeddingIndexScheduler.isEnabled/setEnabled/runNow(context)` —
// a process-global object. The iOS port is the `@MainActor final class BackgroundTaskCoordinator`
// (Platform), built and injected by the App layer. It is exposed to this screen via the environment
// so the screen never hard-references a singleton (CONVENTIONS §2). When absent (e.g. previews) the
// screen falls back to reading/writing the shared `UserDefaults` key directly for the toggle.

private struct BackgroundTaskCoordinatorKey: EnvironmentKey {
    static let defaultValue: BackgroundTaskCoordinator? = nil
}

extension EnvironmentValues {
    /// The background-task coordinator (BGTask scheduling + "run now"); injected by the App layer.
    var backgroundTaskCoordinator: BackgroundTaskCoordinator? {
        get { self[BackgroundTaskCoordinatorKey.self] }
        set { self[BackgroundTaskCoordinatorKey.self] = newValue }
    }
}

// MARK: - SettingsView

/// Settings screen — aesthetics, xAI key, session control, backup, research intelligence, on-device
/// embedding model, and the liquid-glass render engine. Direct port of the
/// `@Composable internal fun SettingsScreen(...)`.
struct SettingsView: View {

    /// Manual `GlassTier` override (`nil` = auto). Two-way bound to `BookmarkApp`'s state — the
    /// Compose `glassTierOverride` / `onSetGlassTierOverride`.
    @Binding var glassTierOverride: GlassTier?
    /// The currently resolved glass tier (drives the card backgrounds + the "Currently resolved" line).
    let resolvedTier: GlassTier
    /// Signs the X session out (`AuthViewModel.onLogout`). Port of `onLogout`.
    let onLogout: () -> Void
    /// Shared library view model.
    @Bindable var viewModel: BookmarkViewModel

    @Environment(\.curioColors) private var colors
    @Environment(\.backgroundTaskCoordinator) private var coordinator

    // MARK: - Local UI state

    /// Transient xAI key input (NOT persisted here — saved into the Keychain by the VM). Port of the
    /// Compose `remember { mutableStateOf("") }` (deliberately not `rememberSaveable`).
    @State private var keyInput: String = ""

    /// Transient HF token entry for the first (gated) embedding-model download. Blank → reuse the
    /// token already saved in TokenStore, so returning users never have to re-enter it.
    @State private var embedHfToken: String = ""

    /// Index-while-charging preference, seeded from the coordinator (or the shared `UserDefaults`
    /// key). Port of the Compose `remember { mutableStateOf(EmbeddingIndexScheduler.isEnabled(...)) }`.
    @State private var indexWhileCharging: Bool = SettingsView.readIndexWhileCharging()
    @State private var embeddingBackend: EmbeddingBackend = EmbeddingPreference.get()
    @State private var showPurgeConfirm: Bool = false

    private let sectionChips: [(label: String, id: String)] = [
        ("Look", "appearance"),
        ("Keys", "keys"),
        ("Agent", "agent"),
        ("Session", "session"),
        ("Data", "data"),
        ("AI Tools", "intel"),
        ("Model", "model")
    ]

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sectionChips, id: \.id) { chip in
                                Button {
                                    withAnimation(CurioMotion.liquid) {
                                        proxy.scrollTo(chip.id, anchor: .top)
                                    }
                                } label: {
                                    Text(chip.label)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(colors.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(colors.primary.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.curioPressBounce)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    aestheticsCard.id("appearance")
                    xaiKeyCard.id("keys")
                    agentWritesCard.id("agent")
                    sessionCard.id("session")
                    backupCard.id("data")
                    researchIntelligenceCard.id("intel")
                    embeddingModelCard.id("model")
                    glassEngineCard
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Purge local cache?",
            isPresented: $showPurgeConfirm,
            titleVisibility: .visible
        ) {
            Button("Purge cache", role: .destructive) {
                viewModel.clearAllData()
                CurioNotifier.notify("Local cache cleared")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears cached bookmark lists and OCR records. Your X session and cloud sync are unaffected.")
        }
    }

    // MARK: - Aesthetics & Colors card

    private var aestheticsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("Aesthetics & Colors")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                Spacer().frame(height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cosmic Slate Palette")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                    Text("Curio uses a fixed premium color scheme on iOS")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(height: 12)
                divider(opacity: 0.08)
                Spacer().frame(height: 12)

                Text("OS Dark Style Preference")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                Spacer().frame(height: 6)

                // Theme radios — order/labels carried verbatim.
                ForEach(themeOptions, id: \.0) { option in
                    let (themeOption, optionTitle) = option
                    radioRow(
                        title: optionTitle,
                        selected: viewModel.themeSetting == themeOption,
                        onSelect: { viewModel.setThemeSetting(themeOption) }
                    )
                }
            }
        }
    }

    /// The three theme options + their exact labels. Port of the Compose `listOf(... to ...)`.
    private var themeOptions: [(AppThemeSetting, String)] {
        [
            (.system, "System Aware (Follow OS Theme)"),
            (.light, "Liquid Glass Frost Light"),
            (.dark, "Liquid Glass Charcoal Dark")
        ]
    }

    // MARK: - xAI API Key card
    //
    // BYOK: Curio ships without any built-in key. Users must supply their own key from
    // console.x.ai to unlock AI features. The key is stored in the Keychain via TokenStore
    // (never leaves the device). Guidance + the console.x.ai link stays visible in BOTH states:
    // when unconfigured it tells the user a key is required; when configured it's still the place
    // to grab a replacement key to rotate. Leading text and colour vary by state.

    private var xaiKeyCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("xAI API Key")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                Text(.init(viewModel.xaiKeyConfigured
                     ? "Key configured — AI analysis, chat, and image generation are active. Rotate it anytime at [console.x.ai](https://console.x.ai) → API Keys. Stored encrypted on this device only."
                     : "Required. Get a free key at [console.x.ai](https://console.x.ai) → API Keys. Stored encrypted on this device only."))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(viewModel.xaiKeyConfigured
                        ? colors.onSurface.opacity(0.6)
                        : colors.error.opacity(0.8))
                    .tint(colors.primary)

                SecureField("xai-…", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("xai_key_input")

                Button {
                    viewModel.saveXaiKey(keyInput)
                    keyInput = ""
                } label: {
                    Text("Save key")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            (keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? colors.primary.opacity(0.4)
                                : colors.primary),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.curioPressBounce)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("xai_key_save")
            }
        }
    }

    // MARK: - Assistant write-access card
    //
    // Controls whether on-device AI agents / system assistants may modify bookmarks via Curio's
    // App Intents. The platform does not expose the calling identity to intent code, so this user
    // toggle is the available defence; read-only discovery stays enabled regardless. The gate
    // lives in CurioIntents (`requireAgentWritesAllowed`).

    private var agentWritesCard: some View {
        cardContainer {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow assistants to modify my bookmarks")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                    Text("When off, AI agents and system assistants can still search and read your library, but can't add bookmarks, edit notes, or change favourites.")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(width: 12)

                Toggle("", isOn: Binding(
                    get: { viewModel.allowAgentWrites },
                    set: { viewModel.setAllowAgentWrites($0) }
                ))
                .labelsHidden()
                .tint(colors.primary)
                .accessibilityIdentifier("agent_writes_switch")
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - X Live Session Control card

    private var sessionCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("X Live Session Control")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                // Authenticated row + LOG OUT pill.
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Authenticated with PKCE")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                        Text("Locally encrypted security token handles active")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onLogout) {
                        Text("LOG OUT")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.error)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                colors.error.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("logout_button")
                }
                .frame(maxWidth: .infinity)

                Spacer().frame(height: 8)
                Rectangle()
                    .fill(colors.error.opacity(0.2))
                    .frame(height: 1)
                Spacer().frame(height: 8)
                Text("DANGER ZONE")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(colors.error.opacity(0.85))
                Spacer().frame(height: 4)

                // Purge Local Database row + PURGE CACHE pill.
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Purge Local Database")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                        Text("Clears cached bookmark lists and OCR records safely")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        showPurgeConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.slash")    // Icons.Default.DeleteSweep
                                .font(.system(size: 16))
                                .accessibilityLabel("Purge DB icon")
                            Text("PURGE CACHE")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.0)
                        }
                        .foregroundStyle(colors.error)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            colors.error.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.curioPressBounce)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Backup & Data Portability card

    private var backupCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Data Portability & Porting")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Backup & Export JSON")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                        Text("Extracts all offline stored bookmarks, screen extractions and AI curation tags securely")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        backupJson()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "icloud.and.arrow.up")    // Icons.Default.CloudSync
                                .font(.system(size: 16))
                                .foregroundStyle(colors.primary)
                                .accessibilityLabel("Export JSON backup icon")
                            Text("BACKUP JSON")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(colors.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            colors.primary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.curioPressBounce)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Exports the raw library as JSON, copies it, and opens the share sheet. Port of the Compose
    /// clickable: empty library → the "No local bookmarks to export!" Toast; otherwise copy + share.
    private func backupJson() {
        let raw = viewModel.rawBookmarks
        if raw.isEmpty {
            CurioNotifier.notify("No local bookmarks to export!")
        } else {
            let jsonString = CurioFormat.exportBackupJson(raw)
            #if canImport(UIKit)
            _ = CurioFormat.copyToClipboard(jsonString, label: "Curio Backup JSON")
            _ = CurioFormat.shareBookmark(jsonString)
            CurioNotifier.notify("Backup copied — share sheet opened")
            #endif
        }
    }

    // MARK: - Research Intelligence card

    private var researchIntelligenceCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Research Intelligence")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Semantic acceleration")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                        Text(semanticAccelerationSubtitle)
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(width: 12)

                    Toggle("", isOn: Binding(
                        get: { viewModel.semanticLayerEnabled },
                        set: { viewModel.setSemanticLayerEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(colors.primary)
                    .accessibilityIdentifier("semantic_layer_switch")
                }
                .frame(maxWidth: .infinity)

                embeddingEngineSection

                divider(opacity: 0.06)

                actionRow(
                    title: "Embed All Bookmarks",
                    subtitle: embedAllSubtitle,
                    actionLabel: "EMBED ALL",
                    accent: colors.primary,
                    background: colors.primary.opacity(0.15),
                    onTap: {
                        viewModel.embedAllBookmarks()
                        CurioNotifier.notify("Generating embeddings…")
                    }
                )

                divider(opacity: 0.06)

                actionRow(
                    title: "Resolve New Sources",
                    subtitle: "Fetch arXiv/GitHub/HF metadata for unresolved bookmarks (up to 10)",
                    actionLabel: "RESOLVE",
                    accent: colors.secondary,
                    background: colors.secondary.opacity(0.15),
                    onTap: {
                        viewModel.resolveNewSources()
                        CurioNotifier.notify("Resolving sources…")
                    }
                )

                divider(opacity: 0.06)

                actionRow(
                    title: "Deduplicate Sources",
                    subtitle: "Merge bookmarks pointing to the same paper/repo into one entry",
                    actionLabel: "DEDUP",
                    accent: colors.error,
                    background: colors.error.opacity(0.12),
                    onTap: {
                        viewModel.deduplicateBySource()
                        CurioNotifier.notify("Deduplicating…")
                    }
                )

                researchStatusLine
            }
        }
    }

    /// Live status for embed/resolve/dedup — mirrors Android Settings `when (researchStatus)`.
    @ViewBuilder
    private var researchStatusLine: some View {
        switch viewModel.syncState {
        case let .loading(message):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(message ?? "Working…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.onSurface.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .success(message):
            Text("✓ \(message)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .error(message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    /// Embedding engine chooser — mirrors Android Settings "Embedding engine" row.
    private var embeddingEngineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Embedding engine")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(colors.onSurface)

            HStack(spacing: 8) {
                ForEach(EmbeddingBackend.allCases, id: \.self) { backend in
                    let selected = embeddingBackend == backend
                    Button {
                        embeddingBackend = backend
                        EmbeddingPreference.set(backend)
                    } label: {
                        Text(backend.settingsLabel)
                            .font(.system(size: 12, weight: selected ? .heavy : .medium))
                            .foregroundStyle(selected ? colors.primary : colors.onSurface.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selected ? colors.primary.opacity(0.18) : colors.onSurface.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.curioPressBounce)
                }
            }

            Text(embeddingBackend.settingsDescription)
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.onSurface.opacity(0.6))
        }
    }

    private var embedAllSubtitle: String {
        switch embeddingBackend {
        case .auto:
            return "Generate semantic vectors (on-device when model ready, else xAI cloud)."
        case .onDevice:
            return "Generate semantic vectors on-device only (requires downloaded model)."
        case .xai:
            return "Generate semantic vectors via xAI cloud."
        }
    }

    private var semanticAccelerationSubtitle: String {
        viewModel.semanticLayerEnabled
            ? "On-device — caches answers, compresses context, and routes reasoning effort by complexity."
            : "Off — chat calls xAI directly with the full retrieved context."
    }

    // MARK: - On-Device Embedding card

    private var embeddingModelCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")    // Icons.Default.Psychology
                        .font(.system(size: 20))
                        .foregroundStyle(colors.primary)
                    Text("On-Device Embedding")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                }

                Text("Private semantic indexing with EmbeddingGemma — vectors are computed entirely on your device, no cloud. \(EmbeddingModelManager.APPROX_SIZE_LABEL) download.")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.onSurface.opacity(0.6))

                // EmbeddingGemma is Gemma-license-gated on Hugging Face, so the first download
                // needs a free HF token. Surface the link + guidance + an (optional) token field
                // here so the download is self-sufficient from Settings — no bare 401, no bouncing
                // to the feed sheet. A blank field reuses the token already saved in TokenStore.
                if viewModel.embeddingModelState != .ready {
                    Text(.init("First download needs a free Hugging Face token — get one at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens), then accept the Gemma license on the model page. Stored encrypted on this device."))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .tint(colors.primary)

                    SecureField("Hugging Face token (optional if already saved)", text: $embedHfToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("embed_hf_token_input")
                }

                // State-driven status + controls.
                modelStateSection

                divider(opacity: 0.06)

                // Index-while-charging toggle.
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Index while charging")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                        Text("Backfill embeddings on-device only when plugged in & battery isn't low")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("", isOn: Binding(
                        get: { indexWhileCharging },
                        set: { newValue in
                            indexWhileCharging = newValue
                            setIndexWhileCharging(newValue)
                        }
                    ))
                    .labelsHidden()
                    .tint(colors.primary)
                    .accessibilityIdentifier("index_while_charging_switch")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The model status block — a `switch` over `EmbeddingModelManager.ModelState` (Absent /
    /// Downloading / Ready / Failed), exactly mirroring the Compose `when (val s = modelState)`.
    @ViewBuilder
    private var modelStateSection: some View {
        switch viewModel.embeddingModelState {
        case .absent:
            HStack(alignment: .center) {
                Text("Model not downloaded")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    viewModel.downloadEmbeddingModel(token: embedHfToken)
                } label: {
                    accentPill("DOWNLOAD", accent: colors.primary, background: colors.primary.opacity(0.15))
                }
                .buttonStyle(.curioPressBounce)
                .accessibilityIdentifier("download_model_button")
            }
            .frame(maxWidth: .infinity)

        case let .downloading(fraction, label):
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.primary)
                if fraction > 0 {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
            }

        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")    // Icons.Default.Check
                            .font(.system(size: 16))
                            .foregroundStyle(Color(argb: 0xFF4CAF50))
                        Text("Model ready · on-device")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(argb: 0xFF4CAF50))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        viewModel.deleteEmbeddingModel()
                    } label: {
                        accentPill("DELETE", accent: colors.error, background: colors.error.opacity(0.12))
                    }
                    .buttonStyle(.curioPressBounce)
                }
                .frame(maxWidth: .infinity)

                // Build the index immediately (foreground, on-device).
                Button {
                    coordinator?.runNow()
                    CurioNotifier.notify("Building on-device index…")
                } label: {
                    Text("BUILD INDEX NOW")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            colors.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.curioPressBounce)
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(colors.error)
                Button {
                    viewModel.downloadEmbeddingModel(token: embedHfToken)
                } label: {
                    accentPill("RETRY", accent: colors.primary, background: colors.primary.opacity(0.15))
                }
                .buttonStyle(.curioPressBounce)
            }
        }
    }

    // MARK: - Liquid-Glass Render Engine card

    private var glassEngineCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("Liquid-Glass Render Engine")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onSurface)

                Spacer().frame(height: 6)

                Text("Currently resolved: \(tierName(resolvedTier).uppercased())")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.1)
                    .foregroundStyle(colors.primary)

                Spacer().frame(height: 12)

                ForEach(glassTierOptions, id: \.label) { option in
                    radioRow(
                        title: option.label,
                        selected: glassTierOverride == option.tier,
                        onSelect: { glassTierOverride = option.tier }
                    )
                }
            }
        }
    }

    /// The four glass-tier options (Auto = nil). Labels carried verbatim.
    private var glassTierOptions: [(tier: GlassTier?, label: String)] {
        [
            (nil, "Auto (Auto-detect features & RAM)"),
            (.full, "Full (RenderEffect Blur + Sheen)"),
            (.blur, "Blur (Frosted Alpha overlay)"),
            (.solid, "Solid (Translucent fill - Low RAM / Battery safe)")
        ]
    }

    /// Mirrors the Kotlin `GlassTier.name` used in `"Currently resolved: ${resolvedTier.name…}"` — the
    /// Android enum cases were `Full/Blur/Solid`, so the displayed (uppercased) names are FULL/BLUR/SOLID.
    private func tierName(_ tier: GlassTier) -> String {
        switch tier {
        case .full: return "Full"
        case .blur: return "Blur"
        case .solid: return "Solid"
        }
    }

    // MARK: - Reusable card / row builders

    /// A glass card container matching the Compose `Box.glassSurface(tier).padding(16)`.
    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: resolvedTier)
    }

    /// A hairline divider (`HorizontalDivider(onSurface@opacity)`).
    private func divider(opacity: Double) -> some View {
        colors.onSurface.opacity(opacity)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    /// A radio-button selection row (theme / glass-tier pickers).
    private func radioRow(title: String, selected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? colors.primary : colors.onSurfaceVariant)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.25)
                    .foregroundStyle(colors.onSurface)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.curioPressBounce)
    }

    /// A title/subtitle row paired with a trailing accent action pill (Research Intelligence rows).
    private func actionRow(
        title: String,
        subtitle: String,
        actionLabel: String,
        accent: Color,
        background: Color,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.onSurface.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onTap) {
                Text(actionLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
        }
        .frame(maxWidth: .infinity)
    }

    /// A standalone accent pill label (DOWNLOAD / DELETE / RETRY).
    private func accentPill(_ label: String, accent: Color, background: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Index-while-charging persistence bridge

    /// UserDefaults key the `BackgroundTaskCoordinator` persists the toggle under. Kept literally equal
    /// so the control stays correct whether or not the coordinator is injected.
    private static let indexWhileChargingKey = "index_while_charging"

    /// Reads the current preference (default ON). Mirrors `EmbeddingIndexScheduler.isEnabled`.
    private static func readIndexWhileCharging() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: indexWhileChargingKey) != nil else { return true }
        return defaults.bool(forKey: indexWhileChargingKey)
    }

    /// Persists + (re)schedules/cancels the charging-time backfill. Prefers the injected coordinator
    /// (which persists AND schedules); falls back to writing the shared key directly so the preference
    /// still round-trips when no coordinator is present (e.g. previews). Mirrors
    /// `EmbeddingIndexScheduler.setEnabled`.
    private func setIndexWhileCharging(_ enabled: Bool) {
        if let coordinator {
            coordinator.setIndexWhileChargingEnabled(enabled)
        } else {
            UserDefaults.standard.set(enabled, forKey: Self.indexWhileChargingKey)
        }
    }
}
