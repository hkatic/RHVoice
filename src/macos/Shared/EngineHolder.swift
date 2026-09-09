// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// Owns the engine instance for the extension process. The engine is created on first use and
/// recreated when the installed packs or the shared preferences change.
final class EngineHolder: @unchecked Sendable {
    static let shared = EngineHolder()

    private let lock = NSLock()
    private var current: RHVEngine?
    private var fingerprint = ""

    /// The current data layout; nil when the app group container is unavailable.
    let layout: DataLayout? = {
        do {
            return try DataLayout.inAppGroup()
        } catch {
            RHVLog.synthesizer.error("No data layout: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// Installed voices as read from disk (no engine needed).
    func catalog() -> VoiceCatalog.Snapshot {
        guard let layout else { return .empty }
        return VoiceCatalog.scan(dataDirectory: layout.engineDataPath)
    }

    /// Returns an engine for the current data and preferences, creating or replacing it as needed.
    func engine() throws -> RHVEngine {
        guard let layout else { throw DataLayoutError.noAppGroupContainer(AppGroup.identifier) }
        let wanted = currentFingerprint(layout: layout)
        lock.lock()
        defer { lock.unlock() }
        if let current, wanted == fingerprint {
            return current
        }
        RHVLog.synthesizer.info("Creating engine (fingerprint changed: \(wanted != self.fingerprint, privacy: .public))")
        let started = Date()
        let created = try RHVEngine(dataPath: layout.engineDataPath.path, configPath: layout.config.path)
        applyPreferences(to: created)
        current = created
        fingerprint = wanted
        RHVLog.synthesizer.info("Engine ready in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms with \(created.voices.count, privacy: .public) voices")
        return created
    }

    /// Drops the engine so the next request rebuilds it.
    func invalidate() {
        lock.lock()
        current = nil
        fingerprint = ""
        lock.unlock()
    }

    private func applyPreferences(to engine: RHVEngine) {
        engine.setConfigValue(SharedPreferences.speechQuality.engineValue, forKey: "quality")
        for (code, enabled) in SharedPreferences.pseudoEnglishOverrides {
            engine.setConfigValue(enabled ? "yes" : "no", forKey: "languages.\(code).use_pseudo_english")
        }
    }

    /// Changes when packs are installed or removed (directory mtimes) or preferences change.
    private func currentFingerprint(layout: DataLayout) -> String {
        let fm = FileManager.default
        let data = layout.engineDataPath
        func stamp(_ url: URL) -> String {
            let date = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            return String(Int(date.timeIntervalSince1970))
        }
        return [
            data.path,
            stamp(data.appendingPathComponent("voices")),
            stamp(data.appendingPathComponent("languages")),
            stamp(layout.configFile),
            String(SharedPreferences.generation),
        ].joined(separator: "|")
    }
}
