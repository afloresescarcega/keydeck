import Foundation

public enum AlfredFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case snippets
    case clipboard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "All"
        case .snippets: "Snippets"
        case .clipboard: "Clips"
        }
    }
}

public enum AlfredResultAction: Equatable, Sendable {
    case insertText(String)
    case runWorkflow(workflow: KeyDeckWorkflow, inlineArgument: String?)
    case promptForArgument(workflow: KeyDeckWorkflow, prompt: String, placeholder: String)
    case triggerVoice(VoiceMode)
    case killMic
}

public struct AlfredSearchResult: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var badge: String?
    public var systemImage: String
    public var score: Int
    public var action: AlfredResultAction
    public var clipboardItemID: UUID?
    public var isPinned: Bool

    public init( // NOSONAR: memberwise init of a plain data model
        id: String,
        title: String,
        subtitle: String,
        badge: String? = nil,
        systemImage: String,
        score: Int,
        action: AlfredResultAction,
        clipboardItemID: UUID? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.systemImage = systemImage
        self.score = score
        self.action = action
        self.clipboardItemID = clipboardItemID
        self.isPinned = isPinned
    }
}

public enum AlfredSearchEngine {

    public static func search(
        query rawQuery: String,
        filter: AlfredFilter = .all,
        workflows: [KeyDeckWorkflow],
        clipboardItems: [ClipboardItem],
        snippetContext: SnippetContext,
        isMicLive: Bool,
        now: Date = Date()
    ) -> [AlfredSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = query.lowercased()
        var results: [AlfredSearchResult] = []

        // 1. Live Inline Utilities (Calculator, Conversions, Timezones, Generators)
        if filter == .all, let util = InlineUtilityEngine.evaluate(query, now: now) {
            results.append(
                AlfredSearchResult(
                    id: "util-\(util.insertText)",
                    title: util.title,
                    subtitle: util.subtitle,
                    badge: "Insert",
                    systemImage: util.systemImage,
                    score: 1000,
                    action: .insertText(util.insertText)
                )
            )
        }

        // 2. Dynamic Snippets & Workflows (supports "keyword argument" syntax like "intro Alex")
        if filter == .all || filter == .snippets {
            let parts = query.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let headKeyword = parts.first.map { String($0).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ";")) } ?? ""
            let inlineArg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil

