// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// The package index served at https://rhvoice.org/download/packages-1.18.json, the same file
/// the Android app and RHVoice-vm use. Schema: src/include/core/package_client.hpp and the
/// Android TtsResource/LanguageResource/VoiceResource classes. Unknown keys are ignored.
struct PackageIndex: Codable, Sendable, Equatable {
    var languages: [LanguagePackage]
    var defaultVoices: [String: [String: String]]?
    /// Seconds the index may be cached (86400 on the live server).
    var ttl: Int?

    static let defaultTTL: TimeInterval = 86400

    var cacheLifetime: TimeInterval {
        ttl.map(TimeInterval.init) ?? Self.defaultTTL
    }

    func language(withId id: String) -> LanguagePackage? {
        languages.first { $0.id == id }
    }

    func language(forVoiceId voiceId: String) -> LanguagePackage? {
        languages.first { $0.voices.contains { $0.id == voiceId } }
    }

    var englishLanguage: LanguagePackage? {
        languages.first { $0.lang2code.lowercased() == "en" }
    }
}

struct PackageVersion: Codable, Sendable, Equatable, Comparable, CustomStringConvertible {
    var major: Int
    var minor: Int

    /// The comparable code the Android app stores (1000 * format + 10 * revision).
    var code: Int { 1000 * major + 10 * minor }

    var description: String { "\(major).\(minor)" }

    static func < (lhs: PackageVersion, rhs: PackageVersion) -> Bool {
        lhs.code < rhs.code
    }
}

/// Fields shared by language and voice packages.
protocol PackageDescriptor: Sendable {
    var name: String { get }
    var id: String { get }
    var version: PackageVersion { get }
    var dataUrl: String { get }
    var dataMd5: String? { get }
}

extension PackageDescriptor {
    var downloadURL: URL? { URL(string: dataUrl) }

    /// The base64-encoded MD5 digest from the index, decoded.
    var expectedMD5: Data? {
        guard let dataMd5, !dataMd5.isEmpty else { return nil }
        return Data(base64Encoded: dataMd5)
    }
}

/// Default id rule shared by the C++ and Java clients: lowercase name with "-" replaced by "_".
func defaultPackageId(forName name: String) -> String {
    name.lowercased().replacingOccurrences(of: "-", with: "_")
}

struct LanguagePackage: Codable, Sendable, Equatable, Identifiable, PackageDescriptor {
    var name: String
    var id: String
    var version: PackageVersion
    var dataUrl: String
    var dataMd5: String?
    var lang2code: String
    var lang3code: String?
    var testMessage: String?
    var pseudoEnglish: Bool?
    var voices: [VoicePackage]

    private enum CodingKeys: String, CodingKey {
        case name, id, version, dataUrl, dataMd5, lang2code, lang3code, testMessage, pseudoEnglish, voices
    }

    init(name: String, id: String? = nil, version: PackageVersion, dataUrl: String, dataMd5: String? = nil,
         lang2code: String, lang3code: String? = nil, testMessage: String? = nil, pseudoEnglish: Bool? = nil,
         voices: [VoicePackage] = []) {
        self.name = name
        self.id = id ?? defaultPackageId(forName: name)
        self.version = version
        self.dataUrl = dataUrl
        self.dataMd5 = dataMd5
        self.lang2code = lang2code
        self.lang3code = lang3code
        self.testMessage = testMessage
        self.pseudoEnglish = pseudoEnglish
        self.voices = voices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        self.init(
            name: name,
            id: try container.decodeIfPresent(String.self, forKey: .id),
            version: try container.decode(PackageVersion.self, forKey: .version),
            dataUrl: try container.decode(String.self, forKey: .dataUrl),
            dataMd5: try container.decodeIfPresent(String.self, forKey: .dataMd5),
            lang2code: try container.decode(String.self, forKey: .lang2code).lowercased(),
            lang3code: try container.decodeIfPresent(String.self, forKey: .lang3code)?.lowercased(),
            testMessage: try container.decodeIfPresent(String.self, forKey: .testMessage),
            pseudoEnglish: try container.decodeIfPresent(Bool.self, forKey: .pseudoEnglish),
            voices: try container.decodeIfPresent([VoicePackage].self, forKey: .voices) ?? [])
    }

    /// Name shown to the user: the system's localized language name when it knows the code.
    var localizedName: String {
        if let localized = Locale.current.localizedString(forLanguageCode: lang2code), !localized.isEmpty {
            return localized.prefix(1).uppercased() + localized.dropFirst()
        }
        return name
    }

    var isEnglish: Bool { lang2code == "en" }
}

struct VoicePackage: Codable, Sendable, Equatable, Identifiable, PackageDescriptor {
    var name: String
    var id: String
    var version: PackageVersion
    var dataUrl: String
    var dataMd5: String?
    var ctry2code: String?
    var ctry3code: String?
    var accent: String?
    var demoUrl: String?

    private enum CodingKeys: String, CodingKey {
        case name, id, version, dataUrl, dataMd5, ctry2code, ctry3code, accent, demoUrl
    }

    init(name: String, id: String? = nil, version: PackageVersion, dataUrl: String, dataMd5: String? = nil,
         ctry2code: String? = nil, ctry3code: String? = nil, accent: String? = nil, demoUrl: String? = nil) {
        self.name = name
        self.id = id ?? defaultPackageId(forName: name)
        self.version = version
        self.dataUrl = dataUrl
        self.dataMd5 = dataMd5
        self.ctry2code = LocaleMapping.normalizedRegion(ctry2code)
        self.ctry3code = ctry3code?.uppercased()
        self.accent = accent?.isEmpty == false ? accent : nil
        self.demoUrl = demoUrl?.isEmpty == false ? demoUrl : nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            id: try container.decodeIfPresent(String.self, forKey: .id),
            version: try container.decode(PackageVersion.self, forKey: .version),
            dataUrl: try container.decode(String.self, forKey: .dataUrl),
            dataMd5: try container.decodeIfPresent(String.self, forKey: .dataMd5),
            ctry2code: try container.decodeIfPresent(String.self, forKey: .ctry2code),
            ctry3code: try container.decodeIfPresent(String.self, forKey: .ctry3code),
            accent: try container.decodeIfPresent(String.self, forKey: .accent),
            demoUrl: try container.decodeIfPresent(String.self, forKey: .demoUrl))
    }

    var demoURL: URL? { demoUrl.flatMap { URL(string: $0) } }
}

extension PackageIndex {
    static func decode(_ data: Data) throws -> PackageIndex {
        try JSONDecoder().decode(PackageIndex.self, from: data)
    }
}
