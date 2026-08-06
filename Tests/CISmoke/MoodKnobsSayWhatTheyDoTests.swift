// MoodKnobsSayWhatTheyDoTests.swift
// Echoel — #354 Slice A. Two of the eight mood dials are SWITCHES, and until this slice the
// panel rendered all eight identically, to four decimals.
//
// ⭐ THE DEFECT, stated as the audit stated it. `MoodProfile` advertises eight continuous
// characters. Six of them are read as gradients by the composer. `darkness` and `romance` are
// each read ONCE, as a comparison: `mood.darkness > 0.6` drops the whole voicing an octave,
// `mood.romance > 0.5` adds the 7th. So a user moving Darkness from 0.20 to 0.59 — a third of
// the control's travel — hears nothing, and the row said `0.5900` while doing it. The mood
// library's own source comment reached the same finding from the other side: "Two moods can
// therefore differ by 0.43 of darkness and produce the SAME notes."
//
// ⭐ WHAT THIS FILE IS AND IS NOT. It does not assert that thresholds are the right design —
// they are not, and `romance` is scheduled to become a real gradient in its own slice because
// that one changes shipped sound. It asserts the COUPLING: as long as the engine reads these
// two as switches, the caption in `moodPanel` must say so, and the rows must not offer four
// decimals of a quantity with two states. When someone makes `romance` continuous,
// `testRomanceIsASwitchAtTheAdvertisedPoint` goes red — that is the point. It is a reminder to
// move the caption in the same commit, not an argument to keep the cliff.
//
// ⛔ WHY `darkness` IS NOT SCHEDULED WITH IT. Register is quantised by construction:
// `key.degree(_:octave:)` moves in whole octaves (anything finer changes pitch classes and
// leaves the key), and `VoiceLeader.resolve` re-octaves the voicing afterwards anyway. A
// "gradient" there would be a number invented to make a control look continuous. The honest
// fix for that half is the caption, which is why the caption is asserted here and not treated
// as decoration.
//
// ⛔ HONEST LIMITS.
//   · The two copy/precision halves are SOURCE SCANS. They prove the caption and the
//     `decimals:` argument are in the file; they cannot prove the caption renders (that is a
//     device read) and they cannot prove `EchoelValueField` honours `decimals` — its own tests
//     own that.
//   · The behavioural halves compare NOTE SIGNATURES, not `Note` values: `Note.id` is a fresh
//     `UUID` per note, so two identical takes are never `==`.

import Foundation
import XCTest
@testable import Echoelmusic

final class MoodKnobsSayWhatTheyDoTests: XCTestCase {

    // MARK: - Composing the same take twice, with one dial moved

    /// Everything except the dial under test is pinned, including the seed and the tempo, so a
    /// difference in the result can only have come from the dial.
    private static func take(darkness: Float = 0.5,
                             romance: Float = 0.3,
                             style: MusicStyle) -> [[String]] {
        var mood = MoodProfile()
        mood.darkness = darkness
        mood.romance = romance
        let input = BioComposer.Input(heartRateBPM: 132, hrvNormalized: 0.3, coherence: 0.3,
                                      breathPhase: 0.25, breathDepth: 0.7,
                                      key: MusicalKey(root: 0, scale: .minor),
                                      style: style, mode: .studioLocked, lockedTempo: 120,
                                      mood: mood, seed: 0x354A)
        return signature(BioComposer.compose(input).notes)
    }

    /// `Note.id` is a fresh UUID per note, so `[Note] == [Note]` is false for two identical
    /// takes. Everything that reaches an ear is here.
    private static func signature(_ notes: [Note]) -> [[String]] {
        notes.map {
            ["\($0.pitch)", "\($0.startTick)", "\($0.lengthTicks)",
             String(format: "%.6f", Double($0.velocity)), "\($0.role)"]
        }
    }

    // MARK: - The two cliffs, measured

    /// ⭐ Below the line, a third of the control's travel does nothing — at EVERY offered genre,
    /// which is why this half sweeps rather than samples. Above it, at least one genre changes.
    ///
    /// "At least one" and not "every": a genre whose profile never reaches `composeHarmonic`'s
    /// default pad path (the hand-built `dubTechno`/`trap` branches) can be indifferent to the
    /// octave shift, and demanding otherwise would pin an unrelated routing decision. The count
    /// is printed so a future narrowing is visible rather than silent.
    func testDarknessIsASwitchAtTheAdvertisedPoint() {
        var changedAbove = 0
        for style in MusicStyle.offered {
            let low = Self.take(darkness: 0.20, style: style)
            let justUnder = Self.take(darkness: 0.59, style: style)
            XCTAssertEqual(low, justUnder, """
                Genre “\(style.rawValue)”: darkness 0.20 and 0.59 no longer produce the same \
                take. If darkness became a gradient, this file's premise changed — update the \
                `moodPanel` caption (it currently promises "drops the octave above 0.60") in \
                the SAME commit, then delete this expectation.
                """)
            if Self.take(darkness: 0.61, style: style) != justUnder { changedAbove += 1 }
        }
        XCTAssertGreaterThan(changedAbove, 0, """
            Crossing 0.60 changed NOTHING at any of \(MusicStyle.offered.count) offered genres. \
            Either the octave shift lost its reader, or the composer stopped reaching the pad \
            path — in both cases the caption's promise is now false.
            """)
    }

