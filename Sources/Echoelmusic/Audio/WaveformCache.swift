// WaveformCache.swift
// Echoel — Stage 2b of the Arrange-timeline plan: turn an audio file into the
// two reduced min/max+RMS tiers the waveform view draws (research-validated pro
// rendering — never draw raw PCM). Chunked AVAudioFile read (no full-file
// buffer), stereo folded to the larger-magnitude channel, results cached in
// memory and on disk (Caches/Waveforms, key = name+size+mtime, so an edited
// file re-reduces and a re-imported identical file hits the cache).
//
// Control-plane only: reduction runs in a detached task; nothing here touches
// the audio render path.

import Foundation

/// The reduced waveform of one audio file, in two mip tiers. The view picks the
/// tier by zoom: `fine` (~256 samples/bucket ≈ 5 ms) for zoomed-in editing,
/// `coarse` (fine × 16 ≈ 85 ms) for the far-out arrangement overview.
public struct WaveformData: Codable, Sendable, Equatable {
    public static let fineBucketSize = 256
    public static let coarseFactor = 16

    public let sampleRate: Double
    public let frameCount: Int64
    public let fine: [WaveformBucket]
    public let coarse: [WaveformBucket]

    public init(sampleRate: Double, frameCount: Int64,
                fine: [WaveformBucket], coarse: [WaveformBucket]) {
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.fine = fine
        self.coarse = coarse
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }
}

/// Stable disk-cache key for a file identity (name + size + mtime). Pure —
/// FNV-1a 64 over the identity string — so it is CI-testable without
/// AVFoundation and never changes across launches.
public enum WaveformCacheKey {
    public static func make(name: String, byteSize: Int64, mtime: Double) -> String {
        let identity = "\(name)|\(byteSize)|\(Int64(mtime))"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

#if canImport(AVFoundation)
import AVFoundation

/// Async provider of `WaveformData` with an in-memory map, a disk cache, and
/// in-flight de-duplication (two views asking for the same file share one
/// reduction). `@MainActor` state; the heavy read/reduce runs detached.
@MainActor
public final class WaveformCache {

    public static let shared = WaveformCache()

    private var memory: [String: WaveformData] = [:]
    private var memoryOrder: [String] = []          // insertion order, for the cap
    private var inFlight: [String: Task<WaveformData?, Never>] = [:]
    private let memoryCap = 16

    private init() {}

    /// The reduced waveform for `url` — from memory, disk, or a fresh chunked
    /// reduction (in that order). Returns nil if the file cannot be read.
    public func waveform(for url: URL) async -> WaveformData? {
        guard let key = Self.key(for: url) else { return nil }
        if let hit = memory[key] { return hit }
        if let running = inFlight[key] { return await running.value }

        let task = Task<WaveformData?, Never>.detached(priority: .utility) {
            if let disk = Self.readDisk(key: key) { return disk }
            guard let data = Self.reduceFile(url: url) else { return nil }
            Self.writeDisk(data, key: key)
            return data
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { store(result, key: key) }
        return result
    }

    private func store(_ data: WaveformData, key: String) {
        if memory[key] == nil {
            memoryOrder.append(key)
            if memoryOrder.count > memoryCap {
                memory[memoryOrder.removeFirst()] = nil
            }
        }
        memory[key] = data
    }

    // MARK: - Identity

    private static func key(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return WaveformCacheKey.make(name: url.lastPathComponent, byteSize: size, mtime: mtime)
    }

    // MARK: - Reduction (detached; chunked — never loads the whole file)

    nonisolated private static func reduceFile(url: URL) -> WaveformData? {
        guard let file = try? AVAudioFile(forReading: url) else {
            log.log(.error, category: .audio, "WaveformCache: cannot read \(url.lastPathComponent)")
            return nil
        }
        let format = file.processingFormat            // float32, deinterleaved
        let totalFrames = file.length
        guard totalFrames > 0 else { return nil }

        // Chunk size is a multiple of the fine bucket size so bucket boundaries
        // stay aligned across chunks (only the file's final bucket may be short).
        let chunkFrames = AVAudioFrameCount(WaveformData.fineBucketSize * 512)   // 131072
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return nil
        }

        var fine: [WaveformBucket] = []
        fine.reserveCapacity(Int(totalFrames) / WaveformData.fineBucketSize + 1)

        file.framePosition = 0
        while file.framePosition < totalFrames {
            do { try file.read(into: buffer, frameCount: chunkFrames) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0, let channels = buffer.floatChannelData else { break }
            let mono: [Float]
            if buffer.format.channelCount >= 2 {
                let left  = [Float](UnsafeBufferPointer(start: channels[0], count: n))
                let right = [Float](UnsafeBufferPointer(start: channels[1], count: n))
                mono = WaveformReducer.foldStereo(left: left, right: right)
            } else {
                mono = [Float](UnsafeBufferPointer(start: channels[0], count: n))
            }
            fine.append(contentsOf: WaveformReducer.reduce(mono, bucketSize: WaveformData.fineBucketSize))
            if n < Int(chunkFrames) { break }        // final partial chunk
        }
        guard !fine.isEmpty else { return nil }

        return WaveformData(
            sampleRate: format.sampleRate,
            frameCount: totalFrames,
            fine: fine,
            coarse: WaveformReducer.downsample(fine, factor: WaveformData.coarseFactor)
        )
    }

    // MARK: - Disk cache (Caches/Waveforms, binary plist)

    nonisolated private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func fileURL(key: String) -> URL? {
        directory?.appendingPathComponent(key).appendingPathExtension("wf")
    }

    nonisolated private static func readDisk(key: String) -> WaveformData? {
        guard let url = fileURL(key: key),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(WaveformData.self, from: raw)
    }

    nonisolated private static func writeDisk(_ data: WaveformData, key: String) {
        guard let url = fileURL(key: key) else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let raw = try? encoder.encode(data) {
            try? raw.write(to: url, options: .atomic)
        }
    }
}
#endif
