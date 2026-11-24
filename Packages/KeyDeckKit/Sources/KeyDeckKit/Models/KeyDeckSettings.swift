import Foundation

public enum AIProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case gemini
    case openai

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openai: "OpenAI"
        }
    }
}

public enum VoicePipelineMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case geminiSinglePass
    case openAITwoPass

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .geminiSinglePass: "Gemini Single-Pass Audio"
        case .openAITwoPass: "OpenAI Transcribe + LLM"
        }
    }

    public var subtitle: String {
        switch self {
        case .geminiSinglePass:
            "Sends audio directly to Gemini in one fast call (hears tone, pauses & self-corrections)."
        case .openAITwoPass:
            "Transcribes with OpenAI STT first, then cleans or edits with your chosen LLM."
        }
    }
}

public enum KeyDeckAccentColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case blue
    case graphite
    case teal
    case orange
    case green
    case indigo
    case pink

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct KeyDeckSettings: Codable, Equatable, Sendable {
    public var voicePipeline: VoicePipelineMode
    public var geminiVoiceModel: String
    public var geminiTextModel: String
    public var openAISTTModel: String
    public var openAITextModel: String
    public var tweakProvider: AIProvider
    public var sendSurroundingContext: Bool
    public var customDictionary: [String]
    public var personalInstructions: String
    public var accentColor: KeyDeckAccentColor
    public var enableHaptics: Bool
    /// Minutes of idle before auto-killing the mic. Always bounded (> 0) so the background mic never stays on indefinitely.
    public var keepSessionAliveMinutes: Int
    /// When true, kills the background mic session immediately after each dictation finishes.
    public var autoDisarmAfterInsert: Bool
    /// Explicit, revocable user permission to send audio/text to the selected third-party AI provider
    /// (App Review Guideline 5.1.2(i)). No AI request is made while this is false.
    public var aiDataSharingConsent: Bool

    public init( // NOSONAR: memberwise init of a plain data model
        voicePipeline: VoicePipelineMode = .geminiSinglePass,
        geminiVoiceModel: String = "gemini-2.5-flash",
        geminiTextModel: String = "gemini-2.5-flash",
        openAISTTModel: String = "gpt-4o-mini-transcribe",
        openAITextModel: String = "gpt-4o-mini",
        tweakProvider: AIProvider = .gemini,
        sendSurroundingContext: Bool = false,
        customDictionary: [String] = [],
        personalInstructions: String = "",
        accentColor: KeyDeckAccentColor = .blue,
        enableHaptics: Bool = true,
        keepSessionAliveMinutes: Int = 5,
        autoDisarmAfterInsert: Bool = false,
        aiDataSharingConsent: Bool = false
    ) {
        self.voicePipeline = voicePipeline
        self.geminiVoiceModel = geminiVoiceModel
        self.geminiTextModel = geminiTextModel
        self.openAISTTModel = openAISTTModel
        self.openAITextModel = openAITextModel
        self.tweakProvider = tweakProvider
        self.sendSurroundingContext = sendSurroundingContext
        self.customDictionary = customDictionary
        self.personalInstructions = personalInstructions
        self.accentColor = accentColor
        self.enableHaptics = enableHaptics
        self.keepSessionAliveMinutes = keepSessionAliveMinutes
        self.autoDisarmAfterInsert = autoDisarmAfterInsert
        self.aiDataSharingConsent = aiDataSharingConsent
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyDeckSettings.standard
        self.voicePipeline = try c.decodeIfPresent(VoicePipelineMode.self, forKey: .voicePipeline) ?? d.voicePipeline
        self.geminiVoiceModel = try c.decodeIfPresent(String.self, forKey: .geminiVoiceModel) ?? d.geminiVoiceModel
        self.geminiTextModel = try c.decodeIfPresent(String.self, forKey: .geminiTextModel) ?? d.geminiTextModel
        self.openAISTTModel = try c.decodeIfPresent(String.self, forKey: .openAISTTModel) ?? d.openAISTTModel
        self.openAITextModel = try c.decodeIfPresent(String.self, forKey: .openAITextModel) ?? d.openAITextModel
        self.tweakProvider = try c.decodeIfPresent(AIProvider.self, forKey: .tweakProvider) ?? d.tweakProvider
        self.sendSurroundingContext = try c.decodeIfPresent(Bool.self, forKey: .sendSurroundingContext) ?? d.sendSurroundingContext
        self.customDictionary = try c.decodeIfPresent([String].self, forKey: .customDictionary) ?? d.customDictionary
        self.personalInstructions = try c.decodeIfPresent(String.self, forKey: .personalInstructions) ?? d.personalInstructions
        self.accentColor = try c.decodeIfPresent(KeyDeckAccentColor.self, forKey: .accentColor) ?? d.accentColor
        self.enableHaptics = try c.decodeIfPresent(Bool.self, forKey: .enableHaptics) ?? d.enableHaptics
        let minutes = try c.decodeIfPresent(Int.self, forKey: .keepSessionAliveMinutes) ?? d.keepSessionAliveMinutes
        self.keepSessionAliveMinutes = minutes > 0 ? minutes : d.keepSessionAliveMinutes
        self.autoDisarmAfterInsert = try c.decodeIfPresent(Bool.self, forKey: .autoDisarmAfterInsert) ?? d.autoDisarmAfterInsert
        self.aiDataSharingConsent = try c.decodeIfPresent(Bool.self, forKey: .aiDataSharingConsent) ?? d.aiDataSharingConsent
    }

    public static let standard = KeyDeckSettings()
}
