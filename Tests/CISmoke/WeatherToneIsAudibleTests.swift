// WeatherToneIsAudibleTests.swift
// Echoel — founder, 2026-08-01: "Ja Wetter soll hörbar werden?" BLOCKING bundle, because the
// other suite cannot fail a merge (#208).
//
// ⭐ WHAT WENT WRONG BEFORE, because this file only makes sense against it. `Param.warmth`
// has always promised "Warm weather brightens the tone, cold darkens it", and its only wiring
// was `MoodProfile.darkness`. `darkness` is not a gradient anywhere in the engine — its two
// readers are both `mood.darkness > 0.6 ? -1 : 0` (`BioComposer`: the ambient octave and the
// pad voicing), and `MoodPreset.swift` records the same finding in its own words ("two moods
// can therefore differ by 0.43 of darkness and produce the SAME notes"). So the few hundredths weather
// moved did nothing at all — unless they happened to cross 0.6, and then they moved a whole
// octave. A control that is inaudible almost everywhere and enormous at one invisible point
// is worse than one that does nothing, and the founder heard exactly that: nothing.
//
// So the load-bearing assertions here are NOT "does the trim do something". They are the four
// properties that separate a fader from a switch, plus the one that keeps weather-off free:
//
//   · OFF IS BIT-IDENTICAL. Intensity 0 must return `ToneTrim.neutral` EXACTLY, and that
//     neutral must convert to `RoleRhythm.TimbreTrim.neutral` — which that type's own test
//     already proves is an exact identity on a patch. Weather is opt-in; a player who never
//     enables it must hear the genre's patch unchanged, and "approximately unchanged" is not
//     the same claim.
//   · IT IS A GRADIENT, NOT A THRESHOLD. Asserted by stepping 1 °C at a time across the whole
//     mapped range and requiring EVERY step to move the value. This is the defect above,
//     written as a test so it cannot come back as a `switch` over temperature bands.
//   · THE BOUND IS DERIVED FROM THE TYPE'S OWN CONSTANTS, so widening a number without
//     widening the declared bound turns red instead of quietly shipping a large trim. Same
//     discipline as `RoleTimbreTrimTests`, and for the same reason: #81/#125 were "every genre
//     converges on one sound", and an absolute per-condition target would rebuild that.
//   · THE DIRECTION MATCHES THE LABEL. Warm and clear brighter, cold and fog darker, night a
//     little darker than day. The copy is user-facing and shipping the inverse would be a
//     lying control, not a taste difference.
//   · IT REACHES THE VOICE. A pure trim nobody applies is the doorless-shelf shape (#322), and
//     this repo keeps a whole shelf of those.
//
// ⚠️ WHAT IT DOES NOT CLAIM. Nothing here says the founder will HEAR the sky, or that ±0.20 of
// brightness is the right amount. That is a device listening call and stays with him. This
// file says the control is continuous, bounded, direction-correct, free when off, and wired.

import Foundation
import XCTest
@testable import Echoelmusic

final class WeatherToneIsAudibleTests: XCTestCase {

    private static let conditions = WeatherSnapshot.Condition.allCases

    private func sky(_ t: Double,
                     _ c: WeatherSnapshot.Condition = .partlyCloudy,
                     day: Bool = true) -> WeatherSnapshot {
        WeatherSnapshot(temperatureC: t, condition: c, isDaylight: day, windKph: 0)
    }

    // MARK: - off is free

    /// The opt-in promise. `WeatherMood.blend` already keeps intensity 0 bit-identical for the
    /// mood targets; the tone half has to earn the same guarantee separately, because it is a
    /// different function with its own clamps.
    func testIntensityZeroIsExactlyNeutralForEverySky() {
        for c in Self.conditions {
            for t in stride(from: -40.0, through: 50.0, by: 5.0) {
                for day in [true, false] {
                    let trim = WeatherMood.toneTrim(for: sky(t, c, day: day), intensity: 0)
                    XCTAssertEqual(trim, WeatherMood.ToneTrim.neutral, """
                        Intensity 0 returned \(trim) for \(c) at \(t) °C — weather is OPT-IN, so \
                        a mixer at zero must be the exact identity, not a small offset. This is \
                        the one assertion that lets the rest of the app claim weather-off is \
                        bit-identical.
                        """)
                }
            }
        }
    }

