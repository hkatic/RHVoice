// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Which packs to download or remove for a voice, following the rules of RHVoice-vm
/// (src/vm/RHVoiceVM/vm.py): a voice needs its language pack, plus the English pack when the
/// language reads English words with English rules; removing the last voice of a language
/// removes the language pack, except English which other languages may depend on.
enum DependencyResolver {
    enum PackKind: Sendable, Equatable {
        case language, voice
    }

    struct Pack: Sendable, Equatable, Identifiable {
        let kind: PackKind
        let id: String
        let name: String
        let version: PackageVersion
        let dataUrl: String
        let dataMd5: String?
        /// Only for voice packs.
        let voice: VoicePackage?
        let language: LanguagePackage

        var descriptor: any PackageDescriptor {
            voice ?? language
        }
    }

    /// Packs to install, in order, so that `voice` of `language` works. Packs already installed
    /// at the index version are skipped; outdated ones are included (updates).
    static func installPlan(voice: VoicePackage, language: LanguagePackage, index: PackageIndex, installed: VoiceCatalog.Snapshot) -> [Pack] {
        var plan: [Pack] = []
        if language.pseudoEnglish == true, !language.isEnglish, let english = index.englishLanguage,
           needsLanguage(english, installed: installed) {
            plan.append(languagePack(english))
        }
        if needsLanguage(language, installed: installed) {
            plan.append(languagePack(language))
        }
        if let installedVoice = installed.voices.first(where: { $0.id == voice.id }),
           installedVoice.format == voice.version.major, installedVoice.revision == voice.version.minor {
            // Voice already current.
        } else {
            plan.append(Pack(kind: .voice, id: voice.id, name: voice.name, version: voice.version, dataUrl: voice.dataUrl, dataMd5: voice.dataMd5, voice: voice, language: language))
        }
        return plan
    }

    /// Whether `voice` (installed) is older than the index, or its language pack is.
    static func updateAvailable(voice: VoicePackage, language: LanguagePackage, installed: VoiceCatalog.Snapshot) -> Bool {
        guard let installedVoice = installed.voices.first(where: { $0.id == voice.id }) else { return false }
        if installedVoice.format < voice.version.major
            || (installedVoice.format == voice.version.major && installedVoice.revision < voice.version.minor) {
            return true
        }
        return needsLanguage(language, installed: installed)
    }

    /// Installed voice directories to remove for `voice`, plus the language pack when no other
    /// installed voice uses it (never English).
    static func uninstallPlan(voice: InstalledVoice, installed: VoiceCatalog.Snapshot) -> (voices: [InstalledVoice], languages: [InstalledLanguage]) {
        var languages: [InstalledLanguage] = []
        if let language = voice.language, language.name != "English" {
            let others = installed.voices.filter { $0.id != voice.id && $0.languageName == language.name }
            if others.isEmpty {
                languages.append(language)
            }
        }
        return ([voice], languages)
    }

    static func needsLanguage(_ language: LanguagePackage, installed: VoiceCatalog.Snapshot) -> Bool {
        guard let existing = installed.languages.first(where: { $0.name == language.name || $0.id == language.id }) else {
            return true
        }
        if existing.format < language.version.major { return true }
        if existing.format == language.version.major && existing.revision < language.version.minor { return true }
        return false
    }

    private static func languagePack(_ language: LanguagePackage) -> Pack {
        Pack(kind: .language, id: language.id, name: language.name, version: language.version, dataUrl: language.dataUrl, dataMd5: language.dataMd5, voice: nil, language: language)
    }
}
