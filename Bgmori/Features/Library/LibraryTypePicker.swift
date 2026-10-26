import SwiftUI

struct LibraryTypePicker: View {
    @Binding var selection: Int?

    private let types: [Int?] = [nil, 2, 1, 3, 4, 6]

    var body: some View {
        TextTabs(values: types, selection: $selection, title: { type in
            type.map(SubjectType.title(for:)) ?? "全部"
        }, horizontalPadding: 11)
        .accessibilityIdentifier("library-types")
    }
}
