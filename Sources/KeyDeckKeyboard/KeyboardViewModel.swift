import Foundation
import KeyDeckKit
import Observation
import UIKit

struct InsertionRecord: Equatable {
    var resultID: UUID
    var mode: VoiceMode
    var insertedText: String
    var replacedText: String
    var rawTranscript: String
}

@MainActor
@Observable
final class KeyboardViewModel {
    private(set) var voiceState: VoiceIPCState = VoiceIPCState()
    private(set) var settings: KeyDeckSettings = .standard
    private(set) var hasFullAccess: Bool = false
    private(set) var needsGlobeKey: Bool = true
    private(set) var hasSelectedText: Bool = false
    private(set) var lastInsertion: InsertionRecord?
    private(set) var isTweaking: Bool = false
    private(set) var statusMessage: String?

    // Phase 2: Command Palette, Snippets & Clipboard
    private(set) var isPaletteOpen: Bool = false
    /// Full-keyboard typing mode: the mini-QWERTY types straight into the host text field.
    /// Works without Full Access and without network (App Review Guideline 4.4.1).
    private(set) var isTypingMode: Bool = false
    var paletteQuery: String = ""
    var paletteFilter: PaletteFilter = .all
    private(set) var workflows: [KeyDeckWorkflow] = []
    private(set) var clipboardItems: [ClipboardItem] = []

    private let store: SharedStore
    private let aiService: VoiceProcessingService
    private let notifier = DarwinNotifier()
    private var pollTimer: Timer?
    private var statusClearTask: Task<Void, Never>?

    private let checkFullAccess: () -> Bool
    private let checkGlobeKey: () -> Bool
    private let readContext: () -> TextContextSnapshot
    private let insertTextAction: (String) -> Void
    private let deleteBackwardCountAction: (Int) -> Void
    private let advanceKeyboardAction: () -> Void
    private let onHeightModeChanged: (Bool) -> Void

    private var pendingReplacedTextByRequestID: [UUID: String] = [:]

    init( // NOSONAR: explicit dependency injection of host callbacks
        store: SharedStore = .shared,
        aiService: VoiceProcessingService = VoiceProcessingService(),
        hasFullAccess: @escaping () -> Bool,
        needsInputModeSwitchKey: @escaping () -> Bool,
        readContext: @escaping () -> TextContextSnapshot,
        insertText: @escaping (String) -> Void,
        deleteBackwardCount: @escaping (Int) -> Void,
        advanceKeyboard: @escaping () -> Void,
        onHeightModeChanged: @escaping (Bool) -> Void = { _ in /* Optional: hosts that don't resize ignore height changes. */ }
    ) {
        self.store = store
        self.aiService = aiService
        self.checkFullAccess = hasFullAccess
        self.checkGlobeKey = needsInputModeSwitchKey
        self.readContext = readContext
        self.insertTextAction = insertText
        self.deleteBackwardCountAction = deleteBackwardCount
        self.advanceKeyboardAction = advanceKeyboard
        self.onHeightModeChanged = onHeightModeChanged
    }

    var isSessionLive: Bool {
        voiceState.isSessionLive()
    }

    var isRecording: Bool {
        voiceState.phase == .recording && voiceState.isSessionLive(maxStalenessSeconds: 20)
    }

    var isProcessing: Bool {
        voiceState.phase == .processing || isTweaking
    }

    var pinnedDashboardWorkflows: [KeyDeckWorkflow] {
        workflows.filter(\.isPinned)
    }

    var paletteResults: [PaletteSearchResult] {
        let context = readContext()
        let latestClip = clipboardItems.first?.text ?? ""
        let snippetCtx = SnippetContext(
            clipboard: latestClip,
            selection: context.selectedText
        )
        return PaletteSearchEngine.search(
            query: paletteQuery,
            filter: paletteFilter,
            workflows: workflows,
            clipboardItems: clipboardItems,
            snippetContext: snippetCtx,
            isMicLive: isSessionLive
        )
    }

    func onAppear() {
        hasFullAccess = checkFullAccess()
        needsGlobeKey = checkGlobeKey()
        settings = store.loadSettings()
        voiceState = store.loadVoiceState()
        workflows = store.loadWorkflows()
        clipboardItems = store.loadClipboardItems()
        refreshContextIndicators()
        consumePendingResultIfAvailable()
        startObserving()
    }

    func onDisappear() {
        stopObserving()
    }

