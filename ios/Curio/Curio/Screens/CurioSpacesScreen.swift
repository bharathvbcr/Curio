//
//  CurioSpacesScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioSpacesScreen.kt
//         (spaceIconKeys, spaceIcon, spacePalette, CurioSpacesScreen, SpaceCard, SmartBadge,
//          SpaceIconButton, SpacesEmptyState, SpaceEditorDialog, SpaceRulesEditor, RulePill,
//          rulePlaceholder, DeleteSpaceDialog, AssignToSpaceDialog).
//
//  DESIGN §10 (Screens): Spaces home + editor/delete/assign dialogs + icon/color registry + rule
//  builder. `struct CurioSpacesView`; `spaceIconKeys` (21), `spacePalette` (18 ARGB),
//  `spaceIcon(_:)` → SF Symbols (Material→SF-Symbol substitutions documented inline); `SpaceCard`,
//  `SmartBadge`; `SpaceEditorDialog` (color/icon grids, `SpaceRulesEditor` tap-to-cycle pills,
//  ANY/ALL, autoFile), `DeleteSpaceDialog`, `AssignToSpaceDialog`, `rulePlaceholder`.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": the screen reads the single injected `BookmarkViewModel` directly
//    (Kotlin `viewModel.spaces.collectAsStateWithLifecycle()` collapses to a plain property read of
//    the computed `spaces`/`stats`). The VM is held as a `@Bindable` reference (owned upstream).
//  - §8 "Theme tokens": Material `ImageVector`s map to SF Symbols via the single `spaceIcon(_:)`
//    lookup (documented substitutions); the packed-ARGB `Space.color` is unpacked to a SwiftUI
//    `Color` ONLY here at the UI boundary via `Color(packedARGB:)`. The `spacePalette` longs are
//    stored as `Int64` and unpacked the same way.
//  - §8 "Glass": every surface uses `glassSurface(tier:shape:tint:borderColor:)`; the dialogs use the
//    shared `SlideUpCard` (a `.sheet` detented to 92%); in-card Cancel/confirm route through
//    `@Environment(\.slideUpDismiss)`.
//  - §8 "Motion": taps use `Button { }.buttonStyle(.curioPressBounce)` (the `pressBounce` analogue),
//    selection pops use `.bounceScale(active:)` (the non-hit-testing `bounceScale`).
//  - Every user-facing string, testTag (→ `.accessibilityIdentifier`), and contentDescription
//    (→ `.accessibilityLabel`) is carried over verbatim.
//
//  This file is the iOS analogue of the Kotlin `CurioSpacesScreen.kt`. It depends on the upstream
//  Domain types (`Space`, `SpaceRule(s)`, `RuleField/Op/Match`) and the `BookmarkViewModel`
//  (Platform) by their declared signatures, plus the shared `SlideUpCard` (Components).
//

import SwiftUI

// MARK: - Icon / color registry

/// The curated set of icons a Space can use, keyed by a stable string persisted on the entity.
/// Ports the Kotlin `internal val spaceIconKeys`. Order is preserved (the editor renders them in
/// this exact order, and `spaceIconKeys.first()` is the create-dialog default).
let spaceIconKeys: [String] = [
    "workspaces", "folder", "star", "science", "code", "book", "lightbulb", "rocket",
    "favorite", "label", "hub", "bolt", "psychology", "dataset", "school", "terminal",
    "image", "public", "flag", "bug", "bookmark"
]

