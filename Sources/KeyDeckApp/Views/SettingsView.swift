import SwiftUI
import KeyDeckKit

struct SettingsView: View {
    @Bindable var sessionManager: VoiceSessionManager

    @State private var geminiKeyInput: String = ""
    @State private var openAIKeyInput: String = ""
    @State private var newDictionaryTerm: String = ""
    @State private var keySaveBanner: String?

    private let timeoutOptions: [(label: String, minutes: Int)] = [
        ("2 minutes", 2),
        ("5 minutes", 5),
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("Manual only", 0)
    ]

    var body: some View {
        NavigationStack {
            Form {
                apiKeysSection
                microphoneControlSection
                voiceRoutingSection
                personalizationSection
                appearanceSection
            }
            .navigationTitle("Settings")
            .onAppear {
                geminiKeyInput = sessionManager.readAPIKey(.gemini)
                openAIKeyInput = sessionManager.readAPIKey(.openAI)
            }
        }
    }

    private var apiKeysSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Gemini API Key")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if sessionManager.hasAPIKey(.gemini) {
                        Text("Saved")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                SecureField("AIza...", text: $geminiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("OpenAI API Key")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if sessionManager.hasAPIKey(.openAI) {
                        Text("Saved")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                SecureField("sk-...", text: $openAIKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Button("Save Keys to Shared Keychain") {
                do {
                    try sessionManager.saveAPIKey(geminiKeyInput, for: .gemini)
                    try sessionManager.saveAPIKey(openAIKeyInput, for: .openAI)
                    keySaveBanner = "Saved securely in Keychain."
                } catch {
                    keySaveBanner = error.localizedDescription
                }
            }

            if let keySaveBanner {
                Text(keySaveBanner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("API Keys")
        } footer: {
            Text("Stored in your iOS Shared Keychain. Calls go directly from your iPhone to Gemini or OpenAI with no backend.")
        }
    }

    private var microphoneControlSection: some View {
        Section {
            Toggle("Auto-Kill Mic After Each Dictation", isOn: $sessionManager.settings.autoDisarmAfterInsert)

            if !sessionManager.settings.autoDisarmAfterInsert {
                Picker("Auto-Kill When Idle", selection: $sessionManager.settings.keepSessionAliveMinutes) {
                    ForEach(timeoutOptions, id: \.minutes) { option in
                        Text(option.label).tag(option.minutes)
                    }
                }
                .tint(.secondary)
            }

            Toggle("Send Surrounding Field Context", isOn: $sessionManager.settings.sendSurroundingContext)
        } header: {
            Text("Microphone & Privacy")
        } footer: {
            Text(
                sessionManager.settings.autoDisarmAfterInsert
                    ? "The microphone shuts off automatically as soon as your text is inserted. The next dictation will briefly open KeyDeck to re-arm."
                    : "Tap the green Mic On pill in the keyboard anytime to kill the mic immediately without leaving your app."
            )
        }
    }

    private var voiceRoutingSection: some View {
        Section {
            Picker("Voice Pipeline", selection: $sessionManager.settings.voicePipeline) {
                ForEach(VoicePipelineMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .tint(.secondary)

            Text(sessionManager.settings.voicePipeline.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("Gemini Model") {
                TextField("gemini-2.5-flash", text: $sessionManager.settings.geminiVoiceModel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            LabeledContent("OpenAI STT") {
                TextField("gpt-4o-mini-transcribe", text: $sessionManager.settings.openAISTTModel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            LabeledContent("OpenAI Text") {
                TextField("gpt-4o-mini", text: $sessionManager.settings.openAITextModel)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Picker("Quick Tweak Provider", selection: $sessionManager.settings.tweakProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .tint(.secondary)
        } header: {
            Text("AI Routing")
        }
    }

    private var personalizationSection: some View {
        Section {
            HStack {
                TextField("Add name, acronym, or jargon", text: $newDictionaryTerm)
                    .textInputAutocapitalization(.never)
                Button("Add") {
                    let trimmed = newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if !sessionManager.settings.customDictionary.contains(trimmed) {
                        sessionManager.settings.customDictionary.append(trimmed)
                    }
                    newDictionaryTerm = ""
                }
                .disabled(newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ForEach(sessionManager.settings.customDictionary, id: \.self) { term in
                Text(term)
            }
            .onDelete { offsets in
                sessionManager.settings.customDictionary.remove(atOffsets: offsets)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal Style Instructions")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $sessionManager.settings.personalInstructions)
                    .frame(minHeight: 72)
            }
        } header: {
            Text("Dictionary & Style")
        } footer: {
            Text("Injected into Rambler, Voice Edit, and Quick Tweak prompts.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance & Feel") {
            Picker("Accent", selection: $sessionManager.settings.accentColor) {
                ForEach(KeyDeckAccentColor.allCases) { accent in
                    Text(accent.displayName).tag(accent)
                }
            }
            .tint(.secondary)
            Toggle("Haptic Feedback", isOn: $sessionManager.settings.enableHaptics)
        }
    }
}
