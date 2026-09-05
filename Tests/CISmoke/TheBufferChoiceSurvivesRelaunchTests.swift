import XCTest
@testable import Echoelmusic

/// #1004 — the buffer tier a performer chose survives the relaunch.
///
/// WHY IT EXISTS. The only latency control in the app was `@State`. A performer who felt the
/// play surface lagging, dug into MASTER → "Audio input" (a *microphone* sheet — nobody tuning
/// touch response looks there), set Ultra (128 frames, ~2.7 ms) and finally got a responsive
/// instrument, was handed 512 back on the next launch with the segmented control cheerfully
/// reading "Normal". The control worked; it just did not remember, which is the kind of defect
/// a user reads as "this app is laggy" rather than as a bug.
///
/// ⚠️ THE SHIPPED DEFAULT IS UNTOUCHED AND STAYS FOUNDER-GATED. 512 is ~10.7 ms, already past
/// this repo's own <10 ms target — a real finding, deliberately NOT fixed here, because a
/// smaller default trades against dropouts on weaker devices and `LatencyMode`'s own doc argues
/// that trade at length. Claim 4 pins the default so this slice cannot quietly become that one.
///
/// ⭐ THE DESIGN DECISION WORTH GUARDING is claim 2. Restoring by writing `currentBufferSize`
/// from the stored string would have been one line — and would have reinstated the exact defect
/// #674/#675 removed: that constant is what `latencyStats()`, the breadcrumb and the on-screen
/// floor all read, and the whole repair was that it moves only AFTER a request the session
/// granted. The restore therefore goes through `setLatencyMode`, the one producer.
///
/// ⚠️ HONEST GRADING, measured rather than assumed. Five claims, transcribed against both
/// trees: **all five are green on the worktree and red on `HEAD`.** I wrote "4 and 5 are
/// counterweights green on both trees" first — the same guess I had just corrected one slice
/// earlier — and the transcription contradicted it again, for a reason that is obvious in
/// hindsight: `StudioDefaultKeys.audioLatencyMode` does not exist one commit back, so even a
/// claim whose PURPOSE is to pin the future cannot compile against the past.
///
/// **A claim's grading and a claim's job are two different questions**, and only the first is
/// measurable by transcription. The jobs here:
///   · 1, 2, 3 prove the repair — no key, no restore, no persistence on `HEAD`
///   · 4 goes red the day the fresh-install tier changes, which is a FOUNDER decision
///   · 5 goes red the day the restore is moved after the two lines that report the buffer, at
///     which point the founder's exported log would print 512 for a session running at 128
final class TheBufferChoiceSurvivesRelaunchTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — LOAD-BEARING, BEHAVIOURAL: the tier round-trips through the real key.
    func testTheTierRoundTripsThroughTheRealKey() {
        let key = StudioDefaultKeys.audioLatencyMode.key
        let suite = "echoel.tests.buffer.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("could not open a throwaway defaults suite — that is a finding, "
                           + "not a reason to skip (#806: a skip is not a pass).")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(defaults.string(forKey: key), """
            A fresh suite already carries \(key). The round trip below would then prove \
            nothing, because the value it reads back could predate the write.
            """)
        defaults.set(AudioConfiguration.LatencyMode.ultraLow.rawValue, forKey: key)
        XCTAssertEqual(AudioConfiguration.LatencyMode(rawValue: defaults.string(forKey: key) ?? ""),
                       .ultraLow, """
            The stored rawValue does not map back to the tier that wrote it. Persisting a tier \
            that cannot be read back is worse than not persisting: the restore then silently \
            takes the "unrecognised string" path and the player's choice vanishes with no log.
            """)
        XCTAssertNil(AudioConfiguration.LatencyMode(rawValue: "turbo"), """
            An unknown tier name resolves to a mode. The restore must fall through to no \
            restore rather than to a nearest guess — the same reasoning `currentLatencyMode` \
            gives for returning nil on an unnamed buffer size.
            """)
    }

    // 2 — LOAD-BEARING: the restore respects the one-producer law.
    func testTheRestoreGoesThroughTheOneProducer() throws {
        let text = try source(Self.config)
        guard let range = text.range(of: "static func applyStoredLatencyMode()") else {
            return XCTFail("""
                `applyStoredLatencyMode()` is gone from \(Self.config). Without it the picker \
                writes a preference nothing ever reads, which looks more finished than a plain \
                `@State` control while behaving identically.
                """)
        }
        let body = String(text[range.lowerBound...].prefix(1400))
        XCTAssertTrue(body.contains("try setLatencyMode(mode)"), """
            The restore no longer calls `setLatencyMode`. Writing `currentBufferSize` from the \
            stored string directly is the tempting one-liner and it reinstates the defect \
            #674/#675 removed: that constant feeds `latencyStats()`, the breadcrumb and the \
            on-screen floor, and the whole repair was that it moves only after a request the \
            session GRANTED.
            """)
        XCTAssertTrue(body.contains("catch"), """
            The restore does not catch. A refused tier would then throw out of `prepareGraph`'s \
            ladder and take the rungs after it down with it — a stored preference must never be \
            able to break the launch it is trying to improve.
            """)
    }

    // 3 — LOAD-BEARING: the write happens, and only after the request.
    func testThePreferenceIsWrittenAfterTheRequest() throws {
        let text = try source(Self.config)
        guard let setRange = text.range(of: "static func setLatencyMode("),
              let writeRange = text.range(
                of: "UserDefaults.standard.set(mode.rawValue, forKey: StudioDefaultKeys.audioLatencyMode.key)") else {
            return XCTFail("""
                `setLatencyMode` no longer persists the chosen tier, so the control is back to \
                forgetting — the whole defect this slice repairs.
                """)
        }
        XCTAssertLessThan(setRange.lowerBound, writeRange.lowerBound,
                          "the persistence line is no longer inside setLatencyMode")
        let between = String(text[setRange.lowerBound..<writeRange.lowerBound])
        XCTAssertTrue(between.contains("setPreferredIOBufferDuration"), """
            The preference is written BEFORE the session request. A tier the session refuses \
            would then come back on the next launch as if it had worked — the same ordering \
            defect the ⚠️ block above `setLatencyMode` already retracted once for \
            `currentBufferSize`.
            """)
    }

    // 4 — COUNTERWEIGHT: the founder's default is not quietly improved.
    func testTheShippedDefaultIsUnchanged() {
        XCTAssertEqual(StudioDefaultKeys.audioLatencyMode.value, "normal", """
            The fresh-install buffer tier changed. That is a FOUNDER decision, not a cleanup: \
            512 is battery-friendly and a smaller default trades against dropouts on weaker \
            devices, which is exactly the argument `LatencyMode`'s doc makes. This slice makes \
            the player's choice stick; it must not make the choice for them.
            """)
        XCTAssertEqual(AudioConfiguration.normalBufferSize, 512, """
            `normalBufferSize` moved. Same reasoning — and every latency number printed in the \
            founder's diagnostics log is derived from it.
            """)
    }

    // 5 — COUNTERWEIGHT: the log cannot disagree with the ears.
    func testTheRestoreRunsBeforeTheBufferIsReported() throws {
        let text = try source(Self.engine)
        guard let restore = text.range(of: "AudioConfiguration.applyStoredLatencyMode()"),
              let stats = text.range(of: "log.audio(AudioConfiguration.latencyStats())") else {
            return XCTFail("""
                Either the launch restore or the latency report is gone from \(Self.engine). \
                Both are load-bearing for this slice: without the restore the preference is \
                write-only, and the report is where a wrong order would show.
                """)
        }
        XCTAssertLessThan(restore.lowerBound, stats.lowerBound, """
            The stored tier is restored AFTER the latency report. Both the report and the \
            breadcrumb read `currentBufferSize`, so the founder's exported log would print the \
            shipped 512 for a session actually running at 128 — a diagnostics file that \
            contradicts the device is worse than one that is missing.
            """)
    }
}
