// FieldAutoPlayArpTests.swift
// Echoel — the arp as a self-play MOTION, in the BLOCKING bundle.
//
// #220 S3. `ArpFigure` (S1/S2) knows which chord tone and where on the surface it lands;
// `FieldAutoPlay.Motion.arp` is what makes that reachable — the Field's existing motion picker
// enumerates `Motion.allCases`, so this case is selectable the moment it exists.
//
// ⚠️ THE TWO PROPERTIES WORTH PINNING, and neither is about a number being in range:
//
//  1. **The walk advances per SOUNDED note, not per cell.** Using the cell index as the walk
//     position compiles, reads correctly, and silently breaks `ArpFigure`'s one guarantee: at
//     density 0.5 every second chord tone would be skipped, so an "up" figure comes out full of
//     holes. That is inaudible in a range check and obvious to an ear.
//  2. **The five older motions must be BYTE-IDENTICAL.** This slice adds two parameters to a
//     function every existing motion goes through. The cheapest proof that nothing shifted is
//     that their output does not depend on either new parameter at all — asserted below over the
//     whole `Motion` set rather than argued in a commit message.

import Foundation
import XCTest
@testable import Echoelmusic

final class FieldAutoPlayArpTests: XCTestCase {

    private func arpParams(density: Float = 1, period: Int = 8, band: Float = 0.5,
                           bandDrift: Float = 0, voices: Int = 1,
                           order: ArpFigure.Order = .up, octaves: Int = 1,
                           chord: [Int] = [0, 2, 4],
                           rhythm: RoleRhythm.Params = RoleRhythm.Params(character: .driving,
                                                                         evolve: 0)
    ) -> FieldAutoPlay.Params {
        FieldAutoPlay.Params(motion: .arp, density: density, span: 0.6, centre: 0.5,
                             band: band, bandDrift: bandDrift, voices: voices,
                             periodSteps: period, arpOrder: order, arpOctaves: octaves,
                             arpChordDegrees: chord, arpRhythm: rhythm)
    }

    private let bands = TouchPitchMap.octaveBands.count

    private func touches(_ step: Int, _ p: FieldAutoPlay.Params,
                         seed: UInt64 = 7) -> [FieldAutoPlay.Touch] {
        FieldAutoPlay.touches(atStep: step, params: p, seed: seed,
                              degreesPerOctave: 7, bandCount: bands)
    }

    // MARK: - One note, not a stack

    /// An arpeggio is a chord played as a SEQUENCE. `voices` is the one dial that would turn it
    /// back into the chord, so it must not apply — and the panel hides the row for exactly this
    /// reason. If this ever returns `voices` touches, the row has to come back.
    func testAnArpCellPlaysOneNoteWhateverVoicesSays() {
        for voices in [1, 2, 5, 8, 999] {
            let hits = touches(0, arpParams(voices: voices))
            XCTAssertEqual(hits.count, 1, "voices \(voices) produced \(hits.count) touches")
        }
    }

    /// `voices: 0` still means silence, exactly as it does for every other motion — the guard
    /// sits above the arp branch and that is deliberate, not an oversight.
    func testVoicesZeroIsStillSilence() {
        XCTAssertTrue(touches(0, arpParams(voices: 0)).isEmpty)
    }

    /// Density 0 is silence for the arp too: the thing runs unattended, so "no rate" must mean
    /// no notes rather than a stuck single tone.
    func testDensityZeroIsSilence() {
        XCTAssertTrue(touches(0, arpParams(density: 0)).isEmpty)
    }

    /// An empty (or all-negative) chord is SILENCE, not a substituted root — the `nil` that
    /// `ArpFigure.step` returns has to survive all the way out of the generator.
    func testAnEmptyChordIsSilenceRatherThanAStuckRoot() {
        for chord in [[], [-1, -4]] {
            for step in 0..<8 {
                XCTAssertTrue(touches(step, arpParams(chord: chord)).isEmpty,
                              "chord \(chord) step \(step) produced a note")
            }
        }
    }

    // MARK: - The walk advances per sounded note

