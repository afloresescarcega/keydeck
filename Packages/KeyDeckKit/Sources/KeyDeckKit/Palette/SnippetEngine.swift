import Foundation

public struct SnippetContext: Sendable {
    public var argument: String
    public var clipboard: String
    public var selection: String
    public var now: Date

    public init(
        argument: String = "",
        clipboard: String = "",
        selection: String = "",
        now: Date = Date()
    ) {
        self.argument = argument
        self.clipboard = clipboard
        self.selection = selection
        self.now = now
    }
}

/// Evaluates dynamic snippets and templates containing live variables:
/// `{{date}}`, `{{date_long}}`, `{{time}}`, `{{iso}}`, `{{weekday}}`,
/// `{{clipboard}}`, `{{selection}}`, and `{{input}}`.
public enum SnippetEngine {

    public static func requiresArgument(for workflow: KeyDeckWorkflow) -> (prompt: String, placeholder: String)? {
        for step in workflow.steps {
            if case let .inputArgument(prompt, placeholder) = step.kind {
                return (prompt, placeholder)
            }
        }
        if let template = primaryTemplateBody(for: workflow), template.contains("{{input}}") {
            return ("Argument", "Type value…")
        }
        return nil
    }

    public static func primaryTemplateBody(for workflow: KeyDeckWorkflow) -> String? {
        for step in workflow.steps {
            if case let .template(body) = step.kind {
                return body
            }
        }
        return nil
    }

    public static func expand(workflow: KeyDeckWorkflow, context: SnippetContext) -> String? {
        guard let body = primaryTemplateBody(for: workflow) else { return nil }
        return expandTemplate(body, context: context)
    }

    public static func expandTemplate(_ template: String, context: SnippetContext) -> String {
        var output = template
        let replacements: [(String, String)] = [
            ("{{date}}", formatISODate(context.now)),
            ("{{date_long}}", formatLongDate(context.now)),
            ("{{time}}", formatTime(context.now)),
            ("{{datetime}}", formatDateTime(context.now)),
            ("{{iso}}", ISO8601DateFormatter().string(from: context.now)),
            ("{{weekday}}", formatWeekday(context.now)),
            ("{{clipboard}}", context.clipboard),
            ("{{selection}}", context.selection),
            ("{{input}}", context.argument)
        ]

        for (token, value) in replacements {
            output = output.replacingOccurrences(of: token, with: value)
        }
        return output
    }

    public static func formatISODate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public static func formatLongDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    public static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    public static func formatDateTime(_ date: Date) -> String {
        "\(formatISODate(date)) \(formatTime(date))"
    }

    public static func formatWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
