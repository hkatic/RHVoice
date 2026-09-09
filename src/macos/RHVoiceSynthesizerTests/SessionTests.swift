// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import XCTest

final class SessionTests: XCTestCase {
    private final class ReleaseProbe: @unchecked Sendable {
        let expectation: XCTestExpectation
        init(_ expectation: XCTestExpectation) { self.expectation = expectation }
        deinit { expectation.fulfill() }
    }

    static func engine() throws -> RHVEngine {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = root.appendingPathComponent("data")
        guard FileManager.default.fileExists(atPath: data.appendingPathComponent("voices/alan/voice.info").path) else {
            throw XCTSkip("Initialize the Alan voice and English language submodules for synthesis tests")
        }
        return try RHVEngine(dataPath: data.path, configPath: root.appendingPathComponent("config").path)
    }

    func testAbandonedSessionReleasesWorkerAndMarkerHandler() throws {
        let engine = try Self.engine()
        let released = expectation(description: "abandoned worker released its marker handler")
        try autoreleasepool {
            let probe = ReleaseProbe(released)
            // Longer than the queue's 5.5 seconds, so an uncancelled worker cannot
            // finish when nobody consumes its audio.
            let text = String(repeating: "This request is abandoned while the voice is speaking. ", count: 12)
            let session = try engine.startSession(withSSML: "<speak>\(text)</speak>", voiceName: "Alan", options: nil,
                                                  markerHandler: { [probe] _, _, _, _, _ in
                withExtendedLifetime(probe) { }
            })
            XCTAssertNotNil(session)
        }
        wait(for: [released], timeout: 3)
    }

    func testCancelledSessionsFinishAndDoNotReturnAudio() throws {
        let engine = try Self.engine()
        for _ in 0..<30 {
            let session = try engine.startSession(withSSML: "<speak>Cancelled navigation announcement.</speak>", voiceName: "Alan", options: nil, markerHandler: nil)
            session.cancel()
            session.waitUntilFinished()
            var buffer = [Float](repeating: 0, count: 512)
            var written: UInt32 = 999
            XCTAssertEqual(session.render(into: &buffer, frameCount: 512, maxWaitMilliseconds: RHVRenderWaitForever, framesWritten: &written), .cancelled)
            XCTAssertEqual(written, 0)
        }
    }

    func testInvalidOutputRateIsRejected() throws {
        let engine = try Self.engine()
        for rate in [0.0, -1.0, Double.nan, Double.infinity] {
            let options = RHVSynthesisOptions()
            options.outputSampleRate = rate
            XCTAssertThrowsError(try engine.startSession(withSSML: "<speak>Hello</speak>", voiceName: "Alan", options: options, markerHandler: nil))
        }
    }
}
