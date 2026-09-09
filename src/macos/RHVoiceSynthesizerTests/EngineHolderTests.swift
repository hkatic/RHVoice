// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import XCTest

final class EngineHolderTests: XCTestCase {
    private func layout() throws -> DataLayout {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let layout = DataLayout(root: root)
        try layout.ensureDirectories()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return layout
    }

    private func addVoice(_ name: String, layout: DataLayout) throws {
        let directory = layout.voiceDirectory(id: name.lowercased())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "name=\(name)\nlanguage=English\nformat=4\nrevision=0\n".write(to: directory.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
    }

    func testCatalogDetectsInstallationsInTheSameSecond() throws {
        let layout = try layout()
        let holder = EngineHolder(layout: layout)
        try addVoice("Alan", layout: layout)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1700000000.1)], ofItemAtPath: layout.voices.path)
        XCTAssertEqual(holder.catalog().voices.map(\.name), ["Alan"])
        try addVoice("BDL", layout: layout)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1700000000.2)], ofItemAtPath: layout.voices.path)
        XCTAssertEqual(holder.catalog().voices.map(\.name), ["Alan", "BDL"])
    }

    func testExplicitInvalidationRefreshesCachedMetadataAndSize() throws {
        let layout = try layout()
        let holder = EngineHolder(layout: layout)
        try addVoice("Alan", layout: layout)
        let voice = try XCTUnwrap(holder.catalog().voices.first)
        let size = holder.sizeOnDisk(of: voice)
        try Data(repeating: 1, count: 4096).write(to: voice.directory.appendingPathComponent("model.data"))
        XCTAssertEqual(holder.sizeOnDisk(of: voice), size)
        holder.invalidate()
        let updated = try XCTUnwrap(holder.catalog().voices.first)
        XCTAssertEqual(holder.sizeOnDisk(of: updated), size + 4096)
    }

    func testConfigurationAndDictionaryEditsReloadEngineWithinOneSecond() throws {
        let layout = try layout()
        // Engine creation reads metadata lazily; no voice models are needed here.
        let english = layout.languageDirectory(id: "english")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try "name=English\nformat=2\nrevision=17\n".write(to: english.appendingPathComponent("language.info"), atomically: true, encoding: .utf8)
        let holder = EngineHolder(layout: layout)
        try "; first config\n".write(to: layout.configFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1700000000.1)], ofItemAtPath: layout.configFile.path)
        let first = try holder.engine()
        XCTAssertTrue(try holder.engine() === first)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1700000000.2)], ofItemAtPath: layout.configFile.path)
        let second = try holder.engine()
        XCTAssertFalse(second === first)
        let dictionary = layout.dicts.appendingPathComponent("example.txt")
        try "; dictionary\n".write(to: dictionary, atomically: true, encoding: .utf8)
        let third = try holder.engine()
        XCTAssertFalse(third === second)
        XCTAssertTrue(try holder.engine() === third)
    }
}
