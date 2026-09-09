// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import XCTest

final class MarkerTests: XCTestCase {
    func testUnicodeRangesUseUTF16Offsets() {
        let text = "<speak>Čitaj 😀 e\u{301} riječ.</speak>"
        for word in ["Čitaj", "😀", "e\u{301}", "riječ"] {
            let range = text.range(of: word)!
            let offset = text[..<range.lowerBound].utf8.count
            XCTAssertEqual(MarkerMapper.range(utf8Offset: offset, utf8Length: word.utf8.count, in: text), NSRange(range, in: text))
        }
        XCTAssertNil(MarkerMapper.range(utf8Offset: 8, utf8Length: 1, in: text), "an offset inside Č is not a scalar boundary")
    }

    func testInvalidOffsetsCannotOverflow() {
        for (offset, length) in [(Int.max, 1), (1, Int.max), (-1, 1), (0, -1)] {
            XCTAssertNil(MarkerMapper.range(utf8Offset: offset, utf8Length: length, in: "Hello"))
        }
        XCTAssertNil(MarkerMapper.marker(kind: .word, utf8Offset: 0, utf8Length: 5, bookmark: nil, frame: .max, in: "Hello"))
    }
}
