import KeyDeckKit
import SwiftUI

struct KeyboardRootView: View {
    @Bindable var viewModel: KeyboardViewModel

    var body: some View {
        Group {
            if viewModel.isPaletteOpen {
                CommandPaletteView(viewModel: viewModel)
            } else {
                DashboardView(viewModel: viewModel)
            }
        }
        .tint(viewModel.settings.accentColor.keyboardColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension KeyDeckAccentColor {
    var keyboardColor: Color {
        switch self {
        case .blue: .blue
        case .graphite: Color(.label)
        case .teal: .teal
        case .orange: .orange
        case .green: .green
        case .indigo: .indigo
        case .pink: .pink
        }
    }
}
