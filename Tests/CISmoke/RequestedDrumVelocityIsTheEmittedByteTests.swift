//
//  RequestedDrumVelocityIsTheEmittedByteTests.swift
//  EchoelmusicTests (CISmoke — the BLOCKING bundle)
//
//  #474. `MIDIFileExporter.drumEvents` split ±20 around the requested `velocity` to keep an
//  accented beat's dynamics alive in the export. With an EMPTY `accents` array every cell
//  took the quiet side, so a caller asking for 100 got 80 on every hit and the number it
//  asked for appeared nowhere in the file. That is not "dynamics survive" — with no accent
//  information there is no dynamic to preserve, only a uniform −20. #474 emits `velocity`
//  literally in exactly that case and leaves the split untouched everywhere else.
//
//  ⭐ THIS FILE IS BEHAVIOURAL, WHICH IS RARE IN THIS BUNDLE AND WORTH SAYING. Most guards
//  here are source-text scans because their subject is `private`, `@MainActor`, or needs a
//  device. `MIDIFileExporter` is `public`, Foundation-only and deterministic: every assertion
//  below drives the SHIPPED function and reads the SHIPPED bytes. Nothing here proves a
//  claim about where text sits.
//
//  ⚠️ HONEST GRADING, because the flattering version would call all six regressions. Exactly
//  TWO are red against the pre-#474 tree:
//    · `testAnExportWithoutAccentsWritesTheRequestedVelocity` — the defect itself.
//    · `testTheTwoExportersAgreeWhenThereAreNoAccents` — the same fact stated as the property
//      rather than as a number, so it survives someone re-deciding the 100.
//  The other four are COUNTERWEIGHTS and are green on both sides. They exist because the
//  obvious next tidy-up is "the exporter emits what you ask for, delete the split" — which
//  would silently flatten every accented pattern a caller DOES supply.
//
//  ⚠️ THE SEAM IS `accents.isEmpty` AND NOTHING FINER, and one counterweight pins precisely
//  that: a PRESENT accent array whose cells are all `false` still takes the −20. The caller
//  declared accent information and said none of these are accented — a different statement
//  from not having any. Widening the seam to "no cell is accented" is a second decision, not
//  a cleanup.
//
//  ⚠️ WHAT THIS CANNOT SHOW: that any user ever receives these bytes. Measured before
//  writing it — `MIDIFileExporter.export(clip:)` has zero call sites in `Sources/`, and the
//  ONE live `exportCombined` call (the MIDI export door in `Studio/EchoelStudioView.swift`)
//  passes `steps: []`, so `drumEvents` emits nothing at all today. The path is dormant; it is
//  repaired because the arithmetic is wrong whether or not a door exists, and because a door
//  that arrives later must not land on a contract that contradicts its own sibling overload.
//
//  ⚠️ The byte assertions search the WHOLE file for a three-byte triple rather than parsing
//  the drum MTrk chunk. A coincidental match is conceivable in principle. ⛔ The first version
//  of this line claimed the mitigation was that "each positive is paired with the NEGATIVE of
//  the value it replaced" — false for the assertion this file is NAMED after. THREE of the
//  five `contains`-based methods pair theirs; `testAnExportWithoutAccentsWritesTheRequested-
//  Velocity` and `testTheTypeZeroExporterStillEmitsTheLiteral` do not, because there the
//  replaced value is a function of the loop variable and at `requested: 1` the negative would
//  be `-19`, which is not a `UInt8`. A claim standing next to its own refutation, written into
//  the very commit that retracts one from `drumEvents` — the class this repo keeps paying for.
//  What actually holds is a MEASUREMENT: in every file these tests build, `0x99` occurs only
//  as the drum note-on status (once per single-hit export, twice in the kick+snare file). The
//  other chunks are ASCII names plus fixed meta (`FF 51 03 …`, `FF 58 04 …`, `FF 03 <len>`)
//  and chunk lengths of the form `00 00 00 XX` with XX < 40. That is a property of THESE
//  small files, not of the technique — a future file with richer meta needs the parser.
//