    /// A negative or NaN mixer must not resurrect the trim through the clamp. `Swift.max(v, lo)`
    /// passes NaN straight through (CLAUDE.md's argument-order note), so the guard cannot be a
    /// clamp alone — it has to be the `i > 0` comparison, which NaN also fails.
    func testANonsenseMixerResolvesToNeutralRatherThanSomethingSmall() {
        let warm = sky(30, .clear)
        for i in [Float(-1), Float(-0.001), Float.nan] {
            XCTAssertEqual(WeatherMood.toneTrim(for: warm, intensity: i),
                           WeatherMood.ToneTrim.neutral, """
                           Intensity \(i) produced a non-neutral trim. A negative mixer would \
                           INVERT the label ("warm brightens") and a NaN one would push NaN into \
                           `filterCutoff`, which is the permanent-silence class this repo has \
                           shipped before.
                           """)
        }
    }

    /// A sensor that hands back nonsense must not colour the sound. WeatherKit can and does
    /// return values this app never validated, and the trim is one multiplication away from the
    /// filter cutoff.
    ///
    /// ⛔ THIS ONE CAUGHT A REAL DEFECT, and the shape is worth keeping: the first version of
    /// the code was NaN-safe and INFINITY-WRONG. `WeatherMood.clampRange` is
    /// `min(max(v, lo), hi)`, and Swift's `max(x, y)` is `y >= x ? y : x` — so `max(+inf, 0)`
    /// returns `+inf` and `min(+inf, 1)` then returns `1`. An infinite temperature was
    /// SATURATED into a perfectly finite offset, sailing past the `shift.isFinite` guard and
    /// producing the MAXIMUM trim (±0.20 brightness, ×1.36 / ×0.82 cutoff) — the exact inverse
    /// of what its own doc promised. Only NaN survives that clamp as non-finite, so testing
    /// NaN alone would have reported a green nobody earned. The fix sanitises the temperature
    /// at the boundary, before any clamp can hide it. `RoleRhythm.clampRange` has the OPPOSITE
    /// argument order and therefore the opposite behaviour; the two must never be reasoned
    /// about interchangeably.
    func testANonFiniteSkyResolvesToNeutral() {
        for t in [Double.nan, .infinity, -.infinity] {
            let trim = WeatherMood.toneTrim(for: sky(t, .clear), intensity: 1)
            XCTAssertEqual(trim, WeatherMood.ToneTrim.neutral, """
                            A temperature of \(t) produced \(trim). Non-finite input at a DSP \
                            boundary is an edge case, not an impossibility — the engineering \
                            rules say so and `EchoelDDSP.applyBioReactive` was hardened for \
                            exactly this after it shipped as permanent silence.
                            """)
        }
    }

    /// The bridge into the patch. `weatherToned` builds a `RoleRhythm.TimbreTrim` from a
    /// `ToneTrim`; if that conversion is not faithful at the identity, "off is free" stops being
    /// true one layer further down, where no test above would see it.
    func testTheNeutralToneConvertsToTheNeutralTimbreTrim() {
        let neutral = WeatherMood.ToneTrim.neutral
        let asTrim = RoleRhythm.TimbreTrim(brightness: neutral.brightness,
                                           cutoffFactor: neutral.cutoffFactor,
                                           attackFactor: 1, releaseFactor: 1)
        XCTAssertEqual(asTrim, RoleRhythm.TimbreTrim.neutral, """
            A neutral `ToneTrim` no longer maps onto `TimbreTrim.neutral`, so the studio's \
            conversion would apply a trim where it promised none. `RoleTimbreTrimTests` proves \
            the neutral trim is an exact identity on a patch — that proof only carries over if \
            this mapping lands on it.
            """)
    }

    // MARK: - a fader, not a switch

