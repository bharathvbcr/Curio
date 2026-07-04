import ActivityKit
import WidgetKit
import SwiftUI

// ============================================================================
// Curio's single Live Activity UI — Lock Screen / banner + Dynamic Island.
// Renders `CurioActivityAttributes.ContentState` (the shared, dependency-free
// model compiled into both the app and this extension). This is the iOS analogue
// of Android's promoted `Notification.ProgressStyle` "Live Update" chip.
// ============================================================================

/// Curio brand tokens, kept local so the widget extension stays self-contained (it does not link the
/// app's theme). Violet ≈ the Android notification accent.
private enum CurioBrand {
    static let accent = Color(red: 0.49, green: 0.36, blue: 0.96)   // ~#7C5CF5
    static let accentSoft = Color(red: 0.62, green: 0.52, blue: 0.98)
    static let danger = Color(red: 0.90, green: 0.30, blue: 0.36)
    static let success = Color(red: 0.30, green: 0.78, blue: 0.55)

    /// The accent that matches the current attention state.
    static func tint(for state: CurioActivityAttributes.ContentState) -> Color {
        switch state.attention {
        case .error: return danger
        case .digestReady: return success
        case .none: return accent
        }
    }
}

struct CurioActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CurioActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            CurioLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CurioGlyph(state: state)
                        .frame(width: 34, height: 34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CurioTrailing(state: state)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.headline)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let detail = state.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CurioProgressBar(state: state)
                }
            } compactLeading: {
                CurioGlyph(state: state)
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                Text(state.shortStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CurioBrand.tint(for: state))
            } minimal: {
                CurioGlyph(state: state)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(CurioBrand.tint(for: state))
        }
    }
}

// MARK: - Lock Screen

private struct CurioLockScreenView: View {
    let state: CurioActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            CurioGlyph(state: state)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(state.headline)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if state.isOngoing {
                        Text(state.shortStatus)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CurioBrand.accentSoft)
                    }
                }
                if let detail = state.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
                CurioProgressBar(state: state)
            }
        }
        .padding(16)
    }
}

// MARK: - Shared pieces

/// The rounded, tinted bookmark glyph shown across every presentation. Uses an SF Symbol per the
/// leading task (or a state-appropriate icon for attention) so the activity always reads as Curio.
private struct CurioGlyph: View {
    let state: CurioActivityAttributes.ContentState

    private var symbol: String {
        switch state.attention {
        case .digestReady: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        case .none: return state.activeTasks.first?.symbol ?? "bookmark.fill"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(CurioBrand.tint(for: state).gradient)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

/// Trailing element for the expanded Dynamic Island: a determinate ring, an indeterminate spinner,
/// or the attention glyph.
private struct CurioTrailing: View {
    let state: CurioActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isOngoing {
                if let p = state.progress {
                    Text("\(Int(p * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CurioBrand.accentSoft)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(CurioBrand.accentSoft)
                }
            } else {
                EmptyView()
            }
        }
    }
}

/// The determinate/indeterminate progress bar shared by the Lock Screen and the expanded island.
/// Hidden entirely for attention (digest-ready / error) states, where there's no progress to show.
private struct CurioProgressBar: View {
    let state: CurioActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isOngoing {
                if let p = state.progress {
                    ProgressView(value: p)
                        .tint(CurioBrand.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(CurioBrand.accent)
                }
            } else {
                EmptyView()
            }
        }
    }
}