    /// Density 1 fires every cell, so the arp must walk its cycle in order and cover every chord
    /// tone exactly once per cycle — the property `ArpFigure` guarantees, asserted through the
    /// generator that actually plays it.
    func testAtFullDensityTheWalkIsTheFigureItself() {
        let p = arpParams(density: 1, period: 12, octaves: 1)
        let xs = (0..<3).map { step -> Float in
            let hits = touches(step, p)
            XCTAssertEqual(hits.count, 1, "step \(step) did not fire at density 1")
            return hits.first?.x ?? -1
        }
        XCTAssertEqual(xs, xs.sorted(), "an ascending arp did not ascend: \(xs)")
        XCTAssertEqual(Set(xs).count, 3, "the three chord tones collapsed: \(xs)")
        // And the cycle repeats: position 3 is the root again.
        XCTAssertEqual(touches(3, p).first?.x ?? -1, xs[0], accuracy: 1e-6)
    }

    /// ⛔ THE DEFECT THIS FILE EXISTS FOR. At density 0.5 only half the cells fire; the walk must
    /// still visit consecutive positions, so the notes that DO sound are the same sequence as at
    /// density 1 — the rate changed, the figure did not. Indexing by cell instead would drop
    /// every second tone and this is the assertion that fails.
    func testALowerDensityChangesTheRateAndNotTheFigure() {
        let full = arpParams(density: 1, period: 8)
        let half = arpParams(density: 0.5, period: 8)

        let figure = (0..<3).compactMap { touches($0, full).first?.x }
        XCTAssertEqual(figure.count, 3)

        // The sounded notes of the sparser setting, in the order they sound.
        let sparse = (0..<8).compactMap { touches($0, half).first?.x }
        XCTAssertGreaterThanOrEqual(sparse.count, 3, "half density fired \(sparse.count) cells")
        XCTAssertEqual(Array(sparse.prefix(3)), figure,
                       "the sparser arp skipped chord tones instead of just playing slower")
    }

    /// Across a traverse boundary the walk keeps counting: the figure must not restart at the
    /// root every traverse, because the traverse length is a RATE setting and has nothing to do
    /// with the length of the chord.
    func testTheWalkKeepsCountingAcrossTraverses() {
        // Three tones, four cells per traverse, every cell firing: after one traverse the walk
        // is at position 4, i.e. the second tone of the second cycle.
        let p = arpParams(density: 1, period: 4)
        let sounded = (0..<8).compactMap { touches($0, p).first?.x }
        XCTAssertEqual(sounded.count, 8)
        // Position 4 (first cell of traverse 2) must be the SECOND tone, not the first.
        XCTAssertEqual(sounded[4], sounded[1], accuracy: 1e-6,
                       "the arp restarted its figure at the traverse boundary")
        XCTAssertNotEqual(sounded[4], sounded[0], accuracy: 1e-6)
    }

    // MARK: - Where it lands

