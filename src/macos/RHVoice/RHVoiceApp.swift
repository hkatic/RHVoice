// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import SwiftUI

@main
struct RHVoiceApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("RHVoice") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.samplePlayer)
                .frame(minWidth: 720, minHeight: 440)
                .task { await model.start() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Voice List") {
                    Task { await model.refreshIndex(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
