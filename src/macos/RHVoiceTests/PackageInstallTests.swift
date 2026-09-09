// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

final class PackageInstallTests: XCTestCase {
    @MainActor
    func testFailedReplacementRestoresInstalledVoice() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let installed = root.appendingPathComponent("installed")
        let trash = root.appendingPathComponent("tmp")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        try "original voice".write(to: installed.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AppModel.replaceDirectory(at: installed, with: root.appendingPathComponent("missing-update"), trash: trash))
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("voice.info"), encoding: .utf8), "original voice")
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: trash.path).isEmpty)
    }
}