    /// ⭐ THE DEFECT, AS A TEST. Every single degree must move the sound. `partlyCloudy` in
    /// daylight is chosen on purpose: its condition and night offsets are both zero, so nothing
    /// clamps anywhere in the mapped range and a flat step can only mean a threshold.
    func testEveryDegreeMovesTheToneAndNoneJumps() {
        var previous = WeatherMood.toneTrim(for: sky(-5), intensity: 1).brightness
        var largestStep = Float(0)
        for degree in stride(from: -4.0, through: 32.0, by: 1.0) {
            let current = WeatherMood.toneTrim(for: sky(degree), intensity: 1).brightness
            let step = current - previous
            XCTAssertGreaterThan(step, 0, """
                Brightness did not rise from \(degree - 1) °C to \(degree) °C (\(previous) → \
                \(current)). A flat step means a band or a threshold has been reintroduced, \
                which is the exact defect this slice exists to remove: the old wiring only ever \
                changed anything when it crossed `darkness > 0.6`.
                """)
            largestStep = Swift.max(largestStep, step)
            previous = current
        }
        // No single degree may be a cliff. The whole mapped span is 0.30 of brightness over
        // 37 °C, so an honest slope is ~0.008 per degree; anything an order of magnitude above
        // that is a step function wearing a slope's clothes.
        XCTAssertLessThan(largestStep, 0.02, """
            One degree moved brightness by \(largestStep). Even if every step is non-zero, a \
            cliff that size is audible as a jump rather than a drift, and weather changes by \
            one degree all the time.
            """)
    }

    /// The mixer must behave like a mixer: half the fader, half the offset. Not a nicety —
    /// `Param.warmth` defaults to 0.5, so the DEFAULT experience is the midpoint of this line.
    func testTheMixerScalesLinearly() {
        let warm = sky(30, .clear)
        let full = WeatherMood.toneTrim(for: warm, intensity: 1).brightness
        for i in [Float(0.25), 0.5, 0.75] {
            let partial = WeatherMood.toneTrim(for: warm, intensity: i).brightness
            XCTAssertEqual(partial, full * i, accuracy: 1e-6, """
                At intensity \(i) the offset was \(partial), not \(full * i). A non-linear mixer \
                makes the fader's lower half feel dead, which is how a working control still \
                reads as "nicht bemerkbar".
                """)
        }
    }

    // MARK: - bounds

    /// Swept over every condition, a wide temperature range and the whole mixer.
    ///
    /// ⛔ READ WHAT THIS DOES AND DOES NOT SHOW. An earlier version of this comment claimed it
    /// was "asserted against the type's own constants, so raising a number without raising the
    /// declared bound turns red — the same contract `RoleRhythm.TimbreTrim` keeps". That was
    /// FALSE, and it is worth leaving the correction here rather than quietly rewriting: the
    /// two constants ARE the clamp (`toneTrim` clamps brightness to ±`maxToneBrightnessShift`
    /// and cutoff to 1 ± `maxToneCutoffDeviation`, and `toneBrightnessShift` clamps a third
    /// time), so raising a `condShift` to −0.5 or the temperature slope to 3.0 leaves every
    /// assertion below green. `RoleTimbreTrimTests` genuinely catches a widened number because
    /// there the per-character table is independent of the bound; here it is not.
    ///
    /// What this test DOES prove is still worth having: that the clamp is present and reached
    /// on every path — every condition, every daylight state, temperatures far outside the
    /// mapped range, and three mixer settings. Delete a clamp and it goes red immediately.
    /// `testTheTemperatureSlopeIsTheDocumentedOne` below is the one that catches a widened
    /// table, and the two must be read together.
    func testNoSkyCanPushTheTrimPastItsDeclaredBound() {
        let maxBright = WeatherMood.maxToneBrightnessShift
        let maxCut = WeatherMood.maxToneCutoffDeviation
        for c in Self.conditions {
            for t in stride(from: -40.0, through: 50.0, by: 2.5) {
                for day in [true, false] {
                    for i in [Float(0.25), 0.5, 1] {
                        let trim = WeatherMood.toneTrim(for: sky(t, c, day: day), intensity: i)
                        XCTAssertLessThanOrEqual(abs(trim.brightness), maxBright, """
                            \(c) at \(t) °C, mixer \(i) produced a brightness offset of \
                            \(trim.brightness), past the declared ±\(maxBright). The bound is \
                            what keeps genres as far apart after the trim as before it.
                            """)
                        XCTAssertLessThanOrEqual(trim.cutoffFactor, 1 + maxCut, """
                            \(c) at \(t) °C, mixer \(i) opened the filter by a factor of \
                            \(trim.cutoffFactor), past the declared 1 ± \(maxCut).
                            """)
                        XCTAssertGreaterThanOrEqual(trim.cutoffFactor, 1 - maxCut, """
                            \(c) at \(t) °C, mixer \(i) closed the filter by a factor of \
                            \(trim.cutoffFactor), past the declared 1 ± \(maxCut).
                            """)
                    }
                }
            }
        }
    }

