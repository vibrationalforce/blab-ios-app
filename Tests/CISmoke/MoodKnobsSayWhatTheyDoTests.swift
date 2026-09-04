// MoodKnobsSayWhatTheyDoTests.swift
// Echoel — #354 Slice A. Two of the eight mood dials are SWITCHES, and until this slice the
// panel rendered all eight identically, to four decimals.
//
// ⭐ THE DEFECT, stated as the audit stated it. `MoodProfile` advertises eight continuous
// characters. Six of them are read as gradients by the composer. `darkness` and `romance` are
// each read ONCE on the live path, as a comparison: `mood.darkness > 0.6` drops the whole
// voicing an octave, `mood.romance > 0.5` adds the 7th. So a user moving Darkness from 0.20 to
// 0.59 — a third of the control's travel — hears nothing, and the row said `0.5900` while doing
// it. The mood library's own source comment reached the same finding from the other side: "Two
// moods can therefore differ by 0.43 of darkness and produce the SAME notes."
//
// ⛔ "ONCE ON THE LIVE PATH", NOT "ONCE". `darkness` is read TWICE in `BioComposer` — the second
// read is in `ambientMelody`, which has had no callers since `.selfObservation` stopped being
// intercepted, and `WeatherMood`'s own doc already says "twice" from that same count. The
// unqualified word would have contradicted a note that is already in the repo.
//
// ⭐ WHAT THIS FILE IS AND IS NOT. It does not assert that thresholds are the right design —
// they are not, and `romance` is scheduled to become a real gradient in its own slice because
// that one changes shipped sound. It asserts the COUPLING: as long as the engine reads these
// two as switches, the caption in `moodPanel` must say so, and the rows must not offer four
// decimals of a quantity with two states. When someone makes `romance` continuous,
// `testRomanceIsInertWhereTheChordAlreadyHasTheSeventh` goes red — that is the point. It is a
// reminder to move the caption in the same commit, not an argument to keep the cliff.
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
//   · The darkness half asserts "at least one genre changes", not a count. Crossing 0.60 shifts
//     the pad/bass octave, but `VoiceLeader.resolve` re-octaves the voicing afterwards, so
//     whether a specific genre's take differs is a property of the voice-leader's cost function,
//     not of the switch. Pinning a count there would pin an unrelated decision. The romance half
//     CAN be exact, because its guard is a plain `!tones.contains(6)` on data this file reads.

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

    /// The genres where romance can do anything at all: its only read is
    /// `if mood.romance > 0.5, !tones.contains(6)`, so a chord that already carries the 7th is
    /// indifferent to the dial at every setting.
    private static var genresWithoutTheSeventh: [MusicStyle] {
        MusicStyle.offered.filter { !$0.harmonicProfile.chordTones.contains(6) }
    }

    // MARK: - The two cliffs, measured

    /// ⭐ Below the line, a third of the control's travel does nothing — at EVERY offered genre,
    /// which is why this half sweeps rather than samples. Above it, at least one genre changes.
    ///
    /// "At least one" and not a count: see the HONEST LIMITS note in the header — the octave
    /// shift goes through `VoiceLeader.resolve`, which re-octaves. The count is printed so a
    /// future narrowing is visible rather than silent.
    func testDarknessIsASwitchAtTheAdvertisedPoint() {
        var changedAbove = 0
        for style in MusicStyle.offered {
            let low = Self.take(darkness: 0.20, style: style)
            let justUnder = Self.take(darkness: 0.59, style: style)
            XCTAssertEqual(low, justUnder, """
                Genre “\(style.rawValue)”: darkness 0.20 and 0.59 no longer produce the same \
                take. If darkness became a gradient, this file's premise changed — update the \
                `moodPanel` caption (it currently promises the octave drop above 0.60) in the \
                SAME commit, then delete this expectation.
                """)
            if Self.take(darkness: 0.61, style: style) != justUnder { changedAbove += 1 }
        }
        XCTAssertGreaterThan(changedAbove, 0, """
            Crossing 0.60 changed NOTHING at any of \(MusicStyle.offered.count) offered genres. \
            Either the octave shift lost its reader, or the composer stopped reaching the pad \
            path — in both cases the caption's promise is now false.
            """)
    }

    /// The same shape for romance's 7th, on the genres it can reach. This is the test that goes
    /// red when romance becomes a gradient — deliberately, see the header.
    func testRomanceIsASwitchAtTheAdvertisedPoint() {
        var changedAbove = 0
        for style in Self.genresWithoutTheSeventh {
            let low = Self.take(romance: 0.10, style: style)
            let justUnder = Self.take(romance: 0.49, style: style)
            XCTAssertEqual(low, justUnder, """
                Genre “\(style.rawValue)”: romance 0.10 and 0.49 no longer produce the same \
                take. If this is the slice that made romance continuous: good — move the \
                `moodPanel` caption off the 0.50 threshold in the same commit.
                """)
            if Self.take(romance: 0.51, style: style) != justUnder { changedAbove += 1 }
        }
        XCTAssertGreaterThan(changedAbove, 0, """
            Crossing 0.50 changed NOTHING at any of the \(Self.genresWithoutTheSeventh.count) \
            genres whose chord lacks the 7th, so the romance dial reaches no sound at all — that \
            is worse than the cliff this file documents, not better.
            """)
    }

    /// ⭐ THE HALF THE REVIEW ADDED, AND THE REASON THE CAPTION IS WORDED THE WAY IT IS. Romance
    /// is not merely a switch; on a genre whose chord already carries the 7th it is INERT at
    /// every setting — and that is 10 of the 19 offered genres, `.selfObservation` (the shipped
    /// default) among them. The first version of the caption promised "adds the 7th above 0.50"
    /// flat, which is false for the genre a first-time user hears.
    func testRomanceIsInertWhereTheChordAlreadyHasTheSeventh() {
        let alreadyLush = MusicStyle.offered.filter { $0.harmonicProfile.chordTones.contains(6) }
        XCTAssertFalse(alreadyLush.isEmpty, """
            No offered genre carries the 7th any more, so the caption's "does not already have \
            one" qualifier now covers all of them and should be simplified.
            """)
        for style in alreadyLush {
            XCTAssertEqual(Self.take(romance: 0.49, style: style),
                           Self.take(romance: 0.51, style: style), """
                Genre “\(style.rawValue)” already has the 7th in `chordTones`, so romance's only \
                read (`!tones.contains(6)`) cannot fire — yet the take changed. Romance grew a \
                second reader; the caption now understates it.
                """)
        }
    }

    /// The caption prints "9 of the 19 offered". This pins that number against the profiles
    /// themselves, so adding a genre — or giving an existing one a 7th — makes the caption's
    /// arithmetic fail here rather than on a user's screen.
    func testTheCaptionsGenreCountIsTheRealOne() {
        XCTAssertEqual(MusicStyle.offered.count, 19, """
            The offered roster changed size. The `moodPanel` caption names it ("… of the 19 \
            offered") — update both in the same commit.
            """)
        XCTAssertEqual(Self.genresWithoutTheSeventh.count, 9, """
            \(Self.genresWithoutTheSeventh.count) offered genres lack the 7th, not 9. The \
            `moodPanel` caption names that number too; a caption that counts wrong is the same \
            defect as a caption that promises a switch it does not have.
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
        XCTAssertTrue(code.contains("switch rather than fade"), """
            The caption no longer says these two dials switch. Either the composer became \
            continuous (then say so, and update the behavioural tests above) or a control that \
            switches is being presented as one that fades.
            """)
        XCTAssertTrue(code.contains("above 0.60 Darkness drops the voicing an octave"), """
            The caption no longer names darkness's threshold or what crossing it does — same two \
            cases as above.
            """)
        XCTAssertTrue(code.contains("above 0.50 Romance adds the 7th"), """
            The caption no longer names romance's threshold — same two cases as darkness.
            """)
        XCTAssertTrue(code.contains("does not already have one (9 of the 19 offered)"), """
            The caption dropped romance's QUALIFIER. Without it the sentence promises the 7th on \
            every genre, which is false for 10 of the 19 — including `.selfObservation`, the \
            shipped default. That is the exact overclaim this slice's review found.
            """)
    }

    /// The precision half. `EchoelValueField.decimals` defaults to 4; these eight rows were the
    /// largest set of `0…1` fields in the app that never passed a value. (Not the ONLY set —
    /// `Energy` and `Hue` in the visual panel still take the default. They are image controls,
    /// not composer parameters, and were deliberately left out of this slice.)
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
