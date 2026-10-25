import Foundation

@MainActor
@Observable
final class LibraryStore {
    private let api: APIClient
    private let auth: AuthManager

    private(set) var collections: [Int: UserSubjectCollection] = [:]
    private(set) var episodeTypes: [Int: [Int: Int]] = [:]
    private(set) var loadedUsername: String?
    private(set) var isLoading = false
    var lastError: String?

    init(api: APIClient, auth: AuthManager) {
        self.api = api
        self.auth = auth
    }

    var sortedCollections: [UserSubjectCollection] {
        collections.values.sorted {
            ($0.updatedAt ?? "") > ($1.updatedAt ?? "")
        }
    }

    var watching: [UserSubjectCollection] {
        sortedCollections.filter { $0.type == CollectionType.doing.rawValue }
    }

    var counts: [CollectionType: Int] {
        Dictionary(grouping: collections.values, by: \.collectionType).mapValues(\.count)
    }

    func collection(for subjectID: Int) -> UserSubjectCollection? {
        collections[subjectID]
    }

    func isWatching(_ subjectID: Int) -> Bool {
        collections[subjectID]?.type == CollectionType.doing.rawValue
    }

    func watchedCount(for subjectID: Int) -> Int {
        if let map = episodeTypes[subjectID] {
            return map.values.filter { $0 == EpisodeCollectionType.done.rawValue }.count
        }
        return collections[subjectID]?.epStatus ?? 0
    }

    func episodeType(_ episodeID: Int, subjectID: Int) -> Int {
        episodeTypes[subjectID]?[episodeID] ?? 0
    }

    func loadIfNeeded() async {
        guard auth.isLoggedIn, let username = auth.username else { return }
        if loadedUsername != username {
            await loadAll(username: username, force: true)
        } else if collections.isEmpty {
            await loadAll(username: username, force: false)
        }
    }

