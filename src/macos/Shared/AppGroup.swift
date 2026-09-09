// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// The app group shared by the app and the synthesizer extension. Its identifier is injected
/// into both Info.plists from the APP_GROUP_ID build setting so that a single value drives the
/// entitlements, the container lookup and the shared preferences.
enum AppGroup {
    static let infoPlistKey = "RHVAppGroupIdentifier"
    static let fallbackIdentifier = "org.rhvoice.RHVoice"

    static var identifier: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String, !value.isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        return fallbackIdentifier
    }

    /// The shared container, or nil when the process is not entitled to the group.
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Preferences shared between the app and the extension.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
