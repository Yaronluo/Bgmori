import Foundation
import Observation

/// Lightweight snapshot of a subject the user opened, kept locally for the
/// search landing page. It intentionally stores only display data so the
/// history stays useful offline and never blocks on the API.
struct RecentSubject: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let type: Int
    let coverURLString: String?
    let nsfw: Bool
    let viewedAt: Date

    init(subject: Subject, viewedAt: Date = .now) {
        id = subject.id
        title = subject.displayTitle
        type = subject.type
        coverURLString = subject.coverURL?.absoluteString
        nsfw = subject.nsfw
        self.viewedAt = viewedAt
    }

    var coverURL: URL? { Images.normalized(coverURLString) }
    var typeName: String { SubjectType.title(for: type) }
}

@MainActor
@Observable
final class RecentSubjectsStore {
    private(set) var subjects: [RecentSubject] = []

    private let defaults: UserDefaults
    private let storageKey = "recentSubjects"
    private let limit = 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentSubject].self, from: data) else {
            return
        }
        subjects = Array(decoded.prefix(limit))
    }

    func record(_ subject: Subject) {
        guard subject.id > 0 else { return }
        subjects.removeAll { $0.id == subject.id }
        subjects.insert(RecentSubject(subject: subject), at: 0)
        if subjects.count > limit {
            subjects.removeLast(subjects.count - limit)
        }
        persist()
    }

    func clear() {
        subjects.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(subjects) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
