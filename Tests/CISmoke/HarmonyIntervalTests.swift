// HarmonyIntervalTests.swift
// Echoel — the harmonizer offers harmony, not arithmetic. BLOCKING bundle.
//
// THE ASK (founder 2026-07-29): *"Harmonizer mit 5th etc? Keine semitone Schritte sondern
// sinnvolle harmonische."*
//
// The two harmony voices were numeric fields in semitones, −12…12, whole numbers: 25 choices of
// which the seconds (±1, ±2), the tritone (±6) and the sevenths (±10, ±11) are not parallel
// harmony at all. Held under every note of a melody by a fixed-ratio shifter they beat rather
// than harmonise. `HarmonyInterval` is the curated fifteen that work, each carrying its own name.
//
// ⚠️ WHAT THIS CHANGE IS NOT, because the founder may have meant the other thing and the
// difference is a project rather than a rename: `EchoelHarmonizer` is an AUDIO effect — a
// delay-line shifter multiplying the whole signal by ONE fixed ratio
// (`EchoelHarmonizer.ratio(for:)`). It does not know which note is sounding, so it cannot be
// DIATONIC: a "third" cannot become minor over a minor chord and major over a major one the way
// a pitch-tracking harmonizer does in scale mode. Naming the intervals — and spelling out
// MAJOR/MINOR where the interval has both forms — is the honest version of the ask.
//
// WHAT THIS FILE PINS, in order of how expensive the mistake would be:
//   1. The curated set stays curated (a later "just add the tritone back" reopens the ask).
//   2. An OFF-GRID stored value is displayed as itself and never snapped. A preset holding +6
//      exists in the wild, and — proven below, not assumed — the macro-morph fader LERPs both
//      intervals continuously, so a fractional 5.5 is reachable in the shipping app. Snapping it
//      on mere panel-open would re-voice a saved sound with no user input: the #163/#170
//      data-loss class, where nothing is lost and everything is quietly changed.
//   3. The shipped DEFAULTS are inside the curated set, or the panel would read "custom" out of
//      the box on a chain nobody has touched.
//
// WHY HERE AND NOT `Tests/EchoelmusicTests`: that bundle builds only under `full-tests.yml`,
// which carries `continue-on-error: true` on both its build and its run step (#208), so a test
// living there cannot turn a merge red.

import Foundation
import XCTest
@testable import Echoelmusic

final class HarmonyIntervalTests: XCTestCase {

    // MARK: - The set stays curated

    /// ⛔ THE ASK, as an assertion. These are the intervals a parallel harmonizer must not offer.
    func testTheDissonantIntervalsAreNotOffered() {
        let offered = Set(HarmonyInterval.allCases.map(\.rawValue))
        for st in [1, -1, 2, -2, 6, -6, 10, -10, 11, -11] {
            XCTAssertFalse(offered.contains(st),
                           "\(st) st is offered again. Seconds, the tritone and sevenths held in "
                           + "parallel under a melody beat rather than harmonise — that is the "
                           + "whole reason the number field was replaced. If one of them is "
                           + "genuinely wanted, it is a founder decision, not an addition.")
        }
        XCTAssertEqual(HarmonyInterval.allCases.count, 15,
                       "The curated set changed size. That is allowed — but the count is pinned "
                       + "so it is a decision someone made, not a drift nobody noticed.")
    }

    /// Every offered interval is a whole semitone inside one octave either way: the range the
    /// old field allowed, and the range `EchoelHarmonizer.ratio(for:)` is voiced for.
    func testEveryOfferedIntervalIsAWholeSemitoneWithinAnOctave() {
        for interval in HarmonyInterval.allCases {
            XCTAssertTrue((-12...12).contains(interval.rawValue),
                          "\(interval) is outside the −12…12 octave the shifter is voiced for")
            XCTAssertEqual(interval.semitones, Float(interval.rawValue),
                           "\(interval).semitones must be exactly its raw value — the persisted "
                           + "format is that Float and a mismatch would silently re-voice presets")
        }
    }

    /// The menu is built straight from `allCases` with no sort, so the declaration order IS the
    /// reading order. Ascending means a performer scans low → high instead of hunting.
    func testTheMenuReadsLowToHigh() {
        let raws = HarmonyInterval.allCases.map(\.rawValue)
        XCTAssertEqual(raws, raws.sorted(),
                       "`allCases` is not ascending, and the picker does not sort: \(raws)")
        XCTAssertEqual(Set(raws).count, raws.count, "two cases share a semitone value")
    }

    /// MAJOR/MINOR is spelled out exactly where the interval has both forms, and nowhere else —
    /// a "Major fifth" would be wrong, and an unqualified "Third" is the ambiguity being removed.
    func testTheNamesQualifyOnlyTheIntervalsThatHaveTwoForms() {
        for interval in HarmonyInterval.allCases {
            let name = interval.displayName
            let size = abs(interval.rawValue)
            let hasTwoForms = [3, 4, 8, 9].contains(size)   // thirds and sixths
            let qualified = name.contains("Major") || name.contains("Minor")
            XCTAssertEqual(qualified, hasTwoForms,
                           "\"\(name)\" is \(qualified ? "" : "not ")qualified but "
                           + "\(hasTwoForms ? "should be" : "should not be") — a fifth, fourth "
                           + "and octave are the same in every mode; a third and a sixth are not.")
            XCTAssertFalse(name.isEmpty, "\(interval) has no name")
        }
    }