    func refreshContextIndicators() {
        hasSelectedText = readContext().hasSelection
    }

    // MARK: - Command Palette & Mini-QWERTY

    func openPalette(initialQuery: String = "", filter: PaletteFilter = .all) {
        triggerHaptic(.light)
        workflows = store.loadWorkflows()
        clipboardItems = store.loadClipboardItems()
        paletteQuery = initialQuery
        paletteFilter = filter
        isPaletteOpen = true
        onHeightModeChanged(true)
    }

    func closePalette() {
        triggerHaptic(.light)
        isPaletteOpen = false
        paletteQuery = ""
        paletteFilter = .all
        onHeightModeChanged(false)
    }

    func setPaletteFilter(_ filter: PaletteFilter) {
        triggerHaptic(.light)
        paletteFilter = filter
    }

    func paletteInsertCharacter(_ text: String) {
        triggerHaptic(.light)
        paletteQuery.append(text)
    }

    func paletteBackspace() {
        triggerHaptic(.light)
        if !paletteQuery.isEmpty {
            paletteQuery.removeLast()
        }
    }

    func paletteClearQuery() {
        triggerHaptic(.light)
        paletteQuery = ""
    }

    func paletteExecuteTopResult() {
        if let first = paletteResults.first {
            executePaletteResult(first)
        } else if !paletteQuery.isEmpty {
            lastInsertion = nil
            insertTextAction(paletteQuery)
            closePalette()
        }
    }

    func executePaletteResult(_ result: PaletteSearchResult) {
        switch result.action {
        case .insertText(let text):
            triggerHaptic(.success)
            insertTextAction(text)
            lastInsertion = nil
            closePalette()

        case .runWorkflow(let workflow, let inlineArg):
            let context = readContext()
            let clipText = readPasteboardOrLatestClip(needsClipboard: workflowUsesClipboard(workflow))
            let snippetCtx = SnippetContext(
                argument: inlineArg ?? "",
                clipboard: clipText,
                selection: context.selectedText
            )
            if let expanded = SnippetEngine.expand(workflow: workflow, context: snippetCtx) {
                triggerHaptic(.success)
                insertTextAction(expanded)
                lastInsertion = nil
                closePalette()
            }

        case .promptForArgument(let workflow, _, _):
            triggerHaptic(.light)
            paletteFilter = .all
            paletteQuery = "\(workflow.keyword) "
            if !isPaletteOpen {
                isPaletteOpen = true
                onHeightModeChanged(true)
            }

        case .triggerVoice(let mode):
            closePalette()
            triggerVoice(mode: mode)

        case .killMic:
            closePalette()
            killMic()
        }
    }

    func tapPinnedWorkflow(_ workflow: KeyDeckWorkflow) {
        if SnippetEngine.requiresArgument(for: workflow) != nil {
            openPalette(initialQuery: "\(workflow.keyword) ", filter: .all)
            return
        }
        let context = readContext()
        let clipText = readPasteboardOrLatestClip(needsClipboard: workflowUsesClipboard(workflow))
        let snippetCtx = SnippetContext(
            clipboard: clipText,
            selection: context.selectedText
        )
        if let expanded = SnippetEngine.expand(workflow: workflow, context: snippetCtx) {
            triggerHaptic(.success)
            lastInsertion = nil
            insertTextAction(expanded)
            showStatus("Inserted \(workflow.name)")
        }
    }