/// Resolves a persisted `iconKey` to its SF Symbol, defaulting to the generic workspaces glyph.
/// Ports the Kotlin `internal fun spaceIcon(iconKey)`.
///
/// Material → SF Symbol substitutions (CONVENTIONS §8 "Icons" — documented):
///   workspaces→square.grid.2x2.fill, folder→folder.fill, star→star.fill, science→atom,
///   code→chevron.left.forward.slash.chevron.right, book→book.fill (Material AutoMirrored MenuBook),
///   lightbulb→lightbulb.fill, rocket→paperplane.fill (RocketLaunch — no rocket symbol pre-iOS-? so
///   the closest launch glyph is used), favorite→heart.fill, label→tag.fill, hub→point.3.connected
///   .trianglepath.dotted (Hub), bolt→bolt.fill, psychology→brain.head.profile, dataset→
///   tablecells.fill (Dataset), school→graduationcap.fill, terminal→terminal.fill, image→photo.fill,
///   public→globe (Public), flag→flag.fill, bug→ladybug.fill (BugReport), bookmark→bookmark.fill
///   (Material Bookmarks plural), default→square.grid.2x2.fill (Workspaces).
func spaceIcon(_ iconKey: String?) -> String {
    switch iconKey {
    case "folder": return "folder.fill"
    case "star": return "star.fill"
    case "science": return "atom"
    case "code": return "chevron.left.forward.slash.chevron.right"
    case "book": return "book.fill"
    case "lightbulb": return "lightbulb.fill"
    case "rocket": return "paperplane.fill"
    case "favorite": return "heart.fill"
    case "label": return "tag.fill"
    case "hub": return "point.3.connected.trianglepath.dotted"
    case "bolt": return "bolt.fill"
    case "psychology": return "brain.head.profile"
    case "dataset": return "tablecells.fill"
    case "school": return "graduationcap.fill"
    case "terminal": return "terminal.fill"
    case "image": return "photo.fill"
    case "public": return "globe"
    case "flag": return "flag.fill"
    case "bug": return "ladybug.fill"
    case "bookmark": return "bookmark.fill"
    default: return "square.grid.2x2.fill"
    }
}

/// Palette offered in the Space editor; values are packed ARGB longs stored on the entity.
/// Ports the Kotlin `internal val spacePalette` — kept as `Int64` (Kotlin `Long`) and unpacked to a
/// `Color` only at the UI boundary. The high alpha byte is `0xFF` exactly like the Kotlin literals.
let spacePalette: [Int64] = [
    0xFF1E88E5, 0xFF43A047, 0xFF8E24AA, 0xFF00BCD4, 0xFFFF9800,
    0xFFE91E63, 0xFF3F51B5, 0xFF009688, 0xFFFFC107, 0xFFFF5722,
    0xFF673AB7, 0xFF607D8B, 0xFF2196F3, 0xFF4CAF50, 0xFFFF4081,
    0xFF795548, 0xFF00E5FF, 0xFFCDDC39
]

// MARK: - CurioSpacesView

/// Spaces home — the user's library organised into named collections. Lives where Insights used to
/// sit in the bottom navigation; Insights moved to the side drawer. Tapping a Space opens the feed
/// scoped to that collection (`onOpenSpace`). Direct port of `@Composable CurioSpacesScreen`.
struct CurioSpacesView: View {
    /// The single shared central library view model (owned upstream, injected here).
    @Bindable var viewModel: BookmarkViewModel
    let tier: GlassTier
    let onOpenSpace: (Space) -> Void

    @Environment(\.curioColors) private var colors

    // Local UI flags — ports of the Compose `remember { mutableStateOf(...) }` dialog targets.
    @State private var editorTarget: Space? = nil
    @State private var showCreate: Bool = false
    @State private var pendingDelete: Space? = nil

    var body: some View {
        let spaces = viewModel.spaces
        let stats = viewModel.stats

        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Header copy.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ORGANIZE YOUR INDEX")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(colors.primary)
                        Text("Group bookmarks into Spaces — collections you control, separate from AI categories.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.6))
                    }
                    .padding(.top, 4)

                    // Create-new-space tile — hidden when empty (empty state has its own CTA).
                    if !spaces.isEmpty {
                    Button {
                        showCreate = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(colors.primary.opacity(0.18))
                                Image(systemName: "plus")
                                    .foregroundStyle(colors.primary)
                            }
                            .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("New Space")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(colors.onSurface)
                                Text("Create a collection")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(colors.onSurface.opacity(0.5))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface(
                            tier: tier,
                            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                            tint: colors.primary.opacity(0.10),
                            borderColor: colors.primary.opacity(0.3)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("create_space_button")
                    }

                    if spaces.isEmpty {
                        SpacesEmptyState(tier: tier, onCreate: { showCreate = true })
                    } else {
                        ForEach(spaces) { space in
                            SpaceCard(
                                space: space,
                                totalCount: stats.totalCount,
                                tier: tier,
                                onOpen: { onOpenSpace(space) },
                                onEdit: { editorTarget = space },
                                onDelete: { pendingDelete = space },
                                onTogglePin: { viewModel.setSpacePinned(id: space.id, pinned: !space.isPinned) },
                                onApplyRules: { viewModel.applySpaceRules(space) }
                            )
                        }
                    }

                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 16)
            }
        }
        // Create dialog.
        .sheet(isPresented: $showCreate) {
            SpaceEditorDialog(
                existing: nil,
                tier: tier,
                onConfirm: { name, color, icon, description, rules, isPinned in
                    viewModel.createSpace(
                        name: name, color: color, icon: icon,
                        description: description, rules: rules, isPinned: isPinned
                    )
                    showCreate = false
                }
            )
        }
        // Edit dialog.
        .sheet(item: $editorTarget) { target in
            SpaceEditorDialog(
                existing: target,
                tier: tier,
                onConfirm: { name, color, icon, description, rules, isPinned in
                    viewModel.updateSpace(
                        id: target.id, name: name, color: color, icon: icon,
                        description: description, rules: rules, isPinned: isPinned
                    )
                    editorTarget = nil
                }
            )
        }
        // Delete confirm.
        .sheet(item: $pendingDelete) { target in
            DeleteSpaceDialog(
                space: target,
                tier: tier,
                onConfirm: {
                    viewModel.deleteSpace(id: target.id)
                    pendingDelete = nil
                }
            )
        }
    }
}

