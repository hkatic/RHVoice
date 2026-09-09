// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

final class PackageIndexTests: XCTestCase {
    func testBundledIndexDecodes() throws {
        let index = IndexRepository.bundledIndex()
        XCTAssertGreaterThanOrEqual(index.languages.count, 20)
        XCTAssertEqual(index.ttl, 86400)
        let english = try XCTUnwrap(index.englishLanguage)
        XCTAssertEqual(english.id, "english")
        XCTAssertTrue(english.voices.contains { $0.id == "alan" })
    }

    func testQuirksAreNormalized() throws {
        let json = """
        {"languages":[{"name":"Polish","lang2code":"PL","version":{"major":1,"minor":20},"dataUrl":"https://x/pl.zip",
          "voices":[{"name":"Alicja","ctry2code":"pl","version":{"major":4,"minor":1},"dataUrl":"https://x//alicja.zip","demoUrl":""},
                    {"name":"Aleksandr-hq","version":{"major":4,"minor":1},"dataUrl":"https://x/a.zip"}]},
         {"name":"Esperanto","lang2code":"eo","version":{"major":1,"minor":3},"dataUrl":"https://x/eo.zip",
          "voices":[{"name":"Spomenka","ctry2code":"","version":{"major":4,"minor":2},"dataUrl":"https://x/s.zip"}]}],
         "unknownKey": 1}
        """
        let index = try PackageIndex.decode(Data(json.utf8))
        let polish = try XCTUnwrap(index.language(withId: "polish"))
        XCTAssertEqual(polish.lang2code, "pl")
        XCTAssertEqual(polish.voices[0].ctry2code, "PL")
        XCTAssertEqual(polish.voices[0].dataUrl, "https://x//alicja.zip", "URLs are used verbatim")
        XCTAssertNil(polish.voices[0].demoURL)
        XCTAssertEqual(polish.voices[1].id, "aleksandr_hq")
        let esperanto = try XCTUnwrap(index.language(withId: "esperanto"))
        XCTAssertNil(esperanto.voices[0].ctry2code)
        XCTAssertNil(index.ttl)
        XCTAssertEqual(index.cacheLifetime, PackageIndex.defaultTTL)
    }

    func testVersionCodeMatchesAndroid() {
        XCTAssertEqual(PackageVersion(major: 4, minor: 5).code, 4050)
        XCTAssertEqual(PackageVersion(major: 1, minor: 23).code, 1230)
        XCTAssertTrue(PackageVersion(major: 4, minor: 5) < PackageVersion(major: 4, minor: 6))
        XCTAssertTrue(PackageVersion(major: 3, minor: 9) < PackageVersion(major: 4, minor: 0))
    }

    func testExpectedMD5DecodesBase64() throws {
        let voice = VoicePackage(name: "X", version: PackageVersion(major: 4, minor: 0), dataUrl: "https://x", dataMd5: "Kt8qf8WHum+Kcbetp4HtZQ==")
        XCTAssertEqual(try XCTUnwrap(voice.expectedMD5).count, 16)
        let none = VoicePackage(name: "Y", version: PackageVersion(major: 4, minor: 0), dataUrl: "https://x", dataMd5: "")
        XCTAssertNil(none.expectedMD5)
    }
}
