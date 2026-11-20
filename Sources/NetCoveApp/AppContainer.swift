//
//  AppContainer.swift
//  全局依赖容器。无付费墙：features 恒为全开。
//

import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    @Published private(set) var environments: [ViewingEnvironment] = [.home]
    @Published var currentEnvironment: ViewingEnvironment = .home
    @Published var libraries: [Library] = []
    @Published var recent: [MediaItem] = []
    @Published private(set) var isBootstrapping = false

    let features = FeatureAccess()
    let api: APIClient
    let auth: SessionStore
    let store: LibraryStore
    let catalog: CatalogService
    let playbackRouter = EngineRouter()
    @Published var useTunedPreferences: Bool =
        UserDefaults.standard.bool(forKey: "netcove.tuning.useTuned") {
        didSet {
            UserDefaults.standard.set(useTunedPreferences, forKey: "netcove.tuning.useTuned")
            playbackRouter.preferences = useTunedPreferences
                ? EnginePreferences.tuned
                : EnginePreferences.default
        }
    }
    let history: WatchHistoryStore
    let watchlistStore: WatchlistStore

    init() {
        let config = AppConfig()
        self.api = APIClient(config: config)
        self.auth = SessionStore(config: config)
        self.store = LibraryStore()
        self.catalog = CatalogService(api: api)
        self.history = WatchHistoryStore()
        self.watchlistStore = WatchlistStore()
        self.sync = CloudSyncEngine()
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        playbackRouter.preferences = useTunedPreferences
            ? EnginePreferences.tuned
            : EnginePreferences.default
        await auth.restore()
        libraries = await store.load()
        recent = await history.recent(limit: 12)
        if sync.isEnabled {
            sync.startPeriodicSync()
            await sync.syncNow()
        }
    }

    func select(environment: ViewingEnvironment) {
        currentEnvironment = environment
        locks[environment.id]?.lock()
    }

    /// 环境锁（每个环境独立 PIN）
    func lock(for environment: ViewingEnvironment) -> EnvironmentLock {
        if let existing = locks[environment.id] { return existing }
        let created = EnvironmentLock(environmentID: environment.id)
        locks[environment.id] = created
        return created
    }

    var currentLock: EnvironmentLock { lock(for: currentEnvironment) }

    // MARK: - 片单

    func watchlist() async -> [MediaItem] {
        await watchlistStore.all()
    }

    func addToWatchlist(_ item: MediaItem) async {
        await watchlistStore.add(item)
    }

    func removeFromWatchlist(_ item: MediaItem) async {
        await watchlistStore.remove(id: item.id)
    }

    func isInWatchlist(_ item: MediaItem) async -> Bool {
        await watchlistStore.contains(id: item.id)
    }

    func add(_ library: Library) async {
        libraries.append(library)
        await store.save(libraries)
    }

    func remove(_ library: Library) async {
        libraries.removeAll { $0.id == library.id }
        await store.save(libraries)
    }
}