            for workflow in workflows {
                let keywordLower = workflow.keyword.lowercased()
                let matchScore: Int
                let resolvedArg: String?

                if query.isEmpty {
                    matchScore = workflow.isPinned ? 400 : 250
                    resolvedArg = nil
                } else if !headKeyword.isEmpty && headKeyword == keywordLower {
                    matchScore = inlineArg != nil ? 950 : 900
                    resolvedArg = inlineArg
                } else if let fuzzy = fuzzyScore(query: lower, candidates: [keywordLower, workflow.name.lowercased(), workflow.summary.lowercased()]) {
                    matchScore = fuzzy + (workflow.isPinned ? 40 : 0)
                    resolvedArg = nil
                } else {
                    continue
                }

                let argRequirement = SnippetEngine.requiresArgument(for: workflow)
                let previewContext = SnippetContext(
                    argument: resolvedArg ?? "",
                    clipboard: snippetContext.clipboard,
                    selection: snippetContext.selection,
                    now: now
                )

                if let req = argRequirement, (resolvedArg == nil || resolvedArg?.isEmpty == true) {
                    results.append(
                        AlfredSearchResult(
                            id: "wf-\(workflow.id.uuidString)",
                            title: workflow.name,
                            subtitle: "Type: \(workflow.keyword) <\(req.placeholder)>",
                            badge: ";\(workflow.keyword)",
                            systemImage: workflow.systemImage,
                            score: matchScore,
                            action: .promptForArgument(workflow: workflow, prompt: req.prompt, placeholder: req.placeholder),
                            isPinned: workflow.isPinned
                        )
                    )
                } else {
                    let preview = SnippetEngine.expand(workflow: workflow, context: previewContext)?
                        .replacingOccurrences(of: "\n", with: " ") ?? workflow.summary
                    results.append(
                        AlfredSearchResult(
                            id: "wf-\(workflow.id.uuidString)",
                            title: resolvedArg != nil ? "\(workflow.name): \(resolvedArg!)" : workflow.name,
                            subtitle: preview,
                            badge: ";\(workflow.keyword)",
                            systemImage: workflow.systemImage,
                            score: matchScore,
                            action: .runWorkflow(workflow: workflow, inlineArgument: resolvedArg),
                            isPinned: workflow.isPinned
                        )
                    )
                }
            }
        }

        // 3. Clipboard Manager & Pinned Clips
        if filter == .all || filter == .clipboard {
            let clipShortcut = (lower == "clip" || lower == "cb" || lower == "paste")
            for item in clipboardItems {
                let score: Int
                if query.isEmpty || clipShortcut {
                    score = item.isPinned ? 360 : 200
                } else if let fuzzy = fuzzyScore(query: lower, candidates: [item.displayTitle.lowercased(), item.text.lowercased()]) {
                    score = fuzzy + (item.isPinned ? 50 : 0)
                } else {
                    continue
                }
                results.append(
                    AlfredSearchResult(
                        id: "clip-\(item.id.uuidString)",
                        title: item.displayTitle,
                        subtitle: item.isPinned ? "Pinned clip" : "Clipboard",
                        badge: item.isPinned ? "Pin" : "Clip",
                        systemImage: item.isPinned ? "pin.fill" : "doc.on.clipboard",
                        score: score,
                        action: .insertText(item.text),
                        clipboardItemID: item.id,
                        isPinned: item.isPinned
                    )
                )
            }
        }

        // 4. Built-in Voice / Mic Commands
        if filter == .all && !query.isEmpty {
            if let s = fuzzyScore(query: lower, candidates: ["rambler", "dictate", "voice"]) {
                results.append(
                    AlfredSearchResult(
                        id: "cmd-rambler",
                        title: "Start Rambler",
                        subtitle: "Voice ramble → clean text",
                        badge: "Voice",
                        systemImage: VoiceMode.rambler.systemImage,
                        score: s,
                        action: .triggerVoice(.rambler)
                    )
                )
            }
            if let s = fuzzyScore(query: lower, candidates: ["voice edit", "rewrite", "edit"]) {
                results.append(
                    AlfredSearchResult(
                        id: "cmd-voice-edit",
                        title: "Start Voice Edit",
                        subtitle: "Speak an instruction to transform text",
                        badge: "Voice",
                        systemImage: VoiceMode.voiceEdit.systemImage,
                        score: s,
                        action: .triggerVoice(.voiceEdit)
                    )
                )
            }
            if isMicLive, let s = fuzzyScore(query: lower, candidates: ["kill mic", "stop mic", "mute", "disarm"]) {
                results.append(
                    AlfredSearchResult(
                        id: "cmd-kill-mic",
                        title: "Kill Mic",
                        subtitle: "Shut off background microphone immediately",
                        badge: "Off",
                        systemImage: "mic.slash.fill",
                        score: s + 80,
                        action: .killMic
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    internal static func fuzzyScore(query: String, candidates: [String]) -> Int? {
        guard !query.isEmpty else { return 0 }
        var best: Int?
        for candidate in candidates where !candidate.isEmpty {
            if candidate == query {
                best = max(best ?? 0, 850)
            } else if candidate.hasPrefix(query) {
                best = max(best ?? 0, 750)
            } else if candidate.contains(query) {
                best = max(best ?? 0, 600)
            } else if isSubsequence(query, of: candidate) {
                best = max(best ?? 0, 450)
            }
        }
        return best
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIndex = needle.startIndex
        for char in haystack {
            if needleIndex < needle.endIndex && char == needle[needleIndex] {
                needleIndex = needle.index(after: needleIndex)
            }
        }
        return needleIndex == needle.endIndex
    }
}
