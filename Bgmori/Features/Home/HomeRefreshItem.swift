import Foundation

/// Bangumi models use ID-only equality. UI snapshots need content equality as
/// well, so metadata can update without changing the card's stable identity.
struct HomeRefreshItem<Value: Encodable & Identifiable>: Identifiable, Equatable {
    let value: Value
    let revision: Data
    var id: Value.ID { value.id }

    init(_ value: Value) {
        self.value = value
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        revision = (try? encoder.encode(value)) ?? Data(UUID().uuidString.utf8)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision
    }
}
