// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import CryptoKit
import Foundation

enum DownloadError: Error, LocalizedError {
    case badResponse(Int)
    case checksumMismatch
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "The server answered with status \(code)."
        case .checksumMismatch: return "The downloaded file is damaged (checksum mismatch)."
        case .cancelled: return "Cancelled."
        }
    }
}

/// Streams a pack archive to disk with progress, resuming a partial download when the server
/// supports byte ranges, and verifies the index's MD5 digest (base64) like the Android app.
/// A pack without a digest in the index is accepted unverified, as on Android.
enum PackageDownloader {
    typealias Progress = @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void

    static func download(from url: URL, to destination: URL, expectedMD5: Data?, progress: @escaping Progress) async throws {
        let partial = destination.appendingPathExtension("part")
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        var resumeOffset: Int64 = 0
        if let size = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value, size > 0 {
            resumeOffset = size
            request.setValue("bytes=\(size)-", forHTTPHeaderField: "Range")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var appending = false
        switch http.statusCode {
        case 206:
            appending = true
        case 200:
            resumeOffset = 0
        case 416:
            // The partial file is already complete (or bogus); start over.
            try? fm.removeItem(at: partial)
            return try await download(from: url, to: destination, expectedMD5: expectedMD5, progress: progress)
        default:
            throw DownloadError.badResponse(http.statusCode)
        }

        if !appending {
            fm.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        if appending {
            try handle.seekToEnd()
        }
        let expectedTotal: Int64? = http.expectedContentLength >= 0 ? http.expectedContentLength + resumeOffset : nil
        var received = resumeOffset
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    lastReport = Date()
                    progress(received, expectedTotal)
                }
            }
            try Task.checkCancellation()
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        try handle.close()
        progress(received, expectedTotal)

        if let expectedMD5 {
            let digest = try md5(of: partial)
            guard Data(digest) == expectedMD5 else {
                try? fm.removeItem(at: partial)
                throw DownloadError.checksumMismatch
            }
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: partial, to: destination)
    }

    static func md5(of url: URL) throws -> Insecure.MD5Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }
}
