import SwiftUI

struct ColorTagOption: Identifiable {
    let id: String
    let name: String
    let color: Color
    
    static let options: [ColorTagOption] = [
        ColorTagOption(id: "red", name: "Red", color: .red),
        ColorTagOption(id: "orange", name: "Orange", color: .orange),
        ColorTagOption(id: "yellow", name: "Yellow", color: .yellow),
        ColorTagOption(id: "green", name: "Green", color: .green),
        ColorTagOption(id: "blue", name: "Blue", color: .blue),
        ColorTagOption(id: "purple", name: "Purple", color: .purple),
        ColorTagOption(id: "gray", name: "Gray", color: .gray)
    ]
    
    static func color(for tag: String?) -> Color? {
        guard let tag = tag else { return nil }
        return options.first(where: { $0.id == tag })?.color
    }
}

struct ColorTagPicker: View {
    @Binding var selectedColor: String?
    let onChange: (String?) -> Void
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: isCompact ? 4 : 8) {
            // Clear button
            Button {
                selectedColor = nil
                onChange(nil)
            } label {
                Image(systemName: selectedColor == nil ? "circle.fill" : "circle")
                    .foregroundColor(selectedColor == nil ? .primary : .gray.opacity(0.3))
                    .font(isCompact ? .caption : .body)
            }
            .buttonStyle(.plain)
            .help("No color")
            
            ForEach(ColorTagOption.options) { option in
                Button {
                    let newColor = selectedColor == option.id ? nil : option.id
                    selectedColor = newColor
                    onChange(newColor)
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: isCompact ? 12 : 16, height: isCompact ? 12 : 16)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            // Show checkmark if selected
                            selectedColor == option.id ?
                            Image(systemName: "checkmark")
                                .font(.system(size: isCompact ? 8 : 10, weight: .bold))
                                .foregroundColor(.white)
                            : nil
                        )
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
        }
    }
}

struct ColorTagIndicator: View {
    let colorTag: String?
    var size: CGFloat = 12
    
    var body: some View {
        if let colorTag = colorTag,
           let color = ColorTagOption.color(for: colorTag) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

// Preview
struct ColorTagPicker_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ColorTagPicker(selectedColor: .constant("red"), onChange: { _ in })
            ColorTagPicker(selectedColor: .constant(nil), onChange: { _ in }, isCompact: true)
            
            HStack {
                ColorTagIndicator(colorTag: "red")
                ColorTagIndicator(colorTag: "blue")
                ColorTagIndicator(colorTag: nil)
            }
        }
        .padding()
    }
}
