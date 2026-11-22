import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var label: String?
    public var isPinned: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        label: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.label = label
        self.isPinned = isPinned
        self.createdAt = createdAt
    }

    public var displayTitle: String {
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 48 {
            return collapsed
        }
        return String(collapsed.prefix(48)) + "…"
    }
}
