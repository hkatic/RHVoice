// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

final class DependencyResolverTests: XCTestCase {
    private let english = LanguagePackage(name: "English", version: PackageVersion(major: 2, minor: 17), dataUrl: "https://x/en.zip", lang2code: "en",
                                          voices: [VoicePackage(name: "Alan", version: PackageVersion(major: 4, minor: 0), dataUrl: "https://x/alan.zip")])
    private let kyrgyz = LanguagePackage(name: "Kyrgyz", version: PackageVersion(major: 1, minor: 23), dataUrl: "https://x/ky.zip", lang2code: "ky", pseudoEnglish: true,
                                         voices: [VoicePackage(name: "Azamat", version: PackageVersion(major: 4, minor: 0), dataUrl: "https://x/azamat.zip")])
    private let croatian = LanguagePackage(name: "Croatian", version: PackageVersion(major: 1, minor: 14), dataUrl: "https://x/hr.zip", lang2code: "hr",
                                           voices: [VoicePackage(name: "Karmela", version: PackageVersion(major: 4, minor: 5), dataUrl: "https://x/karmela.zip"),
                                                    VoicePackage(name: "Marija", version: PackageVersion(major: 4, minor: 1), dataUrl: "https://x/marija.zip")])
    private var index: PackageIndex { PackageIndex(languages: [english, kyrgyz, croatian], defaultVoices: nil, ttl: nil) }

    private func installedLanguage(_ name: String, id: String, format: Int, revision: Int) -> InstalledLanguage {
        InstalledLanguage(id: id, name: name, format: format, revision: revision, language2: nil, language3: nil, country2: nil, directory: URL(fileURLWithPath: "/tmp/\(id)"))
    }

    private func installedVoice(_ name: String, id: String, language: InstalledLanguage, format: Int, revision: Int) -> InstalledVoice {
        InstalledVoice(id: id, name: name, languageName: language.name, gender: .female, format: format, revision: revision, directory: URL(fileURLWithPath: "/tmp/\(id)"), sidecar: nil, language: language)
    }

    func testFreshInstallDownloadsLanguageThenVoice() {
        let plan = DependencyResolver.installPlan(voice: croatian.voices[0], language: croatian, index: index, installed: .empty)
        XCTAssertEqual(plan.map(\.id), ["croatian", "karmela"])
        XCTAssertEqual(plan.map(\.kind), [.language, .voice])
    }

    func testPseudoEnglishLanguagePullsEnglishPackFirst() {
        let plan = DependencyResolver.installPlan(voice: kyrgyz.voices[0], language: kyrgyz, index: index, installed: .empty)
        XCTAssertEqual(plan.map(\.id), ["english", "kyrgyz", "azamat"])
    }

    func testSecondVoiceOfInstalledLanguageOnlyDownloadsTheVoice() {
        let hr = installedLanguage("Croatian", id: "croatian", format: 1, revision: 14)
        let installed = VoiceCatalog.Snapshot(languages: [hr], voices: [installedVoice("Karmela", id: "karmela", language: hr, format: 4, revision: 5)])
        let plan = DependencyResolver.installPlan(voice: croatian.voices[1], language: croatian, index: index, installed: installed)
        XCTAssertEqual(plan.map(\.id), ["marija"])
    }

    func testOutdatedLanguagePackIsUpdated() {
        let hr = installedLanguage("Croatian", id: "croatian", format: 1, revision: 12)
        let installed = VoiceCatalog.Snapshot(languages: [hr], voices: [installedVoice("Karmela", id: "karmela", language: hr, format: 4, revision: 5)])
        XCTAssertTrue(DependencyResolver.updateAvailable(voice: croatian.voices[0], language: croatian, installed: installed))
        let plan = DependencyResolver.installPlan(voice: croatian.voices[0], language: croatian, index: index, installed: installed)
        XCTAssertEqual(plan.map(\.id), ["croatian"], "only the language pack is outdated")
    }

    func testUninstallRemovesLanguageOnlyWhenLastVoiceGoes() {
        let hr = installedLanguage("Croatian", id: "croatian", format: 1, revision: 14)
        let karmela = installedVoice("Karmela", id: "karmela", language: hr, format: 4, revision: 5)
        let marija = installedVoice("Marija", id: "marija", language: hr, format: 4, revision: 1)
        let both = VoiceCatalog.Snapshot(languages: [hr], voices: [karmela, marija])
        XCTAssertTrue(DependencyResolver.uninstallPlan(voice: karmela, installed: both).languages.isEmpty)
        let last = VoiceCatalog.Snapshot(languages: [hr], voices: [karmela])
        XCTAssertEqual(DependencyResolver.uninstallPlan(voice: karmela, installed: last).languages.map(\.id), ["croatian"])
    }

    func testEnglishPackIsNeverRemoved() {
        let en = installedLanguage("English", id: "english", format: 2, revision: 17)
        let alan = installedVoice("Alan", id: "alan", language: en, format: 4, revision: 0)
        let installed = VoiceCatalog.Snapshot(languages: [en], voices: [alan])
        XCTAssertTrue(DependencyResolver.uninstallPlan(voice: alan, installed: installed).languages.isEmpty)
    }
}
