// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import Foundation

/// What the system currently knows about this app's voices.
enum SpeechRegistration {
    /// Identifiers (pack ids) of RHVoice voices the system lists right now.
    static func registeredPackIds() -> Set<String> {
        let prefix = VoiceIdentifiers.systemPrefix
        return Set(AVSpeechSynthesisVoice.speechVoices()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
            .map { VoiceIdentifiers.packId(fromSystemIdentifier: $0) })
    }

    /// Asks the system to rescan this app's synthesizer extension. The refresh is asynchronous
    /// and can take up to about 30 seconds.
    static func notifyVoicesChanged() {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        RHVLog.app.info("updateSpeechVoices() sent")
    }
}