    /// ⭐ THE ONE THAT CATCHES A WIDENED TABLE. Everything in the bound test above is absorbed
    /// by the clamp; this samples the mapping WELL INSIDE it, where the numbers themselves
    /// decide the answer. 20 °C partly cloudy in daylight has no condition and no night term,
    /// so its offset is purely the temperature slope: (25/37 − 0.5) × 0.30 = 0.0527027. Change
    /// the slope, the span, or either endpoint and this goes red — which is exactly what the
    /// bound test cannot do.
    func testTheTemperatureSlopeIsTheDocumentedOne() {
        let mild = WeatherMood.toneTrim(for: sky(20), intensity: 1).brightness
        XCTAssertEqual(mild, 0.0527027, accuracy: 1e-5, """
            20 °C partly cloudy in daylight now offsets brightness by \(mild), not 0.0527027. \
            That point sits far inside every clamp, so the change is in the MAPPING: the −5…32 \
            °C span, the 0.30 slope, or the partly-cloudy/daylight zero. Re-derive the numbers \
            in the header of `WeatherMood.toneBrightnessShift` in the same commit.
            """)
        // The two bounds are not independent — 1.8 is chosen so the brightness bound lands on
        // the cutoff bound. Moving one alone would either make the cutoff clamp start biting
        // (a silent knee in the middle of the fader's travel) or leave it unreachable at a
        // different place than documented.
        let expectedCutoffBound = WeatherMood.maxToneBrightnessShift * 1.8
        XCTAssertEqual(WeatherMood.maxToneCutoffDeviation, expectedCutoffBound, accuracy: 1e-6, """
            `maxToneCutoffDeviation` (\(WeatherMood.maxToneCutoffDeviation)) no longer equals \
            `maxToneBrightnessShift × 1.8` (\(expectedCutoffBound)). The two are coupled by the \
            1.8 in `toneTrim`; change one and the cutoff clamp either starts biting mid-travel \
            or moves somewhere the comment does not say it is.
            """)
    }

    /// Brightness and cutoff are two views of one question ("how open is this sound"). If they
    /// can disagree in sign, a sky can be bright and muffled at once — which is not a weather,
    /// it is a bug that would read as a bad patch.
    func testCutoffNeverDisagreesWithBrightness() {
        for c in Self.conditions {
            for t in stride(from: -30.0, through: 45.0, by: 2.5) {
                let trim = WeatherMood.toneTrim(for: sky(t, c), intensity: 1)
                // A DEADBAND, not sloppiness: every condition crosses zero at some temperature,
                // and asserting a STRICT inequality on a brightness of 1e-9 would test Float
                // rounding rather than the property. Below the band the only claim worth making
                // is that the filter has not moved audibly either.
                if trim.brightness > 1e-4 {
                    XCTAssertGreaterThan(trim.cutoffFactor, 1, """
                        \(c) at \(t) °C brightened the tone (\(trim.brightness)) while closing \
                        the filter (\(trim.cutoffFactor)).
                        """)
                } else if trim.brightness < -1e-4 {
                    XCTAssertLessThan(trim.cutoffFactor, 1, """
                        \(c) at \(t) °C darkened the tone (\(trim.brightness)) while opening \
                        the filter (\(trim.cutoffFactor)).
                        """)
                } else {
                    XCTAssertEqual(trim.cutoffFactor, 1, accuracy: 1e-3, """
                        \(c) at \(t) °C has no audible brightness offset (\(trim.brightness)) \
                        but moved the filter to \(trim.cutoffFactor).
                        """)
                }
            }
        }
    }

    // MARK: - direction

