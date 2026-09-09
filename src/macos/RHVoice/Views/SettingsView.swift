// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var quality = SharedPreferences.speechQuality
    @State private var markers = SharedPreferences.markersEnabled
    @State private var debugLogging = SharedPreferences.debugLogging
    @State private var pseudoEnglish: [String: Bool] = SharedPreferences.pseudoEnglishOverrides

    var body: some View {
        Form {
            Section("Speech quality") {
                Picker("Speech quality", selection: $quality) {
                    Text("Best possible quality").tag(SpeechQuality.max)
                    Text("Standard quality").tag(SpeechQuality.standard)
                    Text("Best possible performance").tag(SpeechQuality.min)
                }
                .onChange(of: quality) { newValue in
                    SharedPreferences.speechQuality = newValue
                    model.engineHolder.invalidate()
                }
                Text("Best possible quality synthesizes each sentence before it starts playing, which adds a short delay on long text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("English words") {
                ForEach(installedLanguagesWithPseudoEnglish, id: \.id) { language in
                    Toggle("Read English words with English rules in \(language.localizedName)", isOn: Binding(
                        get: { pseudoEnglish[language.lang2code] ?? (language.pseudoEnglish ?? false) },
                        set: { value in
                            pseudoEnglish[language.lang2code] = value
                            SharedPreferences.setPseudoEnglish(value, languageCode2: language.lang2code)
                            model.engineHolder.invalidate()
                        }))
                }
                if installedLanguagesWithPseudoEnglish.isEmpty {
                    Text("Install a voice for a language that supports this option to change it.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Advanced") {
                Toggle("Report word positions to VoiceOver", isOn: $markers)
                    .onChange(of: markers) { SharedPreferences.markersEnabled = $0 }
                Toggle("Debug logging (includes spoken text)", isOn: $debugLogging)
                    .onChange(of: debugLogging) { SharedPreferences.debugLogging = $0 }
                HStack {
                    Button("Configuration file") { reveal(model.layout?.configFile, createParent: true) }
                    Button("User dictionaries") { reveal(model.layout?.dicts, createParent: false) }
                }
                Text("RHVoice.conf and the dictionaries follow the format described in the RHVoice documentation. Changes take effect for the next utterance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }

    private var installedLanguagesWithPseudoEnglish: [LanguagePackage] {
        model.languages.filter { language in
            language.pseudoEnglish != nil && model.installedCount(in: language) > 0
        }
    }

    private func reveal(_ url: URL?, createParent: Bool) {
        guard let url else { return }
        let fm = FileManager.default
        if createParent {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                let template = "; RHVoice configuration. See doc/en/Configuration-file.md in the RHVoice repository.\n"
                try? template.write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
    }
}
