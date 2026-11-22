import ActivityKit
import KeyDeckKit
import SwiftUI
import WidgetKit

struct VoiceSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceSessionAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: iconName(for: context.state))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accentColor(for: context.state.phase))

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase == .recording ? context.state.mode.displayName : "KeyDeck Mic")
                        .font(.subheadline.weight(.semibold))
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Link(destination: KeyDeckConstants.DeepLinks.disarmSession()) {
                    Label("Kill", systemImage: "mic.slash.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.state.phase == .recording ? context.state.mode.displayName : "KeyDeck",
                        systemImage: iconName(for: context.state)
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor(for: context.state.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: KeyDeckConstants.DeepLinks.disarmSession()) {
                        Label("Kill Mic", systemImage: "mic.slash.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state))
                    .foregroundStyle(accentColor(for: context.state.phase))
            } compactTrailing: {
                Text(compactLabel(for: context.state.phase))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor(for: context.state.phase))
            } minimal: {
                Image(systemName: iconName(for: context.state))
                    .foregroundStyle(accentColor(for: context.state.phase))
            }
            .widgetURL(KeyDeckConstants.DeepLinks.disarmSession())
        }
    }

    private func iconName(for state: VoiceSessionAttributes.ContentState) -> String {
        switch state.phase {
        case .recording: "waveform"
        case .processing: "sparkles"
        case .armed, .ready: "mic.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "mic.slash"
        }
    }

    private func accentColor(for phase: VoicePhase) -> Color {
        switch phase {
        case .recording: .red
        case .processing: .orange
        case .armed, .ready: .green
        case .failed: .yellow
        case .idle: .secondary
        }
    }

    private func compactLabel(for phase: VoicePhase) -> String {
        switch phase {
        case .recording: "REC"
        case .processing: "AI"
        case .armed, .ready: "ON"
        case .failed: "!"
        case .idle: "OFF"
        }
    }
}
