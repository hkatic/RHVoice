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
    private var catalogFingerprint = ""
    private var cachedCatalog = VoiceCatalog.Snapshot.empty
    private var voiceSizes: [URL: Int64] = [:]

    /// The current data layout; nil when the app group container is unavailable.
    let layout: DataLayout?

    init(layout: DataLayout?) {
        self.layout = layout
    }

    convenience init() {
        self.init(layout: Self.defaultLayout())
    }

    private static func defaultLayout() -> DataLayout? {
        do {
            return try DataLayout.inAppGroup()
        } catch {
            RHVLog.synthesizer.error("No data layout: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Installed voices as read from disk (no engine needed).
    func catalog() -> VoiceCatalog.Snapshot {
        guard let layout else { return .empty }
        lock.lock()
        defer { lock.unlock() }
        let data = layout.engineDataPath
        let wanted = dataFingerprint(data)
        if wanted != catalogFingerprint {
            cachedCatalog = VoiceCatalog.scan(dataDirectory: data)
            catalogFingerprint = wanted
            voiceSizes.removeAll()
        }
        return cachedCatalog
    }

    /// Calculated once per catalog revision, rather than walking every model directory
    /// whenever the speech server enumerates voices.
    func sizeOnDisk(of voice: InstalledVoice) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        if let size = voiceSizes[voice.directory] { return size }
        let size = voice.sizeOnDisk()
        voiceSizes[voice.directory] = size
        return size
    }

    /// Returns an engine for the current data and preferences, creating or replacing it as needed.
    func engine() throws -> RHVEngine {
        guard let layout else { throw DataLayoutError.noAppGroupContainer(AppGroup.identifier) }
        lock.lock()
        defer { lock.unlock() }
        let wanted = currentFingerprint(layout: layout)
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
        catalogFingerprint = ""
        cachedCatalog = .empty
        voiceSizes.removeAll()
        lock.unlock()
    }

    private func applyPreferences(to engine: RHVEngine) {
        engine.setConfigValue(SharedPreferences.speechQuality.engineValue, forKey: "quality")
        for (code, enabled) in SharedPreferences.pseudoEnglishOverrides {
            engine.setConfigValue(enabled ? "yes" : "no", forKey: "languages.\(code).use_pseudo_english")
        }
    }

    // Keep subsecond precision: an installation or config edit may happen in the
    // same second as the preceding request. Include inode/size for file replacement.
    private func stamp(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "missing" }
        let date = attributes[.modificationDate] as? Date ?? .distantPast
        return "\(date.timeIntervalSince1970):\(attributes[.systemFileNumber] ?? 0):\(attributes[.size] ?? 0)"
    }

    private func dataFingerprint(_ data: URL) -> String {
        [data.path, stamp(data.appendingPathComponent("voices")),
         stamp(data.appendingPathComponent("languages"))].joined(separator: "|")
    }

    private func currentFingerprint(layout: DataLayout) -> String {
        // Dictionary edits need to reload the engine too. These are small user files;
        // do not walk voice models or language resources on the utterance path.
        var dictionaries = [stamp(layout.dicts)]
        if let files = FileManager.default.enumerator(at: layout.dicts, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles]) {
            for case let url as URL in files {
                dictionaries.append(url.path + ":" + stamp(url))
            }
        }
        return [dataFingerprint(layout.engineDataPath), stamp(layout.configFile),
                dictionaries.sorted().joined(separator: "|"),
                String(SharedPreferences.generation)].joined(separator: "|")
    }
}
