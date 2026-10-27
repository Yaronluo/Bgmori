import Foundation

@MainActor
protocol LibraryAccountProviding: AnyObject {
    var isLoggedIn: Bool { get }
    var username: String? { get }
}

@MainActor
@Observable
final class LibraryStore {
    private let api: APIClient
    private let auth: any LibraryAccountProviding
    private let snapshots: LibrarySnapshotStore

    private(set) var collections: [Int: UserSubjectCollection] = [:]
    private(set) var episodeTypes: [Int: [Int: Int]] = [:]
    private(set) var loadedUsername: String?
    private(set) var isLoading = false
    var lastError: String?

    private var loadedSource: String?
    private var hasCompleteSnapshot = false
    private var lastReconciliationAt: Date?
    private var accountSwitchID = UUID()
    private var generation = UUID()
    private var loadTask: Task<Bool, Never>?
    private var loadTaskID: UUID?
    private var progressTask: Task<Void, Never>?
    private var episodeTasks: [Int: Task<Void, Never>] = [:]
    private var episodeTaskIDs: [Int: UUID] = [:]

    private let snapshotMaxAge = CacheLifetime.personal
    private let progressHydrationLimit = 12

    init(api: APIClient, auth: any LibraryAccountProviding,
         snapshots: LibrarySnapshotStore = LibrarySnapshotStore()) {
        self.api = api
        self.auth = auth
        self.snapshots = snapshots
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

    /// Restores the account snapshot immediately, then reconciles the whole
    /// library in the background. It never waits for episode progress.
    func loadIfNeeded() async {
        guard auth.isLoggedIn, let username = auth.username else {
            if loadedUsername != nil { reset() }
            return
        }
        if let loadedUsername, loadedUsername != username {
            cancelCurrentLoad(clearMemory: true)
        }
        let source = await api.cacheScope()
        if loadedUsername != username || loadedSource != source {
            await switchAccount(to: username, source: source)
        } else if loadTask == nil, collections.isEmpty || !hasCompleteSnapshot {
            let minimumInterval: TimeInterval = hasCompleteSnapshot ? 300 : 60
            if lastReconciliationAt.map({ Date().timeIntervalSince($0) >= minimumInterval }) ?? true {
                startReconciliation(username: username, source: source, force: false)
            }
        }
    }

    /// Explicit callers (pull to refresh, retry, removal confirmation) can wait
    /// for a complete, atomic reconciliation.
    @discardableResult
    func loadAll(username: String, force: Bool = false) async -> Bool {
        guard auth.isLoggedIn, auth.username == username else { return false }
        if let loadedUsername, loadedUsername != username {
            cancelCurrentLoad(clearMemory: true)
        }
        let source = await api.cacheScope()
        if loadedUsername != username || loadedSource != source {
            await switchAccount(to: username, source: source)
        } else if force, loadTask != nil {
            cancelCurrentLoad(clearMemory: false)
            startReconciliation(username: username, source: source, force: true)
        } else if force {
            startReconciliation(username: username, source: source, force: true)
        } else if loadTask == nil, collections.isEmpty || !hasCompleteSnapshot {
            startReconciliation(username: username, source: source, force: false)
        }

        if let loadTask { return await loadTask.value }
        return loadedUsername == username && lastError == nil
    }

    /// Hydrates one subject's episode progress. Concurrent callers share one
    /// task, so a detail page and the library background pass do not duplicate it.
    func loadEpisodes(subjectID: Int) async {
        guard auth.isLoggedIn, let username = auth.username else { return }
        if let existing = episodeTasks[subjectID] {
            await existing.value
            return
        }
        let generation = self.generation
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchEpisodes(subjectID: subjectID, username: username, generation: generation)
            self.finishEpisodeTask(subjectID: subjectID, id: id)
        }
        episodeTasks[subjectID] = task
        episodeTaskIDs[subjectID] = id
        await task.value
    }

