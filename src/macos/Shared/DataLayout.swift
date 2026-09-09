// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

enum DataLayoutError: Error, LocalizedError {
    case noAppGroupContainer(String)

    var errorDescription: String? {
        switch self {
        case .noAppGroupContainer(let group):
            return "The app group container for \(group) is not available."
        }
    }
}

/// Where everything lives inside the shared app-group container:
///
///     <container>/Library/Application Support/RHVoice/
///         data/languages/<id>/      language packs (engine data_path = data/)
///         data/voices/<id>/         voice packs
///         config/RHVoice.conf       optional user configuration (engine config_path = config/)
///         config/dicts/<Language>/  user dictionaries
///         cache/packages.json       cached package index
///         cache/demos/              downloaded demo clips
///         tmp/                      downloads and extraction in progress
struct DataLayout: Sendable {
    /// Shared-preferences key: when set, the engine loads data from this directory instead of
    /// data/. Development aid only; the extension cannot read outside its sandbox, so the
    /// directory must be inside the container anyway.
    static let devDataPathKey = "RHVoiceDevDataPath"

    let root: URL

    var data: URL { root.appendingPathComponent("data", isDirectory: true) }
    var languages: URL { data.appendingPathComponent("languages", isDirectory: true) }
    var voices: URL { data.appendingPathComponent("voices", isDirectory: true) }
    var config: URL { root.appendingPathComponent("config", isDirectory: true) }
    var dicts: URL { config.appendingPathComponent("dicts", isDirectory: true) }
    var configFile: URL { config.appendingPathComponent("RHVoice.conf", isDirectory: false) }
    var cache: URL { root.appendingPathComponent("cache", isDirectory: true) }
    var demos: URL { cache.appendingPathComponent("demos", isDirectory: true) }
    var indexCache: URL { cache.appendingPathComponent("packages.json", isDirectory: false) }
    var tmp: URL { root.appendingPathComponent("tmp", isDirectory: true) }

    /// The directory handed to the engine as data_path.
    var engineDataPath: URL {
        if let path = AppGroup.sharedDefaults.string(forKey: Self.devDataPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return data
    }

    func languageDirectory(id: String) -> URL {
        languages.appendingPathComponent(id, isDirectory: true)
    }

    func voiceDirectory(id: String) -> URL {
        voices.appendingPathComponent(id, isDirectory: true)
    }

    /// The layout inside the app-group container. Creates the directories if needed.
    static func inAppGroup() throws -> DataLayout {
        guard let container = AppGroup.containerURL() else {
            throw DataLayoutError.noAppGroupContainer(AppGroup.identifier)
        }
        let root = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("RHVoice", isDirectory: true)
        let layout = DataLayout(root: root)
        try layout.ensureDirectories()
        return layout
    }

    func ensureDirectories() throws {
        let fm = FileManager.default
        for directory in [languages, voices, dicts, demos, tmp] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
