// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

struct VoiceListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let language = model.selectedLanguage {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(for: language)
                    ForEach(language.voices) { voice in
                        VoiceRow(voice: voice, language: language)
                    }
                }
                .padding()
            }
            .navigationTitle(language.localizedName)
            .navigationSubtitle(subtitle(for: language))
        } else {
            VStack(spacing: 8) {
                Text("Select a language")
                    .font(.title2)
                Text("Voices for the selected language appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func header(for language: LanguagePackage) -> some View {
        let installedLanguage = model.installed.languages.first { $0.name == language.name || $0.id == language.id }
        VStack(alignment: .leading, spacing: 4) {
            Text("Language pack \(language.name) \(language.version.description)")
                .font(.headline)
            if let installedLanguage {
                Text("Installed version \(installedLanguage.versionString)")
                    .foregroundStyle(.secondary)
            } else {
                Text("The language pack is downloaded together with the first voice.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, 4)
    }

    private func subtitle(for language: LanguagePackage) -> String {
        let count = language.voices.count
        return count == 1 ? "1 voice" : "\(count) voices"
    }
}
