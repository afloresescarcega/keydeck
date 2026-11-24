import Foundation
import Testing
@testable import KeyDeckKit

@Suite("KeyDeckKit Core Tests")
struct KeyDeckKitTests {

    @Test("PromptBuilder includes custom dictionary, personal instructions, and surrounding context when enabled")
    func promptBuilderIncludesContextAndDictionary() {
        var settings = KeyDeckSettings.standard
        settings.customDictionary = ["KeyDeck", "Alex Flores Escarcega", "SwiftData"]
        settings.personalInstructions = "Prefer concise sentences without fluff."
        settings.sendSurroundingContext = true

        let context = TextContextSnapshot(
            beforeCursor: "Hey team, quick update on the keyboard project:",
            afterCursor: "",
            selectedText: ""
        )

        let prompt = PromptBuilder.systemPrompt(mode: .rambler, settings: settings, context: context)
        #expect(prompt.contains("KeyDeck, Alex Flores Escarcega, SwiftData"))
        #expect(prompt.contains("Prefer concise sentences without fluff."))
        #expect(prompt.contains("Hey team, quick update on the keyboard project:"))
    }

    @Test("PromptBuilder omits surrounding context for Rambler when privacy toggle is off")
    func promptBuilderRespectsPrivacyToggle() {
        var settings = KeyDeckSettings.standard
        settings.sendSurroundingContext = false

        let context = TextContextSnapshot(beforeCursor: "Super secret draft text")
        let prompt = PromptBuilder.systemPrompt(mode: .rambler, settings: settings, context: context)
        #expect(!prompt.contains("Super secret draft text"))
    }

    @Test("Gemini single-pass JSON parser handles fenced JSON and plain JSON")
    func geminiSinglePassParser() {
        let client = GeminiClient()
        let fenced = """
        ```json
        {"raw_transcript": "uh meet at 3 actually 4", "output_text": "Let's meet at 4."}
        ```
        """
        let parsed = client.parseSinglePassResponse(fenced)
        #expect(parsed.outputText == "Let's meet at 4.")
        #expect(parsed.rawTranscript == "uh meet at 3 actually 4")
    }

    @Test("SharedStore persists settings, voice state, results, clipboard, and transcript log")
    func sharedStoreRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyDeckTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SharedStore(containerURL: tempDir)

        var settings = KeyDeckSettings.standard
        settings.accentColor = .teal
        settings.autoDisarmAfterInsert = true
        settings.customDictionary = ["KeyDeck"]
        store.saveSettings(settings)
        #expect(store.loadSettings() == settings)

        let reqID = UUID()
        let result = VoiceResult(
            requestID: reqID,
            mode: .rambler,
            outputText: "Clean text",
            rawTranscript: "um clean text",
            providerUsed: .gemini,
            modelUsed: "gemini-2.5-flash"
        )
        store.saveLatestResult(result, notify: false)
        #expect(store.loadLatestResult()?.outputText == "Clean text")

        store.markLatestResultConsumed(id: result.id)
        #expect(store.loadLatestResult()?.consumed == true)

        // Clipboard dedup + pin ordering
        _ = store.saveClipboardText("first clip")
        let afterSecond = store.saveClipboardText("second clip")
        #expect(afterSecond.count == 2)
        #expect(afterSecond.first?.text == "second clip")
        let firstID = try #require(afterSecond.last?.id)
        let afterPin = store.toggleClipboardPin(id: firstID)
        #expect(afterPin.first?.text == "first clip")
        #expect(afterPin.first?.isPinned == true)

        let entry = TranscriptEntry(
            mode: .rambler,
            status: .completed,
            durationSeconds: 12.5,
            outputText: "Clean text",
            rawTranscript: "um clean text",
            providerUsed: .gemini,
            modelUsed: "gemini-2.5-flash"
        )
        store.upsertTranscriptEntry(entry)
        #expect(store.loadTranscriptLog().count == 1)
        #expect(store.loadTranscriptLog().first?.id == entry.id)

