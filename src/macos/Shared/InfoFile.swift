// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Parser for RHVoice's `key=value` metadata files (voice.info, language.info, locale.info).
/// Mirrors the engine's ini_parser: one pair per line, `;` and `#` start comments, values are
/// trimmed. Numeric character escapes are not needed for the keys the port reads.
struct InfoFile: Sendable {
    let values: [String: String]

    subscript(key: String) -> String? {
        values[key]
    }

    func int(_ key: String) -> Int? {
        values[key].flatMap { Int($0) }
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = values[key]?.lowercased() else { return nil }
        switch raw {
        case "true", "yes", "on", "1": return true
        case "false", "no", "off", "0": return false
        default: return nil
        }
    }

    static func load(_ url: URL) throws -> InfoFile {
        let text = try String(contentsOf: url, encoding: .utf8)
        return parse(text)
    }

    static func parse(_ text: String) -> InfoFile {
        var values: [String: String] = [:]
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("[") {
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                values[key] = value
            }
        }
        return InfoFile(values: values)
    }
}