    /// Whatever the dials, the point stays on the surface — this is what the consumer's
    /// `TouchPitchMap.pitch` is handed, and it clamps rather than complaining, so an out-of-range
    /// value here would become a quietly wrong note.
    func testTheArpPointNeverLeavesTheSurface() {
        var checked = 0
        for order in ArpFigure.Order.allCases {
            for octaves in [1, 2, 3, 9] {
                for band in [Float(0), 0.5, 1] {
                    for drift in [Float(0), 0.5, 1] {
                        let p = arpParams(band: band, bandDrift: drift,
                                          order: order, octaves: octaves,
                                          chord: [0, 2, 4, 7, 14])
                        for step in 0..<24 {
                            for t in touches(step, p) {
                                XCTAssertTrue((0...1).contains(t.x), "x \(t.x) \(order)")
                                XCTAssertTrue((0...1).contains(t.y), "y \(t.y) \(order)")
                                XCTAssertTrue(t.velocity > 0 && t.velocity <= 1)
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "the sweep never produced a touch")
    }

    /// The register comes from `band`, and the arp's y snaps to the MIDDLE of that register —
    /// which is why the panel's band-drift caption is different for this motion.
    func testTheRegisterComesFromBandAndSnapsToItsCentre() {
        for (band, expected) in [(Float(0.0), 0), (0.5, 1), (1.0, bands - 1)] {
            let y = touches(0, arpParams(band: band)).first?.y ?? -1
            XCTAssertEqual(Double(y), (Double(expected) + 0.5) / Double(bands), accuracy: 1e-6,
                           "band \(band) landed at y \(y)")
        }
    }

    /// A drift that cannot cross a register boundary must not move the arp at all — the honest
    /// version of the claim the panel now makes for this motion.
    func testASubThresholdDriftDoesNotMoveTheArp() {
        let ys = (0..<24).compactMap { touches($0, arpParams(band: 0.5, bandDrift: 0.2)).first?.y }
        XCTAssertGreaterThan(ys.count, 0)
        XCTAssertEqual(Set(ys).count, 1, "a sub-threshold drift moved the register: \(Set(ys))")
    }

    /// The composition that actually sounds: through the same `TouchPitchMap.pitch` a finger
    /// goes through, in every key the app offers, the arp must produce a legal in-key pitch.
    func testEveryArpNoteIsLegalInEveryKey() {
        var checked = 0
        for root in 0..<12 {
            for scale in Scale.allCases {
                let key = MusicalKey(root: root, scale: scale)
                let classes = Set(key.pitchClasses)
                let p = arpParams(octaves: 2, chord: [0, 2, 4, 7])
                for step in 0..<12 {
                    let hits = FieldAutoPlay.touches(atStep: step, params: p, seed: 5,
                                                     degreesPerOctave: key.degreesPerOctave,
                                                     bandCount: bands)
                    XCTAssertEqual(hits.count, 1, "\(scale) step \(step)")
                    for t in hits {
                        let pitch = TouchPitchMap.pitch(normX: Double(t.x), normY: Double(t.y),
                                                        key: key)
                        XCTAssertTrue((0...127).contains(pitch), "\(scale) → \(pitch)")
                        XCTAssertTrue(classes.contains(((pitch % 12) + 12) % 12),
                                      "root \(root) \(scale) → \(pitch) is out of key")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 12 * Scale.allCases.count * 12)
    }

    // MARK: - The five older motions did not move

    /// ⛔ THE REGRESSION GUARD FOR THIS WHOLE SLICE. `touches` gained two parameters; every
    /// motion except `.arp` must ignore both completely. If a later edit lets the surface facts
    /// leak into the travelling path, this fails instead of a device revealing it.
    func testTheTravellingMotionsIgnoreTheArpsSurfaceArguments() {
        for motion in FieldAutoPlay.Motion.allCases where motion != .arp {
            let p = FieldAutoPlay.Params(motion: motion, density: 1, span: 0.6, centre: 0.5,
                                         band: 0.5, bandDrift: 0.4, voices: 3, periodSteps: 8)
            for step in 0..<16 {
                let a = FieldAutoPlay.touches(atStep: step, params: p, seed: 7,
                                              degreesPerOctave: 5, bandCount: 2)
                let b = FieldAutoPlay.touches(atStep: step, params: p, seed: 7,
                                              degreesPerOctave: 12, bandCount: 7)
                XCTAssertEqual(a, b, "\(motion) step \(step) depends on the arp's arguments")
                XCTAssertEqual(a.count, 3, "\(motion) step \(step) lost its voices")
            }
        }
    }

    /// And the arp DOES depend on them — the mirror of the guard above, so "ignored" cannot be
    /// achieved by the arguments doing nothing anywhere.
    func testTheArpDoesDependOnTheSurfaceFacts() {
        let p = arpParams(chord: [0, 2, 4])
        let five = FieldAutoPlay.touches(atStep: 1, params: p, seed: 7,
                                        degreesPerOctave: 5, bandCount: bands)
        let seven = FieldAutoPlay.touches(atStep: 1, params: p, seed: 7,
                                         degreesPerOctave: 7, bandCount: bands)
        XCTAssertEqual(five.count, 1)
        XCTAssertEqual(seven.count, 1)
        XCTAssertNotEqual(five.first?.x ?? 0, seven.first?.x ?? 0, accuracy: 1e-9,
                          "the degree cell must be as wide as the scale, not a fixed twelfth")
    }

    // MARK: - Persistence (law 9)

    /// A `Params` saved before the arp existed must load with the arp defaults and its own dials
    /// untouched — the whole point of the additive decoder.
    func testAParamsSavedBeforeTheArpExistedLoadsUnchanged() throws {
        let json = """
        {"motion":"drift","density":0.25,"span":0.75,"centre":0.25,"band":0.75,
         "bandDrift":0.4,"voices":3,"periodSteps":32,"schemaVersion":1}
        """
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self,
                                        from: Data(json.utf8))
        XCTAssertEqual(p.motion, .drift)
        XCTAssertEqual(p.density, 0.25, accuracy: 1e-6)
        XCTAssertEqual(p.voices, 3)
        XCTAssertEqual(p.periodSteps, 32)
        // The defaults, pinned against `Params()` itself so the two can never drift apart.
        let d = FieldAutoPlay.Params()
        XCTAssertEqual(p.arpOrder, d.arpOrder)
        XCTAssertEqual(p.arpOctaves, d.arpOctaves)
        XCTAssertEqual(p.arpChordDegrees, d.arpChordDegrees)
    }

    /// An arp order a LATER build removed decodes as the default rather than throwing the whole
    /// setting away — the reason this field uses `try?` and not `decodeIfPresent`, which absorbs
    /// absence but not a `dataCorrupted` throw.
    func testAnUnknownArpOrderFallsBackInsteadOfLosingTheSetting() throws {
        let json = """
        {"motion":"arp","density":0.5,"span":0.6,"centre":0.5,"band":0.5,"bandDrift":0.2,
         "voices":1,"periodSteps":16,"arpOrder":"spiral","arpOctaves":2,
         "arpChordDegrees":[0,3,7]}
        """
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self, from: Data(json.utf8))
        XCTAssertEqual(p.motion, .arp)
        XCTAssertEqual(p.arpOrder, FieldAutoPlay.Params().arpOrder)
        XCTAssertEqual(p.arpOctaves, 2, "one bad field must not discard its neighbours")
        XCTAssertEqual(p.arpChordDegrees, [0, 3, 7])
    }

    /// Absurd stored values are capped at the BOUNDARY, so they never sit in memory looking
    /// legitimate: an octave span past the surface, and a "chord" of hundreds of tones.
    func testAbsurdStoredArpValuesAreCappedOnDecode() throws {
        let json = """
        {"motion":"arp","arpOctaves":9999,"arpChordDegrees":\
        \(Array(0..<500).description)}
        """
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self, from: Data(json.utf8))
        XCTAssertEqual(p.arpOctaves, ArpFigure.maxOctaves)
        XCTAssertEqual(p.arpChordDegrees.count, ArpFigure.maxChordTones)
        XCTAssertEqual(p.motion, .arp, "the other fields still decoded")
    }

    /// A round trip must survive the arp dials, otherwise a saved arp comes back as something
    /// else — the failure `MoodPreset` and `TrackFX` already paid for (#189).
    func testTheArpDialsSurviveASaveAndLoad() throws {
        let original = arpParams(order: .upDown, octaves: 3, chord: [0, 1, 5, 8])
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(FieldAutoPlay.Params.self, from: data)
        XCTAssertEqual(back, original)
    }

    // MARK: - The helper the walk index rests on

    /// The property the walk index rests on, stated INDEPENDENTLY of how `arpFiredCount` is
    /// written: on the default `driving` character the rhythm sounds exactly
    /// `max(1, round(density · period))` cells per traverse — the same even spread the Euclidean
    /// rule produced before #253 A2, with `RoleRhythm`'s one added floor (any density above 0
    /// sounds at least one cell).
    ///
    /// (The first version of this test re-ran the helper's own loop and could only have failed if
    /// the helper stopped calling `fires` — a tautology wearing a green tick. It is stated against
    /// the arithmetic instead.)
    func testATraverseSoundsExactlyTheEvenSpreadCount() {
        let rhythm = RoleRhythm.Params(character: .driving, evolve: 0)
        for period in [1, 3, 4, 8, 16, 32] {
            for density in [Float(0.1), 0.25, 0.5, 0.75, 0.9, 1] {
                var r = rhythm
                r.density = density
                let expected = Swift.max(1, Int((density * Float(period)).rounded()))
                let counted = FieldAutoPlay.arpFiredCount(before: period, bar: 0, rhythm: r,
                                                          period: period, seed: 7)
                XCTAssertEqual(counted, Swift.min(period, expected),
                               "period \(period) density \(density)")
                // And it is a PREFIX count: monotone, and never more than the cells looked at.
                for limit in 0...period {
                    let partial = FieldAutoPlay.arpFiredCount(before: limit, bar: 0, rhythm: r,
                                                              period: period, seed: 7)
                    XCTAssertTrue(partial <= counted && partial <= limit,
                                  "limit \(limit) counted \(partial) of \(counted)")
                }
            }
        }
        // Degenerate limits do not crash and count nothing.
        XCTAssertEqual(FieldAutoPlay.arpFiredCount(before: 0, bar: 0, rhythm: rhythm,
                                                   period: 8, seed: 7), 0)
        XCTAssertEqual(FieldAutoPlay.arpFiredCount(before: -5, bar: 0, rhythm: rhythm,
                                                   period: 8, seed: 7), 0)
    }

    // MARK: - The rhythm the arp walks in (#253 A2)

    /// ⛔ THE POINT OF A2. Six named characters must produce six audibly different arps — if two of
    /// them give the same bar, one is a lie in a picker (#81/#125). Compared over a whole traverse
    /// through the REAL generator, not through `RoleRhythm` in isolation, because the arp overrides
    /// the rhythm's density and maps its own walk on top.
    func testTheSixRhythmCharactersGiveTheArpSixDifferentBars() {
        let bars = RoleRhythm.Character.allCases.map { character -> [FieldAutoPlay.Touch?] in
            let p = arpParams(density: 0.5, period: 16,
                              rhythm: RoleRhythm.Params(character: character, evolve: 0))
            return (0..<16).map { touches($0, p).first }
        }
        for i in bars.indices {
            for j in bars.indices where j > i {
                XCTAssertNotEqual(bars[i], bars[j],
                                  "\(RoleRhythm.Character.allCases[i]) and "
                                  + "\(RoleRhythm.Character.allCases[j]) give the same arp")
            }
        }
    }

    /// The Field's own Density dial stays the ONE rate control: a rhythm stored with a contradicting
    /// density must not win, because the dial the player can see would then be lying.
    func testTheStoredRhythmDensityCannotOverrideTheFieldsOwnDial() {
        var contradicting = RoleRhythm.Params(character: .driving, evolve: 0)
        contradicting.density = 0            // "silence", if it were ever read
        let p = arpParams(density: 1, period: 8, rhythm: contradicting)
        let sounded = (0..<8).compactMap { touches($0, p).first }
        XCTAssertEqual(sounded.count, 8, "the stored density silenced a full-density arp")
    }

    /// The note LENGTH now travels with the touch, and it is the character's — `driving` is the
    /// short one, `flowing` fills its cell. The consumer turns this into seconds against its own
    /// grid; here it must simply be present, in range, and different per character.
    func testTheArpCarriesItsNoteLength() {
        func gate(_ character: RoleRhythm.Character) -> Float? {
            touches(0, arpParams(rhythm: RoleRhythm.Params(character: character, gate: 0.8,
                                                           evolve: 0))).first?.gateFraction
        }
        guard let driving = gate(.driving), let flowing = gate(.flowing) else {
            return XCTFail("the arp produced no note to measure")
        }
        XCTAssertTrue((RoleRhythm.minGate...RoleRhythm.maxGate).contains(driving))
        XCTAssertTrue((RoleRhythm.minGate...RoleRhythm.maxGate).contains(flowing))
        XCTAssertLessThan(driving, flowing, "driving is supposed to be the short one")
    }

    /// ⛔ AND THE FIVE TRAVELLING MOTIONS MUST HAVE NO OPINION ABOUT LENGTH. `nil` is what keeps
    /// their notes ringing for the surface's own `staccatoSeconds` exactly as before this slice; a
    /// defaulted `1` would silently re-time all five, which is not what A2 is allowed to change.
    func testOnlyTheArpSaysHowLongItsNoteIs() {
        for motion in FieldAutoPlay.Motion.allCases where motion != .arp {
            let p = FieldAutoPlay.Params(motion: motion, density: 1, span: 0.6, centre: 0.5,
                                         band: 0.5, bandDrift: 0.4, voices: 2, periodSteps: 8)
            for step in 0..<8 {
                for t in FieldAutoPlay.touches(atStep: step, params: p, seed: 7) {
                    XCTAssertNil(t.gateFraction, "\(motion) grew a note length")
                }
            }
        }
        XCTAssertNotNil(touches(0, arpParams()).first?.gateFraction)
    }

    /// ⛔ THE TWO CAPS MUST BE EQUAL, and this test is the only thing that will say so. `arpTouches`
    /// passes its already-clamped `periodSteps` straight in as `RoleRhythm`'s `cellsPerBar`, so a
    /// smaller cap over there folds the traverse silently: the rhythm would repeat several times
    /// inside one traverse and the "beat" it places accents against would be a quarter of the wrong
    /// number. Nothing else in the suite would notice, because every other test uses a small
    /// traverse. (It was 256 against 1024 when A2 was first written.)
    func testTheRhythmsGridCapMatchesTheTraverseCap() {
        XCTAssertEqual(RoleRhythm.maxCellsPerBar, FieldAutoPlay.maxPeriodSteps,
                       "a traverse the Field allows must be a bar the rhythm allows")
    }

    /// The one place the new rhythm is NOT bit-identical to the old Euclidean rule, pinned so the
    /// claim in `Params.arpRhythm` stays honest: `RoleRhythm.spread` floors the sounding count at
    /// one, so a density too small to round up to a single cell now plays the downbeat instead of
    /// nothing. The Density row offers two decimals, so this band is reachable, not theoretical.
    func testAVeryLowDensityStillSoundsTheDownbeatWhereTheOldRuleWasSilent() {
        let p = arpParams(density: 0.02, period: 16)
        let sounded = (0..<16).filter { !touches($0, p).isEmpty }
        XCTAssertEqual(sounded, [0], "the arp lost its one note at a density it must still play")
        // And the OLD rule really would have been silent here — otherwise this test proves nothing.
        XCTAssertEqual(Int((Float(0.02) * 16).rounded()), 0)
    }

    /// A rhythm saved before A2 (or a payload with a corrupt one) loads the arp's default rhythm
    /// and keeps every neighbouring dial — the additive-decode law, one level down.
    func testAParamsWithNoStoredRhythmLoadsTheArpDefault() throws {
        let json = #"{"motion":"arp","density":0.4,"periodSteps":12,"arpOctaves":2}"#
        let p = try JSONDecoder().decode(FieldAutoPlay.Params.self, from: Data(json.utf8))
        XCTAssertEqual(p.arpRhythm, FieldAutoPlay.Params().arpRhythm)
        XCTAssertEqual(p.arpRhythm.character, .driving)
        XCTAssertEqual(p.arpOctaves, 2, "one absent field must not discard its neighbours")
        XCTAssertEqual(p.periodSteps, 12)
    }

    /// An absurd `bandCount` must not trap either, and this one is a REAL trap that review found
    /// rather than a hypothetical: the arp derives its base band with `Int(y * Float(bands))`,
    /// `Float(Int.max)` rounds to 2^63, and converting that back to `Int` traps. No shipping
    /// caller can pass it (the surface has three bands) — which is exactly the argument this file
    /// already refuses to accept for `periodSteps` and `voices`.
    func testAnAbsurdBandCountDoesNotTrap() {
        for bandCount in [Int.max, Int.min, 0, -3, 1, 10_000] {
            let hits = FieldAutoPlay.touches(atStep: 0, params: arpParams(band: 1, bandDrift: 0),
                                             seed: 7, degreesPerOctave: 7, bandCount: bandCount)
            XCTAssertEqual(hits.count, 1, "bandCount \(bandCount)")
            for t in hits {
                XCTAssertTrue((0...1).contains(t.y), "bandCount \(bandCount) y \(t.y)")
            }
        }
        // And the ceiling is the one the constant names, not an arbitrary number: at band 1.0 the
        // point lands in the TOP band of `maxSurfaceBands`, not of the absurd request.
        let top = FieldAutoPlay.touches(atStep: 0, params: arpParams(band: 1, bandDrift: 0),
                                        seed: 7, degreesPerOctave: 7,
                                        bandCount: Int.max).first?.y ?? -1
        let bandsMax = Double(FieldAutoPlay.maxSurfaceBands)
        XCTAssertEqual(Double(top), (bandsMax - 0.5) / bandsMax, accuracy: 1e-6)
    }

    /// An absurd step must not trap. `traverse * firedPerTraverse` is deliberately wrapping —
    /// a wrap lands somewhere else in the same walk, a trap would kill the self-play path.
    func testAnAbsurdStepDoesNotTrap() {
        for step in [Int.max, Int.min, Int.max - 1, 1_000_000_000] {
            let hits = touches(step, arpParams())
            for t in hits {
                XCTAssertTrue((0...1).contains(t.x), "step \(step) x \(t.x)")
                XCTAssertTrue((0...1).contains(t.y), "step \(step) y \(t.y)")
            }
        }
    }
}
