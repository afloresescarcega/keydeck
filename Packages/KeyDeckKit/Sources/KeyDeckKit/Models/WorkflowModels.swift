import Foundation

/// Forward-compatible schema for Phase 2 (Dynamic Snippets) & Phase 3 (Composable Multi-Step Workflows).
public enum WorkflowStepKind: Codable, Equatable, Sendable {
    case inputSelection
    case inputClipboard
    case inputArgument(prompt: String, placeholder: String)
    case template(body: String)
    case llmPrompt(provider: AIProvider?, model: String?, systemPrompt: String, userPromptTemplate: String)
    case regexReplace(pattern: String, replacement: String)
    case httpRequest(method: String, urlTemplate: String, headers: [String: String], bodyTemplate: String?)
    case outputInsert
    case outputCopy
    case outputAppleShortcut(shortcutName: String)
    case outputOpenURL(urlTemplate: String)
}

public struct WorkflowStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: WorkflowStepKind

    public init(id: UUID = UUID(), title: String, kind: WorkflowStepKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

public struct KeyDeckWorkflow: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var keyword: String
    public var summary: String
    public var systemImage: String
    public var isPinned: Bool
    public var steps: [WorkflowStep]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        keyword: String,
        summary: String,
        systemImage: String = "bolt.fill",
        isPinned: Bool = false,
        steps: [WorkflowStep],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.summary = summary
        self.systemImage = systemImage
        self.isPinned = isPinned
        self.steps = steps
        self.updatedAt = updatedAt
    }

    public static var starterPack: [KeyDeckWorkflow] {
        [
            KeyDeckWorkflow(
                name: "Meeting Note Stamp",
                keyword: "meet",
                summary: "Insert a timestamped meeting header with quick topic placeholder.",
                systemImage: "calendar.badge.clock",
                isPinned: true,
                steps: [
                    WorkflowStep(
                        title: "Topic",
                        kind: .inputArgument(prompt: "Meeting topic", placeholder: "Design sync")
                    ),
                    WorkflowStep(
                        title: "Expand Snippet",
                        kind: .template(body: "## {{input}} — {{date}} {{time}}\n- Attendees: \n- Notes:\n  - ")
                    ),
                    WorkflowStep(title: "Insert", kind: .outputInsert)
                ]
            ),
            KeyDeckWorkflow(
                name: "Today ISO Date",
                keyword: "date",
                summary: "Insert today's date in YYYY-MM-DD format.",
                systemImage: "calendar",
                isPinned: true,
                steps: [
                    WorkflowStep(title: "Format Date", kind: .template(body: "{{date}}")),
                    WorkflowStep(title: "Insert", kind: .outputInsert)
                ]
            ),
            KeyDeckWorkflow(
                name: "Email Intro Snippet",
                keyword: "intro",
                summary: "Expand a friendly email greeting with a recipient name.",
                systemImage: "envelope",
                isPinned: true,
                steps: [
                    WorkflowStep(
                        title: "Recipient",
                        kind: .inputArgument(prompt: "Recipient name", placeholder: "Alex")
                    ),
                    WorkflowStep(
                        title: "Expand",
                        kind: .template(body: "Hey {{input}},\n\nHope your week is going well! ")
                    ),
                    WorkflowStep(title: "Insert", kind: .outputInsert)
                ]
            ),
            KeyDeckWorkflow(
                name: "Quote Clipboard",
                keyword: "quote",
                summary: "Insert clipboard text formatted as a Markdown blockquote.",
                systemImage: "text.quote",
                isPinned: false,
                steps: [
                    WorkflowStep(title: "Template", kind: .template(body: "> {{clipboard}}\n\n")),
                    WorkflowStep(title: "Insert", kind: .outputInsert)
                ]
            )
        ]
    }
}
