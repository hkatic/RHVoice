// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Fetches and caches the package index. Serves the cached copy while it is younger than the
/// index's ttl, falls back to the cached copy on network errors, and to the bundled copy when
/// nothing else is available.
actor IndexRepository {
    enum Source: Sendable, Equatable {
        case network, cache, bundled
    }

    struct Result: Sendable {
        let index: PackageIndex
        let source: Source
        let fetchedAt: Date?
        let error: String?
    }

    static let indexURL = URL(string: "https://rhvoice.org/download/packages-1.18.json")!

    private let cacheURL: URL
    private let session: URLSession

    init(cacheURL: URL) {
        self.cacheURL = cacheURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    func load(forceRefresh: Bool) async -> Result {
        let cached = loadCache()
        if !forceRefresh, let cached, cached.isFresh {
            return Result(index: cached.index, source: .cache, fetchedAt: cached.date, error: nil)
        }
        do {
            let index = try await fetch()
            return Result(index: index, source: .network, fetchedAt: Date(), error: nil)
        } catch {
            RHVLog.installer.error("Index download failed: \(error.localizedDescription, privacy: .public)")
            if let cached {
                return Result(index: cached.index, source: .cache, fetchedAt: cached.date, error: error.localizedDescription)
            }
            return Result(index: Self.bundledIndex(), source: .bundled, fetchedAt: nil, error: error.localizedDescription)
        }
    }

    private struct Cached {
        let index: PackageIndex
        let date: Date
        var isFresh: Bool { Date().timeIntervalSince(date) < index.cacheLifetime }
    }

    private func loadCache() -> Cached? {
        guard let data = try? Data(contentsOf: cacheURL),
              let index = try? PackageIndex.decode(data),
              let date = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return nil
        }
        return Cached(index: index, date: date)
    }

    private func fetch() async throws -> PackageIndex {
        var request = URLRequest(url: Self.indexURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let index = try PackageIndex.decode(data) // a malformed index never replaces the cache
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        RHVLog.installer.info("Index downloaded: \(index.languages.count, privacy: .public) languages")
        return index
    }

    static func bundledIndex() -> PackageIndex {
        guard let url = Bundle.main.url(forResource: "packages-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? PackageIndex.decode(data) else {
            return PackageIndex(languages: [], defaultVoices: nil, ttl: nil)
        }
        return index
    }
}
