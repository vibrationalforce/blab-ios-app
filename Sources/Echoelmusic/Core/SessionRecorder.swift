//
//  SessionRecorder.swift
//  Echoelmusic — Core
//
//  Records a "session": while active it samples the EngineBus bio snapshot
//  once per second and accumulates HR/HRV/coherence averages plus peak
//  coherence, then saves a compact summary. Summaries persist across launches
//  as Codable JSON in UserDefaults — no SwiftData/ModelContainer dependency,
//  so the Works tab is self-contained and cross-platform.
//
//  Averaging is pure and timestamp-deduped (exposed via `ingest`) so it is
//  unit-tested without the bus or a timer. Science-first: only real (or
//  explicitly-labeled Demo) bio frames are counted.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

/// Compact, persistable summary of one recorded session.
public struct BioSessionSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var durationSeconds: Int
    public var avgHeartRate: Float
    public var avgHRV: Float
    public var avgCoherence: Float
    public var peakCoherence: Float
    public var sampleCount: Int
    /// Auto session name (artist · date · key · BPM · Kammerton) stamped at save
    /// time. Optional so summaries persisted before this field still decode.
    public var name: String?

    public init(
        id: UUID = UUID(), date: Date = Date(), durationSeconds: Int = 0,
        avgHeartRate: Float = 0, avgHRV: Float = 0, avgCoherence: Float = 0,
        peakCoherence: Float = 0, sampleCount: Int = 0, name: String? = nil
    ) {
        self.id = id; self.date = date; self.durationSeconds = durationSeconds
        self.avgHeartRate = avgHeartRate; self.avgHRV = avgHRV
        self.avgCoherence = avgCoherence; self.peakCoherence = peakCoherence
        self.sampleCount = sampleCount; self.name = name
    }
}

@MainActor
@Observable
public final class SessionRecorder {

    public private(set) var isRecording = false
    public private(set) var elapsedSeconds = 0
    /// Saved sessions, most-recent first.
    public private(set) var sessions: [BioSessionSummary] = []

    // Live accumulators
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var hrSum: Double = 0
    @ObservationIgnored private var hrvSum: Double = 0
    @ObservationIgnored private var cohSum: Double = 0
    @ObservationIgnored private var peakCoh: Float = 0
    @ObservationIgnored private var count = 0
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private let loop = PollingLoop()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "bioSessions.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Recording lifecycle

    public func start(subscribing bus: EngineBus) {
        guard !isRecording else { return }
        self.bus = bus
        resetAccumulators()
        startDate = Date()
        elapsedSeconds = 0
        isRecording = true
        loop.start(interval: .seconds(1)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            if let frame = bus.latestBio { self.ingest(frame) }
            if let start = self.startDate {
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }
    }

    /// Stops recording and, if any samples were captured, prepends the summary
    /// and persists. Returns the saved summary (nil if nothing was captured).
    @discardableResult
    public func stop(name: String? = nil) -> BioSessionSummary? {
        guard isRecording else { return nil }
        loop.stop()
        isRecording = false
        var summary = currentSummary()
        summary.name = name
        startDate = nil
        guard summary.sampleCount > 0 else { return nil }
        sessions.insert(summary, at: 0)
        save()
        return summary
    }

    public func deleteSessions(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Accumulation (pure, testable)

    /// Folds one frame into the running averages. Deduped on frame timestamp.
    public func ingest(_ frame: BioSampleFrame) {
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp
        hrSum += Double(frame.heartRateBPM)
        hrvSum += Double(frame.hrvNormalized)
        cohSum += Double(frame.coherence)
        peakCoh = max(peakCoh, frame.coherence)
        count += 1
    }

    /// Snapshot of the accumulators as a summary (does not mutate state).
    public func currentSummary() -> BioSessionSummary {
        let n = max(count, 1)
        let duration = startDate.map { Int(Date().timeIntervalSince($0)) } ?? elapsedSeconds
        return BioSessionSummary(
            date: startDate ?? Date(),
            durationSeconds: duration,
            avgHeartRate: count > 0 ? Float(hrSum / Double(n)) : 0,
            avgHRV: count > 0 ? Float(hrvSum / Double(n)) : 0,
            avgCoherence: count > 0 ? Float(cohSum / Double(n)) : 0,
            peakCoherence: peakCoh,
            sampleCount: count
        )
    }

    private func resetAccumulators() {
        hrSum = 0; hrvSum = 0; cohSum = 0; peakCoh = 0; count = 0
        lastFrameTimestamp = -1
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BioSessionSummary].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