    /// The label is user-facing copy. Shipping its inverse is a lying control (the class #164
    /// was opened for), not a matter of taste.
    func testTheDirectionMatchesTheLabel() {
        let hotClearDay = WeatherMood.toneTrim(for: sky(30, .clear), intensity: 1).brightness
        let coldFogNight = WeatherMood.toneTrim(for: sky(-2, .fog, day: false),
                                                intensity: 1).brightness
        XCTAssertGreaterThan(hotClearDay, 0, """
            A hot clear day did not brighten the tone. "Warm weather brightens the tone" is the \
            explanation shown next to the fader.
            """)
        XCTAssertLessThan(coldFogNight, 0, """
            A cold foggy night did not darken the tone — the other half of the same sentence.
            """)

        // Same temperature, different sky: clear must be the most open, fog the most closed.
        let t = 12.0
        let clear = WeatherMood.toneTrim(for: sky(t, .clear), intensity: 1).brightness
        let overcast = WeatherMood.toneTrim(for: sky(t, .overcast), intensity: 1).brightness
        let rain = WeatherMood.toneTrim(for: sky(t, .rain), intensity: 1).brightness
        let fog = WeatherMood.toneTrim(for: sky(t, .fog), intensity: 1).brightness
        XCTAssertGreaterThan(clear, overcast, "A clear sky must be brighter than an overcast one.")
        XCTAssertGreaterThan(overcast, rain, "Overcast must be brighter than rain.")
        XCTAssertGreaterThan(rain, fog, """
            Rain must be brighter than fog. Fog is the most closed sky in the table on purpose — \
            it is the one that removes detail from the world it is describing.
            """)

        // Night is a small darkening, not a second condition.
        let day = WeatherMood.toneTrim(for: sky(t, .clear, day: true), intensity: 1).brightness
        let night = WeatherMood.toneTrim(for: sky(t, .clear, day: false), intensity: 1).brightness
        XCTAssertLessThan(night, day, "Night must be a little darker than the same sky by day.")
        XCTAssertLessThan(day - night, 0.05, """
            Night darkened the tone by \(day - night). Daylight is a modifier here, not a \
            condition of its own — a large night offset would swamp the temperature the label \
            actually names.
            """)
    }

    /// The mapping has a genuine zero, and stating where it is beats leaving it to be
    /// rediscovered: 13.5 °C, partly cloudy, daylight. A sky that is neither warm nor cold nor
    /// notable changes nothing at all, at any mixer setting. If a re-tune moves this point that
    /// is fine — but it should be a decision, not a surprise.
    func testTheNeutralSkyChangesNothing() {
        let trim = WeatherMood.toneTrim(for: sky(13.5, .partlyCloudy), intensity: 1)
        XCTAssertEqual(trim, WeatherMood.ToneTrim.neutral, """
            13.5 °C partly cloudy in daylight produced \(trim) instead of the identity. That \
            temperature is the midpoint of the mapped −5…32 °C span and the condition and \
            daylight offsets are both zero there, so the whole mapping should cancel.
            """)
    }

    // MARK: - one shape, two entry points

    /// `Contribution` carries the full-intensity shift so a stored contribution needs no
    /// snapshot kept beside it — which is exactly how the studio uses it. Two entry points into
    /// one shape function is safe; two copies of the maths is how they drift apart, and only
    /// one of them would be the one the player hears.
    func testAStoredContributionGivesTheSameTrimAsItsSnapshot() {
        for c in Self.conditions {
            for t in stride(from: -20.0, through: 40.0, by: 5.0) {
                for day in [true, false] {
                    let snapshot = sky(t, c, day: day)
                    let viaSnapshot = WeatherMood.toneTrim(for: snapshot, intensity: 0.5)
                    let viaContribution = WeatherMood.contribution(for: snapshot)
                        .toneTrim(intensity: 0.5)
                    XCTAssertEqual(viaSnapshot, viaContribution, """
                        \(c) at \(t) °C: the snapshot says \(viaSnapshot) and the stored \
                        contribution says \(viaContribution). The studio holds a contribution, \
                        not a snapshot, so the contribution is the one that reaches the voice.
                        """)
                }
            }
        }
    }

    // MARK: - it reaches the voice

