import KeyDeckKit
import SwiftUI

struct TweakBarView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: viewModel.undoLastInsertion) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))
                .disabled(viewModel.isTweaking)

                ForEach(TweakAction.allCases) { action in
                    Button {
                        viewModel.applyTweak(action)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                    }
                    .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))
                    .disabled(viewModel.isTweaking)
                }

                if viewModel.isTweaking {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.horizontal, 6)
                }

                Button(action: viewModel.dismissTweakBar) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(KeycapButtonStyle(variant: .chip, cornerRadius: 17))
                .accessibilityLabel("Dismiss tweaks")
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}
