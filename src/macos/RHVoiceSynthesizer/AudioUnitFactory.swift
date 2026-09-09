// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AudioToolbox
import Foundation

/// Principal class of the extension (NSExtensionPrincipalClass in Info.plist).
public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    public func beginRequest(with context: NSExtensionContext) {
    }

    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try RHVoiceAudioUnit(componentDescription: componentDescription, options: [])
    }
}