    /// ⭐ THE DOOR. A pure trim nothing applies is the #322 orphan shape, and the reason this
    /// slice exists is precisely that a built weather influence was not audible. Source text,
    /// because `EchoelStudioView` is a SwiftUI type this bundle cannot build — the house pattern
    /// (`SoundPanelPresetBarTests`, `PoincareViewDoorTests`).
    func testTheStudioAppliesTheToneWhenItPushesAPatch() throws {
        let code = Self.stripComments(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(code.contains("synth.apply(weatherToned("), """
            `applyTakeSound` no longer pushes the patch through `weatherToned`. That single call \
            is the ONLY thing making the sky audible; without it the mixer row, the fetch and \
            the whole mapping are a fader wired to nothing — which is the state the founder \
            reported on 2026-08-01.
            """)
        XCTAssertTrue(code.contains("private func weatherToned("), """
            `weatherToned` is gone from `EchoelStudioView`. If it moved, re-point this guard; if \
            it was removed, remove this file in the same commit rather than leaving a green \
            nobody earned.
            """)
    }

    /// The trim MULTIPLIES (`TimbreTrim.trimmed`), so applying it twice compounds — 0.88² = 0.77,
    /// well outside the stated bound. `RoleRhythm.TimbreTrim`'s own header states this as a law
    /// and the rhythm trim obeys it by living on a local copy at push time. The weather trim
    /// rides the same copy, and the cheapest way to keep it there is to allow exactly one
    /// application site.
    func testTheToneIsAppliedInExactlyOnePlace() throws {
        let code = Self.stripComments(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        let uses = code.components(separatedBy: "weatherToned(").count - 1
        XCTAssertEqual(uses, 2, """
            `weatherToned(` appears \(uses) time(s) in the code (comments excluded); the \
            expected two are its declaration and the one call inside `applyTakeSound`. A third \
            means a second application site: verify it works on a LOCAL copy that is never \
            written back to `currentPatch`, then update this count with the reason. A patch \
            trimmed twice is outside the bound the tests above assert.
            """)
        XCTAssertFalse(code.contains("currentPatch = weatherToned"), """
            The weather-toned patch is being stored back into `currentPatch`. It compounds on \
            every push, and it also makes every number in the Sound panel dishonest — the \
            player would see the patch they chose plus an invisible offset that grows.
            """)
    }

    /// The sky must land on the CURRENT take, not the next one. Holding the tone until the
    /// player happens to regenerate is most of why weather read as "nicht bemerkbar": the salt
    /// and the mood targets are compose-time inputs and correctly wait, so without this push
    /// nothing at all changes at the moment the fetch returns.
    func testTheFetchPushesTheToneImmediately() throws {
        let code = Self.stripComments(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        let landing = "weatherContribution = WeatherMood.contribution(for: snap)"
        guard let stored = code.range(of: landing) else {
            return XCTFail("""
                The weather fetch no longer stores a contribution with `\(landing)` — re-point \
                this guard at whatever replaced it before trusting a green here.
                """)
        }
        let after = String(code[stored.upperBound...].prefix(400))
        XCTAssertTrue(after.contains("applyTakeSound("), """
            Nothing re-pushes the take patch after the weather fetch lands, so the sky becomes \
            audible only at the next generate. The mood targets legitimately wait for the \
            re-seed; the TONE is a patch push and has no reason to.
            """)
    }

    /// The fader must be audible while you set it. `EchoelValueField` already distinguishes
    /// change from commit; a weather mixer without the commit hook only takes effect at the next
    /// generate, which is indistinguishable from a broken fader.
    func testTheWarmthFaderRePushesOnCommit() throws {
        let code = Self.stripComments(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        XCTAssertTrue(code.contains("WeatherMixRow(param: param) { applyTakeSound("), """
            The weather mixer rows no longer re-push the take patch when a fader is released. \
            Moving "Warmth" would then do nothing audible until the next generate — the same \
            symptom this whole slice was opened for, one layer up.
            """)
    }

    // MARK: - helpers

    /// Drops `//` line comments so a guard counts call sites and not the prose about them.
    ///
    /// ⛔ #460: this was a private naive truncate at the first `//`, which is NOT the same
    /// operation — it also cuts a `//` that sits INSIDE a string literal. All four call sites strip
    /// `EchoelStudioView.swift`, which carries one — the WeatherKit attribution
    /// `URL(string: "https://developer.apple.com/…")`, left by the old strip as
    /// `URL(string: "https:`. Exactly one line. Pointedly this guard is ABOUT weather.
    /// Verdict-neutral on today's anchors (measured: 0 flips over every literal in this file) —
    /// but a future needle anywhere on such a line would have gone red on CORRECT code.
    /// `SourceText.codeOnly` (#453) is the ONE definition: string-aware, ordered,
    /// line-count-preserving. Do not re-inline a local copy.
    private static func stripComments(_ code: String) -> String {
        SourceText.codeOnly(code)
    }

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
