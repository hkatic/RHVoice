// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

struct LanguageSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedLanguageId) {
            Section("Languages") {
                ForEach(model.languages) { language in
                    let installed = model.installedCount(in: language)
                    HStack {
                        Text(language.localizedName)
                        Spacer()
                        if installed > 0 {
                            Text("\(installed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .tag(language.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: language, installed: installed))
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.index == nil {
                ProgressView("Loading voice list…")
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refreshIndex(force: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload the list of available voices from the server")
            }
        }
    }

    private func accessibilityLabel(for language: LanguagePackage, installed: Int) -> String {
        let voices = language.voices.count
        var parts = [language.localizedName]
        parts.append(voices == 1 ? "1 voice" : "\(voices) voices")
        if installed > 0 {
            parts.append("\(installed) installed")
        }
        return parts.joined(separator: ", ")
    }
}
