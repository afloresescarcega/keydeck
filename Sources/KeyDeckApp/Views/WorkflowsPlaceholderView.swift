import SwiftUI
import KeyDeckKit

struct WorkflowsPlaceholderView: View {
    enum SectionTab: String, CaseIterable, Identifiable {
        case snippets = "Snippets"
        case clipboard = "Clipboard"
        var id: String { rawValue }
    }

    @State private var activeSection: SectionTab = .snippets
    @State private var workflows: [KeyDeckWorkflow] = SharedStore.shared.loadWorkflows()
    @State private var clipboardItems: [ClipboardItem] = SharedStore.shared.loadClipboardItems()

    @State private var editingWorkflow: KeyDeckWorkflow?
    @State private var showingNewSnippet: Bool = false
    @State private var showingAddClip: Bool = false
    @State private var newClipLabel: String = ""
    @State private var newClipText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $activeSection) {
                    ForEach(SectionTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if activeSection == .snippets {
                    snippetsList
                } else {
                    clipboardList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Alfred")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if activeSection == .snippets {
                            showingNewSnippet = true
                        } else {
                            showingAddClip = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(activeSection == .snippets ? "New snippet" : "Add clip")
                }
            }
            .onAppear {
                workflows = SharedStore.shared.loadWorkflows()
                clipboardItems = SharedStore.shared.loadClipboardItems()
            }
            .sheet(isPresented: $showingNewSnippet) {
                SnippetEditorSheet(existing: nil) { saved in
                    workflows.insert(saved, at: 0)
                    SharedStore.shared.saveWorkflows(workflows)
                }
            }
            .sheet(item: $editingWorkflow) { workflow in
                SnippetEditorSheet(existing: workflow) { saved in
                    if let idx = workflows.firstIndex(where: { $0.id == saved.id }) {
                        workflows[idx] = saved
                    } else {
                        workflows.insert(saved, at: 0)
                    }
                    SharedStore.shared.saveWorkflows(workflows)
                }
            }
            .sheet(isPresented: $showingAddClip) {
                addClipSheet
            }
        }
    }

    // MARK: - Snippets List

    private var snippetsList: some View {
        List {
            Section {
                ForEach(workflows) { workflow in
                    Button {
                        editingWorkflow = workflow
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: workflow.systemImage)
                                .foregroundStyle(workflow.isPinned ? Color.accentColor : Color.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(workflow.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if workflow.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(workflow.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Text(";\(workflow.keyword)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleWorkflowPin(id: workflow.id)
                        } label: {
                            Label(workflow.isPinned ? "Unpin" : "Pin", systemImage: workflow.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete { offsets in
                    workflows.remove(atOffsets: offsets)
                    SharedStore.shared.saveWorkflows(workflows)
                }
            } header: {
                Text("Dynamic Snippets")
            } footer: {
                Text("Pinned snippets appear directly on the keyboard dashboard. Type any keyword in the Alfred palette (e.g. \"intro Alex\") or try inline utilities like \"18% of 240\", \"72f to c\", \"3pm est to cst\", or \"uuid\".")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Clipboard List

    private var clipboardList: some View {
        let pinned = clipboardItems.filter(\.isPinned)
        let recent = clipboardItems.filter { !$0.isPinned }

        return List {
            Section {
                Button {
                    if let text = UIPasteboard.general.string,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        clipboardItems = SharedStore.shared.saveClipboardText(text, pinned: false)
                    }
                } label: {
                    Label("Capture Current Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    showingAddClip = true
                } label: {
                    Label("Create Pinned Clip", systemImage: "pin")
                }
            } footer: {
                Text("Tip: In iOS Settings → KeyDeck → Paste from Other Apps, choose Allow to capture clips without repeated paste banners.")
            }

            if !pinned.isEmpty {
                Section("Pinned Clips") {
                    ForEach(pinned) { item in
                        clipboardRow(item)
                    }
                }
            }

            Section {
                if recent.isEmpty {
                    Text("No recent clips saved yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent) { item in
                        clipboardRow(item)
                    }
                    Button("Clear Recent Clips", role: .destructive) {
                        clipboardItems = SharedStore.shared.clearUnpinnedClipboardItems()
                    }
                }
            } header: {
                Text("Recent Clips")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if item.label != nil {
                Text(item.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                clipboardItems = SharedStore.shared.toggleClipboardPin(id: item.id)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                clipboardItems = SharedStore.shared.deleteClipboardItem(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.text
            }
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                clipboardItems = SharedStore.shared.toggleClipboardPin(id: item.id)
            }
        }
    }

    private var addClipSheet: some View {
        NavigationStack {
            Form {
                Section("Clip Details") {
                    TextField("Optional label (e.g. Work Address)", text: $newClipLabel)
                    TextEditor(text: $newClipText)
                        .frame(minHeight: 110)
                }
            }
            .navigationTitle("New Pinned Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newClipLabel = ""
                        newClipText = ""
                        showingAddClip = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedText = newClipText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedText.isEmpty else { return }
                        clipboardItems = SharedStore.shared.saveClipboardText(
                            trimmedText,
                            label: newClipLabel,
                            pinned: true
                        )
                        newClipLabel = ""
                        newClipText = ""
                        showingAddClip = false
                    }
                    .disabled(newClipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func toggleWorkflowPin(id: UUID) {
        if let idx = workflows.firstIndex(where: { $0.id == id }) {
            workflows[idx].isPinned.toggle()
            SharedStore.shared.saveWorkflows(workflows)
        }
    }
}

private struct SnippetEditorSheet: View {
    let existing: KeyDeckWorkflow?
    let onSave: (KeyDeckWorkflow) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var keyword: String = ""
    @State private var summary: String = ""
    @State private var templateBody: String = ""
    @State private var isPinned: Bool = true
    @State private var requiresInput: Bool = false
    @State private var inputPlaceholder: String = "Value"
    @State private var systemImage: String = "text.badge.plus"

    private let iconOptions = [
        "text.badge.plus", "envelope", "calendar", "calendar.badge.clock",
        "link", "bolt.fill", "text.quote", "terminal", "doc.text", "mappin.and.ellipse"
    ]

    private let tokens = ["{{date}}", "{{time}}", "{{weekday}}", "{{clipboard}}", "{{selection}}", "{{input}}"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name (e.g. Calendar Link)", text: $name)
                    HStack {
                        Text("Keyword")
                        Spacer()
                        TextField("cal", text: $keyword)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Short description", text: $summary)
                    Toggle("Pin to Keyboard Dashboard", isOn: $isPinned)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    systemImage = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.body)
                                        .frame(width: 38, height: 38)
                                        .foregroundStyle(systemImage == icon ? Color.white : Color.primary)
                                        .background(
                                            systemImage == icon ? Color.accentColor : Color(.tertiarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tokens, id: \.self) { token in
                                Button(token) {
                                    templateBody.append(token)
                                    if token == "{{input}}" {
                                        requiresInput = true
                                    }
                                }
                                .font(.caption.monospaced())
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    TextEditor(text: $templateBody)
                        .frame(minHeight: 100)

                    Toggle("Prompt for {{input}} argument", isOn: $requiresInput)
                    if requiresInput {
                        TextField("Argument hint (e.g. Recipient name)", text: $inputPlaceholder)
                    }
                } header: {
                    Text("Template")
                }

                if !templateBody.isEmpty {
                    Section("Live Preview") {
                        Text(
                            SnippetEngine.expandTemplate(
                                templateBody,
                                context: SnippetContext(
                                    argument: inputPlaceholder.isEmpty ? "Alex" : inputPlaceholder,
                                    clipboard: "https://example.com",
                                    selection: "Selected text"
                                )
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSnippet()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || templateBody.isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    keyword = existing.keyword
                    summary = existing.summary
                    isPinned = existing.isPinned
                    systemImage = existing.systemImage
                    templateBody = SnippetEngine.primaryTemplateBody(for: existing) ?? ""
                    if let req = SnippetEngine.requiresArgument(for: existing) {
                        requiresInput = true
                        inputPlaceholder = req.placeholder
                    }
                }
            }
        }
    }

    private func saveSnippet() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKeyword = keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let finalKeyword = cleanKeyword.isEmpty
            ? String(cleanName.lowercased().filter(\.isLetter).prefix(6))
            : cleanKeyword

        var steps: [WorkflowStep] = []
        if requiresInput || templateBody.contains("{{input}}") {
            steps.append(
                WorkflowStep(
                    title: "Argument",
                    kind: .inputArgument(
                        prompt: cleanName,
                        placeholder: inputPlaceholder.isEmpty ? "Value" : inputPlaceholder
                    )
                )
            )
        }
        steps.append(WorkflowStep(title: "Expand Snippet", kind: .template(body: templateBody)))
        steps.append(WorkflowStep(title: "Insert", kind: .outputInsert))

        let saved = KeyDeckWorkflow(
            id: existing?.id ?? UUID(),
            name: cleanName,
            keyword: finalKeyword,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Dynamic snippet (;\(finalKeyword))"
                : summary.trimmingCharacters(in: .whitespacesAndNewlines),
            systemImage: systemImage,
            isPinned: isPinned,
            steps: steps,
            updatedAt: Date()
        )
        onSave(saved)
    }
}