    func loadAll(username: String, force: Bool = false) async {
        if isLoading { return }
        if !force, loadedUsername == username, !collections.isEmpty { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            var result: [Int: UserSubjectCollection] = [:]
            var offset = 0
            var total = Int.max
            while offset < total {
                let page = try await api.userCollections(username, limit: 50, offset: offset)
                total = page.total
                for item in page.data { result[item.subjectId] = item }
                offset += page.data.count
                if page.data.isEmpty { break }
            }
            collections = result
            loadedUsername = username
            // Hydrate progress for currently watching shows in the background.
            let ids = watching.prefix(12).map(\.subjectId)
            for id in ids {
                await loadEpisodes(subjectID: id)
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadEpisodes(subjectID: Int) async {
        guard auth.isLoggedIn else { return }
        do {
            let page = try await api.episodeCollections(subjectID: subjectID)
            var map: [Int: Int] = [:]
            for item in page.data {
                if let episode = item.episode { map[episode.id] = item.type }
            }
            episodeTypes[subjectID] = map
        } catch {
            // Progress is optional for browsing; do not surface a blocking error.
        }
    }

    func save(subject: Subject, patch: CollectionPatch) async throws {
        let existing = collections[subject.id]
        let isNew = existing == nil

        var effective = patch
        if isNew, effective.type == nil { effective.type = CollectionType.wish.rawValue }

        let optimistic: UserSubjectCollection
        if let existing {
            optimistic = existing.applying(effective)
        } else {
            optimistic = UserSubjectCollection(
                subjectId: subject.id,
                subjectType: subject.type,
                rate: effective.rate ?? 0,
                type: effective.type ?? CollectionType.wish.rawValue,
                comment: effective.comment,
                tags: effective.tags ?? [],
                epStatus: effective.epStatus ?? 0,
                volStatus: effective.volStatus ?? 0,
                updatedAt: nil,
                isPrivate: effective.isPrivate ?? false,
                subject: SubjectSummary(subject: subject)
            )
        }
        collections[subject.id] = optimistic

        do {
            if isNew {
                try await api.createOrUpdateCollection(subjectID: subject.id, patch: effective)
            } else {
                try await api.patchCollection(subjectID: subject.id, patch: effective)
            }
        } catch {
            collections[subject.id] = existing
            throw error
        }
    }

    func quickSet(subject: Subject, type: CollectionType) async {
        do {
            try await save(subject: subject, patch: CollectionPatch(type: type.rawValue))
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setType(subjectID: Int, type: CollectionType) async {
        guard let existing = collections[subjectID] else { return }
        let optimistic = existing.applying(CollectionPatch(type: type.rawValue))
        collections[subjectID] = optimistic
        do {
            try await api.patchCollection(subjectID: subjectID, patch: CollectionPatch(type: type.rawValue))
        } catch {
            collections[subjectID] = existing
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setEpisode(subject: Subject, episode: Episode, type: Int) async {
        guard auth.isLoggedIn else {
            lastError = "请先登录 Bangumi"
            return
        }
        let oldType = episodeTypes[subject.id]?[episode.id] ?? 0
        guard oldType != type else { return }

        var map = episodeTypes[subject.id] ?? [:]
        map[episode.id] = type
        episodeTypes[subject.id] = map

        let oldCollection = collections[subject.id]
        if var collection = oldCollection {
            let delta = (type == EpisodeCollectionType.done.rawValue ? 1 : 0) - (oldType == EpisodeCollectionType.done.rawValue ? 1 : 0)
            collection = copy(collection, epStatus: max(0, collection.epStatus + delta))
            collections[subject.id] = collection
        }

        do {
            try await api.updateEpisode(episodeID: episode.id, type: type)
        } catch {
            if let map = episodeTypes[subject.id] {
                var reverted = map
                reverted[episode.id] = oldType
                episodeTypes[subject.id] = reverted
            }
            collections[subject.id] = oldCollection
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setProgress(subject: Subject, episodes: [Episode], watchedCount: Int) async {
        guard auth.isLoggedIn else {
            lastError = "请先登录 Bangumi"
            return
        }
        let mainEpisodes = episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
        guard !mainEpisodes.isEmpty else { return }
        let target = min(max(0, watchedCount), mainEpisodes.count)
        let current = episodeTypes[subject.id] ?? [:]

        let toDone = mainEpisodes.prefix(target).map(\.id).filter { (current[$0] ?? 0) != EpisodeCollectionType.done.rawValue }
        let toNone = mainEpisodes.dropFirst(target).map(\.id).filter { (current[$0] ?? 0) == EpisodeCollectionType.done.rawValue }

        var optimistic = current
        for id in toDone { optimistic[id] = EpisodeCollectionType.done.rawValue }
        for id in toNone { optimistic[id] = EpisodeCollectionType.none.rawValue }
        episodeTypes[subject.id] = optimistic

        let oldCollection = collections[subject.id]
        if let collection = oldCollection {
            collections[subject.id] = copy(collection, epStatus: target)
        }

        do {
            if !toDone.isEmpty {
                try await api.batchUpdateEpisodes(subjectID: subject.id, episodeIDs: toDone, type: EpisodeCollectionType.done.rawValue)
            }
            if !toNone.isEmpty {
                try await api.batchUpdateEpisodes(subjectID: subject.id, episodeIDs: toNone, type: EpisodeCollectionType.none.rawValue)
            }
        } catch {
            episodeTypes[subject.id] = current
            collections[subject.id] = oldCollection
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reset() {
        collections.removeAll()
        episodeTypes.removeAll()
        loadedUsername = nil
        lastError = nil
    }

    private func copy(_ collection: UserSubjectCollection, epStatus: Int? = nil, volStatus: Int? = nil) -> UserSubjectCollection {
        UserSubjectCollection(
            subjectId: collection.subjectId,
            subjectType: collection.subjectType,
            rate: collection.rate,
            type: collection.type,
            comment: collection.comment,
            tags: collection.tags,
            epStatus: epStatus ?? collection.epStatus,
            volStatus: volStatus ?? collection.volStatus,
            updatedAt: collection.updatedAt,
            isPrivate: collection.isPrivate,
            subject: collection.subject
        )
    }
}
