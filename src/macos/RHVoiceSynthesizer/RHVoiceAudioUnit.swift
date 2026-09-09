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

    private final class RequestToken: @unchecked Sendable {
        private let active = OSAllocatedUnfairLock(initialState: true)
        var isActive: Bool { active.withLock { $0 } }
        func cancel() { active.withLock { $0 = false } }
    }

    private final class RenderResources: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private struct RenderState: Sendable {
        var token: RequestToken?
        var session: RHVSynthesisSession?
        var resources: RenderResources?
    }

    /// Relays markers from the synthesis thread to the host without capturing the audio unit
    /// in a Sendable closure.
    private final class MarkerRelay: @unchecked Sendable {
        weak var unit: RHVoiceAudioUnit?
        let request: AVSpeechSynthesisProviderRequest
        let text: String
        let token: RequestToken

        init(unit: RHVoiceAudioUnit, request: AVSpeechSynthesisProviderRequest, token: RequestToken) {
            self.unit = unit
            self.request = request
            self.text = request.ssmlRepresentation
            self.token = token
        }

        func deliver(kind: RHVMarkerKind, offset: UInt, length: UInt, bookmark: String?, frame: UInt64) {
            guard token.isActive, let offset = Int(exactly: offset), let length = Int(exactly: length),
                  let unit, let block = unit.speechSynthesisOutputMetadataBlock,
                  let marker = MarkerMapper.marker(kind: kind, utf8Offset: offset, utf8Length: length, bookmark: bookmark, frame: frame, in: text) else {
                return
            }
            block([marker], request)
        }
    }

    private let outputBus: AUAudioUnitBus
    private let engineHolder: EngineHolder
    private var outputBusArray: AUAudioUnitBusArray!
    private let renderState = OSAllocatedUnfairLock(initialState: RenderState())

    @objc
    public override convenience init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions) throws {
        try self.init(componentDescription: componentDescription, options: options, engineHolder: .shared)
    }

    init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions, engineHolder: EngineHolder) throws {
        self.engineHolder = engineHolder
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.outputSampleRate, channels: 1) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.supportedChannelCounts = [1]
        try super.init(componentDescription: componentDescription, options: options)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        RHVLog.synthesizer.info("Audio unit instantiated")
    }

    deinit {
        cancelCurrentSession()
    }

    public override func allocateRenderResources() throws {
        let format = outputBus.format
        guard format.sampleRate == Self.outputSampleRate, format.channelCount == 1,
              format.commonFormat == .pcmFormatFloat32,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        try super.allocateRenderResources()
        let resources = RenderResources(buffer: buffer)
        renderState.withLock { $0.resources = resources }
    }

    public override func deallocateRenderResources() {
        cancelCurrentSession()
        renderState.withLock { $0.resources = nil }
        super.deallocateRenderResources()
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
            let snapshot = engineHolder.catalog()
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
                provided.voiceSize = engineHolder.sizeOnDisk(of: voice)
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
        let token = RequestToken()
        cancelCurrentSession(replacingWith: token)
        // Setup can overlap cancellation or another request. Only this token may
        // publish its session, and old relays must stop sending VoiceOver markers.
        defer {
            renderState.withLock { state in
                if state.token === token && state.session == nil {
                    token.cancel()
                    state.token = nil
                }
            }
        }
        if SharedPreferences.debugLogging {
            RHVLog.synthesizer.debug("Request for \(speechRequest.voice.identifier, privacy: .public): \(speechRequest.ssmlRepresentation, privacy: .public)")
        } else {
            RHVLog.synthesizer.info("Request for \(speechRequest.voice.identifier, privacy: .public) (\(speechRequest.ssmlRepresentation.count, privacy: .public) characters)")
        }
        let identifier = speechRequest.voice.identifier
        let voiceId = VoiceIdentifiers.packId(fromSystemIdentifier: identifier)
        guard let voice = engineHolder.catalog().voices.first(where: { $0.id == voiceId || $0.providerIdentifier == identifier }) else {
            RHVLog.synthesizer.error("Unknown voice \(identifier, privacy: .public)")
            return
        }
        do {
            guard token.isActive else { return }
            let engine = try engineHolder.engine()
            guard token.isActive else { return }
            let options = RHVSynthesisOptions()
            options.outputSampleRate = Self.outputSampleRate
            let relay = SharedPreferences.markersEnabled ? MarkerRelay(unit: self, request: speechRequest, token: token) : nil
            let handler: RHVMarkerHandler? = relay.map { relay in
                { kind, offset, length, bookmark, frame in
                    relay.deliver(kind: kind, offset: offset, length: length, bookmark: bookmark, frame: frame)
                }
            }
            let session = try engine.startSession(withSSML: speechRequest.ssmlRepresentation, voiceName: voice.name, options: options, markerHandler: handler)
            let installed = renderState.withLock { state in
                guard state.token === token else { return false }
                state.session = session
                return true
            }
            if !installed { session.cancel() }
        } catch {
            RHVLog.synthesizer.error("Cannot start synthesis: \(error.localizedDescription, privacy: .public)")
        }
    }

    public override func cancelSpeechRequest() {
        RHVLog.synthesizer.info("Cancel requested")
        cancelCurrentSession()
    }

    private func cancelCurrentSession(replacingWith token: RequestToken? = nil) {
        let previous = renderState.withLock { state in
            let current = (state.token, state.session)
            state.token = token
            state.session = nil
            return current
        }
        previous.0?.cancel()
        previous.1?.cancel()
    }

    // MARK: Rendering

    public override var internalRenderBlock: AUInternalRenderBlock {
        let renderState = self.renderState
        return { actionFlags, _, frameCount, outputBusNumber, outputData, _, _ in
            guard outputBusNumber == 0 else { return kAudioUnitErr_InvalidElement }
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count == 1 else {
                return kAudioUnitErr_InvalidParameter
            }
            let (token, session, resources) = renderState.withLock { ($0.token, $0.session, $0.resources) }
            guard let resources else { return kAudioUnitErr_Uninitialized }
            guard frameCount <= resources.buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
            let frames = Int(frameCount)
            let byteCount = frameCount * UInt32(MemoryLayout<Float>.size)
            if buffers[0].mData == nil {
                // Hosts are allowed to request storage owned by the Audio Unit.
                buffers[0].mData = UnsafeMutableRawPointer(resources.buffer.floatChannelData![0])
            } else if buffers[0].mDataByteSize < byteCount {
                return kAudioUnitErr_InvalidParameter
            }
            let output = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            var written: UInt32 = 0
            var status: RHVRenderStatus = token == nil ? .complete : .rendering
            if let session {
                // The speech host pulls offline and may request audio faster than it is
                // synthesized. Fill the whole buffer across engine chunks; padding a short
                // read or a synthesis timeout with silence inserts audible gaps. Cancellation
                // aborts the queue and wakes this wait without holding renderState's lock.
                status = session.render(into: output, frameCount: frameCount, maxWaitMilliseconds: RHVRenderWaitForever, framesWritten: &written)
                let finished = status != .rendering
                let stillCurrent = renderState.withLock { state in
                    guard state.token === token && state.session === session else { return false }
                    if finished {
                        state.session = nil
                        state.token = nil
                    }
                    return true
                }
                if !stillCurrent {
                    // An old render must neither play cancelled samples nor complete
                    // the newer request that replaced it while it was waiting.
                    written = 0
                    status = .rendering
                }
            }
            if Int(written) < frames {
                (output + Int(written)).initialize(repeating: 0, count: frames - Int(written))
            }
            buffers[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
            buffers[0].mNumberChannels = 1
            if status != .rendering {
                actionFlags.pointee.insert(.offlineUnitRenderAction_Complete)
            }
            return noErr
        }
    }
}
