#!/usr/bin/env swift
// Lists the RHVoice voices the system currently knows about.
//   swift scripts/list-voices.swift [--all] [--update] [--wait SECONDS]
// --all     list every voice on the system
// --update  call AVSpeechSynthesisProviderVoice.updateSpeechVoices() first
// --wait N  keep polling for up to N seconds until an RHVoice voice appears
import AVFAudio
import Foundation

let arguments = CommandLine.arguments
let showAll = arguments.contains("--all")
var waitSeconds = 0
if let index = arguments.firstIndex(of: "--wait"), index + 1 < arguments.count {
    waitSeconds = Int(arguments[index + 1]) ?? 0
}
if arguments.contains("--update") {
    AVSpeechSynthesisProviderVoice.updateSpeechVoices()
    print("updateSpeechVoices() called")
}
let prefix = "org.rhvoice.RHVoice.Synthesizer."
func fetch() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices()
        .filter { showAll || $0.identifier.hasPrefix(prefix) }
        .sorted { $0.identifier < $1.identifier }
}
var voices = fetch()
let deadline = Date(timeIntervalSinceNow: TimeInterval(waitSeconds))
while voices.isEmpty && Date() < deadline {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
    voices = fetch()
}
if voices.isEmpty {
    print(showAll ? "No voices." : "No RHVoice voices are registered with the system.")
    exit(1)
}
for voice in voices {
    let quality: String
    switch voice.quality {
    case .enhanced: quality = "enhanced"
    case .premium: quality = "premium"
    default: quality = "default"
    }
    print("\(voice.identifier)\t\(voice.language)\t\(voice.name)\t\(quality)")
}