    func save(subject: Subject, patch: CollectionPatch) async throws {
        let generation = self.generation
        let account = auth.username
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
        let previous = collections[subject.id]
        collections[subject.id] = optimistic

        do {
            if isNew {
                try await api.createOrUpdateCollection(subjectID: subject.id, patch: effective)
            } else {
                try await api.patchCollection(subjectID: subject.id, patch: effective)
            }
            guard generation == self.generation, auth.username == account else { return }
            if hasCompleteSnapshot, loadedUsername == auth.username {
                await persistSnapshot()
            } else if auth.isLoggedIn, let username = auth.username {
                if loadTask != nil { cancelCurrentLoad(clearMemory: false) }
                startReconciliation(username: username, source: await api.cacheScope(), force: true)
            }
        } catch {
            if generation == self.generation, auth.username == account {
                collections[subject.id] = previous
            }
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
        let generation = self.generation
        let account = auth.username
        let optimistic = existing.applying(CollectionPatch(type: type.rawValue))
        collections[subjectID] = optimistic
        do {
            try await api.patchCollection(subjectID: subjectID, patch: CollectionPatch(type: type.rawValue))
            guard generation == self.generation, auth.username == account else { return }
            await persistSnapshot()
        } catch {
            if generation == self.generation, auth.username == account {
                collections[subjectID] = existing
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setEpisode(subject: Subject, episode: Episode, type: Int) async {
        guard auth.isLoggedIn, let username = auth.username else {
            lastError = "请先登录 Bangumi"
            return
        }
        let oldType = episodeTypes[subject.id]?[episode.id] ?? 0
        guard oldType != type else { return }
        let generation = self.generation
        let account = username

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
            guard generation == self.generation, auth.username == account else { return }
            await persistSnapshot()
        } catch {
            guard generation == self.generation, auth.username == account else {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
            if let map = episodeTypes[subject.id] {
                var reverted = map
                reverted[episode.id] = oldType
                episodeTypes[subject.id] = reverted
            }
            collections[subject.id] = oldCollection
            if let actual = await reconcileProgress(subjectID: subject.id, username: username, after: error) {
                if actual[episode.id] == type { return }
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setProgress(subject: Subject, episodes: [Episode], watchedCount: Int) async {
        guard auth.isLoggedIn, let username = auth.username else {
            lastError = "请先登录 Bangumi"
            return
        }
        let mainEpisodes = episodes.filter { $0.type == 0 }.sorted { $0.sort < $1.sort }
        guard !mainEpisodes.isEmpty else { return }
        let target = min(max(0, watchedCount), mainEpisodes.count)
        let current = episodeTypes[subject.id] ?? [:]
        let generation = self.generation
        let account = username

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
            guard generation == self.generation, auth.username == account else { return }
            await persistSnapshot()
        } catch {
            guard generation == self.generation, auth.username == account else {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
            episodeTypes[subject.id] = current
            collections[subject.id] = oldCollection
            if let actual = await reconcileProgress(subjectID: subject.id, username: username, after: error),
               toDone.allSatisfy({ actual[$0] == EpisodeCollectionType.done.rawValue }),
               toNone.allSatisfy({ (actual[$0] ?? 0) == EpisodeCollectionType.none.rawValue }) { return }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Read back an ambiguous write; never repeat the mutation itself.
    private func reconcileProgress(subjectID: Int, username: String, after error: Error) async -> [Int: Int]? {
        let generation = self.generation
        guard !Task.isCancelled, let failure = error as? APIError, failure.isUncertainWrite,
              let page = try? await api.episodeCollections(subjectID: subjectID, username: username, force: true) else { return nil }
        var actual: [Int: Int] = [:]
        for item in page.data {
            if let episode = item.episode { actual[episode.id] = item.type }
        }
        guard generation == self.generation, auth.username == username else { return nil }
        episodeTypes[subjectID] = actual
        if let collection = try? await api.userCollection(username, subjectID: subjectID, force: true) {
            guard generation == self.generation, auth.username == username else { return nil }
            collections[subjectID] = collection
        }
        await persistSnapshot()
        return actual
    }

    func clearSnapshot() async {
        guard let username = loadedUsername ?? auth.username else { return }
        await snapshots.clear(username: username)
    }

    func reset() {
        cancelCurrentLoad(clearMemory: true)
        progressTask?.cancel()
        progressTask = nil
        for task in episodeTasks.values { task.cancel() }
        episodeTasks.removeAll()
        episodeTaskIDs.removeAll()
        loadedUsername = nil
        loadedSource = nil
    }

    // MARK: - Account lifecycle

    private func switchAccount(to username: String, source: String) async {
        let switchID = UUID()
        cancelCurrentLoad(clearMemory: true, invalidateSwitch: false)
        accountSwitchID = switchID
        loadedSource = source
        let snapshot = await snapshots.read(username: username, source: source, maxAge: snapshotMaxAge)
        guard accountSwitchID == switchID else { return }
        if let snapshot {
            apply(snapshot)
            loadedUsername = username
            hasCompleteSnapshot = true
            isLoading = false
        } else {
            loadedUsername = username
            hasCompleteSnapshot = false
            isLoading = true
        }
        startReconciliation(username: username, source: source, force: true)
    }

    private func cancelCurrentLoad(clearMemory: Bool, invalidateSwitch: Bool = true) {
        if invalidateSwitch { accountSwitchID = UUID() }
        generation = UUID()
        progressTask?.cancel()
        progressTask = nil
        for task in episodeTasks.values { task.cancel() }
        episodeTasks.removeAll()
        episodeTaskIDs.removeAll()
        loadTask?.cancel()
        loadTask = nil
        loadTaskID = nil
        isLoading = false
        if clearMemory {
            hasCompleteSnapshot = false
            lastReconciliationAt = nil
            collections.removeAll()
            episodeTypes.removeAll()
            loadedUsername = nil
            loadedSource = nil
            lastError = nil
        }
    }

    private func startReconciliation(username: String, source: String, force: Bool) {
        if loadTask != nil { return }
        lastReconciliationAt = Date()
        let generation = self.generation
        let id = UUID()
        isLoading = collections.isEmpty && loadedUsername == username && !hasCompleteSnapshot
        lastError = nil
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            let result = await self.performReconciliation(username: username, source: source,
                                                          force: force, generation: generation)
            self.finishLoad(id: id)
            return result
        }
        loadTask = task
        loadTaskID = id
    }

    private func finishLoad(id: UUID) {
        guard loadTaskID == id else { return }
        loadTask = nil
        loadTaskID = nil
        isLoading = false
    }

    private func performReconciliation(username: String, source: String,
                                       force: Bool, generation: UUID) async -> Bool {
        guard auth.username == username else { return false }
        do {
            var result: [Int: UserSubjectCollection] = [:]
            var offset = 0
            var total = Int.max
            while offset < total {
                try Task.checkCancellation()
                let page = try await api.userCollections(username, limit: 50, offset: offset, force: force)
                try Task.checkCancellation()
                guard generation == self.generation, auth.username == username else { return false }
                total = page.total
                for item in page.data { result[item.subjectId] = item }
                offset += page.data.count
                if page.data.isEmpty { break }
            }
            guard generation == self.generation, auth.username == username else { return false }
            // Replace the visible library only after every page succeeded.
            collections = result
            episodeTypes = episodeTypes.filter { result[$0.key] != nil }
            loadedUsername = username
            loadedSource = source
            hasCompleteSnapshot = true
            lastError = nil
            isLoading = false
            await persistSnapshot()
            startProgressHydration(username: username, generation: generation)
            return true
        } catch {
            guard generation == self.generation else { return false }
            if Task.isCancelled || Self.isCancellation(error) { return false }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
            return false
        }
    }

    private func startProgressHydration(username: String, generation: UUID) {
        let ids = watching.prefix(progressHydrationLimit).map(\.subjectId)
        guard !ids.isEmpty else { return }
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            guard let self else { return }
            for id in ids {
                guard !Task.isCancelled, generation == self.generation else { return }
                await self.loadEpisodes(subjectID: id)
            }
        }
    }

    private func fetchEpisodes(subjectID: Int, username: String, generation: UUID) async {
        guard generation == self.generation, auth.username == username else { return }
        if let hit = await api.cachedEpisodeCollections(subjectID: subjectID, username: username) {
            guard generation == self.generation, auth.username == username else { return }
            applyProgress(hit.value, subjectID: subjectID)
            if hit.isFresh { return }
            guard await api.beginBackgroundRefresh(hit.cacheKey, minimumInterval: 60) else { return }
        }
        do {
            let page = try await api.episodeCollections(subjectID: subjectID, username: username)
            guard generation == self.generation, auth.username == username, !Task.isCancelled else { return }
            applyProgress(page, subjectID: subjectID)
            await persistSnapshot()
        } catch {
            // Episode progress is secondary; cached progress remains visible.
        }
    }

    private func applyProgress(_ page: Paged<EpisodeCollection>, subjectID: Int) {
        var map: [Int: Int] = [:]
        for item in page.data {
            if let episode = item.episode { map[episode.id] = item.type }
        }
        episodeTypes[subjectID] = map
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        collections = Dictionary(snapshot.collections.map { ($0.subjectId, $0) },
                                 uniquingKeysWith: { _, latest in latest })
        var progress: [Int: [Int: Int]] = [:]
        for item in snapshot.progress {
            progress[item.subjectID, default: [:]][item.episodeID] = item.type
        }
        episodeTypes = progress
    }

    private func persistSnapshot() async {
        guard hasCompleteSnapshot, loadedUsername == auth.username,
              let username = loadedUsername, let source = loadedSource else { return }
        let progress = episodeTypes
            .filter { collections[$0.key] != nil }
            .flatMap { subjectID, map in
                map.map { LibraryEpisodeProgress(subjectID: subjectID, episodeID: $0.key, type: $0.value) }
            }
        let snapshot = LibrarySnapshot(
            version: LibrarySnapshot.version,
            username: username,
            source: source,
            savedAt: Date(),
            collections: Array(collections.values),
            progress: progress
        )
        await snapshots.write(snapshot)
    }

    private func finishEpisodeTask(subjectID: Int, id: UUID) {
        guard episodeTaskIDs[subjectID] == id else { return }
        episodeTasks[subjectID] = nil
        episodeTaskIDs[subjectID] = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let api = error as? APIError, case .cancelled = api { return true }
        return false
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
