// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

/// Languages on the left, the selected language's voices on the right.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            LanguageSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VoiceListView()
        }
        .navigationTitle("RHVoice")
        .safeAreaInset(edge: .bottom) {
            StatusBar()
        }
        .alert("Cannot access voice data", isPresented: Binding(
            get: { model.setupError != nil },
            set: { if !$0 { model.setupError = nil } }
        )) {
            Button("OK") { model.setupError = nil }
        } message: {
            Text(model.setupError ?? "")
        }
        .confirmationDialog(
            "Are you sure you want to uninstall this voice?",
            isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { model.confirmRemoval() }
            Button("Cancel", role: .cancel) { model.pendingRemoval = nil }
        } message: {
            if let pending = model.pendingRemoval {
                Text("\(pending.voice.name) (\(pending.language.localizedName)) will be removed from this Mac.")
            }
        }
    }
}