// MARK: - SpaceCard

/// A single Space row: gradient icon orb, name + smart badge + pin marker, a derived count/%-of-index
/// line, the per-Space action buttons (apply-rules when smart, pin/unpin, edit, delete), and an
/// optional description. Direct port of the private `@Composable SpaceCard`.
private struct SpaceCard: View {
    let space: Space
    let totalCount: Int
    let tier: GlassTier
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onApplyRules: () -> Void

    @Environment(\.curioColors) private var colors

    private var color: Color { Color(packedARGB: space.color) }

    /// `"{count} bookmark(s)[ · {pct}% of index]"`. Mirrors the Kotlin `buildString { … }` exactly,
    /// including the `coerceAtLeast(1)` integer-division guard.
    private var countLine: String {
        var s = "\(space.count) "
        s += (space.count == 1 ? "bookmark" : "bookmarks")
        if totalCount > 0 {
            let denom = max(totalCount, 1)
            s += " · \((space.count * 100) / denom)% of index"
        }
        return s
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 14) {
                    // Gradient icon orb.
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.95), color.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: spaceIcon(space.icon))
                            .font(.system(size: 24))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 48, height: 48)

                    // Title + count column.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(space.name)
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(colors.onSurface)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            if space.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(color)
                                    .accessibilityLabel("Pinned")
                            }
                            if space.isSmart { SmartBadge(color: color) }
                            Spacer(minLength: 0)
                        }
                        Text(countLine)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Per-Space action buttons.
                    if space.isSmart {
                        SpaceIconButton(
                            icon: "sparkles",
                            label: "Apply rules for \(space.name)",
                            tint: color.opacity(0.9),
                            onClick: onApplyRules
                        )
                    }
                    SpaceIconButton(
                        icon: space.isPinned ? "pin.fill" : "pin",
                        label: space.isPinned ? "Unpin \(space.name)" : "Pin \(space.name)",
                        tint: space.isPinned ? color : colors.onSurface.opacity(0.45),
                        onClick: onTogglePin
                    )
                    SpaceIconButton(
                        icon: "pencil",
                        label: "Edit \(space.name)",
                        tint: colors.onSurface.opacity(0.55),
                        onClick: onEdit
                    )
                    SpaceIconButton(
                        icon: "trash",
                        label: "Delete \(space.name)",
                        tint: colors.error.opacity(0.8),
                        onClick: onDelete
                    )
                }

                if !space.description.isBlank {
                    Text(space.description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.leading, 2)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(
                tier: tier,
                shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                tint: color.opacity(0.08)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
        .accessibilityIdentifier("space_card_\(space.id)")
    }
}

// MARK: - SmartBadge

/// Small "SMART" pill marking a rule-driven Space. Direct port of the private `@Composable SmartBadge`.
private struct SmartBadge: View {
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text("SMART")
                .font(.system(size: 8, weight: .black))
                .tracking(0.5)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - SpaceIconButton

/// A 48pt tappable icon button used in the `SpaceCard` action row. Direct port of the private
/// `@Composable SpaceIconButton`.
private struct SpaceIconButton: View {
    let icon: String
    let label: String
    let tint: Color
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel(label)
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - SpacesEmptyState

/// The no-Spaces empty state shown in place of the list. Direct port of the private `@Composable
/// SpacesEmptyState`.
private struct SpacesEmptyState: View {
    let tier: GlassTier
    let onCreate: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(colors.primary.opacity(0.12))
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(colors.primary)
            }
            .frame(width: 72, height: 72)