    // MARK: - The shipped defaults must be offerable

    /// If a default were off the curated grid, a chain nobody has touched would open showing
    /// "custom" — the control reporting an exotic state for the factory sound. Read from the real
    /// chain rather than from literals, so re-voicing the default reddens this instead of
    /// silently producing that.
    func testTheShippedDefaultsAreCuratedIntervals() {
        let chain = EchoelFXChain()
        for (label, value) in [("Voice 1", chain.harmonizer.interval1),
                               ("Voice 2", chain.harmonizer.interval2)] {
            XCTAssertNotNil(HarmonyInterval.curated(forSemitones: value),
                            "\(label)'s shipped default is \(value) st, which is not a curated "
                            + "interval — the Harmonizer panel would read \"custom\" on a chain "
                            + "nobody has touched. Either add the interval or re-voice the "
                            + "default; do not leave the factory sound unnameable.")
        }
    }

    // MARK: - An off-grid value must display as itself

    /// ⛔ THE ONE THAT PROTECTS SAVED SOUNDS. `curated` returns nil rather than the nearest
    /// neighbour, so the row shows the stored value instead of quietly becoming a different one.
    func testAnOffGridValueIsNotSnappedToANeighbour() {
        for st in [Float(6), -6, 1, -2, 10, 11, 5.5, -3.25] {
            XCTAssertNil(HarmonyInterval.curated(forSemitones: st),
                         "\(st) st resolved to a curated interval. Snapping re-voices a saved "
                         + "preset the moment its panel is OPENED, with no user input.")
        }
        for st in [Float(0), 3, 4, 5, 7, 8, 9, 12, -3, -4, -5, -7, -8, -9, -12] {
            guard let found = HarmonyInterval.curated(forSemitones: st) else {
                XCTFail("\(st) st is one of the fifteen and must resolve, or a saved preset "
                        + "holding it would suddenly read as \"custom\"")
                continue
            }
            XCTAssertEqual(found.semitones, st,
                           "\(st) st resolved to \(found) — the lookup must be exact, because "
                           + "the value written back is the interval's own semitones")
        }
    }

    /// …and the menu grows by exactly one entry to hold it, first, so the row can display the
    /// state it is actually in. Same idiom as `FXModCarrier.choices(including:)`.
    func testTheMenuCarriesAnOffGridValueAndOnlyThen() throws {
        let withCustom = HarmonyInterval.choices(includingSemitones: 6)
        XCTAssertEqual(withCustom.count, HarmonyInterval.allCases.count + 1)
        // ⚠️ `XCTUnwrap` then `XCTAssertNil`, NOT `XCTAssertNil(withCustom.first)` — `.first` on
        // `[HarmonyInterval?]` is a DOUBLE optional, and the custom entry makes it `.some(.none)`.
        // `XCTAssertNil` takes `Any?` and the type checker prefers the optional-to-optional
        // conversion, so `.some(.none)` arrives as non-nil and the assertion fails with the
        // useless message `XCTAssertNil failed: "nil"`. My first draft did exactly that; unwrapping
        // one level also stops an empty array from passing the check vacuously.
        XCTAssertNil(try XCTUnwrap(withCustom.first),
                     "the stored off-grid value must be the FIRST entry")
        XCTAssertEqual(withCustom.compactMap { $0 }, HarmonyInterval.allCases,
                       "the curated set must follow unchanged and in order")

        // Annotated rather than relying on `[T]` → `[T?]` covariance being inferred through
        // `XCTAssertEqual`'s generic parameter, which is a conversion the type checker is not
        // obliged to find.
        let curatedOnly: [HarmonyInterval?] = HarmonyInterval.allCases.map { $0 }
        XCTAssertEqual(HarmonyInterval.choices(includingSemitones: 7), curatedOnly,
                       "a curated value must NOT add a custom entry — an always-present "
                       + "\"custom\" row is a choice nobody can meaningfully make")
    }

