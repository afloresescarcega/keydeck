import Foundation

public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    public let containerURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "keydeck.sharedstore", qos: .userInitiated)

    public init(containerURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let containerURL {
            self.containerURL = containerURL
        } else if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: KeyDeckConstants.appGroupID) {
            self.containerURL = groupURL
        } else {
            let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.containerURL = fallback.appendingPathComponent("KeyDeckShared", isDirectory: true)
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: self.containerURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: self.recordingsDirectoryURL, withIntermediateDirectories: true)
    }

    public var recordingsDirectoryURL: URL {
        containerURL.appendingPathComponent(KeyDeckConstants.FileNames.recordingsDir, isDirectory: true)
    }

    public func recordingURL(for filename: String) -> URL {
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        return recordingsDirectoryURL.appendingPathComponent(safeName)
    }

    // MARK: - Settings

    public func loadSettings() -> KeyDeckSettings {
        read(KeyDeckSettings.self, filename: KeyDeckConstants.FileNames.settings) ?? .standard
    }

    public func saveSettings(_ settings: KeyDeckSettings) {
        write(settings, filename: KeyDeckConstants.FileNames.settings)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.settingsChanged)
    }

    // MARK: - Voice IPC State

    public func loadVoiceState() -> VoiceIPCState {
        read(VoiceIPCState.self, filename: KeyDeckConstants.FileNames.ipcState) ?? VoiceIPCState()
    }

    public func saveVoiceState(_ state: VoiceIPCState, notify: Bool = true) {
        write(state, filename: KeyDeckConstants.FileNames.ipcState)
        if notify {
            DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.stateChanged)
        }
    }

    // MARK: - Pending Command

    public func loadPendingCommand() -> VoiceIPCCommand? {
        read(VoiceIPCCommand.self, filename: KeyDeckConstants.FileNames.pendingCommand)
    }

    public func savePendingCommand(_ command: VoiceIPCCommand, notify: Bool = true) {
        write(command, filename: KeyDeckConstants.FileNames.pendingCommand)
        if notify {
            DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.commandPosted)
        }
    }

    public func clearPendingCommand() {
        remove(filename: KeyDeckConstants.FileNames.pendingCommand)
    }

    // MARK: - Latest Voice Result

    public func loadLatestResult() -> VoiceResult? {
        read(VoiceResult.self, filename: KeyDeckConstants.FileNames.latestResult)
    }

    public func saveLatestResult(_ result: VoiceResult, notify: Bool = true) {
        write(result, filename: KeyDeckConstants.FileNames.latestResult)
        if notify {
            DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.resultReady)
        }
    }

    public func markLatestResultConsumed(id: UUID) {
        guard var latest = loadLatestResult(), latest.id == id else { return }
        latest.consumed = true
        write(latest, filename: KeyDeckConstants.FileNames.latestResult)
    }

    // MARK: - Transcript & Audio Fallback Log

    public func loadTranscriptLog() -> [TranscriptEntry] {
        read([TranscriptEntry].self, filename: KeyDeckConstants.FileNames.transcriptLog) ?? []
    }

    public func upsertTranscriptEntry(_ entry: TranscriptEntry, maxEntries: Int = 100) {
        var entries = loadTranscriptLog()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        if entries.count > maxEntries {
            let overflow = entries.suffix(from: maxEntries)
            for old in overflow {
                if let audioFilename = old.audioFilename {
                    try? fileManager.removeItem(at: recordingURL(for: audioFilename))
                }
            }
            entries = Array(entries.prefix(maxEntries))
        }
        write(entries, filename: KeyDeckConstants.FileNames.transcriptLog)
    }

    public func deleteTranscriptEntry(id: UUID) {
        var entries = loadTranscriptLog()
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            if let audioFilename = entries[idx].audioFilename {
                try? fileManager.removeItem(at: recordingURL(for: audioFilename))
            }
            entries.remove(at: idx)
            write(entries, filename: KeyDeckConstants.FileNames.transcriptLog)
        }
    }

    // MARK: - Workflows (Phase 2/3 Foundation)

    public func loadWorkflows() -> [KeyDeckWorkflow] {
        if let existing = read([KeyDeckWorkflow].self, filename: KeyDeckConstants.FileNames.workflows) {
            return existing
        }
        let starter = KeyDeckWorkflow.starterPack
        write(starter, filename: KeyDeckConstants.FileNames.workflows)
        return starter
    }

    public func saveWorkflows(_ workflows: [KeyDeckWorkflow]) {
        write(workflows, filename: KeyDeckConstants.FileNames.workflows)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.workflowsChanged)
    }

    // MARK: - Clipboard History & Pinned Clips

    public func loadClipboardItems() -> [ClipboardItem] {
        let items = read([ClipboardItem].self, filename: KeyDeckConstants.FileNames.clipboardHistory) ?? []
        return items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    @discardableResult
    public func saveClipboardText(
        _ rawText: String,
        label: String? = nil,
        pinned: Bool = false,
        maxUnpinned: Int = 30
    ) -> [ClipboardItem] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return loadClipboardItems() }
        let cleanLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = (cleanLabel?.isEmpty == false) ? cleanLabel : nil

        var items = loadClipboardItems()
        if let existingIndex = items.firstIndex(where: { $0.text == rawText }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = Date()
            if pinned { existing.isPinned = true }
            if let resolvedLabel { existing.label = resolvedLabel }
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipboardItem(text: rawText, label: resolvedLabel, isPinned: pinned, createdAt: Date()), at: 0)
        }

        let pinnedItems = items.filter(\.isPinned)
        let unpinnedItems = Array(items.filter { !$0.isPinned }.prefix(maxUnpinned))
        let merged = pinnedItems + unpinnedItems
        write(merged, filename: KeyDeckConstants.FileNames.clipboardHistory)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.clipboardChanged)
        return merged
    }

    public func toggleClipboardPin(id: UUID) -> [ClipboardItem] {
        var items = loadClipboardItems()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isPinned.toggle()
        }
        let sorted = items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
        write(sorted, filename: KeyDeckConstants.FileNames.clipboardHistory)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.clipboardChanged)
        return sorted
    }

    public func deleteClipboardItem(id: UUID) -> [ClipboardItem] {
        var items = loadClipboardItems()
        items.removeAll { $0.id == id }
        write(items, filename: KeyDeckConstants.FileNames.clipboardHistory)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.clipboardChanged)
        return items
    }

    public func clearUnpinnedClipboardItems() -> [ClipboardItem] {
        let pinned = loadClipboardItems().filter(\.isPinned)
        write(pinned, filename: KeyDeckConstants.FileNames.clipboardHistory)
        DarwinNotifier.post(KeyDeckConstants.DarwinNotifications.clipboardChanged)
        return pinned
    }

    // MARK: - Atomic JSON Helpers

    private func fileURL(for filename: String) -> URL {
        containerURL.appendingPathComponent(filename)
    }

    private func read<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        queue.sync {
            let url = fileURL(for: filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    private func write<T: Encodable>(_ value: T, filename: String) {
        queue.sync {
            let url = fileURL(for: filename)
            guard let data = try? encoder.encode(value) else { return }
            #if os(iOS)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try? data.write(to: url, options: [.atomic])
            #endif
        }
    }

    private func remove(filename: String) {
        queue.sync {
            try? fileManager.removeItem(at: fileURL(for: filename))
        }
    }
}
