// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

/// Bottom bar: index source, installed/registered counts, and playback errors.
struct StatusBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: SamplePlayer

    var body: some View {
        HStack(spacing: 16) {
            Text(indexDescription)
            Divider().frame(height: 14)
            Text("\(model.installed.voices.count) installed, \(model.registeredPackIds.count) available to VoiceOver")
            if let error = player.lastError {
                Divider().frame(height: 14)
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var indexDescription: String {
        switch model.indexSource {
        case .network: return "Voice list: up to date"
        case .cache: return model.indexError == nil ? "Voice list: cached" : "Voice list: cached (server unreachable)"
        case .bundled: return "Voice list: built-in copy (server unreachable)"
        case nil: return "Voice list: loading…"
        }
    }
}
