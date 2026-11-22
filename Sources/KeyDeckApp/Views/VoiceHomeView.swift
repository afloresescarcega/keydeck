import SwiftUI
import KeyDeckKit

struct VoiceHomeView: View {
    @Bindable var sessionManager: VoiceSessionManager
    @Binding var selectedTab: AppTab

    @State private var scratchpadText: String = ""
    @State private var copiedLatest: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if sessionManager.launchedFromKeyboardBanner && sessionManager.isSessionArmed {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mic Ready in Background")
                                    .font(.subheadline.weight(.semibold))
                                Text("Swipe back to your app to dictate in place.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                microphoneSection
                quickCaptureSection

                if let error = sessionManager.lastErrorMessage {
                    Section("Last Error") {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let latest = sessionManager.lastResult {
                    latestOutputSection(latest)
                }

                sandboxSection
                setupSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("KeyDeck")
        }
    }

    // MARK: - Microphone Section

    private var microphoneSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: sessionManager.isSessionArmed ? "mic.fill" : "mic.slash")
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.body.weight(.semibold))
                    Text(statusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 2)

            if sessionManager.phase == .recording {
                HStack(spacing: 12) {
                    Button {
                        Task { await sessionManager.stopRecordingAndProcess() }
                    } label: {
                        Label("Stop & Process", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button(role: .destructive) {
                        Task { await sessionManager.cancelRecording() }
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } else if sessionManager.phase == .processing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Processing with \(sessionManager.settings.voicePipeline.displayName)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if sessionManager.isSessionArmed {
                Button(role: .destructive) {
                    Task { await sessionManager.disarmSession() }
                } label: {
                    Label("Kill Mic", systemImage: "mic.slash.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button {
                    Task { await sessionManager.armSession() }
                } label: {
                    Label("Arm Mic for Keyboard", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            Text("Microphone")
        } footer: {
            Text(microphoneFooter)
        }
    }

    // MARK: - Direct Capture Section

    private var quickCaptureSection: some View {
        Section("Dictate Here") {
            ForEach(VoiceMode.allCases) { mode in
                let isRecordingMode = sessionManager.phase == .recording && sessionManager.activeMode == mode
                Button {
                    Task {
                        if isRecordingMode {
                            await sessionManager.stopRecordingAndProcess()
                        } else {
                            let context = TextContextSnapshot(beforeCursor: scratchpadText)
                            await sessionManager.startRecording(mode: mode, context: context)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isRecordingMode ? "stop.circle.fill" : mode.systemImage)
                            .foregroundStyle(isRecordingMode ? Color.red : Color.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isRecordingMode ? "Stop \(mode.displayName)" : mode.displayName)
                                .foregroundStyle(.primary)
                            Text(mode.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRecordingMode {
                            Text("LIVE")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(sessionManager.phase == .processing)
            }
        }
    }

    // MARK: - Latest Output

    private func latestOutputSection(_ result: VoiceResult) -> some View {
        Section {
            Text(result.outputText)
                .font(.body)
                .textSelection(.enabled)

            if result.rawTranscript != result.outputText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw Transcript")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(result.rawTranscript)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                UIPasteboard.general.string = result.outputText
                copiedLatest = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copiedLatest = false
                }
            } label: {
                Label(copiedLatest ? "Copied" : "Copy Output", systemImage: copiedLatest ? "checkmark" : "doc.on.doc")
            }
        } header: {
            Text("Latest \(result.mode.displayName)")
        }
    }

    // MARK: - Keyboard Sandbox

    private var sandboxSection: some View {
        Section {
            TextEditor(text: $scratchpadText)
                .frame(minHeight: 96)

            if !scratchpadText.isEmpty {
                Button("Clear Scratchpad", role: .destructive) {
                    scratchpadText = ""
                }
            }
        } header: {
            Text("Keyboard Sandbox")
        } footer: {
            Text("Switch to KeyDeck using the globe key to test dictation, Voice Edit, and instant mic kill.")
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        let hasAnyKey = sessionManager.hasAPIKey(.gemini) || sessionManager.hasAPIKey(.openAI)
        return Section("Setup") {
            Button {
                selectedTab = .settings
            } label: {
                HStack {
                    Label(
                        hasAnyKey ? "API Key Configured" : "Add Gemini or OpenAI Key",
                        systemImage: hasAnyKey ? "checkmark.circle.fill" : "key.fill"
                    )
                    .foregroundStyle(hasAnyKey ? Color.green : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label("Keyboard & Full Access Settings", systemImage: "keyboard")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Status Text

    private var statusTitle: String {
        switch sessionManager.phase {
        case .idle: "Mic Off"
        case .armed, .ready: "Mic Armed"
        case .recording: "Recording \(sessionManager.activeMode.displayName)…"
        case .processing: "Processing…"
        case .failed: "Attention Needed"
        }
    }

    private var statusDetail: String {
        if !sessionManager.isSessionArmed {
            return "Hardware microphone is completely off."
        }
        if sessionManager.phase == .recording {
            return "Audio is actively capturing."
        }
        if sessionManager.settings.autoDisarmAfterInsert {
            return "Ready — will auto-kill right after next dictation."
        }
        if sessionManager.settings.keepSessionAliveMinutes > 0 {
            return "Ready in background — auto-kills after \(sessionManager.settings.keepSessionAliveMinutes)m idle."
        }
        return "Ready in background until you tap Kill Mic."
    }

    private var microphoneFooter: String {
        "You can also kill the mic anytime directly from the KeyDeck keyboard top bar without leaving your app."
    }

    private var statusColor: Color {
        switch sessionManager.phase {
        case .idle: .secondary
        case .armed, .ready: .green
        case .recording: .red
        case .processing: .orange
        case .failed: .orange
        }
    }
}
