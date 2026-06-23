import XCTest
@testable import Echoelmusic

@MainActor
final class SessionRecorderTests: XCTestCase {

    private func frame(hr: Float, hrv: Float = 0.5, coh: Float = 0.5, ts: TimeInterval) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: ts, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: 12, breathPhase: 0.5, coherence: coh,
            motionEnergy: 0, source: .fallback
        )
    }

    private func freshRecorder() -> (SessionRecorder, UserDefaults, String) {
        let suite = "SessionRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SessionRecorder(defaults: defaults), defaults, suite)
    }

    func testIngest_averagesAcrossFrames() {
        let (rec, _, suite) = freshRecorder()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        rec.ingest(frame(hr: 100, ts: 1))
        rec.ingest(frame(hr: 200, ts: 2))
        let s = rec.currentSummary()
        XCTAssertEqual(s.avgHeartRate, 150, accuracy: 1e-3)
        XCTAssertEqual(s.sampleCount, 2)
    }

    func testIngest_dedupsOnTimestamp() {
        let (rec, _, suite) = freshRecorder()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        rec.ingest(frame(hr: 100, ts: 5))
        rec.ingest(frame(hr: 999, ts: 5)) // same ts → ignored
        let s = rec.currentSummary()
        XCTAssertEqual(s.sampleCount, 1)
        XCTAssertEqual(s.avgHeartRate, 100, accuracy: 1e-3)
    }

    func testIngest_tracksPeakCoherence() {
        let (rec, _, suite) = freshRecorder()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        rec.ingest(frame(hr: 80, coh: 0.3, ts: 1))
        rec.ingest(frame(hr: 80, coh: 0.9, ts: 2))
        rec.ingest(frame(hr: 80, coh: 0.5, ts: 3))
        XCTAssertEqual(rec.currentSummary().peakCoherence, 0.9, accuracy: 1e-6)
    }

    func testEmptySummary_isZeroSamples() {
        let (rec, _, suite) = freshRecorder()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let s = rec.currentSummary()
        XCTAssertEqual(s.sampleCount, 0)
        XCTAssertEqual(s.avgCoherence, 0)
    }

    func testStop_persistsAndReloads() {
        let suite = "SessionRecorderTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let bus = EngineBus()

        let rec = SessionRecorder(defaults: defaults)
        rec.start(subscribing: bus)
        rec.ingest(frame(hr: 120, coh: 0.7, ts: 100))
        rec.ingest(frame(hr: 140, coh: 0.8, ts: 101))
        let saved = rec.stop()
        XCTAssertEqual(saved?.sampleCount, 2)
        XCTAssertEqual(rec.sessions.count, 1)

        // A new recorder on the same defaults reloads the saved session.
        let reloaded = SessionRecorder(defaults: defaults)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions.first?.avgHeartRate ?? 0, 130, accuracy: 1e-3)
    }

    func testStop_withNoSamples_savesNothing() {
        let (rec, _, suite) = freshRecorder()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let bus = EngineBus()
        rec.start(subscribing: bus)
        let saved = rec.stop() // no ingests
        XCTAssertNil(saved)
        XCTAssertTrue(rec.sessions.isEmpty)
    }
}

/// Pure analytics over saved sessions — streak + coherence trend.
final class SessionStatsTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    /// "now" anchor: 2026-06-23 12:00 UTC.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 6, day: 23, hour: 12))! }

    private func summary(daysAgo: Int, coh: Float = 0.5) -> BioSessionSummary {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
        return BioSessionSummary(date: day, durationSeconds: 600, avgCoherence: coh,
                                 peakCoherence: coh, sampleCount: 600)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let s = [summary(daysAgo: 0), summary(daysAgo: 1), summary(daysAgo: 2)]
        XCTAssertEqual(SessionStats.streakDays(s, calendar: cal, now: now), 3)
    }

    func testStreakSurvivesNotPracticedYetToday() {
        // No session today, but yesterday + the day before → streak of 2 (grace).
        let s = [summary(daysAgo: 1), summary(daysAgo: 2)]
        XCTAssertEqual(SessionStats.streakDays(s, calendar: cal, now: now), 2)
    }

    func testStreakBreaksOnAMissedDay() {
        // Today + a gap at day 1 → only today counts.
        let s = [summary(daysAgo: 0), summary(daysAgo: 2), summary(daysAgo: 3)]
        XCTAssertEqual(SessionStats.streakDays(s, calendar: cal, now: now), 1)
    }

    func testStreakIsZeroWhenStale() {
        let s = [summary(daysAgo: 5)]
        XCTAssertEqual(SessionStats.streakDays(s, calendar: cal, now: now), 0)
    }

    func testStreakEmptyIsZero() {
        XCTAssertEqual(SessionStats.streakDays([], calendar: cal, now: now), 0)
    }

    func testMultipleSessionsSameDayCountOnce() {
        let s = [summary(daysAgo: 0, coh: 0.4), summary(daysAgo: 0, coh: 0.6), summary(daysAgo: 1)]
        XCTAssertEqual(SessionStats.streakDays(s, calendar: cal, now: now), 2)
    }

    func testCoherenceTrendPositiveWhenImproving() {
        // newest-first: recent two high, prior two low → positive trend.
        let s = [summary(daysAgo: 0, coh: 0.8), summary(daysAgo: 1, coh: 0.8),
                 summary(daysAgo: 2, coh: 0.4), summary(daysAgo: 3, coh: 0.4)]
        XCTAssertGreaterThan(SessionStats.coherenceTrend(s, window: 2), 0)
    }

    func testCoherenceTrendZeroWithoutEnoughHistory() {
        XCTAssertEqual(SessionStats.coherenceTrend([summary(daysAgo: 0)], window: 5), 0, accuracy: 1e-6)
    }
}
