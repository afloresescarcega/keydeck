import ActivityKit
import AVFoundation
import Foundation
import KeyDeckKit
import Observation
import UIKit

@MainActor
@Observable
final class VoiceSessionManager {
    private(set) var phase: VoicePhase = .idle
    private(set) var activeMode: VoiceMode = .rambler
    private(set) var isSessionArmed: Bool = false
    private(set) var audioLevel: Float = 0
    private(set) var recordingStartedAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var lastResult: VoiceResult?
    private(set) var transcriptLog: [TranscriptEntry] = []
    private(set) var permissionDenied: Bool = false
    private(set) var launchedFromKeyboardBanner: Bool = false

    var settings: KeyDeckSettings {
        didSet {
            store.saveSettings(settings)
        }
    }

    private let store: SharedStore
    private let keychain: SharedKeychain
    private let aiService: VoiceProcessingService
    private let notifier = DarwinNotifier()
    private let captureEngine = LiveAudioCaptureEngine()

    private var currentRequestID: UUID?
    private var currentContext: TextContextSnapshot = TextContextSnapshot()

    private var meterTimer: Timer?
    private var heartbeatTimer: Timer?
    private var idleDisarmTask: Task<Void, Never>?
    private var liveActivityID: String?

    init(
        store: SharedStore = .shared,
        keychain: SharedKeychain = SharedKeychain()
    ) {
        self.store = store
        self.keychain = keychain
        self.aiService = VoiceProcessingService(keychain: keychain)
        self.settings = store.loadSettings()
        self.transcriptLog = store.loadTranscriptLog()
        self.lastResult = store.loadLatestResult()

        setupDarwinObservers()
        publishIPCState(notify: false)
    }

    // MARK: - API Key Helpers

    func hasAPIKey(_ slot: APIKeySlot) -> Bool {
        keychain.hasKey(slot)
    }

    func readAPIKey(_ slot: APIKeySlot) -> String {
        keychain.read(slot) ?? ""
    }

    func saveAPIKey(_ value: String, for slot: APIKeySlot) throws {
        try keychain.save(value, for: slot)
    }

    // MARK: - Public Controls

    func armSession() async {
        guard await ensureMicPermission() else { return }
        do {
            try captureEngine.arm()
            isSessionArmed = true
            if phase == .idle || phase == .failed || phase == .ready {
                phase = .armed
            }
            lastErrorMessage = nil
            startHeartbeat()
            scheduleIdleDisarm()
            await startOrUpdateLiveActivity(statusText: "Mic armed — dictate from keyboard")
            publishIPCState()
        } catch {
            fail(with: "Could not start audio session: \(error.localizedDescription)")
        }
    }

    func disarmSession() async {
        stopMetering()
        captureEngine.disarm()
        stopHeartbeat()
        idleDisarmTask?.cancel()
        isSessionArmed = false
        phase = .idle
        audioLevel = 0
        recordingStartedAt = nil
        launchedFromKeyboardBanner = false
        await endLiveActivity()
        publishIPCState()
    }

    func handleExternalStart(mode: VoiceMode, requestID: UUID?) async {
        launchedFromKeyboardBanner = true
        let pending = store.loadPendingCommand()
        let context = (pending?.id == requestID ? pending?.context : nil) ?? TextContextSnapshot()
        let resolvedID = requestID ?? pending?.id ?? UUID()
        store.clearPendingCommand()

        if !isSessionArmed {
            await armSession()
        }
        guard isSessionArmed else { return }
        await startRecording(mode: mode, requestID: resolvedID, context: context)
    }

    func startRecording(
        mode: VoiceMode,
        requestID: UUID = UUID(),
        context: TextContextSnapshot = TextContextSnapshot()
    ) async {
        guard await ensureMicPermission() else { return }

        if !isSessionArmed || !captureEngine.isArmed {
            await armSession()
        }
        guard isSessionArmed else { return }

        let baseURL = store.recordingsDirectoryURL.appendingPathComponent("rec-\(requestID.uuidString)")

        do {
            _ = try captureEngine.beginCapture(baseURLWithoutExtension: baseURL)

            currentRequestID = requestID
            currentContext = context
            activeMode = mode
            recordingStartedAt = Date()
            phase = .recording
            lastErrorMessage = nil
            idleDisarmTask?.cancel()

            startMetering()
            await startOrUpdateLiveActivity(statusText: "Recording \(mode.displayName)…")
            publishIPCState()
        } catch {
            fail(with: "Recording error: \(error.localizedDescription)")
        }
    }