    func captureCurrentClipboard(pin: Bool = false) {
        triggerHaptic(.medium)
        guard hasFullAccess else {
            showStatus("Enable Allow Full Access to read clipboard.")
            return
        }
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStatus("Clipboard is empty")
            return
        }
        clipboardItems = store.saveClipboardText(text, pinned: pin)
        showStatus(pin ? "Pinned clipboard item" : "Saved to Clipboard history")
    }

    func toggleClipboardPin(id: UUID) {
        triggerHaptic(.light)
        clipboardItems = store.toggleClipboardPin(id: id)
    }

    private func workflowUsesClipboard(_ workflow: KeyDeckWorkflow) -> Bool {
        SnippetEngine.primaryTemplateBody(for: workflow)?.contains("{{clipboard}}") == true
    }

    private func readPasteboardOrLatestClip(needsClipboard: Bool) -> String {
        guard needsClipboard else { return clipboardItems.first?.text ?? "" }
        if hasFullAccess, let live = UIPasteboard.general.string, !live.isEmpty {
            clipboardItems = store.saveClipboardText(live)
            return live
        }
        return clipboardItems.first?.text ?? ""
    }

    // MARK: - Voice & Mic Lifecycle

    func triggerVoice(mode: VoiceMode) {
        triggerHaptic(.medium)

        guard hasFullAccess else {
            showStatus("Enable Allow Full Access in iOS Keyboard Settings.")
            return
        }

        guard settings.aiDataSharingConsent else {
            showStatus("Allow AI Data Sharing in the KeyDeck app first.")
            return
        }

        if isRecording {
            stopRecording()
            return
        }

        // Guideline 4.4.1: keyboards must not launch other apps. The user starts the mic
        // in the KeyDeck app themselves; the keyboard only explains how.
        guard voiceState.isSessionLive() else {
            showStartMicHint()
            return
        }

        // Data minimization: with Send Surrounding Field Context off, Rambler captures no field text and
        // Voice Edit captures only its target (the selection, or text before the cursor).
        let fullContext = readContext()
        let context: TextContextSnapshot
        if settings.sendSurroundingContext {
            context = fullContext
        } else if mode == .voiceEdit {
            context = TextContextSnapshot(
                beforeCursor: fullContext.hasSelection ? "" : fullContext.beforeCursor,
                afterCursor: "",
                selectedText: fullContext.selectedText
            )
        } else {
            context = TextContextSnapshot()
        }
        let requestID = UUID()
        if mode == .voiceEdit {
            pendingReplacedTextByRequestID[requestID] = context.effectiveTargetText
        }

        let command = VoiceIPCCommand(
            id: requestID,
            kind: .startRecording,
            mode: mode,
            context: context
        )

        store.savePendingCommand(command, notify: true)
        voiceState.phase = .recording
        voiceState.activeMode = mode
        voiceState.activeRequestID = requestID
        voiceState.recordingStartedAt = Date()
    }

    func stopRecording() {
        triggerHaptic(.light)
        let command = VoiceIPCCommand(kind: .stopRecording, mode: voiceState.activeMode)
        store.savePendingCommand(command, notify: true)
        voiceState.phase = .processing
        showStatus("Processing…")
    }

    func cancelRecording() {
        triggerHaptic(.light)
        let command = VoiceIPCCommand(kind: .cancelRecording, mode: voiceState.activeMode)
        store.savePendingCommand(command, notify: true)
        voiceState.phase = isSessionLive ? .armed : .idle
        showStatus("Cancelled")
    }

    /// Immediately kills the background microphone session in-place without leaving the current app.
    func killMic() {
        triggerHaptic(.medium)
        let command = VoiceIPCCommand(kind: .disarmSession)
        store.savePendingCommand(command, notify: true)
        voiceState.sessionArmed = false
        voiceState.phase = .idle
        voiceState.recordingStartedAt = nil
        voiceState.audioLevel = 0
        voiceState.heartbeatAt = .distantPast
        showStatus("Mic killed")
    }

    /// Explains how to start the mic. Deliberately does not open the KeyDeck app (Guideline 4.4.1).
    func showStartMicHint() {
        triggerHaptic(.light)
        guard hasFullAccess else {
            showStatus("Enable Allow Full Access in iOS Keyboard Settings to use voice.")
            return
        }
        showStatus("Mic is off. Open the KeyDeck app and tap Start Mic, then come back.")
    }

    func togglePrivacyContext() {
        triggerHaptic(.light)
        guard hasFullAccess else {
            showStatus("Enable Allow Full Access in iOS Keyboard Settings to change this.")
            return
        }
        settings.sendSurroundingContext.toggle()
        store.saveSettings(settings)
        showStatus(settings.sendSurroundingContext ? "Field context on" : "Field context off (private)")
    }

    // MARK: - Auto-Insert, Undo & Quick Tweaks

    func undoLastInsertion() {
        guard let record = lastInsertion else { return }
        triggerHaptic(.medium)

        deleteBackwardCountAction(record.insertedText.count)
        if !record.replacedText.isEmpty {
            insertTextAction(record.replacedText)
        }
        lastInsertion = nil
        showStatus("Undid insert")
    }

    func dismissTweakBar() {
        triggerHaptic(.light)
        lastInsertion = nil
    }

    func applyTweak(_ action: TweakAction) {
        guard let record = lastInsertion, !isTweaking else { return }
        triggerHaptic(.light)

        if action == .raw {
            replaceLastInsertedText(with: record.rawTranscript)
            showStatus("Restored raw transcript")
            return
        }

        isTweaking = true
        showStatus("Refining (\(action.label))…")

        Task {
            do {
                let tweaked = try await aiService.tweakText(
                    action: action,
                    rawTranscript: record.rawTranscript,
                    currentOutput: record.insertedText,
                    settings: settings
                )
                isTweaking = false
                replaceLastInsertedText(with: tweaked.text)
                showStatus("Updated: \(action.label)")
            } catch {
                isTweaking = false
                showStatus(error.localizedDescription)
            }
        }
    }

    private func replaceLastInsertedText(with newText: String) {
        guard var record = lastInsertion else { return }
        deleteBackwardCountAction(record.insertedText.count)
        insertTextAction(newText)
        record.insertedText = newText
        lastInsertion = record
    }

    // MARK: - Typing Mode

    func openTypingMode() {
        triggerHaptic(.light)
        isTypingMode = true
    }

    func closeTypingMode() {
        triggerHaptic(.light)
        isTypingMode = false
    }

    func typeCharacter(_ text: String) {
        triggerHaptic(.light)
        lastInsertion = nil
        insertTextAction(text)
    }

    func typeBackspace() {
        triggerHaptic(.light)
        lastInsertion = nil
        deleteBackwardCountAction(1)
    }

    func typeReturn() {
        triggerHaptic(.light)
        lastInsertion = nil
        insertTextAction("\n")
    }

    // MARK: - Quick-Edit Keys

    func tapGlobe() {
        triggerHaptic(.light)
        advanceKeyboardAction()
    }

    // Manual edits invalidate Undo/Tweak, which delete `insertedText.count` characters before the cursor.
    func tapSpace() {
        triggerHaptic(.light)
        lastInsertion = nil
        insertTextAction(" ")
    }

    func tapReturn() {
        triggerHaptic(.light)
        lastInsertion = nil
        insertTextAction("\n")
    }

    func tapBackspace() {
        triggerHaptic(.light)
        lastInsertion = nil
        deleteBackwardCountAction(1)
    }

    // MARK: - Observation & Auto-Insert

    private func startObserving() {
        notifier.removeAll()
        notifier.observe(KeyDeckConstants.DarwinNotifications.stateChanged) { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncStateFromStore()
            }
        }
        notifier.observe(KeyDeckConstants.DarwinNotifications.resultReady) { [weak self] in
            Task { @MainActor [weak self] in
                self?.consumePendingResultIfAvailable()
            }
        }
        notifier.observe(KeyDeckConstants.DarwinNotifications.settingsChanged) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.settings = self.store.loadSettings()
            }
        }
        notifier.observe(KeyDeckConstants.DarwinNotifications.workflowsChanged) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.workflows = self.store.loadWorkflows()
            }
        }
        notifier.observe(KeyDeckConstants.DarwinNotifications.clipboardChanged) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.clipboardItems = self.store.loadClipboardItems()
            }
        }

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncStateFromStore()
                self?.consumePendingResultIfAvailable()
            }
        }
    }

    private func stopObserving() {
        notifier.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func syncStateFromStore() {
        let latest = store.loadVoiceState()
        voiceState = latest
        if latest.phase == .failed, let err = latest.errorMessage {
            showStatus(err)
        }
    }

    private func consumePendingResultIfAvailable() {
        guard let result = store.loadLatestResult(), !result.consumed else { return }
        guard Date().timeIntervalSince(result.createdAt) < 300 else {
            store.markLatestResultConsumed(id: result.id)
            return
        }

        store.markLatestResultConsumed(id: result.id)

        let replacedText = pendingReplacedTextByRequestID.removeValue(forKey: result.requestID) ?? ""
        if result.mode == .voiceEdit && !result.replacesSelection && result.replaceBeforeCursorLength > 0 {
            deleteBackwardCountAction(result.replaceBeforeCursorLength)
        }

        insertTextAction(result.outputText)
        triggerHaptic(.success)

        lastInsertion = InsertionRecord(
            resultID: result.id,
            mode: result.mode,
            insertedText: result.outputText,
            replacedText: replacedText,
            rawTranscript: result.rawTranscript
        )
        showStatus(nil)
    }

    private func showStatus(_ message: String?) {
        statusClearTask?.cancel()
        statusMessage = message
        guard message != nil else { return }
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private enum HapticKind {
        case light, medium, success
    }

    private func triggerHaptic(_ kind: HapticKind) {
        guard settings.enableHaptics else { return }
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
