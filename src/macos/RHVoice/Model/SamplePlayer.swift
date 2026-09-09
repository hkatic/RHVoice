// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import Foundation

/// Plays voice samples: installed voices are synthesized in-process through the same bridge the
/// extension uses; voices that are not installed play the demo clip from the package index.
@MainActor
final class SamplePlayer: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(voiceId: String)
        case playing(voiceId: String)
    }

    @Published private(set) var state: State = .idle
    @Published var lastError: String?

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var playerNode: AVAudioPlayerNode?
    private var session: RHVSynthesisSession?
    private var demoTask: Task<Void, Never>?
    private var completionTimer: Timer?

    var playingVoiceId: String? {
        switch state {
        case .idle: return nil
        case .loading(let id), .playing(let id): return id
        }
    }

    // MARK: Installed voice: synthesize

    func play(voice: InstalledVoice, text: String, holder: EngineHolder) {
        stop()
        state = .loading(voiceId: voice.id)
        do {
            let engine = try holder.engine()
            let options = RHVSynthesisOptions()
            options.outputSampleRate = RHVoiceAudioUnitConstants.outputSampleRate
            let ssml = "<speak>" + Self.escape(text) + "</speak>"
            let session = try engine.startSession(withSSML: ssml, voiceName: voice.name, options: options, markerHandler: nil)
            self.session = session
            try startSourceNode(session: session)
            state = .playing(voiceId: voice.id)
        } catch {
            lastError = error.localizedDescription
            RHVLog.app.error("Sample synthesis failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private func startSourceNode(session: RHVSynthesisSession) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: session.sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let output = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudioUnitErr_InvalidParameter
            }
            var written: UInt32 = 0
            // Never block the audio thread; silence until the engine has produced audio.
            _ = session.render(into: output, frameCount: frameCount, maxWaitMilliseconds: 0, framesWritten: &written)
            if Int(written) < Int(frameCount) {
                (output + Int(written)).initialize(repeating: 0, count: Int(frameCount) - Int(written))
            }
            return noErr
        }
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        sourceNode = node
        try audioEngine.start()
        // Poll for completion: the render callback runs on the audio thread and cannot touch UI state.
        completionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = self.session else { return }
                var probe: Float = 0
                var written: UInt32 = 0
                // A zero-frame render just reports the state without consuming audio.
                let status = session.render(into: &probe, frameCount: 0, maxWaitMilliseconds: 0, framesWritten: &written)
                if status != .rendering {
                    self.stop()
                }
            }
        }
    }

    // MARK: Demo clips

    func playDemo(voiceId: String, url: URL, cacheDirectory: URL) {
        stop()
        state = .loading(voiceId: voiceId)
        demoTask = Task { [weak self] in
            do {
                let file = try await DemoDecoder.cachedDemo(for: voiceId, url: url, cacheDirectory: cacheDirectory)
                try Task.checkCancellation()
                let buffer = try await DemoDecoder.decode(file)
                try Task.checkCancellation()
                self?.playBuffer(buffer, voiceId: voiceId)
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.stop()
                }
            }
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer, voiceId: String) {
        let node = AVAudioPlayerNode()
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: buffer.format)
        playerNode = node
        do {
            try audioEngine.start()
        } catch {
            lastError = error.localizedDescription
            stop()
            return
        }
        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in
                if self?.playingVoiceId == voiceId { self?.stop() }
            }
        }
        node.play()
        state = .playing(voiceId: voiceId)
    }

    // MARK: Stop

    func stop() {
        demoTask?.cancel()
        demoTask = nil
        completionTimer?.invalidate()
        completionTimer = nil
        session?.cancel()
        session = nil
        if let node = playerNode {
            node.stop()
            audioEngine.detach(node)
            playerNode = nil
        }
        if let node = sourceNode {
            audioEngine.detach(node)
            sourceNode = nil
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        state = .idle
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }
}

/// Shared with the extension's audio unit: the output sample rate of the bridge sessions.
enum RHVoiceAudioUnitConstants {
    static let outputSampleRate: Double = 24000
}
