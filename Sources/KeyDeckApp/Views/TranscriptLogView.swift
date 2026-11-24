import SwiftUI
import KeyDeckKit

struct TranscriptLogView: View {
    @Bindable var sessionManager: VoiceSessionManager

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.transcriptLog.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "waveform",
                        description: Text("Recordings are saved here locally before processing so you never lose a ramble if your connection drops.")
                    )
                } else {
                    List {
                        ForEach(sessionManager.transcriptLog) { entry in
                            TranscriptRow(
                                entry: entry,
                                onRetry: {
                                    Task { await sessionManager.retryEntry(entry) }
                                },
                                onCopy: {
                                    if let text = entry.outputText ?? entry.rawTranscript {
                                        UIPasteboard.general.string = text
                                    }
                                }
                            )
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                sessionManager.deleteEntry(sessionManager.transcriptLog[index])
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .onAppear {
                sessionManager.reloadTranscriptLog()
            }
        }
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let onRetry: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.mode.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if entry.durationSeconds > 0 {
                    Text("· \(String(format: "%.1fs", entry.durationSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                statusIcon
                Text(entry.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let output = entry.outputText, !output.isEmpty {
                Text(output)
                    .font(.body)
                    .lineLimit(5)
                if entry.status == .failed, let error = entry.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if let error = entry.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text("Processing audio…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let raw = entry.rawTranscript, raw != entry.outputText {
                Text(raw)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if entry.outputText != nil {
                Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                    .tint(.blue)
            }
        }
        .contextMenu {
            if entry.outputText != nil {
                Button("Copy Output", systemImage: "doc.on.doc", action: onCopy)
            }
            if entry.audioFilename != nil {
                Button(
                    entry.status == .failed ? "Retry Processing" : "Re-run AI",
                    systemImage: "arrow.clockwise",
                    action: onRetry
                )
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .processing:
            ProgressView()
                .controlSize(.mini)
        }
    }
}
