// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import Foundation

/// Converts the engine's UTF-8 byte offsets into the UTF-16 ranges the system expects.
enum MarkerMapper {
    /// Bytes per output frame (Float32 mono).
    static let bytesPerFrame = 4

    static func range(utf8Offset: Int, utf8Length: Int, in text: String) -> NSRange? {
        let utf8 = text.utf8
        guard utf8Offset >= 0, utf8Length >= 0, utf8Offset + utf8Length <= utf8.count else { return nil }
        let start = utf8.index(utf8.startIndex, offsetBy: utf8Offset)
        let end = utf8.index(start, offsetBy: utf8Length)
        guard let startIndex = start.samePosition(in: text.unicodeScalars),
              let endIndex = end.samePosition(in: text.unicodeScalars) else {
            return nil
        }
        return NSRange(startIndex..<endIndex, in: text)
    }

    static func marker(kind: RHVMarkerKind, utf8Offset: Int, utf8Length: Int, bookmark: String?, frame: UInt64, in text: String) -> AVSpeechSynthesisMarker? {
        let byteOffset = Int(frame) * bytesPerFrame
        switch kind {
        case .bookmark:
            guard let bookmark else { return nil }
            if #available(macOS 14.0, *) {
                return AVSpeechSynthesisMarker(bookmarkName: bookmark, atByteSampleOffset: byteOffset)
            }
            return nil
        case .word, .sentence:
            guard let range = range(utf8Offset: utf8Offset, utf8Length: utf8Length, in: text) else { return nil }
            let mark: AVSpeechSynthesisMarker.Mark = (kind == .word) ? .word : .sentence
            return AVSpeechSynthesisMarker(markerType: mark, forTextRange: range, atByteSampleOffset: byteOffset)
        @unknown default:
            return nil
        }
    }
}