    func stopRecordingAndProcess() async {
        guard phase == .recording else { return }

        let requestID = currentRequestID ?? UUID()
        let mode = activeMode
        let context = currentContext

        stopMetering()
        recordingStartedAt = nil
        audioLevel = 0

        guard let summary = captureEngine.endCapture(discard: false) else {
            phase = isSessionArmed ? .armed : .idle
            publishIPCState()
            return
        }

        phase = .processing
        publishIPCState()
        await startOrUpdateLiveActivity(statusText: "Processing \(mode.displayName)…")

        // Immediately save local fallback entry BEFORE calling network so recordings are never lost
        var entry = TranscriptEntry(
            id: requestID,
            createdAt: Date(),
            mode: mode,
            status: .processing,
            audioFilename: summary.fileURL.lastPathComponent,
            durationSeconds: summary.durationSeconds,
            contextSnapshot: context
        )
        store.upsertTranscriptEntry(entry)
        reloadTranscriptLog()

        do {
            let output = try await aiService.processAudio(
                audioURL: summary.fileURL,
                mimeType: summary.mimeType,
                mode: mode,
                context: context,
                settings: settings
            )

            entry.status = .completed
            entry.outputText = output.outputText
            entry.rawTranscript = output.rawTranscript
            entry.providerUsed = output.providerUsed
            entry.modelUsed = output.modelUsed
            entry.errorMessage = nil
            store.upsertTranscriptEntry(entry)
            reloadTranscriptLog()

            let replaceBeforeLen = (mode == .voiceEdit && !context.hasSelection)
                ? context.beforeCursor.count
                : 0
            let result = VoiceResult(
                requestID: requestID,
                mode: mode,
                outputText: output.outputText,
                rawTranscript: output.rawTranscript,
                replacesSelection: mode == .voiceEdit && context.hasSelection,
                replaceBeforeCursorLength: replaceBeforeLen,
                providerUsed: output.providerUsed,
                modelUsed: output.modelUsed
            )

            lastResult = result
            store.saveLatestResult(result, notify: true)

            if settings.autoDisarmAfterInsert {
                await disarmSession()
                return
            }

            phase = isSessionArmed ? .armed : .ready
            lastErrorMessage = nil
            scheduleIdleDisarm()
            await startOrUpdateLiveActivity(statusText: "Ready — inserted via keyboard")
            publishIPCState()
        } catch {
            entry.status = .failed
            entry.errorMessage = error.localizedDescription
            store.upsertTranscriptEntry(entry)
            reloadTranscriptLog()

            fail(with: error.localizedDescription)
            scheduleIdleDisarm()
            await startOrUpdateLiveActivity(statusText: "Failed — saved in History to retry")
        }
    }

    func cancelRecording() async {
        stopMetering()
        _ = captureEngine.endCapture(discard: true)
        recordingStartedAt = nil
        audioLevel = 0
        phase = isSessionArmed ? .armed : .idle
        lastErrorMessage = nil
        scheduleIdleDisarm()
        await startOrUpdateLiveActivity(statusText: "Mic armed — dictate from keyboard")
        publishIPCState()
    }

    func retryEntry(_ entry: TranscriptEntry) async {
        guard let filename = entry.audioFilename else { return }
        let url = store.recordingURL(for: filename)
        let mimeType = url.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/mp4"

        var updated = entry
        updated.status = .processing
        updated.errorMessage = nil
        store.upsertTranscriptEntry(updated)
        reloadTranscriptLog()

        do {
            let output = try await aiService.processAudio(
                audioURL: url,
                mimeType: mimeType,
                mode: entry.mode,
                context: entry.contextSnapshot ?? TextContextSnapshot(),
                settings: settings
            )

            updated.status = .completed
            updated.outputText = output.outputText
            updated.rawTranscript = output.rawTranscript
            updated.providerUsed = output.providerUsed
            updated.modelUsed = output.modelUsed
            store.upsertTranscriptEntry(updated)
            reloadTranscriptLog()

            let result = VoiceResult(
                requestID: entry.id,
                mode: entry.mode,
                outputText: output.outputText,
                rawTranscript: output.rawTranscript,
                providerUsed: output.providerUsed,
                modelUsed: output.modelUsed
            )
            lastResult = result
            store.saveLatestResult(result, notify: true)
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
            store.upsertTranscriptEntry(updated)
            reloadTranscriptLog()
        }
    }

    func deleteEntry(_ entry: TranscriptEntry) {
        store.deleteTranscriptEntry(id: entry.id)
        reloadTranscriptLog()
    }

    func reloadTranscriptLog() {
        transcriptLog = store.loadTranscriptLog()
    }

    // MARK: - Darwin IPC

