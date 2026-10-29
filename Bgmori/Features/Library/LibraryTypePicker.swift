import SwiftUI

struct LibraryTypePicker: View {
    @Binding var selection: Int?

    private let types: [Int?] = [nil, 2, 1, 3, 4, 6]

    var body: some View {
        Picker("作品类型", selection: $selection) {
            ForEach(types, id: \.self) { type in
                Text(type.map(SubjectType.title(for:)) ?? "全部")
                    .tag(type)
                    .accessibilityIdentifier("library-type-\(type.map(String.init) ?? "all")")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        // Reserve only the selector's intrinsic height above the summary and results.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("library-types")
    }
}
