import SwiftUI

/// Letter keyboard that types directly into the host text field.
/// Needs neither Full Access nor network, so KeyDeck always works as a keyboard (Guideline 4.4.1).
struct TypingView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button(action: viewModel.closeTypingMode) {
                    Label("KeyDeck", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
                .accessibilityLabel("Back to KeyDeck dashboard")

                Spacer()

                if viewModel.needsGlobeKey {
                    Button(action: viewModel.tapGlobe) {
                        Image(systemName: "globe")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 34)
                    }
                    .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 9))
                    .accessibilityLabel("Next keyboard")
                }
            }

            MiniQWERTYView(
                onCharacter: viewModel.typeCharacter,
                onBackspace: viewModel.typeBackspace,
                onReturn: viewModel.typeReturn,
                returnLabel: "return"
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}
