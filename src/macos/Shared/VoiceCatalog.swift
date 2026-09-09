// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// A language pack found on disk.
struct InstalledLanguage: Sendable, Identifiable, Equatable {
    /// Directory name (the package index id for packs installed by the app).
    let id: String
    /// Name from language.info, the key voices refer to ("English", "Croatian").
    let name: String
    let format: Int
    let revision: Int
    let language2: String?
    let language3: String?
    let country2: String?
    let directory: URL

    var versionString: String { "\(format).\(revision)" }
}

enum VoiceGender: String, Sendable {
    case unknown, male, female
}

/// A voice pack found on disk, joined with its language pack.
struct InstalledVoice: Sendable, Identifiable, Equatable {
    /// Directory name (the package index id for packs installed by the app).
    let id: String
    /// Name from voice.info; the value the engine selects the voice by ("Alan").
    let name: String
    let languageName: String
    let gender: VoiceGender
    let format: Int
    let revision: Int
    let directory: URL
    let sidecar: PackSidecar?
    let language: InstalledLanguage?

    /// The identifier the extension hands to the system for this voice. The system prefixes it
    /// with the extension's bundle identifier, see `VoiceIdentifiers`.
    var providerIdentifier: String { id }

    /// The identifier under which the system lists this voice (AVSpeechSynthesisVoice.identifier).
    var systemIdentifier: String { VoiceIdentifiers.systemPrefix + id }

    var versionString: String { "\(format).\(revision)" }

    /// "voiceFormat.voiceRevision.languageFormat.languageRevision", like the Android app.
    var fullVersionString: String {
        if let language {
            return "\(format).\(revision).\(language.format).\(language.revision)"
        }
        return versionString
    }

    var language2: String {
        if let code = language?.language2, !code.isEmpty { return code }
        if let compiled = LocaleMapping.compiledInLanguages[languageName] { return compiled.language2 }
        return "und"
    }

    /// Region for the BCP 47 tag: the index's country for this voice when the system knows the
    /// combination, otherwise the language pack's country, otherwise the compiled-in default.
    var region: String? {
        if let own = LocaleMapping.normalizedRegion(sidecar?.ctry2code),
           LocaleMapping.isKnownLocale(language2: language2, region: own) {
            return own
        }
        if let packRegion = LocaleMapping.normalizedRegion(language?.country2) {
            return packRegion
        }
        return LocaleMapping.compiledInLanguages[languageName]?.region
    }

    var bcp47: String { LocaleMapping.tag(language2: language2, region: region) }

    /// Tags the voice is announced for: the specific one plus the bare language.
    var supportedLanguageTags: [String] {
        let primary = bcp47
        return primary == language2 ? [primary] : [primary, language2]
    }

    /// Size of the pack on disk, in bytes.
    func sizeOnDisk() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

/// Reads the installed languages and voices from a data directory without loading the engine.
enum VoiceCatalog {
    struct Snapshot: Sendable {
        var languages: [InstalledLanguage]
        var voices: [InstalledVoice]

        static let empty = Snapshot(languages: [], voices: [])
    }

    static func scan(dataDirectory: URL) -> Snapshot {
        let languages = scanLanguages(dataDirectory.appendingPathComponent("languages", isDirectory: true))
        let byName = Dictionary(languages.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let voices = scanVoices(dataDirectory.appendingPathComponent("voices", isDirectory: true), languagesByName: byName)
        return Snapshot(languages: languages, voices: voices)
    }

    private static func subdirectories(of directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func scanLanguages(_ directory: URL) -> [InstalledLanguage] {
        subdirectories(of: directory).compactMap { dir -> InstalledLanguage? in
            guard let info = try? InfoFile.load(dir.appendingPathComponent("language.info")),
                  let name = info["name"], !name.isEmpty else {
                return nil
            }
            let locale = try? InfoFile.load(dir.appendingPathComponent("locale.info"))
            let compiled = LocaleMapping.compiledInLanguages[name]
            return InstalledLanguage(
                id: dir.lastPathComponent,
                name: name,
                format: info.int("format") ?? 0,
                revision: info.int("revision") ?? 0,
                language2: locale?["language2"] ?? compiled?.language2,
                language3: locale?["language3"] ?? compiled?.language3,
                country2: locale?["country2"] ?? compiled?.region,
                directory: dir)
        }
    }

    private static func scanVoices(_ directory: URL, languagesByName: [String: InstalledLanguage]) -> [InstalledVoice] {
        subdirectories(of: directory).compactMap { dir -> InstalledVoice? in
            guard let info = try? InfoFile.load(dir.appendingPathComponent("voice.info")),
                  let name = info["name"], !name.isEmpty,
                  let languageName = info["language"], !languageName.isEmpty else {
                return nil
            }
            let gender: VoiceGender
            switch info["gender"]?.lowercased() {
            case "male": gender = .male
            case "female": gender = .female
            default: gender = .unknown
            }
            return InstalledVoice(
                id: dir.lastPathComponent,
                name: name,
                languageName: languageName,
                gender: gender,
                format: info.int("format") ?? 0,
                revision: info.int("revision") ?? 0,
                directory: dir,
                sidecar: PackSidecar.load(from: dir),
                language: languagesByName[languageName])
        }
    }
}

/// How voice identifiers relate between the extension and the rest of the system.
///
/// The extension provides bare pack ids ("alan"). The system exposes each voice as
/// "<extension bundle identifier>.<provided identifier>", e.g.
/// "org.rhvoice.RHVoice.Synthesizer.alan".
enum VoiceIdentifiers {
    static let synthesizerBundleSuffix = ".Synthesizer"

    /// Bundle identifier of the synthesizer extension, derived from the running bundle.
    static var synthesizerBundleIdentifier: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "org.rhvoice.RHVoice"
        if bundleId.hasSuffix(synthesizerBundleSuffix) {
            return bundleId // running inside the extension
        }
        return bundleId + synthesizerBundleSuffix
    }

    static var systemPrefix: String { synthesizerBundleIdentifier + "." }

    /// Extracts the pack id from a system identifier, or returns the input unchanged.
    static func packId(fromSystemIdentifier identifier: String) -> String {
        identifier.hasPrefix(systemPrefix) ? String(identifier.dropFirst(systemPrefix.count)) : identifier
    }
}
