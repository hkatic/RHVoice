// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

/// Downloads one Ogg Vorbis demo (rhvoice.org) and one MP3 demo (GitHub) from the live index
/// and decodes both. Skipped when the index cannot be fetched.
final class DemoDecoderTests: XCTestCase {
    func testOggAndMp3DemosDecode() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("demos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        let repository = IndexRepository(cacheURL: cache.appendingPathComponent("packages.json"))
        let result = await repository.load(forceRefresh: true)
        guard result.source == .network else {
            throw XCTSkip("Package index not reachable")
        }
        let voices = result.index.languages.flatMap(\.voices)
        let ogg = try XCTUnwrap(voices.first { $0.demoUrl?.hasSuffix(".ogg") == true })
        let mp3 = try XCTUnwrap(voices.first { $0.demoUrl?.hasSuffix(".mp3") == true })
        for voice in [ogg, mp3] {
            let file = try await DemoDecoder.cachedDemo(for: voice.id, url: try XCTUnwrap(voice.demoURL), cacheDirectory: cache)
            let buffer = try await DemoDecoder.decode(file)
            XCTAssertGreaterThan(buffer.frameLength, 8000, "\(voice.name): at least a fraction of a second of audio")
            XCTAssertGreaterThan(buffer.format.sampleRate, 8000)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
            XCTAssertTrue(samples.contains { abs($0) > 0.05 }, "\(voice.name): decoded audio is not silent")
        }
    }
}
