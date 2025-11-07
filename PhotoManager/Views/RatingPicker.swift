import SwiftUI

struct RatingPicker: View {
    @Binding var rating: Int
    let onChange: (Int) -> Void
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(0..<6) { index in
                Button {
                    // Toggle: clicking same rating sets to 0, clicking higher sets to that rating
                    let newRating = rating == index ? 0 : index
                    rating = newRating
                    onChange(newRating)
                } label: {
                    Image(systemName: index <= rating ? "flag.fill" : "flag")
                        .foregroundColor(index <= rating ? .orange : .gray.opacity(0.4))
                        .font(isCompact ? .caption : .body)
                }
                .buttonStyle(.plain)
                .help("\\(index) flag\\(index == 1 ? "" : "s")")
            }
        }
    }
}

struct RatingPickerLabel: View {
    let rating: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<rating, id: \\.self) { _ in
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            }
        }
    }
}

// Preview
struct RatingPicker_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RatingPicker(rating: .constant(3), onChange: { _ in })
            RatingPicker(rating: .constant(5), onChange: { _ in }, isCompact: true)
            RatingPickerLabel(rating: 4)
        }
        .padding()
    }
}
