// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import ZIPFoundation

enum ExtractionError: Error, LocalizedError {
    case unsafeEntry(String)
    case missingInfoFile(String)
    case versionMismatch(expected: PackageVersion, found: String)

    var errorDescription: String? {
        switch self {
        case .unsafeEntry(let path): return "The archive contains an unsafe entry: \(path)"
        case .missingInfoFile(let name): return "The archive does not contain \(name)."
        case .versionMismatch(let expected, let found): return "The pack version (\(found)) does not match the index (\(expected))."
        }
    }
}

/// Unpacks a pack archive into a fresh directory and checks that it is the pack the index
/// promised. Archive entries are validated against path traversal (Zip-Slip), which the
/// Android implementation does not do.
enum PackageExtractor {
    /// Extracts `archiveURL` into `destination` (created, must not exist).
    static func extract(archiveURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let archive = try Archive(url: archiveURL, accessMode: .read)
        for entry in archive {
            let path = entry.path
            guard !path.hasPrefix("/"), !path.contains("\\"),
                  !path.split(separator: "/").contains(where: { $0 == ".." }) else {
                throw ExtractionError.unsafeEntry(path)
            }
            switch entry.type {
            case .symlink:
                throw ExtractionError.unsafeEntry(path)
            case .directory:
                let target = destination.appendingPathComponent(path, isDirectory: true)
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            case .file:
                let target = destination.appendingPathComponent(path, isDirectory: false)
                let resolved = target.standardizedFileURL.path
                guard resolved.hasPrefix(root + "/") else {
                    throw ExtractionError.unsafeEntry(path)
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: target, skipCRC32: false)
            }
            try Task.checkCancellation()
        }
    }

    /// Reads `<kind>.info` from an extracted pack and checks format/revision against the index.
    @discardableResult
    static func verify(extractedPack directory: URL, kind: DependencyResolver.PackKind, expected: PackageVersion) throws -> InfoFile {
        let fileName = kind == .voice ? "voice.info" : "language.info"
        let url = directory.appendingPathComponent(fileName)
        guard let info = try? InfoFile.load(url) else {
            throw ExtractionError.missingInfoFile(fileName)
        }
        let format = info.int("format") ?? 0
        let revision = info.int("revision") ?? 0
        let found = PackageVersion(major: format, minor: revision)
        guard found.code == expected.code else {
            throw ExtractionError.versionMismatch(expected: expected, found: found.description)
        }
        return info
    }
}
