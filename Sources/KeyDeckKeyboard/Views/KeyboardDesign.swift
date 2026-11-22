import SwiftUI

/// Tactile iOS keycap button style modeled after Apple's native keyboard surfaces:
/// adaptive Light/Dark keycap fill, hairline border, subtle 1pt bottom key lip,
/// and responsive press-down physics.
struct KeycapButtonStyle: ButtonStyle {
    enum Variant {
        case primary        // Elevated white / dark-elevated keycap (letter/action keys)
        case secondary      // Utility keycap (backspace, return, subtle actions)
        case destructive    // Crisp red confirmation / kill keycap
        case chip           // Compact capsule chip (tweak bar)
    }

    var variant: Variant = .primary
    var cornerRadius: CGFloat = 11

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .opacity(isEnabled ? 1.0 : 0.42)
            .background {
                shape
                    .fill(backgroundColor(pressed: configuration.isPressed))
                    .overlay {
                        shape.strokeBorder(borderColor, lineWidth: 0.5)
                    }
                    .shadow(
                        color: shadowColor,
                        radius: configuration.isPressed ? 0 : 0.5,
                        x: 0,
                        y: configuration.isPressed ? 0 : 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.78), value: configuration.isPressed)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch variant {
        case .primary:
            if colorScheme == .dark {
                return Color(white: pressed ? 0.34 : 0.27)
            } else {
                return pressed ? Color(white: 0.91) : Color(.systemBackground)
            }
        case .secondary:
            if colorScheme == .dark {
                return Color(white: pressed ? 0.26 : 0.19)
            } else {
                return pressed ? Color(white: 0.80) : Color(.secondarySystemFill)
            }
        case .destructive:
            return pressed ? Color.red.opacity(0.85) : Color.red
        case .chip:
            if colorScheme == .dark {
                return Color(white: pressed ? 0.30 : 0.22)
            } else {
                return pressed ? Color(white: 0.86) : Color(.systemBackground).opacity(0.88)
            }
        }
    }

    private var borderColor: Color {
        switch variant {
        case .destructive:
            return Color.white.opacity(0.15)
        default:
            return colorScheme == .dark
                ? Color.white.opacity(0.09)
                : Color.black.opacity(0.06)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .destructive:
            return Color.red.opacity(0.28)
        default:
            return colorScheme == .dark
                ? Color.black.opacity(0.45)
                : Color.black.opacity(0.16)
        }
    }
}

/// Live 7-bar reactive waveform driven by normalized audio RMS level (0...1).
struct LiveWaveformView: View {
    let level: Float
    var tint: Color = .red

    private let weights: [CGFloat] = [0.42, 0.74, 0.96, 1.0, 0.88, 0.64, 0.38]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<weights.count, id: \.self) { index in
                let clamped = CGFloat(max(0.08, min(1.0, level)))
                let barHeight = max(5, 22 * clamped * weights[index])
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: barHeight)
            }
        }
        .frame(height: 24)
        .animation(.spring(response: 0.14, dampingFraction: 0.72), value: level)
    }
}
