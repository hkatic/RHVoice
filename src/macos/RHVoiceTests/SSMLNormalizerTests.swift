// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import XCTest
@testable import RHVoice

final class SSMLNormalizerTests: XCTestCase {
    private func normalize(_ ssml: String) -> String {
        RHVEngine.normalizedSSML(ssml)
    }

    func testSystemRequestIsLeftUntouched() {
        // Captured from the macOS speech server (rate 0.2, pitch multiplier 0.6).
        let request = "<speak><lang xml:lang=\"hr-HR\"><prosody pitch=\"-40.0%\" rate=\"40.0%\">Sporo i nisko.</prosody></lang></speak>"
        XCTAssertEqual(normalize(request), request)
    }

    func testNamedValuesBecomePercentages() {
        XCTAssertEqual(normalize("<speak><prosody rate=\"x-fast\" pitch='high' volume=\"soft\">Hi</prosody></speak>"),
                       "<speak><prosody rate=\"200%\" pitch='125%' volume=\"50%\">Hi</prosody></speak>")
    }

    func testMultipliersSemitonesAndDecibels() {
        XCTAssertEqual(normalize("<speak><prosody rate=\"1.5\">a</prosody></speak>"), "<speak><prosody rate=\"150%\">a</prosody></speak>")
        XCTAssertEqual(normalize("<speak><prosody pitch=\"+12st\">a</prosody></speak>"), "<speak><prosody pitch=\"200%\">a</prosody></speak>")
        XCTAssertEqual(normalize("<speak><prosody volume=\"-6dB\">a</prosody></speak>"), "<speak><prosody volume=\"50%\">a</prosody></speak>")
        XCTAssertEqual(normalize("<speak><prosody volume=\"0\">a</prosody></speak>"), "<speak><prosody volume=\"1%\">a</prosody></speak>")
    }

    func testTextAndOtherElementsAreNeverModified() {
        let ssml = "<speak>rate=\"x-fast\" is text <break time=\"1s\"/><prosody rate=\"fast\">x</prosody> pitch='low'</speak>"
        XCTAssertEqual(normalize(ssml), "<speak>rate=\"x-fast\" is text <break time=\"1s\"/><prosody rate=\"150%\">x</prosody> pitch='low'</speak>")
        XCTAssertEqual(normalize("plain text, no markup"), "plain text, no markup")
    }
}
