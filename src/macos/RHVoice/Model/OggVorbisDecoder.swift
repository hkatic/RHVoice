// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import Foundation

/// Decodes an Ogg Vorbis file into a PCM buffer using stb_vorbis (ThirdParty/stb_vorbis).
enum OggVorbisDecoder {
    static func decode(_ data: Data) throws -> AVAudioPCMBuffer {
        var channels: Int32 = 0
        var sampleRate: Int32 = 0
        var output: UnsafeMutablePointer<Int16>? = nil
        let frames = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return stb_vorbis_decode_memory(base, Int32(raw.count), &channels, &sampleRate, &output)
        }
        guard frames > 0, channels > 0, sampleRate > 0, let samples = output else {
            throw DemoError.unsupportedFormat
        }
        defer { free(samples) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: AVAudioChannelCount(channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channelData = buffer.floatChannelData else {
            throw DemoError.unsupportedFormat
        }
        let channelCount = Int(channels)
        for frame in 0..<Int(frames) {
            for channel in 0..<channelCount {
                channelData[channel][frame] = Float(samples[frame * channelCount + channel]) / 32768.0
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }
}