import XCTest
@testable import Echoelmusic

final class RequestedDrumVelocityIsTheEmittedByteTests: XCTestCase {

    /// 8 tracks × 16 steps, all silent — the exporter's expected grid shape.
    private func emptyGrid() -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: 16), count: 8)
    }

    /// One kick (GM note 36, track 0) on step 0.
    private func oneKick() -> [[Bool]] {
        var grid = emptyGrid()
        grid[0][0] = true
        return grid
    }

    /// A kick (36) and a snare (38), both on step 0, so one export can carry an accented and
    /// an unaccented hit at once.
    private func kickAndSnare() -> [[Bool]] {
        var grid = emptyGrid()
        grid[0][0] = true
        grid[1][0] = true
        return grid
    }

    private func contains(_ haystack: Data, _ needle: [UInt8]) -> Bool {
        haystack.range(of: Data(needle)) != nil
    }

    /// The velocity byte of the FIRST channel-10 note-on for `note` in an exported file.
    /// `nil` when the file carries no such note-on at all — which every caller below asserts
    /// against, so a structural regression (no drum events emitted) cannot read as agreement.
    private func firstDrumVelocity(in data: Data, note: UInt8) -> UInt8? {
        guard let r = data.range(of: Data([0x99, note])), r.upperBound < data.endIndex else {
            return nil
        }
        return data[r.upperBound]
    }

    // MARK: - The two regressions

    /// RED before #474 at `requested` 15/100/127 — the file carried 1/1/80/107 for the four
    /// values below. ⛔ The first version said "the file carried 80 and never carried 100",
    /// which describes ONE iteration and was presented as describing all four. At
    /// `requested: 1` the old `max(1, v - 20)` floor already produced 1, so that iteration is
    /// bit-identical on both trees and asserts nothing about #474 — it is here for the floor.
    /// The method is still a genuine regression: `XCTAssertTrue` records and continues, so the
    /// other three iterations fail it against the old code.
    ///
    /// `Humanizer.tight` is `(timingTicks: 0, velocityJitter: 0)` and `jitter` returns
    /// `(0, 1)` for it, so there is no rounding to hide behind — the byte is exact.
    func testAnExportWithoutAccentsWritesTheRequestedVelocity() {
        for requested: UInt8 in [1, 15, 100, 127] {
            let data = MIDIFileExporter.exportCombined(
                notes: [], steps: oneKick(), accents: [], tempo: 120, velocity: requested)
            XCTAssertTrue(contains(data, [0x99, 36, requested]), """
                A drum export with NO accent information must write the velocity the caller \
                asked for (\(requested)), not a number derived from it. Before #474 \
                `drumEvents` sent every cell down the `velocity - 20` branch even when there \
                was no accent array to be quiet relative to.
                """)
        }
    }

    /// RED before #474, and the more durable half: it states the PROPERTY (the two exporters
    /// of the same grid agree when no accents are involved) instead of a number, so it still
    /// means something if someone re-decides what 100 should be.
    ///
    /// The Type-0 `export(steps:tempo:velocity:)` overload has no accent parameter at all and
    /// has always emitted the literal. Until #474 the same argument name meant two different
    /// things on two exporters of the same grid.
    func testTheTwoExportersAgreeWhenThereAreNoAccents() {
        for requested: UInt8 in [1, 15, 100, 127] {
            let type0 = MIDIFileExporter.export(steps: oneKick(), tempo: 120, velocity: requested)
            let type1 = MIDIFileExporter.exportCombined(
                notes: [], steps: oneKick(), accents: [], tempo: 120, velocity: requested)
            let a = firstDrumVelocity(in: type0, note: 36)
            let b = firstDrumVelocity(in: type1, note: 36)
            XCTAssertNotNil(a, "the Type-0 export emitted no kick note-on at all")
            XCTAssertNotNil(b, "the Type-1 export emitted no kick note-on at all")
            XCTAssertEqual(a, b, """
                The Type-0 and Type-1 exporters disagree about the drum velocity byte for the \
                same grid and the same `velocity: \(requested)` argument, with no accents \
                supplied. `velocity:` must mean one thing on both; until #474 it meant the \
                emitted byte on one and the accent centre on the other.
                """)
        }
    }

    // MARK: - Counterweights (green on both sides, and that is the point)

    /// The ±20 split is NOT deleted. An accented cell sits above the requested velocity and
    /// an unaccented one below it, in the same file.
    func testSuppliedAccentsStillStraddleTheRequestedVelocity() {
        let data = MIDIFileExporter.exportCombined(
            notes: [], steps: kickAndSnare(),
            accents: [[true], [false]], tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x99, 36, 120]), """
            An accented drum cell must be written LOUDER than the requested velocity \
            (100 + 20 = 120). #474 removed the ±20 only where there is no accent array; \
            deleting it outright would flatten every beat a caller does accent.
            """)
        XCTAssertTrue(contains(data, [0x99, 38, 80]), """
            An unaccented cell in a pattern that DOES carry accent information must sit back \
            (100 - 20 = 80). If this went to 100 the split has been widened past its seam.
            """)
        XCTAssertFalse(contains(data, [0x99, 36, 100]), """
            With accents supplied, `velocity` is the accent CENTRE and must not itself be \
            emitted for the accented kick.
            """)
    }

    /// The seam is total absence, not "nothing happens to be accented". A present, all-false
    /// accent array keeps the quiet branch — deliberately.
    func testAPresentButAllFalseAccentArrayKeepsTheQuietBranch() {
        let data = MIDIFileExporter.exportCombined(
            notes: [], steps: oneKick(),
            accents: [[false, false, false, false]], tempo: 120, velocity: 100)
        XCTAssertTrue(contains(data, [0x99, 36, 80]), """
            A caller that supplies an accent array and marks nothing accented has stated \
            something ("none of these are accented"); a caller that supplies no array has \
            stated nothing. #474 changes only the second case. Treating them alike is a \
            second decision with its own reasoning, not a tidy-up of this one.
            """)
        XCTAssertFalse(contains(data, [0x99, 36, 100]), """
            The requested velocity must not be emitted literally when accent information IS \
            present — that would be the seam widening past `accents.isEmpty`.
            """)
    }

    /// The clamps around the split survive: the top saturates at the MIDI ceiling and the
    /// bottom at 1, never at 0 (a 0-velocity note-on IS a note-off in SMF, so an over-quiet
    /// hit would silently disappear rather than merely soften).
    func testTheSplitStaysInsideTheMIDIRange() {
        let loud = MIDIFileExporter.exportCombined(
            notes: [], steps: oneKick(), accents: [[true]], tempo: 120, velocity: 120)
        XCTAssertTrue(contains(loud, [0x99, 36, 127]), "accent above 127 must saturate at 127")

        let quiet = MIDIFileExporter.exportCombined(
            notes: [], steps: oneKick(), accents: [[false]], tempo: 120, velocity: 10)
        XCTAssertTrue(contains(quiet, [0x99, 36, 1]), "an unaccented cell must floor at 1")
        XCTAssertFalse(contains(quiet, [0x99, 36, 0]), """
            A note-on with velocity 0 is a note-OFF in the SMF spec — the hit would vanish \
            instead of getting quieter.
            """)
    }

    /// The Type-0 overload is untouched by #474 — it never had accents and always emitted the
    /// literal. Stated so a later "unify the two velocity rules" cannot move it by accident.
    func testTheTypeZeroExporterStillEmitsTheLiteral() {
        for requested: UInt8 in [1, 64, 127] {
            let data = MIDIFileExporter.export(steps: oneKick(), tempo: 120, velocity: requested)
            XCTAssertTrue(contains(data, [0x99, 36, requested]),
                          "the Type-0 grid export has no accents and must emit \(requested) as written")
        }
    }
}