    private func setupDarwinObservers() {
        notifier.observe(KeyDeckConstants.DarwinNotifications.commandPosted) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.processPendingCommand()
            }
        }
        notifier.observe(KeyDeckConstants.DarwinNotifications.settingsChanged) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let loaded = self.store.loadSettings()
                if loaded != self.settings {
                    self.settings = loaded
                }
            }
        }
    }

    private func processPendingCommand() async {
        guard let command = store.loadPendingCommand() else { return }
        store.clearPendingCommand()

        switch command.kind {
        case .startRecording:
            await startRecording(mode: command.mode, requestID: command.id, context: command.context)
        case .stopRecording:
            await stopRecordingAndProcess()
        case .cancelRecording:
            await cancelRecording()
        case .disarmSession:
            await disarmSession()
        case .tweakResult:
            guard let action = command.tweakAction,
                  let raw = command.sourceTranscript,
                  let previous = command.previousOutput else { return }
            await performTweak(
                requestID: command.id,
                action: action,
                rawTranscript: raw,
                previousOutput: previous
            )
        }
    }

    private func performTweak(
        requestID: UUID,
        action: TweakAction,
        rawTranscript: String,
        previousOutput: String
    ) async {
        phase = .processing
        publishIPCState()
        do {
            let tweaked = try await aiService.tweakText(
                action: action,
                rawTranscript: rawTranscript,
                currentOutput: previousOutput,
                settings: settings
            )
            let result = VoiceResult(
                requestID: requestID,
                mode: activeMode,
                outputText: tweaked.text,
                rawTranscript: rawTranscript,
                providerUsed: tweaked.provider,
                modelUsed: tweaked.model
            )
            lastResult = result
            store.saveLatestResult(result, notify: true)
            phase = isSessionArmed ? .armed : .ready
            publishIPCState()
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    // MARK: - Permissions & Timers

    private func ensureMicPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionDenied = false
            return true
        case .denied:
            permissionDenied = true
            fail(with: "Microphone permission denied. Enable it in iOS Settings → KeyDeck.")
            return false
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            permissionDenied = !granted
            if !granted {
                fail(with: "Microphone permission is required for Rambler & Voice Edit.")
            }
            return granted
        @unknown default:
            return false
        }
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .recording else { return }
                self.audioLevel = self.captureEngine.currentAudioLevel
                self.publishIPCState(notify: false)
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.publishIPCState(notify: false)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func scheduleIdleDisarm() {
        idleDisarmTask?.cancel()
        let minutes = settings.keepSessionAliveMinutes
        guard minutes > 0 else { return }
        idleDisarmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            guard let self, self.phase != .recording, self.phase != .processing else { return }
            await self.disarmSession()
        }
    }

    private func publishIPCState(notify: Bool = true) {
        let state = VoiceIPCState(
            phase: phase,
            activeMode: activeMode,
            activeRequestID: currentRequestID,
            sessionArmed: isSessionArmed,
            audioLevel: audioLevel,
            recordingStartedAt: recordingStartedAt,
            heartbeatAt: isSessionArmed ? Date() : .distantPast,
            errorMessage: lastErrorMessage
        )
        store.saveVoiceState(state, notify: notify)
    }

    private func fail(with message: String) {
        lastErrorMessage = message
        phase = .failed
        publishIPCState()
    }

    // MARK: - Live Activity

    private func startOrUpdateLiveActivity(statusText: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let contentState = VoiceSessionAttributes.ContentState(
            phase: phase,
            mode: activeMode,
            statusText: statusText,
            updatedAt: Date()
        )
        liveActivityID = await Self.syncLiveActivity(
            existingID: liveActivityID,
            state: contentState
        )
    }

    private func endLiveActivity() async {
        let finalState = VoiceSessionAttributes.ContentState(
            phase: .idle,
            mode: activeMode,
            statusText: "Session ended",
            updatedAt: Date()
        )
        await Self.stopLiveActivities(finalState: finalState)
        liveActivityID = nil
    }

    private nonisolated static func syncLiveActivity(
        existingID: String?,
        state: VoiceSessionAttributes.ContentState
    ) async -> String? {
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
        if let existingID,
           let existing = Activity<VoiceSessionAttributes>.activities.first(where: { $0.id == existingID }) {
            await existing.update(content)
            return existing.id
        }
        if let existing = Activity<VoiceSessionAttributes>.activities.first {
            await existing.update(content)
            return existing.id
        }
        let attributes = VoiceSessionAttributes(startedAt: Date())
        let created = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        return created?.id
    }

    private nonisolated static func stopLiveActivities(
        finalState: VoiceSessionAttributes.ContentState
    ) async {
        let content = ActivityContent(state: finalState, staleDate: nil)
        for activity in Activity<VoiceSessionAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
