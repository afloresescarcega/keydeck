import Foundation

public enum KeyDeckConstants {
    public static let appName = "KeyDeck"
    public static let urlScheme = "keydeck"

    /// Resolved dynamically from `Info.plist` (`KeyDeckAppGroupID`, populated via `Config/Local.xcconfig`)
    /// so forks and contributors never have to edit Swift source code to change bundle identifiers.
    public static var appGroupID: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "KeyDeckAppGroupID") as? String,
           !value.isEmpty,
           !value.contains("$(") {
            return value
        }
        return "group.com.example.keydeck"
    }

    public static var keychainAccessGroupSuffix: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "KeyDeckKeychainSuffix") as? String,
           !value.isEmpty,
           !value.contains("$(") {
            return value
        }
        return "com.example.keydeck"
    }

    public static var keychainService: String {
        "\(keychainAccessGroupSuffix).secrets"
    }

    public enum DarwinNotifications {
        public static var commandPosted: String { "\(keychainAccessGroupSuffix).commandPosted" }
        public static var stateChanged: String { "\(keychainAccessGroupSuffix).stateChanged" }
        public static var resultReady: String { "\(keychainAccessGroupSuffix).resultReady" }
        public static var settingsChanged: String { "\(keychainAccessGroupSuffix).settingsChanged" }
        public static var workflowsChanged: String { "\(keychainAccessGroupSuffix).workflowsChanged" }
        public static var clipboardChanged: String { "\(keychainAccessGroupSuffix).clipboardChanged" }
    }

    public enum DeepLinks {
        public static func startVoice(mode: VoiceMode, requestID: UUID) -> URL {
            var components = URLComponents()
            components.scheme = urlScheme
            components.host = "voice"
            components.path = "/start" // NOSONAR: fixed deep-link route
            components.queryItems = [
                URLQueryItem(name: "mode", value: mode.rawValue),
                URLQueryItem(name: "requestId", value: requestID.uuidString)
            ]
            return components.url!
        }

        public static func armSession() -> URL {
            URL(string: "\(urlScheme)://voice/arm")!
        }

        public static func disarmSession() -> URL {
            URL(string: "\(urlScheme)://voice/disarm")!
        }

        public static func openSettings() -> URL {
            URL(string: "\(urlScheme)://settings")!
        }
    }

    public enum Links {
        // swiftlint:disable force_unwrapping
        public static let privacyPolicy = URL(string: "https://afloresescarcega.github.io/keydeck/privacy.html")!
        public static let support = URL(string: "https://github.com/afloresescarcega/keydeck/issues")!
        public static let geminiAPITerms = URL(string: "https://ai.google.dev/gemini-api/terms")!
        public static let openAIPrivacy = URL(string: "https://openai.com/policies/privacy-policy")!
        // swiftlint:enable force_unwrapping
    }

    public enum FileNames {
        public static let settings = "settings.json"
        public static let ipcState = "voice_ipc_state.json"
        public static let pendingCommand = "voice_pending_command.json"
        public static let latestResult = "voice_latest_result.json"
        public static let transcriptLog = "transcript_log.json"
        public static let workflows = "workflows.json"
        public static let clipboardHistory = "clipboard_history.json"
        public static let recordingsDir = "Recordings"
    }
}
