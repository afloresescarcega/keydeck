import Foundation
import Testing
@testable import KeyDeckKit

@Suite("KeyDeckKit Core Tests")
struct KeyDeckKitTests {

    @Test("PromptBuilder includes custom dictionary, personal instructions, and surrounding context when enabled")
    func promptBuilderIncludesContextAndDictionary() {
        var settings = KeyDeckSettings.default
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
        var settings = KeyDeckSettings.default
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

        var settings = KeyDeckSettings.default
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
            clipboard: "https://example.com",
            selection: "hello",
            now: fixedDate
        )
        let expanded = SnippetEngine.expandTemplate(
            "Hey {{input}}, link: {{clipboard}}, sel: {{selection}}, date: {{date}}",
            context: ctx
        )
        #expect(expanded.contains("Hey Bob"))
        #expect(expanded.contains("https://example.com"))
        #expect(expanded.contains("sel: hello"))
        #expect(expanded.contains("2026-11-22"))
    }

    @Test("AlfredSearchEngine ranks inline math and keyword+argument snippets first")
    func alfredSearchRanking() {
        let workflows = KeyDeckWorkflow.starterPack
        let clips = [ClipboardItem(text: "alex@example.com", label: "Work Email", isPinned: true)]

        let mathResults = AlfredSearchEngine.search(
            query: "18% of 240",
            workflows: workflows,
            clipboardItems: clips,
            snippetContext: SnippetContext(),
            isMicLive: false
        )
        #expect(mathResults.first?.insertTextIfStatic == "43.2")

        let argResults = AlfredSearchEngine.search(
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

        let clipResults = AlfredSearchEngine.search(
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
}

private extension AlfredSearchResult {
    var insertTextIfStatic: String? {
        if case let .insertText(text) = action { return text }
        return nil
    }
}
