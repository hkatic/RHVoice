// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

enum SpeechQuality: String, CaseIterable, Sendable {
    case max
    case standard
    case min

    /// The value the engine's "quality" setting accepts.
    var engineValue: String { rawValue }
}

/// Settings shared between the app and the extension through the app-group defaults.
/// Every change bumps `generation`, which the extension uses to know when to reconfigure.
enum SharedPreferences {
    enum Key {
        static let speechQuality = "speechQuality"
        static let pseudoEnglishPrefix = "pseudoEnglish."
        static let debugLogging = "debugLogging"
        static let markersEnabled = "markersEnabled"
        static let generation = "preferencesGeneration"
    }

    static var defaults: UserDefaults { AppGroup.sharedDefaults }

    static var speechQuality: SpeechQuality {
        get { defaults.string(forKey: Key.speechQuality).flatMap(SpeechQuality.init(rawValue:)) ?? .max }
        set { defaults.set(newValue.rawValue, forKey: Key.speechQuality); bumpGeneration() }
    }

    /// nil means "engine default" for the language.
    static func pseudoEnglish(languageCode2: String) -> Bool? {
        let key = Key.pseudoEnglishPrefix + languageCode2
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    static func setPseudoEnglish(_ enabled: Bool?, languageCode2: String) {
        let key = Key.pseudoEnglishPrefix + languageCode2
        if let enabled {
            defaults.set(enabled, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        bumpGeneration()
    }

    /// All per-language pseudo-English overrides, keyed by ISO 639-1 code.
    static var pseudoEnglishOverrides: [String: Bool] {
        var result: [String: Bool] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Key.pseudoEnglishPrefix) {
            if let flag = value as? Bool {
                result[String(key.dropFirst(Key.pseudoEnglishPrefix.count))] = flag
            }
        }
        return result
    }

    static var debugLogging: Bool {
        get { defaults.bool(forKey: Key.debugLogging) }
        set { defaults.set(newValue, forKey: Key.debugLogging) }
    }

    static var markersEnabled: Bool {
        get { defaults.object(forKey: Key.markersEnabled) == nil ? true : defaults.bool(forKey: Key.markersEnabled) }
        set { defaults.set(newValue, forKey: Key.markersEnabled) }
    }

    static var generation: Int {
        defaults.integer(forKey: Key.generation)
    }

    static func bumpGeneration() {
        defaults.set(generation + 1, forKey: Key.generation)
    }
}
