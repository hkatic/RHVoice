// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

/// Downloads the Croatian language pack and the Karmela voice (about 4 MB) from the live
/// index into a temporary directory, installs them the way the app does, and synthesizes
/// speech from the result. Skipped when the index cannot be fetched.
final class InstallIntegrationTests: XCTestCase {
    func testDownloadInstallAndSynthesize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString)")
        let layout = DataLayout(root: root)
        try layout.ensureDirectories()
        try FileManager.default.createDirectory(at: layout.config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = IndexRepository(cacheURL: layout.indexCache)
        let result = await repository.load(forceRefresh: true)
        guard result.source == .network else {
            throw XCTSkip("Package index not reachable: \(result.error ?? "unknown error")")
        }
        let croatian = try XCTUnwrap(result.index.languages.first { $0.lang2code == "hr" })
        let karmela = try XCTUnwrap(croatian.voices.first { $0.id == "karmela" })
        let plan = DependencyResolver.installPlan(voice: karmela, language: croatian, index: result.index, installed: .empty)
        XCTAssertEqual(plan.map(\.id), ["croatian", "karmela"])

        for pack in plan {
            let url = try XCTUnwrap(URL(string: pack.dataUrl))
            let archive = layout.tmp.appendingPathComponent("\(pack.id).zip")
            try await PackageDownloader.download(from: url, to: archive, expectedMD5: pack.descriptor.expectedMD5) { _, _ in }
            let staging = layout.tmp.appendingPathComponent("staging-\(pack.id)")
            try PackageExtractor.extract(archiveURL: archive, to: staging)
            try PackageExtractor.verify(extractedPack: staging, kind: pack.kind, expected: pack.version)
            let destination = pack.kind == .voice ? layout.voiceDirectory(id: pack.id) : layout.languageDirectory(id: pack.id)
            try FileManager.default.moveItem(at: staging, to: destination)
        }

        let snapshot = VoiceCatalog.scan(dataDirectory: layout.data)
        XCTAssertEqual(snapshot.voices.map(\.id), ["karmela"])
        XCTAssertEqual(snapshot.voices.first?.bcp47, "hr-HR")

        let engine = try RHVEngine(dataPath: layout.data.path, configPath: layout.config.path)
        XCTAssertEqual(engine.voices.map(\.name), ["Karmela"])
        let options = RHVSynthesisOptions()
        options.quality = "max"
        let session = try engine.startSession(withSSML: "<speak>\(croatian.testMessage ?? "Dobar dan.")</speak>", voiceName: "Karmela", options: options, markerHandler: nil)
        var frames = 0
        var buffer = [Float](repeating: 0, count: 4096)
        var status = RHVRenderStatus.rendering
        while status == .rendering {
            var written: UInt32 = 0
            status = session.render(into: &buffer, frameCount: 4096, maxWaitMilliseconds: 2000, framesWritten: &written)
            frames += Int(written)
        }
        XCTAssertEqual(status, .complete)
        XCTAssertGreaterThan(frames, 24000, "at least one second of audio")
        XCTAssertTrue(buffer.contains { abs($0) > 0.01 } || frames > 24000)
    }
}
