// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Builds the BCP 47 tags the system uses to group voices.
///
/// Data-only languages ship a locale.info with `language2`/`country2`; the languages compiled
/// into the engine (English, Russian, ...) do not, so their codes are listed here. The engine's
/// own alpha-2 country parsing is wrong for several languages (src/core/voice.cpp), which is
/// why the port never relies on it.
enum LocaleMapping {
    struct Codes: Sendable {
        let language2: String
        let language3: String?
        let region: String?
    }

    /// Languages implemented in C++ (src/core/language.cpp) keyed by the name in language.info.
    static let compiledInLanguages: [String: Codes] = [
        "English": Codes(language2: "en", language3: "eng", region: "US"),
        "Russian": Codes(language2: "ru", language3: "rus", region: "RU"),
        "Esperanto": Codes(language2: "eo", language3: "epo", region: nil),
        "Georgian": Codes(language2: "ka", language3: "kat", region: "GE"),
        "Ukrainian": Codes(language2: "uk", language3: "ukr", region: "UA"),
        "Kyrgyz": Codes(language2: "ky", language3: "kir", region: "KG"),
        "Tatar": Codes(language2: "tt", language3: "tat", region: "RU"),
        "Brazilian-Portuguese": Codes(language2: "pt", language3: "por", region: "BR"),
        "Macedonian": Codes(language2: "mk", language3: "mkd", region: "MK"),
        "Vietnamese": Codes(language2: "vi", language3: "vie", region: "VN"),
    ]

    /// Uppercases and validates a two-letter region code; returns nil for anything else
    /// (the package index contains lowercase and empty values).
    static func normalizedRegion(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              raw.count == 2,
              raw.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            return nil
        }
        return raw
    }

    static func tag(language2: String, region: String?) -> String {
        if let region = normalizedRegion(region) {
            return "\(language2)-\(region)"
        }
        return language2
    }

    /// Whether the system knows this language/region combination as a locale, e.g. en-GB yes,
    /// en-RU no. Used to decide whether a voice's own region is worth exposing.
    static func isKnownLocale(language2: String, region: String) -> Bool {
        let identifier = "\(language2)_\(region)"
        return Locale.availableIdentifiers.contains(identifier)
    }
}