    /// The same shape for romance's 7th. This is the test that goes red when romance becomes a
    /// gradient — deliberately, see the header.
    func testRomanceIsASwitchAtTheAdvertisedPoint() {
        var changedAbove = 0
        for style in MusicStyle.offered {
            let low = Self.take(romance: 0.10, style: style)
            let justUnder = Self.take(romance: 0.49, style: style)
            XCTAssertEqual(low, justUnder, """
                Genre “\(style.rawValue)”: romance 0.10 and 0.49 no longer produce the same \
                take. If this is the slice that made romance continuous: good — move the \
                `moodPanel` caption off "adds the 7th above 0.50" in the same commit.
                """)
            if Self.take(romance: 0.51, style: style) != justUnder { changedAbove += 1 }
        }
        XCTAssertGreaterThan(changedAbove, 0, """
            Crossing 0.50 changed NOTHING at any of \(MusicStyle.offered.count) offered genres, \
            so the romance dial reaches no sound at all — that is worse than the cliff this \
            file documents, not better.
            """)
    }

    // ⭐ THE COUNTERWEIGHT IS DELIBERATELY NOT HERE, AND SAYING WHY IS PART OF THE FILE. The
    // obvious companion assertion is "the OTHER six dials are not switches" — otherwise a later
    // "simplify the mood model" could turn all eight into comparisons and everything above would
    // still pass. That guard exists already and is better than the one this file would write:
    // `LivelinessReachesTheDensityDecisionTests` (#418) sweeps `MusicStyle.offered` and demands
    // two liveliness values produce DIFFERENT takes, and `LivelinessMovesTheStillnessGateTests`
    // (#419) does the same for the sustained genres the first one cannot reach. Restating it here
    // with numbers I cannot run would add a second, weaker copy of a live assertion — the
    // duplicate-definition defect #416 is about, one file over.

    // MARK: - The panel must say it

    /// ⛔ ANCHOR FIRST, OR THE SCAN CANNOT FAIL (#367). Assert the caption exists before
    /// asserting what it contains, otherwise a deleted caption reads as a passing test.
    func testTheMoodCaptionNamesBothSwitches() throws {
        let code = try Self.studioSource()
        XCTAssertTrue(code.contains("Blends with your live signal"), """
            The mood panel's caption is gone or reworded past recognition. It is the only place \
            the two threshold dials are explained; if it moved, move these assertions with it.
            """)
        XCTAssertTrue(code.contains("drops the octave above 0.60"), """
            The caption no longer names darkness's threshold. Either the composer became \
            continuous (then say so, and update the behavioural tests above) or a control that \
            switches is being presented as one that fades.
            """)
        XCTAssertTrue(code.contains("adds the 7th above 0.50"), """
            The caption no longer names romance's threshold — same two cases as darkness.
            """)
    }

    /// The precision half. `EchoelValueField.decimals` defaults to 4; these rows were the only
    /// `0…1` fields in the app that never passed a value.
    func testMoodRowsOfferTwoDecimals() throws {
        let code = try Self.studioSource()
        guard let range = code.range(of: "private func moodKnob(") else {
            return XCTFail("`moodKnob` is gone — the eight mood rows are built somewhere else now")
        }
        let body = code[range.lowerBound...].prefix(400)
        XCTAssertTrue(body.contains("decimals: 2"), """
            `moodKnob` stopped passing `decimals: 2`, so the eight mood rows fall back to \
            `EchoelValueField`'s default of 4 and read `0.5000` — the state #354 found. Two is \
            the app's own idiom for a 0…1 row (every FX parameter, master volume, the weather \
            mixers).
            """)
    }

    // MARK: - Reading the source

    /// Comments stripped, because this file's own prose quotes every string it forbids and the
    /// source file quotes them too (the #416 trap: a scan that reads its own documentation).
    private static func studioSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/CISmoke
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("EchoelStudioView.swift not present — this scan cannot report green")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop { $0 == " " }
                if trimmed.hasPrefix("//") { return "" }
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined(separator: "\n")
    }
}
