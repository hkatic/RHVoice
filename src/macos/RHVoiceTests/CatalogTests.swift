// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

final class CatalogTests: XCTestCase {
    func testInfoFileParsing() {
        let info = InfoFile.parse("""
        ; comment
        name=Alan
        language = English
        gender=male
        format=4
        revision=0
        data_only=true
        """)
        XCTAssertEqual(info["name"], "Alan")
        XCTAssertEqual(info["language"], "English")
        XCTAssertEqual(info.int("format"), 4)
        XCTAssertEqual(info.bool("data_only"), true)
        XCTAssertNil(info["missing"])
    }

    func testRegionNormalization() {
        XCTAssertEqual(LocaleMapping.normalizedRegion("pl"), "PL")
        XCTAssertEqual(LocaleMapping.normalizedRegion(" Cz "), "CZ")
        XCTAssertNil(LocaleMapping.normalizedRegion(""))
        XCTAssertNil(LocaleMapping.normalizedRegion("GBR"))
        XCTAssertNil(LocaleMapping.normalizedRegion(nil))
    }

    func testBCP47ForDataOnlyAndCompiledInLanguages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString)")
        let croatian = root.appendingPathComponent("languages/croatian")
        let english = root.appendingPathComponent("languages/english")
        let karmela = root.appendingPathComponent("voices/karmela")
        let alan = root.appendingPathComponent("voices/alan")
        let dasha = root.appendingPathComponent("voices/dasha_eng")
        for dir in [croatian, english, karmela, alan, dasha] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "name=Croatian\ndata_only=true\nformat=1\nrevision=14\n".write(to: croatian.appendingPathComponent("language.info"), atomically: true, encoding: .utf8)
        try "language2=hr\nlanguage3=hrv\ncountry2=HR\ncountry3=HRV\n".write(to: croatian.appendingPathComponent("locale.info"), atomically: true, encoding: .utf8)
        try "name=English\nformat=2\nrevision=17\n".write(to: english.appendingPathComponent("language.info"), atomically: true, encoding: .utf8)
        try "name=Karmela\nlanguage=Croatian\ngender=female\nformat=4\nrevision=5\n".write(to: karmela.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        try "name=Alan\nlanguage=English\ngender=male\nformat=4\nrevision=0\n".write(to: alan.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        try "name=Dasha-Eng\nlanguage=English\ngender=female\nformat=4\nrevision=2\n".write(to: dasha.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        var alanSidecar = PackSidecar()
        alanSidecar.ctry2code = "GB"
        try alanSidecar.write(to: alan)
        var dashaSidecar = PackSidecar()
        dashaSidecar.ctry2code = "XX" // not a locale the system knows
        try dashaSidecar.write(to: dasha)

        let snapshot = VoiceCatalog.scan(dataDirectory: root)
        XCTAssertEqual(snapshot.languages.map(\.id), ["croatian", "english"])
        let voices = Dictionary(uniqueKeysWithValues: snapshot.voices.map { ($0.id, $0) })
        XCTAssertEqual(voices["karmela"]?.bcp47, "hr-HR")
        XCTAssertEqual(voices["karmela"]?.fullVersionString, "4.5.1.14")
        XCTAssertEqual(voices["alan"]?.bcp47, "en-GB")
        XCTAssertEqual(voices["dasha_eng"]?.bcp47, "en-US", "an unknown region falls back to the language default")
        XCTAssertTrue(LocaleMapping.isKnownLocale(language2: "en", region: "RU"), "the system lists English (Russia), so the index region is honored")
        XCTAssertEqual(voices["alan"]?.supportedLanguageTags, ["en-GB", "en"])
        XCTAssertEqual(voices["alan"]?.systemIdentifier, VoiceIdentifiers.systemPrefix + "alan")
        XCTAssertEqual(voices["alan"]?.gender, .male)
        try? FileManager.default.removeItem(at: root)
    }

    func testSystemIdentifierRoundTrip() {
        let prefix = VoiceIdentifiers.systemPrefix
        XCTAssertTrue(prefix.hasSuffix(".Synthesizer."))
        XCTAssertEqual(VoiceIdentifiers.packId(fromSystemIdentifier: prefix + "alan"), "alan")
        XCTAssertEqual(VoiceIdentifiers.packId(fromSystemIdentifier: "alan"), "alan")
    }
}
