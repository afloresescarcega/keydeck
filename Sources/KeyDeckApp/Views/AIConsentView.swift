import SwiftUI
import KeyDeckKit

/// Explicit, in-app disclosure and permission before any data is sent to a third-party AI provider
/// (App Review Guideline 5.1.2(i)). The choice is stored in `KeyDeckSettings.aiDataSharingConsent`
/// and can be revoked at any time from Settings.
struct AIConsentView: View {
    /// When true (already allowed), the sheet is informational: a single Done button that changes nothing.
    var isAlreadyAllowed: Bool = false
    var onDecision: (Bool) -> Void = { _ in /* informational presentation records no decision */ }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised.square.on.square")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("KeyDeck uses third-party AI to turn your voice into text and to edit text. Before anything is sent, here's exactly what happens.")
                        .font(.body)

                    disclosureRow(
                        icon: "waveform",
                        title: "What is sent",
                        detail: "Only when you tap a voice or AI action: your voice recording, the text you ask to edit, your custom dictionary and style instructions, and — only if you turn on Send Surrounding Field Context — text near your cursor. Text from password fields is never read."
                    )
                    disclosureRow(
                        icon: "building.2",
                        title: "Who receives it",
                        detail: "Google (Gemini API) and/or OpenAI, depending on which API key you add and which provider you pick in Settings. Requests go directly from your iPhone to the provider using your own API key. KeyDeck has no server and never sees your data."
                    )
                    disclosureRow(
                        icon: "doc.text.magnifyingglass",
                        title: "How it's handled",
                        detail: "The provider processes your request under its own API terms and privacy policy, which may include temporary retention for abuse monitoring. Review them in your Google or OpenAI account."
                    )
                    disclosureRow(
                        icon: "switch.2",
                        title: "You're in control",
                        detail: "You can turn this off anytime in KeyDeck → Settings → AI Data Sharing. While it's off, KeyDeck makes no AI requests. The calculator, snippets, and clipboard tools keep working."
                    )

                    HStack(spacing: 16) {
                        Link("Google API Terms", destination: KeyDeckConstants.Links.geminiAPITerms)
                        Link("OpenAI Privacy", destination: KeyDeckConstants.Links.openAIPrivacy)
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if isAlreadyAllowed {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            onDecision(true)
                            dismiss()
                        } label: {
                            Text("Allow AI Data Sharing")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Not Now") {
                            onDecision(false)
                            dismiss()
                        }
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("AI Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!isAlreadyAllowed)
    }

    private func disclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
