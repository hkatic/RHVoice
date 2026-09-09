#!/usr/bin/env swift
// Speaks text with a registered voice through the system speech synthesizer, printing the
// word ranges the synthesizer reports, then exits.
//   swift scripts/speak.swift <voice identifier> "text to speak" [rate 0..1] [pitch 0.5..2]
import AVFAudio
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: speak.swift <voice identifier> \"text\" [rate] [pitch]")
    exit(2)
}
guard let voice = AVSpeechSynthesisVoice(identifier: args[1]) else {
    print("Voice not found: \(args[1]) (run list-voices.swift)")
    exit(1)
}
let utterance = AVSpeechUtterance(string: args[2])
utterance.voice = voice
if args.count > 3, let rate = Float(args[3]) { utterance.rate = rate }
if args.count > 4, let pitch = Float(args[4]) { utterance.pitchMultiplier = pitch }

final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
    let started = Date()
    func stamp() -> String { String(format: "%6.0f ms", Date().timeIntervalSince(started) * 1000) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("\(stamp())  start")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let text = (utterance.speechString as NSString).substring(with: characterRange)
        print("\(stamp())  word \(characterRange): \"\(text)\"")
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("\(stamp())  finished")
        exit(0)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("\(stamp())  cancelled")
        exit(1)
    }
}

let delegate = Delegate()
let synthesizer = AVSpeechSynthesizer()
synthesizer.delegate = delegate
print("Speaking with \(voice.name) (\(voice.identifier))")
synthesizer.speak(utterance)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 120))
print("timeout")
exit(1)
