import SwiftUI

/// Compact built-in tactile mini-QWERTY dedicated purely to Alfred palette queries,
/// math expressions, unit/timezone conversions, and snippet fill-in arguments.
struct MiniQWERTYView: View {
    let onCharacter: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void
    var returnLabel: String = "Insert"

    @State private var isNumbersMode: Bool = false
    @State private var isShifted: Bool = false

    private let alphaRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    private let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["+", "-", "*", "/", "(", ")", "%", "=", ":", "."],
        [";", "@", "#", "$", "_", "&", "?"]
    ]

    private let keyHeight: CGFloat = 37

    var body: some View {
        VStack(spacing: 6) {
            let rows = isNumbersMode ? numberRows : alphaRows

            // Row 1 (10 keys)
            HStack(spacing: 4) {
                ForEach(rows[0], id: \.self) { key in
                    characterKey(key)
                }
            }

            // Row 2 (9 or 10 keys)
            HStack(spacing: 4) {
                ForEach(rows[1], id: \.self) { key in
                    characterKey(key)
                }
            }
            .padding(.horizontal, isNumbersMode ? 0 : 14)

            // Row 3 (Shift/Mode + 7 keys + Backspace)
            HStack(spacing: 4) {
                Button {
                    if isNumbersMode {
                        isNumbersMode = false
                    } else {
                        isShifted.toggle()
                    }
                } label: {
                    Group {
                        if isNumbersMode {
                            Text("ABC")
                                .font(.caption.weight(.semibold))
                        } else {
                            Image(systemName: isShifted ? "shift.fill" : "shift")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .foregroundStyle(isShifted && !isNumbersMode ? Color.accentColor : Color.primary)
                    .frame(width: 42, height: keyHeight)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 7))

                ForEach(rows[2], id: \.self) { key in
                    characterKey(key)
                }

                Button(action: onBackspace) {
                    Image(systemName: "delete.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: keyHeight)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 7))
            }

            // Row 4 (123/ABC + Space + Return)
            HStack(spacing: 6) {
                Button {
                    isNumbersMode.toggle()
                    isShifted = false
                } label: {
                    Text(isNumbersMode ? "ABC" : "123")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 62, height: keyHeight)
                }
                .buttonStyle(KeycapButtonStyle(variant: .secondary, cornerRadius: 8))

                Button {
                    onCharacter(" ")
                } label: {
                    Text("space")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: keyHeight)
                }
                .buttonStyle(KeycapButtonStyle(variant: .primary, cornerRadius: 8))

                Button(action: onReturn) {
                    Text(returnLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 74)
                        .frame(height: keyHeight)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func characterKey(_ raw: String) -> some View {
        let display = (!isNumbersMode && isShifted) ? raw.uppercased() : raw
        return Button {
            onCharacter(display)
            if isShifted && !isNumbersMode {
                isShifted = false
            }
        } label: {
            Text(display)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
        }
        .buttonStyle(KeycapButtonStyle(variant: .primary, cornerRadius: 7))
    }
}
