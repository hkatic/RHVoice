// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
import ZIPFoundation
@testable import RHVoice

final class PackageExtractorTests: XCTestCase {
    private func makeArchive(entries: [(path: String, content: String)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).zip")
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            let data = Data(entry.content.utf8)
            try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(data.count), provider: { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            })
        }
        return url
    }

    func testZipSlipEntryIsRejected() throws {
        let archive = try makeArchive(entries: [("voice.info", "name=X\n"), ("../evil.txt", "boom")])
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("extract-\(UUID().uuidString)")
        XCTAssertThrowsError(try PackageExtractor.extract(archiveURL: archive, to: destination)) { error in
            guard case ExtractionError.unsafeEntry(let path) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(path, "../evil.txt")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().appendingPathComponent("evil.txt").path))
    }

    func testVersionCheck() throws {
        let archive = try makeArchive(entries: [("voice.info", "name=X\nlanguage=English\nformat=4\nrevision=5\n"), ("24000/voice.data", "data")])
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("extract-\(UUID().uuidString)")
        try PackageExtractor.extract(archiveURL: archive, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("24000/voice.data").path))
        XCTAssertNoThrow(try PackageExtractor.verify(extractedPack: destination, kind: .voice, expected: PackageVersion(major: 4, minor: 5)))
        XCTAssertThrowsError(try PackageExtractor.verify(extractedPack: destination, kind: .voice, expected: PackageVersion(major: 4, minor: 6)))
        XCTAssertThrowsError(try PackageExtractor.verify(extractedPack: destination, kind: .language, expected: PackageVersion(major: 4, minor: 5)))
    }
}
