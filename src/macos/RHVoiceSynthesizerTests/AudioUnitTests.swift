// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import AudioToolbox
import XCTest

final class AudioUnitTests: XCTestCase {
    private func unit() throws -> RHVoiceAudioUnit {
        let description = AudioComponentDescription(componentType: kAudioUnitType_SpeechSynthesizer,
                                                    componentSubType: 0x72687663, componentManufacturer: 0x5248566f,
                                                    componentFlags: 0, componentFlagsMask: 0)
        let unit = try RHVoiceAudioUnit(componentDescription: description, options: [], engineHolder: EngineHolder(layout: nil))
        unit.maximumFramesToRender = 512
        return unit
    }

    private func render(_ unit: RHVoiceAudioUnit, frames: UInt32 = 512, bus: Int = 0,
                        buffer: inout AudioBufferList, flags: inout AudioUnitRenderActionFlags) -> OSStatus {
        var timestamp = AudioTimeStamp()
        return unit.internalRenderBlock(&flags, &timestamp, frames, bus, &buffer, nil, nil)
    }

    func testHostCanRequestAudioUnitOwnedBuffer() throws {
        let unit = try unit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        var flags: AudioUnitRenderActionFlags = .offlineUnitRenderAction_Render
        XCTAssertEqual(render(unit, buffer: &buffer, flags: &flags), noErr)
        let pointer = try XCTUnwrap(buffer.mBuffers.mData?.assumingMemoryBound(to: Float.self))
        XCTAssertEqual(buffer.mBuffers.mDataByteSize, 512 * 4)
        XCTAssertTrue(UnsafeBufferPointer(start: pointer, count: 512).allSatisfy { $0 == 0 })
        XCTAssertTrue(flags.contains(.offlineUnitRenderAction_Complete))
        XCTAssertTrue(flags.contains(.offlineUnitRenderAction_Render))
    }

    func testRenderValidatesAllocationBusAndFrameCapacity() throws {
        let unit = try unit()
        var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        var flags: AudioUnitRenderActionFlags = []
        XCTAssertEqual(render(unit, buffer: &buffer, flags: &flags), kAudioUnitErr_Uninitialized)
        try unit.allocateRenderResources()
        XCTAssertEqual(render(unit, frames: 513, buffer: &buffer, flags: &flags), kAudioUnitErr_TooManyFramesToProcess)
        XCTAssertEqual(render(unit, bus: 1, buffer: &buffer, flags: &flags), kAudioUnitErr_InvalidElement)
        unit.deallocateRenderResources()
        XCTAssertEqual(render(unit, buffer: &buffer, flags: &flags), kAudioUnitErr_Uninitialized)
    }

    func testUnsupportedHostSampleRateIsRejected() throws {
        let unit = try unit()
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!)
        XCTAssertThrowsError(try unit.allocateRenderResources())
    }

    func testHostBufferCapacityIsCheckedBeforeWriting() throws {
        let unit = try unit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        var sample: Float = 123
        withUnsafeMutablePointer(to: &sample) { pointer in
            var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 4, mData: pointer))
            var flags: AudioUnitRenderActionFlags = []
            XCTAssertEqual(render(unit, buffer: &buffer, flags: &flags), kAudioUnitErr_InvalidParameter)
        }
        XCTAssertEqual(sample, 123)
    }
}

extension AudioUnitTests {
    private final class ConcurrentProvider: @unchecked Sendable {
        let unit: RHVoiceAudioUnit
        let voice: AVSpeechSynthesisProviderVoice
        init(unit: RHVoiceAudioUnit, voice: AVSpeechSynthesisProviderVoice) {
            self.unit = unit
            self.voice = voice
        }
    }

    func testRapidConcurrentRequestsCannotSurviveFinalCancellation() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = repo.appendingPathComponent("data")
        guard FileManager.default.fileExists(atPath: data.appendingPathComponent("voices/alan/voice.info").path) else {
            throw XCTSkip("Initialize the Alan and English submodules for synthesis tests")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("data"), withDestinationURL: data)
        let layout = DataLayout(root: root)
        try layout.ensureDirectories()
        let description = AudioComponentDescription(componentType: kAudioUnitType_SpeechSynthesizer,
                                                    componentSubType: 0x72687663, componentManufacturer: 0x5248566f,
                                                    componentFlags: 0, componentFlagsMask: 0)
        let unit = try RHVoiceAudioUnit(componentDescription: description, options: [], engineHolder: EngineHolder(layout: layout))
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        let voice = try XCTUnwrap(unit.speechVoices.first { $0.name == "Alan" })
        let provider = ConcurrentProvider(unit: unit, voice: voice)
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            if i % 3 == 0 {
                provider.unit.cancelSpeechRequest()
            } else {
                let request = AVSpeechSynthesisProviderRequest(ssmlRepresentation: "<speak>Navigation announcement number \(i).</speak>", voice: provider.voice)
                provider.unit.synthesizeSpeechRequest(request)
            }
        }
        unit.cancelSpeechRequest()
        var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        var flags: AudioUnitRenderActionFlags = []
        XCTAssertEqual(render(unit, buffer: &buffer, flags: &flags), noErr)
        XCTAssertTrue(flags.contains(.offlineUnitRenderAction_Complete))
        let pointer = try XCTUnwrap(buffer.mBuffers.mData?.assumingMemoryBound(to: Float.self))
        XCTAssertTrue(UnsafeBufferPointer(start: pointer, count: 512).allSatisfy { $0 == 0 })
    }
}
