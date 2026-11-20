//
//  LibraryStore.swift
//  媒体库持久化 + 扫描分发。原 App 用 WCDB + CloudKit；这里给文件持久化，
//  接口保持 actor，替换成 WCDB 只需改实现。
//

import Foundation

protocol LibraryPersisting {
    func load() async -> [Library]
    func save(_ libraries: [Library]) async
    func delete(id: UUID) async
}

actor LibraryStore: LibraryPersisting {
    private var cache: [Library] = []
    private var itemsByLibrary: [UUID: [MediaItem]] = [:]
    private let persistence: NetCovePersistence

    init(persistence: NetCovePersistence = PersistenceFactory.make()) {
        self.persistence = persistence
    }

    func load() async -> [Library] {
        if cache.isEmpty {
            cache = await persistence.readLibraries()
        }
        return cache
    }

    func save(_ libraries: [Library]) async {
        cache = libraries
        await persistence.writeLibraries(libraries)
    }

    func delete(id: UUID) async {
        cache.removeAll { $0.id == id }
        itemsByLibrary[id] = nil
        await persistence.writeLibraries(cache)
    }

    func items(in libraryID: UUID) async -> [MediaItem] {
        if let cached = itemsByLibrary[libraryID] { return cached }
        let loaded = await persistence.readItems(libraryID: libraryID)
        itemsByLibrary[libraryID] = loaded
        return loaded
    }

    // MARK: - 扫描

    @discardableResult
    func scan(_ library: Library, credentials: LibraryCredentials?) async throws -> [MediaItem] {
        let items: [MediaItem]
        switch library.sourceType {
        case .jellyfin, .emby:
            items = try await scanEmbyFamily(library, credentials: credentials)
        case .plex:
            items = try await scanPlex(library, credentials: credentials)
        case .smb:
            items = try await scanSMB(library, credentials: credentials)
        case .webdav, .webdavs:
            items = try await scanWebDAV(library, credentials: credentials)
        case .local, .strm:
            items = try scanLocal(library)
        case .pan115, .ugreen, .guangya:
            items = try await scanCloudDrive(library, credentials: credentials)
        }

        itemsByLibrary[library.id] = items
        await persistence.writeItems(items, libraryID: library.id)
        if let index = cache.firstIndex(where: { $0.id == library.id }) {
            cache[index].itemCount = items.count
            cache[index].lastScanAt = Date()
            await persistence.writeLibraries(cache)
        }
        return items
    }

    // MARK: - 各源实现

    private func scanEmbyFamily(_ library: Library,
                                credentials: LibraryCredentials?) async throws -> [MediaItem] {
        guard let credentials, let serverURL = library.serverURL else {
            throw ProviderError.notConfigured("Jellyfin/Emby credentials")
        }
        let family: EmbyFamilyClient.Family = library.sourceType == .jellyfin ? .jellyfin : .emby
        let client = EmbyFamilyClient(family: family, baseURL: serverURL,
                                      userName: credentials.userName, password: credentials.password)
        let auth = try await client.authenticate()
        let raw = try await client.fetchItems(token: auth.accessToken, userID: auth.user.id)

        return raw.map { item in
            let kind: MediaItem.Kind = item.type == "Series" ? .series : .movie
            return MediaItem(
                sourceID: item.id,
                libraryID: library.id,
                title: item.name,
                originalTitle: nil,
                year: item.productionYear,
                kind: kind,
                overview: item.overview,
                posterURL: client.imageURL(itemID: item.id, tag: item.imageTags?["Primary"]),
                backdropURL: client.imageURL(itemID: item.id, tag: item.imageTags?["Backdrop"],
                                             kind: "Backdrop", width: 1280),
                runtimeSeconds: item.runTimeTicks.map { Int($0 / 10_000_000) },
                genres: item.genres ?? [],
                rating: item.communityRating,
                parentID: item.seriesId,
                indexNumber: item.indexNumber,
                seasonNumber: item.parentIndexNumber
            )
        }
    }

    private func scanPlex(_ library: Library,
                          credentials: LibraryCredentials?) async throws -> [MediaItem] {
        guard let credentials, let serverURL = library.serverURL else {
            throw ProviderError.notConfigured("Plex token")
        }
        let client = PlexClient(baseURL: serverURL, token: credentials.password)
        let sections = try await client.sections()
        var items: [MediaItem] = []
        for section in sections where section.type == "movie" || section.type == "show" {
            let raw = try await client.items(sectionKey: section.key)
            items += raw.map { entry in
                MediaItem(
                    sourceID: entry.ratingKey,
                    libraryID: library.id,
                    title: entry.title,
                    originalTitle: nil,
                    year: entry.year,
                    kind: entry.type == "show" ? .series : .movie,
                    overview: entry.summary,
                    posterURL: client.imageURL(path: entry.thumb),
                    backdropURL: client.imageURL(path: entry.art, width: 1280),
                    runtimeSeconds: entry.duration.map { $0 / 1000 },
                    indexNumber: entry.index,
                    seasonNumber: entry.parentIndex
                )
            }
        }
        return items
    }

    private func scanSMB(_ library: Library,
                         credentials: LibraryCredentials?) async throws -> [MediaItem] {
        guard let serverURL = library.serverURL else {
            throw ProviderError.notConfigured("SMB server URL")
        }
        let client = SMBClient(serverURL: serverURL,
                               domain: "",
                               user: credentials?.userName ?? "",
                               password: credentials?.password ?? "")
        try await client.connect()
        let listing = try await client.list("/")
        let fileScanner = FileScanner()
        return listing
            .filter { !$0.isDirectory && fileScanner.videoExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
            .map { entry in
                let guess = ScrapePipeline.guess(fileName: entry.name)
                return MediaItem(sourceID: entry.name,
                                 libraryID: library.id,
                                 title: guess.title,
                                 year: guess.year,
                                 kind: guess.season == nil ? .movie : .episode,
                                 indexNumber: guess.episode,
                                 seasonNumber: guess.season)
            }
    }

    private func scanWebDAV(_ library: Library,
                            credentials: LibraryCredentials?) async throws -> [MediaItem] {
        guard let serverURL = library.serverURL else {
            throw ProviderError.notConfigured("WebDAV URL")
        }
        let client = WebDAVClient(baseURL: serverURL,
                                  userName: credentials?.userName,
                                  password: credentials?.password)
        let entries = try await client.list()
        let fileScanner = FileScanner()
        return entries
            .filter { !$0.isDirectory && fileScanner.videoExtensions.contains($0.href.pathExtension.lowercased()) }
            .map { entry in
                let guess = ScrapePipeline.guess(fileName: entry.href.lastPathComponent)
                return MediaItem(sourceID: entry.href.absoluteString,
                                 libraryID: library.id,
                                 title: guess.title,
                                 year: guess.year,
                                 kind: guess.season == nil ? .movie : .episode,
                                 indexNumber: guess.episode,
                                 seasonNumber: guess.season)
            }
    }

    private func scanLocal(_ library: Library) throws -> [MediaItem] {
        guard let root = library.serverURL else { throw ProviderError.notConfigured("Folder path") }
        var scanner = FileScanner()
        scanner.skipPaths = library.skipPaths
        let files = try scanner.scan(root: root)

        return files.map { file in
            let isStrm = file.url.pathExtension.lowercased() == "strm"
            if isStrm, let resolved = try? scanner.resolveStrm(file.url) {
                let guess = ScrapePipeline.guess(fileName: file.url.lastPathComponent)
                return MediaItem(sourceID: resolved.absoluteString,
                                 libraryID: library.id,
                                 title: guess.title,
                                 year: guess.year,
                                 kind: guess.season == nil ? .movie : .episode,
                                 indexNumber: guess.episode,
                                 seasonNumber: guess.season)
            }
            let guess = ScrapePipeline.guess(fileName: file.url.lastPathComponent)
            return MediaItem(sourceID: file.url.absoluteString,
                             libraryID: library.id,
                             title: guess.title,
                             year: guess.year,
                             kind: guess.season == nil ? .movie : .episode,
                             indexNumber: guess.episode,
                             seasonNumber: guess.season)
        }
    }

    private func scanCloudDrive(_ library: Library,
                                credentials: LibraryCredentials?) async throws -> [MediaItem] {
        let provider = CloudDriveRegistry.make(for: library.sourceType)
        let token = try await provider.authenticate(credentials: credentials)
        let rootPath = library.serverURL?.absoluteString ?? "0"
        let entries = try await provider.list(path: rootPath, token: token)

        let scanner = FileScanner()
        return entries
            .filter { !$0.isDirectory && scanner.videoExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
            .map { entry in
                let guess = ScrapePipeline.guess(fileName: entry.name)
                return MediaItem(sourceID: entry.id,
                                 libraryID: library.id,
                                 title: guess.title,
                                 year: guess.year,
                                 kind: guess.season == nil ? .movie : .episode,
                                 indexNumber: guess.episode,
                                 seasonNumber: guess.season)
            }
    }

}

struct LibraryCredentials {
    var userName: String
    var password: String
}
