import KeyDeckKit
import SwiftUI

struct CommandPaletteView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 6) {
            searchInputBar
            resultsArea
            MiniQWERTYView(
                onCharacter: viewModel.paletteInsertCharacter,
                onBackspace: viewModel.paletteBackspace,
                onReturn: viewModel.paletteExecuteTopResult,
                returnLabel: returnButtonLabel
            )
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Search Input & Filter Row

    private var searchInputBar: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.closePalette) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
            .accessibilityLabel("Back to dashboard")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if viewModel.paletteQuery.isEmpty {
                    Text("Type math, snippet, or clip…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 1) {
                        Text(viewModel.paletteQuery)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 1.5, height: 15)
                    }
                }

                Spacer(minLength: 0)

                if !viewModel.paletteQuery.isEmpty {
                    Button(action: viewModel.paletteClearQuery) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }

            if viewModel.paletteQuery.isEmpty {
                filterMenuButton
            }

            if viewModel.needsGlobeKey {
                Button(action: viewModel.tapGlobe) {
                    Image(systemName: "globe")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
                .accessibilityLabel("Next keyboard")
            }
        }
    }

    private var filterMenuButton: some View {
        HStack(spacing: 4) {
            ForEach(PaletteFilter.allCases) { filter in
                let selected = viewModel.paletteFilter == filter
                Button {
                    viewModel.setPaletteFilter(filter)
                } label: {
                    Text(filter.label)
                        .font(.caption2.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(
                            selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemFill)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Live Ranked Results

    private var resultsArea: some View {
        let results = viewModel.paletteResults
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
                if viewModel.paletteFilter == .clipboard {
                    Button {
                        viewModel.captureCurrentClipboard(pin: false)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                            Text("Save Current Clipboard")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                    }
                    .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 9))
                }

                if results.isEmpty {
                    HStack {
                        Text("No matches — try \"18% of 240\", \"72f to c\", \"uuid\", or \"intro Alex\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                } else {
                    ForEach(Array(results.prefix(12).enumerated()), id: \.element.id) { index, item in
                        resultRow(item, isTop: index == 0)
                    }
                }
            }
        }
        .frame(height: 112)
    }

    private func resultRow(_ item: PaletteSearchResult, isTop: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.executePaletteResult(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isTop ? Color.accentColor : Color.secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let badge = item.badge {
                        Text(badge)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }

                    if isTop {
                        Image(systemName: "return")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(KeycapButtonStyle(variant: isTop ? .primary : .chip, cornerRadius: 9))

            if let clipID = item.clipboardItemID {
                Button {
                    viewModel.toggleClipboardPin(id: clipID)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(item.isPinned ? Color.orange : Color.secondary)
                        .frame(width: 32, height: 42)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
                .accessibilityLabel(item.isPinned ? "Unpin clip" : "Pin clip")
            }
        }
    }

    private var returnButtonLabel: String {
        guard let first = viewModel.paletteResults.first else { return "Insert" }
        switch first.action {
        case .promptForArgument: return "Next"
        case .triggerVoice: return "Speak"
        case .killMic: return "Kill"
        case .insertText, .runWorkflow: return "Insert"
        }
    }
}
