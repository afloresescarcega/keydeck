import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@available(iOS 16.2, *)
public struct VoiceSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: VoicePhase
        public var mode: VoiceMode
        public var statusText: String
        public var updatedAt: Date

        public init(
            phase: VoicePhase,
            mode: VoiceMode,
            statusText: String,
            updatedAt: Date = Date()
        ) {
            self.phase = phase
            self.mode = mode
            self.statusText = statusText
            self.updatedAt = updatedAt
        }
    }

    public var startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
#endif
