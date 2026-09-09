// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import AVFAudio
import Foundation

enum DemoError: Error, LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "The demo clip is in a format this app cannot play."
    }
}

/// Downloads demo clips into the cache and decodes them. The index mixes Ogg Vorbis clips
/// (rhvoice.org) and MP3 clips (GitHub releases); macOS decodes MP3 natively, Ogg Vorbis goes
/// through the bundled stb_vorbis decoder.
enum DemoDecoder {
    static func cachedDemo(for voiceId: String, url: URL, cacheDirectory: URL) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let target = cacheDirectory.appendingPathComponent("\(voiceId).\(ext)")
        if fm.fileExists(atPath: target.path) {
            return target
        }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.badResponse(http.statusCode)
        }
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: temporary, to: target)
        return target
    }

    static func decode(_ file: URL) async throws -> AVAudioPCMBuffer {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        if data.starts(with: Array("OggS".utf8)) {
            return try OggVorbisDecoder.decode(data)
        }
        let audioFile = try AVAudioFile(forReading: file)
        let format = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: audioFile.processingFormat.channelCount)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
            throw DemoError.unsupportedFormat
        }
        try audioFile.read(into: buffer)
        return buffer
    }
}