        store.deleteTranscriptEntry(id: entry.id)
        #expect(store.loadTranscriptLog().isEmpty)
    }

    @Test("VoiceIPCState liveness respects staleness threshold")
    func voiceStateLiveness() {
        let now = Date()
        let live = VoiceIPCState(phase: .armed, sessionArmed: true, heartbeatAt: now.addingTimeInterval(-3))
        #expect(live.isSessionLive(now: now))

        let stale = VoiceIPCState(phase: .armed, sessionArmed: true, heartbeatAt: now.addingTimeInterval(-30))
        #expect(!stale.isSessionLive(now: now))
    }

    @Test("InlineUtilityEngine evaluates math, percentages, units, timezones, and generators")
    func inlineUtilityTests() {
        #expect(InlineUtilityEngine.evaluate("(12 + 8) * 3")?.insertText == "60")
        #expect(InlineUtilityEngine.evaluate("18% of 240")?.insertText == "43.2")
        #expect(InlineUtilityEngine.evaluate("sqrt(144) + 3")?.insertText == "15")
        #expect(InlineUtilityEngine.evaluate("32f to c")?.insertText == "0°C")
        #expect(InlineUtilityEngine.evaluate("100c to f")?.insertText == "212°F")
        #expect(InlineUtilityEngine.evaluate("10 km to mi")?.insertText.hasPrefix("6.2137") == true)
        #expect(InlineUtilityEngine.evaluate("uuid")?.insertText.count == 36)
        #expect(InlineUtilityEngine.evaluate("shrug")?.insertText == #"¯\_(ツ)_/¯"#)
        #expect(InlineUtilityEngine.evaluate("3pm est to cst")?.insertText == "2:00 PM CT")
        #expect(InlineUtilityEngine.evaluate("42") == nil) // Plain numbers shouldn't hijack search
    }

    @Test("SnippetEngine expands dynamic tokens and inline arguments")
    func snippetExpansionTests() {
        let fixedDate = Date(timeIntervalSince1970: 1_795_370_400) // Nov 22, 2026
        let ctx = SnippetContext(
            argument: "Bob",
            clipboard: "https://example.com", // NOSONAR: test fixture
            selection: "hello",
            now: fixedDate
        )
        let expanded = SnippetEngine.expandTemplate(
            "Hey {{input}}, link: {{clipboard}}, sel: {{selection}}, date: {{date}}",
            context: ctx
        )
        #expect(expanded.contains("Hey Bob"))
        #expect(expanded.contains("https://example.com")) // NOSONAR: test fixture
        #expect(expanded.contains("sel: hello"))
        #expect(expanded.contains("2026-11-22"))
    }

    @Test("PaletteSearchEngine ranks inline math and keyword+argument snippets first")
    func paletteSearchRanking() {
        let workflows = KeyDeckWorkflow.starterPack
        let clips = [ClipboardItem(text: "alex@example.com", label: "Work Email", isPinned: true)]

        let mathResults = PaletteSearchEngine.search(
            query: "18% of 240",
            workflows: workflows,
            clipboardItems: clips,
            snippetContext: SnippetContext(),
            isMicLive: false
        )
        #expect(mathResults.first?.insertTextIfStatic == "43.2")

        let argResults = PaletteSearchEngine.search(
            query: "intro Bob",
            workflows: workflows,
            clipboardItems: clips,
            snippetContext: SnippetContext(),
            isMicLive: false
        )
        guard case let .runWorkflow(wf, arg) = argResults.first?.action else {
            Issue.record("Expected runWorkflow action for 'intro Bob'")
            return
        }
        #expect(wf.keyword == "intro")
        #expect(arg == "Bob")

        let clipResults = PaletteSearchEngine.search(
            query: "email",
            workflows: workflows,
            clipboardItems: clips,
            snippetContext: SnippetContext(),
            isMicLive: false
        )
        #expect(clipResults.contains(where: { $0.title == "Work Email" }))
    }

    @Test("Starter workflows decode and encode cleanly")
    func workflowSchemaRoundTrip() throws {
        let workflows = KeyDeckWorkflow.starterPack
        let data = try JSONEncoder().encode(workflows)
        let decoded = try JSONDecoder().decode([KeyDeckWorkflow].self, from: data)
        #expect(decoded == workflows)
        #expect(decoded.count >= 3)
    }

    @Test("AI requests are blocked until the user grants AI data sharing consent (Guideline 5.1.2(i))")
    func aiRequestsRequireConsent() async throws {
        let settings = KeyDeckSettings.standard
        #expect(settings.aiDataSharingConsent == false)
        #expect(settings.sendSurroundingContext == false)

        let service = VoiceProcessingService()
        await #expect(throws: AIError.self) {
            _ = try await service.tweakText(
                action: .shorter, rawTranscript: "hello", currentOutput: "hello", settings: settings
            )
        }
        await #expect(throws: AIError.self) {
            _ = try await service.processAudio(
                audioURL: URL(fileURLWithPath: "/nonexistent.m4a"),
                mode: .rambler, context: TextContextSnapshot(), settings: settings
            )
        }

        // Raw restore is local-only and stays available without consent.
        let raw = try await service.tweakText(
            action: .raw, rawTranscript: "raw text", currentOutput: "clean", settings: settings
        )
        #expect(raw.text == "raw text")
        #expect(AIError.aiDataSharingNotAllowed.errorDescription?.contains("AI Data Sharing") == true)
    }

    @Test("Older settings files without the consent key decode to consent = false")
    func legacySettingsDefaultToNoConsent() throws {
        let legacy = Data(#"{"voicePipeline":"geminiSinglePass","enableHaptics":true}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyDeckSettings.self, from: legacy)
        #expect(decoded.aiDataSharingConsent == false)
    }

    @Test("Legacy 'manual only' idle timeout (0) decodes to a bounded default (Guideline 2.5.4)")
    func legacyManualOnlyTimeoutIsBounded() throws {
        let legacy = Data(#"{"keepSessionAliveMinutes":0}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyDeckSettings.self, from: legacy)
        #expect(decoded.keepSessionAliveMinutes > 0)
    }
}

private extension PaletteSearchResult {
    var insertTextIfStatic: String? {
        if case let .insertText(text) = action { return text }
        return nil
    }
}
