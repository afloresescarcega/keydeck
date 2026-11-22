import Foundation

public enum VoiceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case rambler
    case voiceEdit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rambler: "Rambler"
        case .voiceEdit: "Voice Edit"
        }
    }

    public var subtitle: String {
        switch self {
        case .rambler: "Talk freely — AI organizes your thoughts"
        case .voiceEdit: "Speak an instruction to transform text"
        }
    }

    public var systemImage: String {
        switch self {
        case .rambler: "waveform.and.mic"
        case .voiceEdit: "wand.and.stars"
        }
    }
}

public enum VoicePhase: String, Codable, Sendable {
    case idle
    case armed
    case recording
    case processing
    case ready
    case failed
}

public struct TextContextSnapshot: Codable, Equatable, Sendable {
    public var beforeCursor: String
    public var afterCursor: String
    public var selectedText: String

    public init(
        beforeCursor: String = "",
        afterCursor: String = "",
        selectedText: String = ""
    ) {
        self.beforeCursor = beforeCursor
        self.afterCursor = afterCursor
        self.selectedText = selectedText
    }

    public var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var effectiveTargetText: String {
        if hasSelection {
            return selectedText
        }
        return beforeCursor
    }

    public var isEmpty: Bool {
        beforeCursor.isEmpty && afterCursor.isEmpty && selectedText.isEmpty
    }
}

public enum VoiceIPCCommandKind: String, Codable, Sendable {
    case startRecording
    case stopRecording
    case cancelRecording
    case disarmSession
    case tweakResult
}

public struct VoiceIPCCommand: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: VoiceIPCCommandKind
    public var mode: VoiceMode
    public var context: TextContextSnapshot
    public var tweakAction: TweakAction?
    public var sourceTranscript: String?
    public var previousOutput: String?
    public var createdAt: Date

    public init( // NOSONAR: memberwise init of a plain data model
        id: UUID = UUID(),
        kind: VoiceIPCCommandKind,
        mode: VoiceMode = .rambler,
        context: TextContextSnapshot = TextContextSnapshot(),
        tweakAction: TweakAction? = nil,
        sourceTranscript: String? = nil,
        previousOutput: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.mode = mode
        self.context = context
        self.tweakAction = tweakAction
        self.sourceTranscript = sourceTranscript
        self.previousOutput = previousOutput
        self.createdAt = createdAt
    }
}

public struct VoiceIPCState: Codable, Equatable, Sendable {
    public var phase: VoicePhase
    public var activeMode: VoiceMode
    public var activeRequestID: UUID?
    public var sessionArmed: Bool
    public var audioLevel: Float
    public var recordingStartedAt: Date?
    public var heartbeatAt: Date
    public var errorMessage: String?

    public init( // NOSONAR: memberwise init of a plain data model
        phase: VoicePhase = .idle,
        activeMode: VoiceMode = .rambler,
        activeRequestID: UUID? = nil,
        sessionArmed: Bool = false,
        audioLevel: Float = 0,
        recordingStartedAt: Date? = nil,
        heartbeatAt: Date = .distantPast,
        errorMessage: String? = nil
    ) {
        self.phase = phase
        self.activeMode = activeMode
        self.activeRequestID = activeRequestID
        self.sessionArmed = sessionArmed
        self.audioLevel = audioLevel
        self.recordingStartedAt = recordingStartedAt
        self.heartbeatAt = heartbeatAt
        self.errorMessage = errorMessage
    }

    /// True if the companion app has recently heartbeated an active background session.
    public func isSessionLive(now: Date = Date(), maxStalenessSeconds: TimeInterval = 12) -> Bool {
        sessionArmed && now.timeIntervalSince(heartbeatAt) <= maxStalenessSeconds
    }
}

public enum TweakAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case shorter
    case bullets
    case casual
    case professional
    case raw

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shorter: "Shorter"
        case .bullets: "Bullets"
        case .casual: "Casual"
        case .professional: "Work"
        case .raw: "Raw"
        }
    }

    public var systemImage: String {
        switch self {
        case .shorter: "arrow.down.right.and.arrow.up.left"
        case .bullets: "list.bullet"
        case .casual: "message"
        case .professional: "briefcase"
        case .raw: "text.quote"
        }
    }
}

public struct VoiceResult: Codable, Equatable, Sendable {
    public var id: UUID
    public var requestID: UUID
    public var mode: VoiceMode
    public var outputText: String
    public var rawTranscript: String
    public var replacesSelection: Bool
    public var replaceBeforeCursorLength: Int
    public var providerUsed: AIProvider
    public var modelUsed: String
    public var createdAt: Date
    public var consumed: Bool

    public init( // NOSONAR: memberwise init of a plain data model
        id: UUID = UUID(),
        requestID: UUID,
        mode: VoiceMode,
        outputText: String,
        rawTranscript: String,
        replacesSelection: Bool = false,
        replaceBeforeCursorLength: Int = 0,
        providerUsed: AIProvider,
        modelUsed: String,
        createdAt: Date = Date(),
        consumed: Bool = false
    ) {
        self.id = id
        self.requestID = requestID
        self.mode = mode
        self.outputText = outputText
        self.rawTranscript = rawTranscript
        self.replacesSelection = replacesSelection
        self.replaceBeforeCursorLength = replaceBeforeCursorLength
        self.providerUsed = providerUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
        self.consumed = consumed
    }
}

public enum TranscriptEntryStatus: String, Codable, Sendable {
    case completed
    case failed
    case processing
}

public struct TranscriptEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var mode: VoiceMode
    public var status: TranscriptEntryStatus
    public var audioFilename: String?
    public var durationSeconds: TimeInterval
    public var outputText: String?
    public var rawTranscript: String?
    public var contextSnapshot: TextContextSnapshot?
    public var providerUsed: AIProvider?
    public var modelUsed: String?
    public var errorMessage: String?

    public init( // NOSONAR: memberwise init of a plain data model
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: VoiceMode,
        status: TranscriptEntryStatus,
        audioFilename: String? = nil,
        durationSeconds: TimeInterval = 0,
        outputText: String? = nil,
        rawTranscript: String? = nil,
        contextSnapshot: TextContextSnapshot? = nil,
        providerUsed: AIProvider? = nil,
        modelUsed: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.status = status
        self.audioFilename = audioFilename
        self.durationSeconds = durationSeconds
        self.outputText = outputText
        self.rawTranscript = rawTranscript
        self.contextSnapshot = contextSnapshot
        self.providerUsed = providerUsed
        self.modelUsed = modelUsed
        self.errorMessage = errorMessage
    }
}
