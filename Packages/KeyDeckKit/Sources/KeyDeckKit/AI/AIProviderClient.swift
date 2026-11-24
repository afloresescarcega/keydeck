import Foundation

public enum AIError: LocalizedError, Sendable {
    case missingAPIKey(AIProvider)
    case invalidResponse(String)
    case httpError(statusCode: Int, message: String)
    case emptyOutput
    case missingAudioFile
    case aiDataSharingNotAllowed

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Missing \(provider.displayName) API key. Add it in KeyDeck Settings."
        case .invalidResponse(let detail):
            "Unexpected AI response: \(detail)"
        case .httpError(let statusCode, let message):
            "API error (\(statusCode)): \(message)"
        case .emptyOutput:
            "The model returned empty text."
        case .missingAudioFile:
            "Recorded audio file could not be read."
        case .aiDataSharingNotAllowed:
            "Allow AI data sharing in the KeyDeck app (Settings → AI Data Sharing) to use voice and AI features."
        }
    }
}

public struct VoiceAIOutput: Codable, Equatable, Sendable {
    public var outputText: String
    public var rawTranscript: String
    public var providerUsed: AIProvider
    public var modelUsed: String

    public init(
        outputText: String,
        rawTranscript: String,
        providerUsed: AIProvider,
        modelUsed: String
    ) {
        self.outputText = outputText
        self.rawTranscript = rawTranscript
        self.providerUsed = providerUsed
        self.modelUsed = modelUsed
    }
}

public enum PromptBuilder {
    public static func systemPrompt(
        mode: VoiceMode,
        settings: KeyDeckSettings,
        context: TextContextSnapshot
    ) -> String {
        var sections: [String] = []

        switch mode {
        case .rambler:
            sections.append("""
            You are KeyDeck Rambler, an expert voice-to-text editor embedded in an iOS keyboard.
            The user is speaking naturally—sometimes rambling, pausing, thinking aloud, or correcting themselves mid-thought.

            Your job:
            1. Produce `raw_transcript`: a clean, faithful transcription of what was spoken.
            2. Produce `output_text`: a polished, well-structured version ready to paste directly into the user's active text field.
               - Remove filler words ("um", "uh", "like", "you know"), false starts, and verbal detours.
               - Honor self-corrections (e.g., "let's meet at 3—actually make it 4" -> "Let's meet at 4.").
               - Keep short, casual thoughts concise and natural (do NOT over-format a 1-sentence message).
               - Organize longer rambles into clean paragraphs or bullet lists when genuinely helpful.
               - Preserve the user's authentic voice and intent without inventing new facts.
               - Return ONLY the text to insert in `output_text`—no preamble, quotes, or meta-commentary.
            """)

        case .voiceEdit:
            sections.append("""
            You are KeyDeck Voice Edit, an expert inline text transformer embedded in an iOS keyboard.
            The user is speaking a voice instruction to edit or transform existing text from their input field.

            Your job:
            1. Produce `raw_transcript`: what the user actually said as their instruction.
            2. Produce `output_text`: ONLY the transformed replacement text that satisfies the user's voice instruction.
               - Apply the instruction cleanly to the provided target text (e.g., shorten, change tone, fix grammar, translate, convert to bullets, draft a reply).
               - Return ONLY the resulting text to insert—no explanations, markdown wrappers, or preamble.
            """)
        }

        if !settings.customDictionary.isEmpty {
            let terms = settings.customDictionary
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !terms.isEmpty {
                sections.append("Custom vocabulary (spell these exact terms/names accurately): \(terms)")
            }
        }

        let personal = settings.personalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !personal.isEmpty {
            sections.append("User's global style instructions:\n\(personal)")
        }

        if settings.sendSurroundingContext && !context.isEmpty {
            var contextLines: [String] = []
            if context.hasSelection {
                contextLines.append("Selected text:\n\"\"\"\n\(context.selectedText)\n\"\"\"")
            }
            if !context.beforeCursor.isEmpty {
                let tail = String(context.beforeCursor.suffix(600))
                contextLines.append("Text immediately before cursor:\n\"\"\"\n\(tail)\n\"\"\"")
            }
            if !context.afterCursor.isEmpty {
                let head = String(context.afterCursor.prefix(200))
                contextLines.append("Text immediately after cursor:\n\"\"\"\n\(head)\n\"\"\"")
            }
            if !contextLines.isEmpty {
                sections.append("Active text field context:\n" + contextLines.joined(separator: "\n\n"))
            }
        } else if mode == .voiceEdit && !context.effectiveTargetText.isEmpty {
            sections.append("Target text to edit:\n\"\"\"\n\(context.effectiveTargetText)\n\"\"\"")
        }

        return sections.joined(separator: "\n\n")
    }

    public static func tweakPrompts(
        action: TweakAction,
        rawTranscript: String,
        currentOutput: String,
        settings: KeyDeckSettings
    ) -> (system: String, user: String) {
        let instruction: String = switch action {
        case .shorter:
            "Make the text noticeably more concise and punchy while keeping all key meaning."
        case .bullets:
            "Restructure the text into a clean, scannable bulleted list using '- '."
        case .casual:
            "Rewrite in a natural, relaxed, friendly conversational tone suitable for messaging."
        case .professional:
            "Rewrite in a clear, polished, professional tone suitable for work email or Slack."
        case .raw:
            "Return the raw transcript cleanly punctuated."
        }

        var system = """
        You are KeyDeck Quick Tweak. Transform the text according to the instruction.
        Return ONLY the rewritten text—no quotes, labels, or commentary.
        """
        let personal = settings.personalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !personal.isEmpty {
            system += "\nUser style rules:\n\(personal)"
        }

        let user = """
        Instruction: \(instruction)

        Original spoken transcript:
        \"\"\"
        \(rawTranscript)
        \"\"\"

        Current text:
        \"\"\"
        \(currentOutput)
        \"\"\"
        """
        return (system, user)
    }
}

