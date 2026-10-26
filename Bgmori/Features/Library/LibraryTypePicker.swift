import SwiftUI

struct LibraryTypePicker: View {
    @Binding var selection: Int?

    private let types: [Int?] = [nil, 2, 1, 3, 4, 6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(types, id: \.self) { type in
                Button { selection = type } label: {
                    Text(type.map(SubjectType.title(for:)) ?? "全部")
                        .font(.subheadline.weight(selection == type ? .semibold : .regular))
                        .foregroundStyle(selection == type ? Color.brandPink : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, 4)
                        .background(selection == type ? Color.brandPink.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == type ? .isSelected : [])
                .accessibilityIdentifier("library-type-\(type.map(String.init) ?? "all")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-types")
    }
}