    /// The custom entry reads as the number it is. And it must not TRAP: `Int(Float)` crashes on a
    /// non-finite value AND on any finite value outside `Int`'s range, so both guards are two-part.
    /// This matters because `curated` runs from a `Binding.get` on every body build and `FXPreset`
    /// does not clamp the decoded field — a corrupt preset would crash on OPENING the FX panel.
    func testTheCustomLabelReadsAsTheStoredNumber() {
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: 6), "+6 st")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: -10), "−10 st")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: 5.5), "+5.5 st")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: 0), "0 st",
                       "zero takes no sign — and zero is `unison`, so this label is only ever "
                       + "reached if the curated lookup itself is bypassed")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: .nan), "— st")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: .infinity), "— st")
        XCTAssertNil(HarmonyInterval.curated(forSemitones: .nan),
                     "a NaN interval must resolve to nil without trapping in `Int(_:)`")
        // ⛔ THE CRASH PATH, exercised. A finite 1e30 is not "a large interval" — `Int(Float)` traps
        // on it exactly as it does on NaN, and this test would abort the whole bundle rather than
        // fail if the range half of the guard were dropped. `-Float.greatestFiniteMagnitude` is the
        // same trap from the other side.
        XCTAssertNil(HarmonyInterval.curated(forSemitones: 1e30),
                     "a finite but out-of-Int value must resolve to nil, not trap")
        XCTAssertNil(HarmonyInterval.curated(forSemitones: -.greatestFiniteMagnitude))
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: 1e30), "— st")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: 129), "— st",
                       "the bound is the MIDI note span; 129 st is not a musical interval and the "
                       + "row says so rather than printing a number nobody can act on")
        XCTAssertEqual(HarmonyInterval.customLabel(forSemitones: -24), "−24 st",
                       "a legacy two-octave value is still inside the bound and must read honestly")
    }

    // MARK: - The premise, measured rather than assumed

    /// ⛔ WHY `curated` MAY NOT SNAP — proven, not argued. The macro-morph control calls
    /// `FXPreset.morphed(to:amount:)`, which LERPs both harmonizer intervals; the result is
    /// written straight to the live chain (`FXViewModel.morph`). So a fractional interval is
    /// reachable in the shipped app by dragging ONE control, and the row must be able to show it.
    /// (It is the `EchoelValueField(label: "Morph", …)` — the #480 follow-up renamed the panel's
    /// own footer for the same reason: there is no fader in `EchoelFXView`, and calling it one
    /// sends the next session looking for a `Slider` that does not exist.)
    ///
    /// If a future change quantises the morph, this test fails — and the right response is to
    /// rewrite this file's rationale, not to start snapping.
    func testTheMorphFaderReallyProducesAnOffGridInterval() {
        let a = EchoelFXChain()
        a.harmonizer.interval1 = 4          // major third up
        let presetA = FXPreset.capture(from: a, fxEnabled: true, name: "a")

        let b = EchoelFXChain()
        b.harmonizer.interval1 = 7          // fifth up
        let presetB = FXPreset.capture(from: b, fxEnabled: true, name: "b")

        let midway = presetA.morphed(to: presetB, amount: 0.5)
        XCTAssertEqual(midway.harmonizerInterval1, 5.5, accuracy: 1e-5,
                       "the morph no longer interpolates the interval")
        XCTAssertNil(HarmonyInterval.curated(forSemitones: midway.harmonizerInterval1),
                     "5.5 st must not resolve to a curated interval — mid-morph the row shows "
                     + "the real value, and re-opening the panel must not round the sound")
    }

    // MARK: - The row is actually wired to the picker

    /// The Harmonizer section must use `intervalRow`, not the numeric `field`. Source text
    /// because the section is a `@ViewBuilder` block on a `private` SwiftUI `View` with no seam
    /// to call and no local toolchain to build a UI host with — the same reason
    /// `CleanIsDryTests` reads source. What it cannot prove is that the picker renders or that
    /// VoiceOver reaches it; it proves only that the number field is gone from these two rows.
    func testTheHarmonizerRowsUseNamedIntervals() throws {
        let block = try blockBody(after: "effectSection(\"Harmonizer\"",
                                  in: "Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertTrue(block.contains("intervalRow(\"Voice 1\", $vm.harmInterval1)"),
                      "Voice 1 is not on the named-interval row:\n\(block)")
        XCTAssertTrue(block.contains("intervalRow(\"Voice 2 interval\", $vm.harmInterval2)"),
                      "Voice 2 is not on the named-interval row:\n\(block)")
        XCTAssertFalse(block.contains("unit: \"st\""),
                       "a harmonizer interval is back on a raw semitone field — that is the "
                       + "control the founder asked to replace:\n\(block)")
    }

    // MARK: - Reading the source

    /// The lines from the one containing `marker` to its matching closing brace, whole-line
    /// comments dropped BEFORE the brace arithmetic so a comment quoting an unbalanced brace
    /// cannot desync the depth and silently return the wrong span. Throws rather than returning
    /// empty on a miss: an empty block would make the assertions above pass vacuously.
    private func blockBody(after marker: String, in relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let matches = lines.indices.filter { lines[$0].contains(marker) }
        guard let start = matches.first else {
            XCTFail("Marker not found: \(marker) in \(relativePath) — it was renamed or moved. "
                    + "Re-point this test rather than deleting it.")
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(matches.count, 1,
                       "Marker `\(marker)` appears \(matches.count) times; this scan reads only "
                       + "the first, so the guard may be pointing at the wrong one.")
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up. A
    /// source-reading test that cannot find the source must SKIP, not pass.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return root
    }
}