public struct VoiceProcessingService: Sendable {
    private let keychain: SharedKeychain
    private let geminiClient: GeminiClient
    private let openAIClient: OpenAIClient

    public init(
        keychain: SharedKeychain = SharedKeychain(),
        geminiClient: GeminiClient = GeminiClient(),
        openAIClient: OpenAIClient = OpenAIClient()
    ) {
        self.keychain = keychain
        self.geminiClient = geminiClient
        self.openAIClient = openAIClient
    }

    public func processAudio(
        audioURL: URL,
        mimeType: String = "audio/mp4",
        mode: VoiceMode,
        context: TextContextSnapshot,
        settings: KeyDeckSettings
    ) async throws -> VoiceAIOutput {
        guard settings.aiDataSharingConsent else {
            throw AIError.aiDataSharingNotAllowed
        }
        guard let audioData = try? Data(contentsOf: audioURL), !audioData.isEmpty else {
            throw AIError.missingAudioFile
        }

        let systemPrompt = PromptBuilder.systemPrompt(mode: mode, settings: settings, context: context)

        switch settings.voicePipeline {
        case .geminiSinglePass:
            if let geminiKey = keychain.read(.gemini), !geminiKey.isEmpty {
                return try await geminiClient.processAudioSinglePass(
                    audioData: audioData,
                    mimeType: mimeType,
                    model: settings.geminiVoiceModel,
                    systemPrompt: systemPrompt,
                    apiKey: geminiKey
                )
            }
            // Graceful fallback to OpenAI if only OpenAI key is configured
            if let openAIKey = keychain.read(.openAI), !openAIKey.isEmpty {
                return try await runOpenAITwoPass(
                    audioData: audioData,
                    filename: audioURL.lastPathComponent,
                    mimeType: mimeType,
                    systemPrompt: systemPrompt,
                    settings: settings,
                    openAIKey: openAIKey
                )
            }
            throw AIError.missingAPIKey(.gemini)

        case .openAITwoPass:
            guard let openAIKey = keychain.read(.openAI), !openAIKey.isEmpty else {
                throw AIError.missingAPIKey(.openai)
            }
            return try await runOpenAITwoPass(
                audioData: audioData,
                filename: audioURL.lastPathComponent,
                mimeType: mimeType,
                systemPrompt: systemPrompt,
                settings: settings,
                openAIKey: openAIKey
            )
        }
    }

    public func tweakText(
        action: TweakAction,
        rawTranscript: String,
        currentOutput: String,
        settings: KeyDeckSettings
    ) async throws -> (text: String, provider: AIProvider, model: String) {
        if action == .raw {
            return (rawTranscript, settings.tweakProvider, "raw-transcript")
        }
        guard settings.aiDataSharingConsent else {
            throw AIError.aiDataSharingNotAllowed
        }

        let prompts = PromptBuilder.tweakPrompts(
            action: action,
            rawTranscript: rawTranscript,
            currentOutput: currentOutput,
            settings: settings
        )

        // Try preferred provider first, fall back to whichever key exists
        let order: [AIProvider] = settings.tweakProvider == .gemini ? [.gemini, .openai] : [.openai, .gemini]
        for provider in order {
            switch provider {
            case .gemini:
                if let key = keychain.read(.gemini), !key.isEmpty {
                    let result = try await geminiClient.generateText(
                        systemPrompt: prompts.system,
                        userPrompt: prompts.user,
                        model: settings.geminiTextModel,
                        apiKey: key
                    )
                    return (result, .gemini, settings.geminiTextModel)
                }
            case .openai:
                if let key = keychain.read(.openAI), !key.isEmpty {
                    let result = try await openAIClient.generateText(
                        systemPrompt: prompts.system,
                        userPrompt: prompts.user,
                        model: settings.openAITextModel,
                        apiKey: key
                    )
                    return (result, .openai, settings.openAITextModel)
                }
            }
        }

        throw AIError.missingAPIKey(settings.tweakProvider)
    }

    private func runOpenAITwoPass(
        audioData: Data,
        filename: String,
        mimeType: String,
        systemPrompt: String,
        settings: KeyDeckSettings,
        openAIKey: String
    ) async throws -> VoiceAIOutput {
        let dictionaryPrompt = settings.customDictionary.joined(separator: ", ")
        let rawTranscript = try await openAIClient.transcribeAudio(
            audioData: audioData,
            filename: filename,
            mimeType: mimeType,
            model: settings.openAISTTModel,
            promptHint: dictionaryPrompt.isEmpty ? nil : dictionaryPrompt,
            apiKey: openAIKey
        )

        let userMessage = """
        Spoken transcript:
        \"\"\"
        \(rawTranscript)
        \"\"\"

        Return ONLY the final `output_text` ready to insert.
        """

        let cleaned = try await openAIClient.generateText(
            systemPrompt: systemPrompt,
            userPrompt: userMessage,
            model: settings.openAITextModel,
            apiKey: openAIKey
        )

        return VoiceAIOutput(
            outputText: cleaned,
            rawTranscript: rawTranscript,
            providerUsed: .openai,
            modelUsed: "\(settings.openAISTTModel) + \(settings.openAITextModel)"
        )
    }
}
