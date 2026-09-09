// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Written by the installer next to a pack's `.info` file as `macos.json`. Records what the
/// package index knew about the pack at install time, since the pack itself has no region or
/// index-version information.
struct PackSidecar: Codable, Sendable, Equatable {
    static let fileName = "macos.json"

    var indexId: String?
    var indexMajor: Int?
    var indexMinor: Int?
    var ctry2code: String?
    var ctry3code: String?
    var accent: String?
    var installedAt: Date?

    static func load(from directory: URL) -> PackSidecar? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PackSidecar.self, from: data)
    }

    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
