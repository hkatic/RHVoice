// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import AudioToolbox
import Foundation
import os

/// The speech synthesis provider. The system instantiates it through AudioUnitFactory,
/// asks for `speechVoices`, and for every utterance calls `synthesizeSpeechRequest(_:)`
/// followed by render calls until the render block reports completion.
public final class RHVoiceAudioUnit: AVSpeechSynthesisProviderAudioUnit {
    /// Fixed output format: what the engine produces at standard/max quality.
    static let outputSampleRate: Double = 24000

    private struct RenderState: Sendable {
        var session: RHVSynthesisSession?
        var renderedFrames: Bool = false
    }

    /// Relays markers from the synthesis thread to the host without capturing the audio unit
    /// in a Sendable closure.
    private final class MarkerRelay: @unchecked Sendable {
        weak var unit: RHVoiceAudioUnit?
        let request: AVSpeechSynthesisProviderRequest
        let text: String

        init(unit: RHVoiceAudioUnit, request: AVSpeechSynthesisProviderRequest) {
            self.unit = unit
            self.request = request
            self.text = request.ssmlRepresentation
        }

        func deliver(kind: RHVMarkerKind, offset: UInt, length: UInt, bookmark: String?, frame: UInt64) {
            guard let unit, let block = unit.speechSynthesisOutputMetadataBlock,
                  let marker = MarkerMapper.marker(kind: kind, utf8Offset: Int(offset), utf8Length: Int(length), bookmark: bookmark, frame: frame, in: text) else {
                return
            }
            block([marker], request)
        }
    }

    private let outputBus: AUAudioUnitBus
    private var outputBusArray: AUAudioUnitBusArray!
    private let renderState = OSAllocatedUnfairLock(initialState: RenderState())

    @objc
    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.outputSampleRate, channels: 1) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.supportedChannelCounts = [1]
        try super.init(componentDescription: componentDescription, options: options)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        RHVLog.synthesizer.info("Audio unit instantiated")
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }

    /// No inputs, one mono output.
    public override var channelCapabilities: [NSNumber]? {
        [0, 1]
    }

    // MARK: Voices

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            let snapshot = EngineHolder.shared.catalog()
            let voices = snapshot.voices.map { voice -> AVSpeechSynthesisProviderVoice in
                let provided = AVSpeechSynthesisProviderVoice(
                    name: voice.name,
                    identifier: voice.providerIdentifier,
                    primaryLanguages: [voice.bcp47],
                    supportedLanguages: voice.supportedLanguageTags)
                switch voice.gender {
                case .male: provided.gender = .male
                case .female: provided.gender = .female
                case .unknown: provided.gender = .unspecified
                }
                provided.version = voice.fullVersionString
                provided.voiceSize = voice.sizeOnDisk()
                return provided
            }
            RHVLog.synthesizer.info("speechVoices: \(voices.count, privacy: .public) voices")
            return voices
        }
        set {
        }
    }

    // MARK: Requests

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        cancelCurrentSession()
        if SharedPreferences.debugLogging {
            RHVLog.synthesizer.debug("Request for \(speechRequest.voice.identifier, privacy: .public): \(speechRequest.ssmlRepresentation, privacy: .public)")
        } else {
            RHVLog.synthesizer.info("Request for \(speechRequest.voice.identifier, privacy: .public) (\(speechRequest.ssmlRepresentation.count, privacy: .public) characters)")
        }
        let identifier = speechRequest.voice.identifier
        let voiceId = VoiceIdentifiers.packId(fromSystemIdentifier: identifier)
        guard let voice = EngineHolder.shared.catalog().voices.first(where: { $0.id == voiceId || $0.providerIdentifier == identifier }) else {
            RHVLog.synthesizer.error("Unknown voice \(identifier, privacy: .public)")
            return
        }
        do {
            let engine = try EngineHolder.shared.engine()
            let options = RHVSynthesisOptions()
            options.outputSampleRate = Self.outputSampleRate
            let relay = SharedPreferences.markersEnabled ? MarkerRelay(unit: self, request: speechRequest) : nil
            let handler: RHVMarkerHandler? = relay.map { relay in
                { kind, offset, length, bookmark, frame in
                    relay.deliver(kind: kind, offset: offset, length: length, bookmark: bookmark, frame: frame)
                }
            }
            let session = try engine.startSession(withSSML: speechRequest.ssmlRepresentation, voiceName: voice.name, options: options, markerHandler: handler)
            renderState.withLock { state in
                state.session = session
                state.renderedFrames = false
            }
        } catch {
            RHVLog.synthesizer.error("Cannot start synthesis: \(error.localizedDescription, privacy: .public)")
        }
    }

    public override func cancelSpeechRequest() {
        RHVLog.synthesizer.info("Cancel requested")
        cancelCurrentSession()
    }

    private func cancelCurrentSession() {
        let session = renderState.withLock { state -> RHVSynthesisSession? in
            let current = state.session
            state.session = nil
            return current
        }
        session?.cancel()
    }

    // MARK: Rendering

    public override var internalRenderBlock: AUInternalRenderBlock {
        let renderState = self.renderState
        return { actionFlags, _, frameCount, _, outputData, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count > 0, let output = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudioUnitErr_InvalidParameter
            }
            let frames = Int(frameCount)
            let (session, firstBuffer) = renderState.withLock { state in
                (state.session, !state.renderedFrames)
            }
            var written: UInt32 = 0
            var status: RHVRenderStatus = .complete
            if let session {
                // Wait briefly for the engine so the stream does not start with silence, but
                // never stall the host: later buffers wait at most a couple of render periods.
                status = session.render(into: output, frameCount: frameCount, maxWaitMilliseconds: firstBuffer ? 250 : 40, framesWritten: &written)
                let producedFrames = written > 0
                let finished = status != .rendering
                renderState.withLock { state in
                    guard state.session === session else { return }
                    if producedFrames { state.renderedFrames = true }
                    if finished { state.session = nil }
                }
            }
            if Int(written) < frames {
                (output + Int(written)).initialize(repeating: 0, count: frames - Int(written))
            }
            buffers[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
            buffers[0].mNumberChannels = 1
            if status != .rendering {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }
    }
}
