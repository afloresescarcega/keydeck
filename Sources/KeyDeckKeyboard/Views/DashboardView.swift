import KeyDeckKit
import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 8) {
            topBar

            if !viewModel.hasFullAccess {
                fullAccessBanner
            } else if viewModel.isRecording {
                liveRecordingSurface
            } else {
                primaryActionRow
            }

            contextualStrip

            Spacer(minLength: 0)

            bottomKeyRow
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Top Command & Mic Control Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.openPalette()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Commands, snippets, math…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
            }
            .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 10))

            Button(action: viewModel.togglePrivacyContext) {
                Image(systemName: viewModel.settings.sendSurroundingContext ? "eye" : "eye.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(viewModel.settings.sendSurroundingContext ? Color.primary : Color.orange)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 10))
            .accessibilityLabel("Toggle surrounding text context")

            micControlButton
        }
    }

    private var micControlButton: some View {
        Button {
            if viewModel.isSessionLive {
                viewModel.killMic()
            } else {
                viewModel.openCompanionToArm()
            }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isSessionLive {
                    Image(systemName: "mic.slash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("Kill Mic")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "mic")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Mic Off")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 10))
        .accessibilityLabel(viewModel.isSessionLive ? "Kill background microphone" : "Arm microphone")
    }

    // MARK: - Primary Tactile Voice Keycaps

    private var primaryActionRow: some View {
        HStack(spacing: 8) {
            voiceKeycap(
                mode: .rambler,
                title: "Rambler",
                status: ramblerStatusText,
                accentBadge: true
            )
            voiceKeycap(
                mode: .voiceEdit,
                title: "Voice Edit",
                status: voiceEditStatusText,
                accentBadge: false
            )
        }
    }

    private func voiceKeycap(
        mode: VoiceMode,
        title: String,
        status: String,
        accentBadge: Bool
    ) -> some View {
        let isBusy = viewModel.isProcessing && viewModel.voiceState.activeMode == mode
        return Button {
            viewModel.triggerVoice(mode: mode)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Image(systemName: mode.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accentBadge ? Color.white : Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(
                            accentBadge
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(Color.accentColor.opacity(0.14)),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    Spacer()

                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.isSessionLive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    } else {
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .buttonStyle(KeycapButtonStyle(variant: .primary, cornerRadius: 12))
        .disabled(viewModel.isProcessing)
    }

    private var ramblerStatusText: String {
        if viewModel.isProcessing && viewModel.voiceState.activeMode == .rambler {
            return "Processing…"
        }
        return viewModel.isSessionLive ? "Ready" : "Tap to arm & speak"
    }

    private var voiceEditStatusText: String {
        if viewModel.isProcessing && viewModel.voiceState.activeMode == .voiceEdit {
            return "Rewriting…"
        }
        return viewModel.hasSelectedText ? "Selection ready" : "Transform field text"
    }

    // MARK: - Live Recording Surface

    private var liveRecordingSurface: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LiveWaveformView(level: viewModel.voiceState.audioLevel)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.voiceState.activeMode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let started = viewModel.voiceState.recordingStartedAt {
                        Text(started, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: viewModel.cancelRecording) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 10))
                .accessibilityLabel("Cancel recording")

                Button(action: viewModel.stopRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Insert")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                }
                .buttonStyle(KeycapButtonStyle(variant: .destructive, cornerRadius: 10))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Contextual Strip (Tweak Bar, Status, or Pinned Snippets + Clips)

    @ViewBuilder
    private var contextualStrip: some View {
        if viewModel.lastInsertion != nil {
            TweakBarView(viewModel: viewModel)
        } else if let status = viewModel.statusMessage {
            HStack(spacing: 6) {
                if viewModel.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 36)
        } else {
            pinnedQuickStrip
        }
    }

    private var pinnedQuickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    viewModel.openPalette(filter: .clipboard)
                } label: {
                    Label("Clips", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))

                Button {
                    viewModel.captureCurrentClipboard(pin: false)
                } label: {
                    Label("Save Clip", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))

                ForEach(viewModel.pinnedDashboardWorkflows) { workflow in
                    Button {
                        viewModel.tapPinnedWorkflow(workflow)
                    } label: {
                        Label(workflow.name, systemImage: workflow.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                    }
                    .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Full Access Banner

    private var fullAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.open")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Full Access Required")
                    .font(.subheadline.weight(.semibold))
                Text("Settings → General → Keyboard → Keyboards → KeyDeck")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bottom Native Keycap Row

    private var bottomKeyRow: some View {
        HStack(spacing: 6) {
            if viewModel.needsGlobeKey {
                Button(action: viewModel.tapGlobe) {
                    Image(systemName: "globe")
                        .font(.body)
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
            }

            Button(action: viewModel.tapSpace) {
                Text("space")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(KeycapButtonStyle(variant: .primary, cornerRadius: 9))

            Button(action: viewModel.tapBackspace) {
                Image(systemName: "delete.left")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 42)
            }
            .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))

            Button(action: viewModel.tapReturn) {
                Image(systemName: "return")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 62, height: 42)
            }
            .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
        }
    }
}