            Text("NO SPACES YET")
                .font(.system(size: 16, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.onSurface)

            Text("Create your first Space to start grouping bookmarks — like \"To Read\", \"Diffusion\", or \"Thesis\".")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .multilineTextAlignment(.center)

            Button(action: onCreate) {
                Text("CREATE A SPACE")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(colors.onPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(colors.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .glassSurface(
            tier: tier,
            shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: colors.surface.opacity(0.4)
        )
        .padding(.top, 24)
    }
}

// MARK: - SpaceEditorDialog

/// Create-or-edit dialog for a Space. Supplies a name field, an optional description, a color and
/// icon picker, a "pin to top" toggle, and a Smart-Space rule builder. Reused for both creation
/// (`existing == nil`) and editing. Direct port of `internal @Composable SpaceEditorDialog`.
struct SpaceEditorDialog: View {
    let existing: Space?
    let tier: GlassTier
    let onConfirm: (_ name: String, _ color: Int64, _ icon: String, _ description: String, _ rules: SpaceRules, _ isPinned: Bool) -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    // Editor state, seeded from `existing` (Compose `remember { mutableStateOf(existing?…) }`).
    @State private var name: String
    @State private var description: String
    @State private var color: Int64
    @State private var icon: String
    @State private var isPinned: Bool

    // Rule-builder state.
    @State private var rules: [SpaceRule]
    @State private var matchMode: RuleMatch
    @State private var autoFile: Bool

    init(
        existing: Space?,
        tier: GlassTier,
        onConfirm: @escaping (String, Int64, String, String, SpaceRules, Bool) -> Void
    ) {
        self.existing = existing
        self.tier = tier
        self.onConfirm = onConfirm
        _name = State(initialValue: existing?.name ?? "")
        _description = State(initialValue: existing?.description ?? "")
        _color = State(initialValue: existing?.color ?? spacePalette.first!)
        _icon = State(initialValue: existing?.icon ?? spaceIconKeys.first!)
        _isPinned = State(initialValue: existing?.isPinned ?? false)
        _rules = State(initialValue: existing?.rules.rules ?? [])
        _matchMode = State(initialValue: existing?.rules.match ?? .ANY)
        _autoFile = State(initialValue: existing?.rules.autoFile ?? true)
    }

    private var accent: Color { Color(packedARGB: color) }

    private func assembledRules() -> SpaceRules {
        SpaceRules(match: matchMode, autoFile: autoFile, rules: rules)
    }

    /// `name.isNotBlank()`.
    private var canSave: Bool { !name.isBlank }

    var body: some View {
        SlideUpCard(tier: tier, spacing: 18) {
            Text(existing == nil ? "NEW SPACE" : "EDIT SPACE")
                .font(.system(size: 16, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.primary)

            // Name field.
            TextField("Space name", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent, lineWidth: 1)
                }
                .accessibilityIdentifier("space_name_input")

            // Description field.
            TextField("Description (optional)", text: $description)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent, lineWidth: 1)
                }
                .accessibilityIdentifier("space_description_input")

            // Pin-to-top toggle.
            HStack(spacing: 10) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 18))
                    .foregroundStyle(isPinned ? accent : colors.onSurface.opacity(0.5))
                Text("Pin to top")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $isPinned)
                    .labelsHidden()
                    .tint(accent)
                    .accessibilityIdentifier("space_pin_switch")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(colors.onSurface.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { isPinned.toggle() }

            // Color picker.
            Text("COLOR")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowGrid(items: spacePalette, spacing: 10) { swatch in
                let selected = swatch == color
                Button { color = swatch } label: {
                    ZStack {
                        Circle().fill(Color(packedARGB: swatch))
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle().stroke(colors.onSurface, lineWidth: selected ? 3 : 0)
                    }
                    .bounceScale(active: selected)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Icon picker.
            Text("ICON")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowGrid(items: spaceIconKeys, spacing: 10) { key in
                let selected = key == icon
                Button { icon = key } label: {
                    Image(systemName: spaceIcon(key))
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? accent : colors.onSurface.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(
                            (selected ? accent.opacity(0.2) : colors.onSurface.opacity(0.05)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? accent : Color.clear, lineWidth: 1)
                        }
                        .bounceScale(active: selected)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel(key)
                }
                .buttonStyle(.plain)
            }

            // Smart-Space rule builder.
            SpaceRulesEditor(
                accent: accent,
                rules: $rules,
                matchMode: $matchMode,
                autoFile: $autoFile
            )

            // Cancel / Create-or-Save actions.
            HStack(spacing: 12) {
                Button { dismissCard() } label: {
                    Text("CANCEL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.onSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)

                Button {
                    if canSave {
                        onConfirm(name, color, icon, description, assembledRules(), isPinned)
                    }
                } label: {
                    Text(existing == nil ? "CREATE" : "SAVE")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            (canSave ? accent : colors.onSurface.opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.curioPressBounce)
                .disabled(!canSave)
                .accessibilityIdentifier("space_save_button")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - SpaceRulesEditor

/// The Smart-Space rule editor. Each rule is "[field] [op] [value]"; field/op are cycled by tapping
/// their pill (a deliberately dropdown-free design that stays reliable inside a bottom sheet). When
/// at least one rule exists, an ANY/ALL match toggle and an "auto-file" switch appear. Direct port of
/// the private `@Composable SpaceRulesEditor` (the Compose `SnapshotStateList` becomes a `@Binding`).
private struct SpaceRulesEditor: View {
    let accent: Color
    @Binding var rules: [SpaceRule]
    @Binding var matchMode: RuleMatch
    @Binding var autoFile: Bool

    @Environment(\.curioColors) private var colors

    private var onSurface: Color { colors.onSurface }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(accent)
                Text("SMART RULES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(onSurface.opacity(0.6))
            }
            Text("Auto-file bookmarks that match these conditions.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(onSurface.opacity(0.45))

            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RuleEnumMenu(
                            label: rule.field.label,
                            accent: accent,
                            options: RuleField.allCases.map { ($0.label, $0) }
                        ) { field in
                            rules[index] = SpaceRule(field: field, op: rule.op, value: rule.value)
                        }
                        .accessibilityIdentifier("space_rule_field_\(index)")

                        RuleEnumMenu(
                            label: rule.op.label,
                            accent: accent,
                            options: RuleOp.allCases.map { ($0.label, $0) }
                        ) { op in
                            rules[index] = SpaceRule(field: rule.field, op: op, value: rule.value)
                        }

                        Spacer(minLength: 0)

                        Button {
                            rules.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundStyle(colors.error.opacity(0.8))
                                .frame(width: 20, height: 20)
                                .contentShape(Circle())
                                .accessibilityLabel("Remove rule")
                        }
                        .buttonStyle(.plain)
                    }

                    // Per-rule value field. Binding writes back via a fresh SpaceRule (value is `let`).
                    let valueBinding = Binding<String>(
                        get: { index < rules.count ? rules[index].value : "" },
                        set: { newValue in
                            guard index < rules.count else { return }
                            let r = rules[index]
                            rules[index] = SpaceRule(field: r.field, op: r.op, value: newValue)
                        }
                    )
                    TextField(rulePlaceholder(rule.field), text: valueBinding)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(accent, lineWidth: 1)
                        }
                        .accessibilityIdentifier("space_rule_value_\(index)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(onSurface.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("space_rule_\(index)")
            }

            // Add-rule button.
            Button {
                rules.append(SpaceRule(field: .KEYWORD, op: .CONTAINS, value: ""))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundStyle(accent)
                    Text(rules.isEmpty ? "Add a rule" : "Add another rule")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space_add_rule_button")

            // Match-mode + auto-file controls only matter once a rule exists.
            if !rules.isEmpty {
                if rules.count > 1 {
                    HStack(spacing: 8) {
                        Text("Match")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(onSurface.opacity(0.6))
                        ForEach(RuleMatch.allCases, id: \.self) { mode in
                            let selected = mode == matchMode
                            Button { matchMode = mode } label: {
                                Text(mode == .ANY ? "Any rule" : "All rules")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(selected ? accent : onSurface.opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        (selected ? accent.opacity(0.18) : onSurface.opacity(0.05)),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(selected ? accent : Color.clear, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Auto-file matches")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(onSurface)
                        Text(autoFile
                             ? "New & existing matches are filed automatically."
                             : "Rules run only when you tap Apply.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(onSurface.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("", isOn: $autoFile)
                        .labelsHidden()
                        .tint(accent)
                        .accessibilityIdentifier("space_autofile_switch")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - RuleEnumMenu

/// Dropdown menu for picking a rule field or operator (Android `RuleEnumDropdown` analogue).
private struct RuleEnumMenu<T: Hashable>: View {
    let label: String
    let accent: Color
    let options: [(String, T)]
    let onSelect: (T) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                Button(pair.0) { onSelect(pair.1) }
            }
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            }
        }
    }
}

/// Field-specific hint text for a rule's value input. Direct port of `private fun rulePlaceholder`.
private func rulePlaceholder(_ field: RuleField) -> String {
    switch field {
    case .KEYWORD: return "e.g. diffusion"
    case .TAG: return "e.g. transformers"
    case .CATEGORY: return "e.g. agents"
    case .SOURCE: return "ARXIV, GITHUB, HUGGING_FACE, TWEET"
    case .AUTHOR: return "e.g. karpathy"
    case .URL: return "e.g. github.com"
    }
}

// MARK: - DeleteSpaceDialog

/// Two-step delete confirmation. Reassures the user the bookmarks stay in the library (no FK cascade
/// — they're just unfiled). Direct port of the private `@Composable DeleteSpaceDialog`.
struct DeleteSpaceDialog: View {
    let space: Space
    let tier: GlassTier
    let onConfirm: () -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    /// `"Delete \"{name}\"? The {n} bookmark[s] inside stay in your library — they're just unfiled
    /// from this Space."`. Mirrors the Kotlin string-template pluralisation exactly.
    private var bodyText: String {
        let plural = space.count == 1 ? "" : "s"
        return "Delete \"\(space.name)\"? The \(space.count) bookmark\(plural) inside stay in your library — they're just unfiled from this Space."
    }

    var body: some View {
        SlideUpCard(
            tier: tier,
            borderColor: colors.error.opacity(0.3),
            spacing: 16
        ) {
            Text("DELETE SPACE")
                .font(.system(size: 16, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.error)

            Text(bodyText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.7))

            HStack(spacing: 12) {
                Button { dismissCard() } label: {
                    Text("CANCEL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.onSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)

                Button(action: onConfirm) {
                    Text("DELETE")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onError)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.error, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
                .accessibilityIdentifier("space_delete_confirm_\(space.id)")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - AssignToSpaceDialog

/// Picks a Space (or removes membership) for a set of bookmarks. Shared by the feed's bulk action
/// bar and a single card's option sheet. `currentSpaceId` highlights the active membership when all
/// selected items share one. Direct port of `internal @Composable AssignToSpaceDialog`.
struct AssignToSpaceDialog: View {
    let spaces: [Space]
    let currentSpaceId: String?
    let tier: GlassTier
    let onAssign: (_ spaceId: String?) -> Void
    let onCreateSpace: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        SlideUpCard(tier: tier, contentPadding: 20, spacing: 8) {
            Text("MOVE TO SPACE")
                .font(.system(size: 16, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.primary)
                .padding(.bottom, 6)

            if spaces.isEmpty {
                Text("You don't have any Spaces yet.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .padding(.vertical, 4)
            }

            ForEach(spaces) { space in
                let color = Color(packedARGB: space.color)
                let selected = space.id == currentSpaceId
                Button {
                    onAssign(space.id)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(color.opacity(0.9))
                            Image(systemName: spaceIcon(space.icon))
                                .font(.system(size: 18))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 34, height: 34)

                        Text(space.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.onSurface)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(space.count)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.5))

                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18))
                                .foregroundStyle(color)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(
                        (selected ? color.opacity(0.14) : colors.onSurface.opacity(0.04)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assign_space_\(space.id)")
            }

            // Remove-from-space option (only meaningful when something is filed).
            if currentSpaceId != nil {
                Button {
                    onAssign(nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(colors.error)
                        Text("Remove from Space")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.error)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(colors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // New space shortcut.
            Button {
                onCreateSpace()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 18))
                        .foregroundStyle(colors.primary)
                    Text("New Space…")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(colors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("assign_new_space_button")
        }
    }
}

// MARK: - FlowGrid (Compose FlowRow analogue)

/// A wrapping row of equally-positioned items — the iOS analogue of Compose `FlowRow` with a fixed
/// `horizontalArrangement`/`verticalArrangement` spacing. Lays children left-to-right, wrapping to a
/// new line when the next item would overflow the available width. Used by the color/icon pickers,
/// which is exactly the `FlowRow` usage in the Kotlin editor.
private struct FlowGrid<Item: Hashable, ItemView: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> ItemView

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Note: the wrapping `FlowLayout` (Compose `FlowRow` analogue) is the shared one declared in
// `Components/CurioPostCard.swift`; `FlowGrid` above reuses it via `FlowLayout(spacing:)`.
