import AVFoundation
import Foundation

/// Thread-safe persistent AVAudioEngine capture engine.
///
/// iOS forbids starting a *new* microphone hardware stream (`AVAudioRecorder.record()`)
/// while an app is in the background (`OSStatus 561015905`). By starting a single
/// `AVAudioEngine` with an input tap once while armed in the foreground, background
/// recording from the keyboard extension simply opens an `AVAudioFile` and flips a
/// thread-safe capture flag — zero audio session reconfiguration and ~0ms start latency.
final class LiveAudioCaptureEngine: @unchecked Sendable {
    struct CaptureSummary: Sendable {
        let fileURL: URL
        let mimeType: String
        let durationSeconds: TimeInterval
    }

    private let lock = NSLock()
    private var storedIsArmed = false
    private var storedIsCapturing = false
    private var storedActiveFile: AVAudioFile?
    private var storedActiveFileURL: URL?
    private var storedActiveMimeType: String = "audio/mp4"
    private var storedCaptureStartedAt: Date?
    private var storedLatestLevel: Float = 0
    private var storedWriteError: String?

    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var inputFormat: AVAudioFormat?
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    var currentAudioLevel: Float {
        lock.lock(); defer { lock.unlock() }
        return storedLatestLevel
    }

    var isArmed: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsArmed
    }

    var isCapturing: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedIsCapturing
    }

    init() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        disarm()
    }

    func arm() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true)

        if engine.isRunning && tapInstalled {
            lock.lock(); storedIsArmed = true; lock.unlock()
            return
        }

        try startEngineWithInputTap()
        lock.lock(); storedIsArmed = true; lock.unlock()
    }

    func disarm() {
        _ = endCapture(discard: true)
        removeTapIfNeeded()
        if engine.isRunning {
            engine.stop()
        }
        lock.lock()
        storedIsArmed = false
        storedLatestLevel = 0
        lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func beginCapture(baseURLWithoutExtension: URL) throws -> (fileURL: URL, mimeType: String) {
        if !engine.isRunning || !tapInstalled {
            try startEngineWithInputTap()
        }

        let format = inputFormat ?? engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "KeyDeck.Audio",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone audio format unavailable. Re-arm KeyDeck in the app."]
            )
        }

        // Prefer compact AAC (.m4a); fall back to 16-bit PCM (.wav) if the hardware sample rate rejects AAC
        let (file, fileURL, mimeType) = try openOutputFile(
            baseURL: baseURLWithoutExtension,
            inputFormat: format
        )

        lock.lock()
        storedActiveFile = file
        storedActiveFileURL = fileURL
        storedActiveMimeType = mimeType
        storedCaptureStartedAt = Date()
        storedWriteError = nil
        storedIsCapturing = true
        storedIsArmed = true
        lock.unlock()

        return (fileURL, mimeType)
    }

    func endCapture(discard: Bool) -> CaptureSummary? {
        lock.lock()
        let url = storedActiveFileURL
        let mime = storedActiveMimeType
        let started = storedCaptureStartedAt
        storedIsCapturing = false
        storedActiveFile = nil // Closes and flushes the AVAudioFile cleanly
        storedActiveFileURL = nil
        storedCaptureStartedAt = nil
        storedLatestLevel = 0
        lock.unlock()

        guard let url else { return nil }
        if discard {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let duration = max(0.1, Date().timeIntervalSince(started ?? Date()))
        return CaptureSummary(
            fileURL: url,
            mimeType: mime,
            durationSeconds: duration
        )
    }

    // MARK: - Private Engine Management

    private func startEngineWithInputTap() throws {
        removeTapIfNeeded()
        if engine.isRunning {
            engine.stop()
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "KeyDeck.Audio",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio input unavailable (sample rate 0). Open KeyDeck to re-arm."]
            )
        }
        self.inputFormat = format

        // Touch mainMixerNode so the audio graph stays valid and active in background
        _ = engine.mainMixerNode

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.processIncomingBuffer(buffer)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
    }

    private func removeTapIfNeeded() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func handleConfigurationChange() {
        lock.lock()
        let shouldRestart = storedIsArmed && !storedIsCapturing
        lock.unlock()
        if shouldRestart {
            try? startEngineWithInputTap()
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        if type == .ended {
            lock.lock()
            let wasArmed = storedIsArmed
            lock.unlock()
            guard wasArmed else { return }

            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? startEngineWithInputTap()
            }
        }
    }

    private func openOutputFile(
        baseURL: URL,
        inputFormat: AVAudioFormat
    ) throws -> (AVAudioFile, URL, String) {
        let m4aURL = baseURL.appendingPathExtension("m4a")
        let aacSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        if let file = try? AVAudioFile(
            forWriting: m4aURL,
            settings: aacSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        ) {
            return (file, m4aURL, "audio/mp4")
        }

        let wavURL = baseURL.appendingPathExtension("wav")
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let wavFile = try AVAudioFile(
            forWriting: wavURL,
            settings: pcmSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
        return (wavFile, wavURL, "audio/wav")
    }

    private func processIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let shouldWrite = storedIsCapturing
        lock.unlock()
        guard shouldWrite else { return }

        let rms = computeNormalizedLevel(buffer: buffer)
        lock.lock()
        defer { lock.unlock() }
        storedLatestLevel = rms
        guard storedIsCapturing, let file = storedActiveFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            storedWriteError = error.localizedDescription
        }
    }

    private func computeNormalizedLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 0.00001))
        return max(0, min(1, (db + 50) / 50))
    }
}
