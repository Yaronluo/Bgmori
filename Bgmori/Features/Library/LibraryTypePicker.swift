import SwiftUI

struct LibraryTypePicker: View {
    @Binding var selection: Int?

    private let types: [Int?] = [nil, 2, 1, 3, 4, 6]

    var body: some View {
        #if os(macOS)
        tabs
        #else
        ScrollView(.horizontal) {
            tabs
        }
        .scrollIndicators(.hidden)
        #endif
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(types, id: \.self) { type in
                Button { selection = type } label: {
                    Text(type.map(SubjectType.title(for:)) ?? "全部")
                        .font(.subheadline.weight(selection == type ? .semibold : .regular))
                        .foregroundStyle(selection == type ? Color.brandPink : Color.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        #if os(macOS)
                        .frame(minHeight: 36)
                        #else
                        .frame(minHeight: 44)
                        #endif
                        .overlay(alignment: .bottom) {
                            if selection == type {
                                Capsule()
                                    .fill(Color.brandPink)
                                    .frame(width: 20, height: 2)
                            }
                        }
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
