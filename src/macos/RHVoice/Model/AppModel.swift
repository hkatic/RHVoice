// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation
import SwiftUI

/// Per-voice state shown in the voice list.
enum VoiceState: Equatable, Sendable {
    case notInstalled
    case downloading(packName: String, fraction: Double?)
    case installing(packName: String)
    case installed
    case updateAvailable
    case removing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .installing, .removing: return true
        default: return false
        }
    }

    var isInstalled: Bool {
        switch self {
        case .installed, .updateAvailable: return true
        default: return false
        }
    }
}

/// The application state: package index, installed packs, per-voice operations and the
/// system registration status. Everything UI-facing lives on the main actor.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var index: PackageIndex?
    @Published private(set) var indexSource: IndexRepository.Source?
    @Published private(set) var indexError: String?
    @Published private(set) var installed: VoiceCatalog.Snapshot = .empty
    @Published private(set) var voiceStates: [String: VoiceState] = [:]
    @Published private(set) var registeredPackIds: Set<String> = []
    @Published var selectedLanguageId: String? {
        didSet { UserDefaults.standard.set(selectedLanguageId, forKey: "selectedLanguageId") }
    }
    @Published var setupError: String?
    @Published var pendingRemoval: (voice: VoicePackage, language: LanguagePackage)?

    let layout: DataLayout?
    let engineHolder = EngineHolder.shared
    let samplePlayer = SamplePlayer()
    private let repository: IndexRepository?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var registrationPoll: Task<Void, Never>?

    init() {
        do {
            let layout = try DataLayout.inAppGroup()
            self.layout = layout
            repository = IndexRepository(cacheURL: layout.indexCache)
        } catch {
            layout = nil
            repository = nil
            setupError = error.localizedDescription
        }
    }

    // MARK: Lifecycle

    func start() async {
        refreshInstalled()
        refreshRegistration()
        startWatching()
        SpeechRegistration.notifyVoicesChanged()
        await refreshIndex(force: false)
    }

    func refreshIndex(force: Bool) async {
        guard let repository else { return }
        let result = await repository.load(forceRefresh: force)
        index = result.index
        indexSource = result.source
        indexError = result.error
        if selectedLanguageId == nil {
            let remembered = UserDefaults.standard.string(forKey: "selectedLanguageId")
            if let remembered, result.index.language(withId: remembered) != nil {
                selectedLanguageId = remembered
            } else {
                selectedLanguageId = preferredLanguageId(in: result.index)
            }
        }
        recomputeStates()
    }

    private func preferredLanguageId(in index: PackageIndex) -> String? {
        let preferred = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        for code in preferred {
            if let language = index.languages.first(where: { $0.lang2code == code }) {
                return language.id
            }
        }
        return index.languages.sorted { $0.localizedName < $1.localizedName }.first?.id
    }

    func refreshInstalled() {
        guard let layout else { return }
        installed = VoiceCatalog.scan(dataDirectory: layout.engineDataPath)
        recomputeStates()
    }

    func refreshRegistration() {
        registeredPackIds = SpeechRegistration.registeredPackIds()
    }

    /// Polls the system voice list for a while after a change; registration is asynchronous.
    private func pollRegistration() {
        registrationPoll?.cancel()
        registrationPoll = Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let before = self.registeredPackIds
                self.refreshRegistration()
                if self.registeredPackIds != before {
                    return
                }
            }
        }
    }

    private func startWatching() {
        guard let layout else { return }
        for directory in [layout.voices, layout.languages] {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                self?.refreshInstalled()
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    // MARK: Derived state

    var languages: [LanguagePackage] {
        (index?.languages ?? []).sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    var selectedLanguage: LanguagePackage? {
        guard let selectedLanguageId else { return nil }
        return index?.language(withId: selectedLanguageId)
    }

    func installedVoice(for voice: VoicePackage) -> InstalledVoice? {
        installed.voices.first { $0.id == voice.id }
    }

    func installedCount(in language: LanguagePackage) -> Int {
        language.voices.filter { installedVoice(for: $0) != nil }.count
    }

    func state(of voice: VoicePackage) -> VoiceState {
        voiceStates[voice.id] ?? .notInstalled
    }

    func isRegistered(_ voice: VoicePackage) -> Bool {
        registeredPackIds.contains(voice.id)
    }

    private func recomputeStates() {
        guard let index else { return }
        var states = voiceStates
        for language in index.languages {
            for voice in language.voices {
                if let current = states[voice.id], current.isBusy { continue }
                if case .failed = states[voice.id] { continue }
                if installedVoice(for: voice) != nil {
                    states[voice.id] = DependencyResolver.updateAvailable(voice: voice, language: language, installed: installed) ? .updateAvailable : .installed
                } else {
                    states[voice.id] = .notInstalled
                }
            }
        }
        voiceStates = states
    }

    // MARK: Install / update

    func install(_ voice: VoicePackage, in language: LanguagePackage) {
        guard let index, let layout, tasks[voice.id] == nil else { return }
        let plan = DependencyResolver.installPlan(voice: voice, language: language, index: index, installed: installed)
        guard !plan.isEmpty else {
            recomputeStates()
            return
        }
        voiceStates[voice.id] = .downloading(packName: plan[0].name, fraction: nil)
        tasks[voice.id] = Task { [weak self] in
            defer { self?.tasks[voice.id] = nil }
            do {
                for pack in plan {
                    try Task.checkCancellation()
                    try await self?.installPack(pack, layout: layout, voiceId: voice.id)
                }
                self?.voiceStates[voice.id] = .installed
                self?.engineHolder.invalidate()
                self?.refreshInstalled()
                SpeechRegistration.notifyVoicesChanged()
                self?.pollRegistration()
            } catch is CancellationError {
                self?.voiceStates[voice.id] = nil
                self?.refreshInstalled()
            } catch {
                RHVLog.installer.error("Install of \(voice.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                self?.voiceStates[voice.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func installPack(_ pack: DependencyResolver.Pack, layout: DataLayout, voiceId: String) async throws {
        guard let url = URL(string: pack.dataUrl) else { throw URLError(.badURL) }
        let archive = layout.tmp.appendingPathComponent("\(pack.kind == .voice ? "voice" : "language")-\(pack.id)-\(pack.version).zip")
        voiceStates[voiceId] = .downloading(packName: pack.name, fraction: nil)
        try await PackageDownloader.download(from: url, to: archive, expectedMD5: pack.descriptor.expectedMD5) { received, expected in
            let fraction = expected.map { $0 > 0 ? Double(received) / Double($0) : nil } ?? nil
            Task { @MainActor [weak self] in
                self?.voiceStates[voiceId] = .downloading(packName: pack.name, fraction: fraction)
            }
        }
        voiceStates[voiceId] = .installing(packName: pack.name)
        let staging = layout.tmp.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
        let kind = pack.kind
        let expected = pack.version
        try await Task.detached(priority: .userInitiated) {
            try PackageExtractor.extract(archiveURL: archive, to: staging)
            try PackageExtractor.verify(extractedPack: staging, kind: kind, expected: expected)
        }.value
        try? FileManager.default.removeItem(at: archive)

        let destination = pack.kind == .voice ? layout.voiceDirectory(id: pack.id) : layout.languageDirectory(id: pack.id)
        var sidecar = PackSidecar()
        sidecar.indexId = pack.id
        sidecar.indexMajor = pack.version.major
        sidecar.indexMinor = pack.version.minor
        sidecar.ctry2code = pack.voice?.ctry2code
        sidecar.ctry3code = pack.voice?.ctry3code
        sidecar.accent = pack.voice?.accent
        sidecar.installedAt = Date()
        try sidecar.write(to: staging)
        try Self.replaceDirectory(at: destination, with: staging, trash: layout.tmp)
        RHVLog.installer.info("Installed \(pack.kind == .voice ? "voice" : "language", privacy: .public) \(pack.id, privacy: .public) \(pack.version.description, privacy: .public)")
    }

    /// Moves `source` into place at `destination`, retiring any previous directory to a trash
    /// folder first (a speaking extension keeps valid file handles) and deleting it afterwards.
    private static func replaceDirectory(at destination: URL, with source: URL, trash: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var retired: URL?
        if fm.fileExists(atPath: destination.path) {
            let target = trash.appendingPathComponent("trash-\(UUID().uuidString)", isDirectory: true)
            try fm.moveItem(at: destination, to: target)
            retired = target
        }
        try fm.moveItem(at: source, to: destination)
        if let retired {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                try? FileManager.default.removeItem(at: retired)
            }
        }
    }

    func cancel(_ voice: VoicePackage) {
        tasks[voice.id]?.cancel()
    }

    // MARK: Uninstall

    func requestRemoval(of voice: VoicePackage, in language: LanguagePackage) {
        pendingRemoval = (voice, language)
    }

    func confirmRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        uninstall(pending.voice)
    }

    func uninstall(_ voice: VoicePackage) {
        guard let layout, let installedVoice = installedVoice(for: voice), tasks[voice.id] == nil else { return }
        if samplePlayer.playingVoiceId == voice.id {
            samplePlayer.stop()
        }
        voiceStates[voice.id] = .removing
        let plan = DependencyResolver.uninstallPlan(voice: installedVoice, installed: installed)
        tasks[voice.id] = Task { [weak self] in
            defer { self?.tasks[voice.id] = nil }
            do {
                for directory in plan.voices.map(\.directory) + plan.languages.map(\.directory) {
                    try Self.retire(directory, trash: layout.tmp)
                }
                RHVLog.installer.info("Removed voice \(voice.id, privacy: .public) and \(plan.languages.count, privacy: .public) language pack(s)")
                self?.voiceStates[voice.id] = .notInstalled
            } catch {
                self?.voiceStates[voice.id] = .failed(error.localizedDescription)
            }
            self?.engineHolder.invalidate()
            self?.refreshInstalled()
            SpeechRegistration.notifyVoicesChanged()
            self?.pollRegistration()
        }
    }

    private static func retire(_ directory: URL, trash: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let target = trash.appendingPathComponent("trash-\(UUID().uuidString)", isDirectory: true)
        try fm.moveItem(at: directory, to: target)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            try? FileManager.default.removeItem(at: target)
        }
    }

    func clearFailure(_ voice: VoicePackage) {
        voiceStates[voice.id] = nil
        recomputeStates()
    }

    // MARK: Samples

    func toggleSample(for voice: VoicePackage, in language: LanguagePackage) {
        if samplePlayer.playingVoiceId == voice.id {
            samplePlayer.stop()
            return
        }
        if let installedVoice = installedVoice(for: voice) {
            let text = language.testMessage ?? "\(voice.name)."
            samplePlayer.play(voice: installedVoice, text: text, holder: engineHolder)
        } else if let url = voice.demoURL, let layout {
            samplePlayer.playDemo(voiceId: voice.id, url: url, cacheDirectory: layout.demos)
        }
    }

    func canPlaySample(_ voice: VoicePackage) -> Bool {
        installedVoice(for: voice) != nil || voice.demoURL != nil
    }
}
