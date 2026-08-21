// AGrainCannotClickOrRunAwayTests.swift
// Echoel — #684. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS GUARDS. `EchoelGranular` is new DSP destined for the audio thread, and a
// granular stage has exactly two ways to ruin a take that a compiler cannot see:
//   1. A CLICK. A grain whose envelope does not start and end at zero splices a step
//      discontinuity into the signal, once per grain, forever. Claim 1 pins the envelope.
//   2. A RUNAWAY. Grains sum, so density silently doubles as a volume control unless the
//      sum is normalised — and a wet stage that gets louder as you turn a texture knob is
//      how a limiter ends up doing the mixing. Claims 4 and 6 pin the ceiling and the pool.
// Claims 2 and 3 are the boundary laws every stage in this repo owes: an exact bypass and
// a non-finite input that cannot escape or poison the ring buffer.
//
// ⭐ CLAIM 5 ALREADY DID THAT ONCE. It used to assert the core was NOT wired, and its
// failure message said wiring it would be "the intended next slice, not a defect — delete
// this claim and correct the header in the SAME commit (#456)". #687 wired it and the claim
// inverted on its own instructions. It now pins the six wiring sites plus the two switches
// that keep the stage inert, and carries ONE forward-looking negative — `FXPreset` must not
// yet mention granular — which will go red on the next slice for the same good reason.
// A guard that reds on the change it predicted is working, not failing.
//
// ⚠️ HONEST LIMITS. 7 tests, 25 assertion statements (5+3+4+3+4+2+4; counted in Python over
// lines whose first token is XCTAssert). Everything here is executed behaviour on the real
// type — no mocks, no host, no source scanning except claim 5. What no test can prove: that
// it SOUNDS like a granular effect. Grain size, density and spray are taste, and taste is a
// device probe (NEEDS-FOUNDER-VERIFY once it is wired and reachable).
//
// ⚠️ THE BOUND IN CLAIM 4 IS DERIVED, NOT WISHED FOR. Worst case is every one of the 8
// pool slots sounding at window peak with a hard-panned gain of 1, divided by the densest
// normalisation (overlap 3.5 → ×1/1.75): 8 / 1.75 ≈ 4.58. The test asserts 5.0 and not a
// tidier 2.0 precisely because a bound that the maths does not support is a test that
// passes today and reds on an input nobody predicted. The scheduler spaces grains out, so
// the typical peak is far below this — but "typical" is not a guarantee.
//
// ⭐ GRADING (§3). FORWARD in full: the type does not exist at the parent, so every claim
// is red there by one absence (#486). Numbers hand-derived (#442): `window` is
// 0.5 − 0.5·cos(2πx), so x=0 → 0.5 − 0.5·1 = 0, x=0.5 → 0.5 + 0.5 = 1, x=1 → 0 again.

import Foundation
import XCTest
@testable import Echoelmusic

final class AGrainCannotClickOrRunAwayTests: XCTestCase {

    // MARK: - 1: the envelope opens and closes at exactly zero

    /// The no-click promise, and the only part of it that is a pure function. A window
    /// that starts at anything but 0 puts a step into the signal once per grain.
    func testTheGrainEnvelopeStartsAndEndsAtZero() {
        XCTAssertEqual(EchoelGranular.window(0), 0, accuracy: 1e-6,
                       "A grain that opens above zero splices a step into the signal.")
        XCTAssertEqual(EchoelGranular.window(1), 0, accuracy: 1e-6,
                       "A grain that closes above zero clicks on its last sample.")
        XCTAssertEqual(EchoelGranular.window(0.5), 1, accuracy: 1e-6,
                       "The envelope must reach unity at the centre or grains lose level.")
        XCTAssertEqual(EchoelGranular.window(1.5), 0, accuracy: 1e-6, """
            A position past the grain's end must contribute NOTHING. Wrapping the cosine \
            instead would restart the window mid-signal — a click by another route.
            """)
        XCTAssertEqual(EchoelGranular.window(.nan), 0, accuracy: 1e-6,
                       "A non-finite position must read as silence, never as a gain.")
    }

    // MARK: - 2: mix 0 is an exact bypass and schedules nothing

    /// Not "close to" the input — identical. A stage that colours its own bypass cannot be
    /// A/B'd, and this one is destined to sit in a chain where every stage claims the same.
    func testZeroMixReturnsTheInputExactlyAndLaunchesNoGrain() {
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 0
        g.density = 1
        var allExact = true
        for i in 0..<4800 {
            let x = Float(i % 97) / 97.0 - 0.5
            let (l, r) = g.processStereo(x, -x)
            if l != x || r != -x { allExact = false; break }
        }
        XCTAssertTrue(allExact, """
            A bypassed grain stage changed the signal. Bypass must be bit-exact for finite \
            input — that is what makes an A/B honest.
            """)
        XCTAssertEqual(g.activeGrainCount, 0, """
            Grains were scheduled while the stage was bypassed. The house switch-crackle \
            rule is that a bypassed stage FREEZES, so re-enabling starts from silence.
            """)
        // ⛔ THE FIRST VERSION MADE ONE ENABLED CALL HERE AND WOULD HAVE GONE RED. The
        // bypass guard returns BEFORE the spawn accumulator advances, so 4 800 bypassed
        // calls leave it at exactly 0 — and one enabled call at these settings adds
        // 3.5/3840 = 0.00091. The first grain launches on call 1 098, about 23 ms in.
        // That wait is CORRECT behaviour; the expectation was what was wrong. 4 800 calls
        // accumulate 4.37, so this clears the threshold with room.
        g.mix = 0.5
        for i in 0..<4800 { _ = g.processStereo(Float(i % 97) / 97.0 - 0.5, 0.1) }
        XCTAssertGreaterThan(g.activeGrainCount, 0, """
            Turning the mix up scheduled nothing over 4 800 samples. An enabled effect that \
            never launches a grain is indistinguishable from a broken one (#454 — without \
            this the claim above would pass on a stage that does nothing at all).
            """)
    }

    // MARK: - 3: a non-finite sample cannot escape, and cannot poison the ring buffer

    /// ⛔ THE FIRST VERSION OF THIS CLAIM COULD NOT FAIL FOR THE REASON IT NAMED (#367). It
    /// fed one NaN and then asserted every later output was finite — but `processStereo`
    /// ends with `outL.isFinite ? outL : dryL`, so a POISONED buffer would surface as a
    /// silent fall back to dry, which is finite. The assertion passed on the exact defect it
    /// claimed to guard.
    ///
    /// The falsifiable form is a DIFFERENTIAL: two same-seeded instances, one fed a NaN
    /// where the other is fed a 0. If the sanitise-before-write at the top of
    /// `processStereo` holds, the NaN BECOMES a 0 and the two render bit-identically. Remove
    /// that sanitise and the poisoned instance falls back to dry for every sample a grain
    /// reads the bad region — visibly different from the clean one.
    ///
    /// ⚠️ `spraySeconds = 0` and `pitchSemitones = 0` are what make it DETERMINISTIC rather
    /// than probabilistic: every grain then starts at delay 1 and holds there, so the sample
    /// written on the injection call is read by every live grain on the very next call. With
    /// the default spray a grain only sweeps the poisoned slot if its random start happens to
    /// land near it, which would trade an unfalsifiable claim for a flaky one.
    func testANonFiniteInputNeitherEscapesNorPoisonsTheRingBuffer() {
        func run(injecting bad: Float) -> [Float] {
            let g = EchoelGranular(sampleRate: 48000, seed: 4242)
            g.mix = 1; g.density = 1; g.spraySeconds = 0; g.pitchSemitones = 0
            var out: [Float] = []
            for i in 0..<1200 { _ = g.processStereo(sinf(Float(i) * 0.01), sinf(Float(i) * 0.01)) }
            _ = g.processStereo(bad, bad)
            for i in 1200..<3200 {
                out.append(g.processStereo(sinf(Float(i) * 0.01), sinf(Float(i) * 0.01)).0)
            }
            return out
        }
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 1
        let (badL, badR) = g.processStereo(.nan, .infinity)
        XCTAssertTrue(badL.isFinite && badR.isFinite,
                      "A non-finite input escaped the stage on the very call that carried it.")

        let poisoned = run(injecting: .nan)
        let clean = run(injecting: 0)
        XCTAssertEqual(poisoned.count, clean.count, "Sanity: the two runs must be comparable.")
        let firstDiff = zip(poisoned, clean).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        XCTAssertNil(firstDiff, """
            The two runs diverged at sample \(firstDiff ?? -1). A NaN must be turned into a 0 \
            BEFORE it enters the ring buffer, so a run that saw one is indistinguishable from \
            a run that saw a zero. Divergence means the bad sample reached the buffer and every \
            grain reading that region now falls back to dry.
            """)
        XCTAssertTrue(poisoned.allSatisfy { $0.isFinite }, "A later output went non-finite.")
    }

    // MARK: - 4: density is a texture control, not a volume control

    /// See the ⚠️ note in the header for where 5.0 comes from. The point of the claim is
    /// that a BOUND exists at all — an unnormalised grain sum has none.
    func testTheDensestSettingStaysWithinItsDerivedCeiling() {
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 1
        g.density = 1
        g.grainMilliseconds = 40
        g.spraySeconds = 0.2
        var peak: Float = 0
        var allFinite = true
        for _ in 0..<48000 {
            let (l, r) = g.processStereo(1, 1)
            if !l.isFinite || !r.isFinite { allFinite = false; break }
            peak = Swift.max(peak, Swift.max(abs(l), abs(r)))
        }
        XCTAssertTrue(allFinite, "The dense path produced a non-finite sample.")
        XCTAssertLessThanOrEqual(peak, 5.0, """
            Peak \(peak) exceeds the ceiling the pool size and normalisation allow \
            (8 slots / 1.75 ≈ 4.58). Either the sum lost its normalisation or the pool cap \
            is not holding — both mean density has become a volume control.
            """)
        XCTAssertGreaterThan(peak, 0, """
            The dense path produced pure silence, which would make the ceiling above \
            vacuous (#454).
            """)
    }

    // MARK: - 5: wired at every site, and inert until two things are opened

    /// ⭐ THIS CLAIM INVERTED IN #687, ON ITS OWN INSTRUCTIONS. It used to assert that
    /// nothing in `Sources/` constructed `EchoelGranular`, and its failure message said:
    /// wiring it "is the intended next slice, not a defect — delete this claim and correct
    /// the header in the SAME commit (#456)". That is what happened. The guard did its job
    /// by going red on purpose, which is the only kind of red that is good news.
    ///
    /// It now pins the six sites, because a stage wired at five of them is the worse bug:
    /// it sounds right until the render sleeps, and then sprays second-old audio into a new
    /// take. `noteRenderSleeping` matters here more than for any other stage — this one
    /// holds the longest buffer in the chain.
    func testTheStageIsWiredAtEverySiteAndIsInertByDefault() throws {
        // ⛔ WHITESPACE-NORMALISED, and the first version was not. Two needles carried three
        // literal spaces (`if granularEnabled   {`) that exist only because the flag is
        // column-aligned to the longest name in the file. Add a stage with an 18-character
        // flag and the column re-indents — both needles miss and the guard reports the stage
        // as UNWIRED while it is fully wired. That is #646 in its purest form: a needle
        // naming a spelling a harmless reformat breaks.
        let chain = try source("Sources/Echoelmusic/DSP/EchoelFXChain.swift")
            .replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        let sites: [(String, String)] = [
            ("declaration",   "public let granular: EchoelGranular"),
            ("bypass flag",   "public var granularEnabled: Bool = false"),
            ("crackle reset", "if newValue && !granularEnabled { granular.reset() }"),
            ("construction",  "self.granular = EchoelGranular(sampleRate: sampleRate)"),
            ("render path",   "if granularEnabled { (l, r) = granular.processStereo(l, r) }"),
            ("sleep drain",   "if granularEnabled { granular.reset() }"),
        ]
        let missing = sites.filter { !chain.contains($0.1) }.map { $0.0 }
        XCTAssertEqual(missing, [], """
            The granular stage is missing from \(missing) in `EchoelFXChain`. Five of six is \
            the dangerous state, not a partial one — a stage absent from `noteRenderSleeping()` \
            sounds correct until the render sleeps, then sprays second-old audio into the next \
            take.
            """)
        // ⛔ READ RAW, AND THE FIRST VERSION OF THESE TWO DID NOT — a trap I set for myself
        // one line after fixing the missing stripper. The signal-flow line is a `///` DOC
        // COMMENT, so `codeOnly` blanks it: asserting on it through the stripped text would
        // have failed on a perfectly correct tree. A stripper is not a default; it is a choice
        // per needle, and a needle aimed at PROSE must read prose.
        let chainRaw = try rawSource("Sources/Echoelmusic/DSP/EchoelFXChain.swift")
        XCTAssertTrue(chainRaw.contains("in → filter → saturation"), """
            The file's canonical signal-flow line is gone or reworded. Re-anchor the assertion \
            below rather than letting it pass on a line that no longer exists (#454).
            """)
        XCTAssertTrue(chainRaw.contains("tremolo → granular → delay"), """
            The signal-flow line at the top of `EchoelFXChain.swift` does not place granular \
            between tremolo and delay. #687 wired the stage at six code sites and left this \
            line — the SEVENTH site, and the one a session reads to learn the chain — still \
            listing fourteen stages. The file then stated its own order in two places that \
            disagreed.
            """)
        let core = try source("Sources/Echoelmusic/DSP/EchoelGranular.swift")
        XCTAssertTrue(core.contains("public var mix: Float = 0"), """
            The stage's own wet mix no longer defaults to 0. Inert TWICE over is deliberate \
            while there is no door: the bypass flag and the mix are independent switches.
            """)
    }

    // MARK: - 5b: the persistence gap, named so its red is self-describing

    /// ⚠️ SPLIT OUT OF CLAIM 5 (#688). It lived inside the wiring test, so the day the
    /// persistence slice lands the red would have been reported under a test name that says
    /// "the wiring is broken" — a predicted red that misdescribes itself is worse than none.
    /// Forbids nothing (#364): its message names the block to correct in the same commit.
    func testFXPresetDoesNotYetCarryGranular() throws {
        let preset = try source("Sources/Echoelmusic/DSP/FXPreset.swift")
        XCTAssertTrue(preset.contains("harmonizerMix"), """
            `FXPreset` no longer carries harmonizer state — re-anchor this scan; without a \
            known-present neighbour the negative below proves nothing (#454).
            """)
        // `granularEnabled`, not `granular`: "granularity" is live English in this codebase
        // (`EchoelFXView`), so the looser needle would red on an ordinary doc comment.
        XCTAssertFalse(preset.contains("granularEnabled"), """
            `FXPreset` now carries granular state — the intended NEXT slice, not a defect. \
            Delete this test and correct the ⛔ "not persisted and it has no door" block in \
            `EchoelGranular.swift`'s header in the SAME commit (#456).
            """)
    }

    // MARK: - 6: same seed, same grains — and reset() really rewinds

    /// Determinism is what makes every claim above reproducible; without it a failure here
    /// could never be re-run. It also proves the pool cap, which needs a dense run to test.
    func testItIsDeterministicAndResetRewindsCompletely() {
        func render(_ g: EchoelGranular) -> ([Float], Int) {
            g.mix = 1; g.density = 1; g.grainMilliseconds = 30
            var out: [Float] = []
            var maxActive = 0
            for i in 0..<24000 {
                let (l, _) = g.processStereo(sinf(Float(i) * 0.02), sinf(Float(i) * 0.02))
                out.append(l)
                maxActive = Swift.max(maxActive, g.activeGrainCount)
            }
            return (out, maxActive)
        }
        let a = EchoelGranular(sampleRate: 48000, seed: 12345)
        let b = EchoelGranular(sampleRate: 48000, seed: 12345)
        let (outA, maxA) = render(a)
        let (outB, _) = render(b)
        // Compared by first-mismatch index rather than by whole array: XCTest dumps both
        // operands on failure, and 24 000 floats would bury the message under them.
        let diffAB = zip(outA, outB).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        XCTAssertNil(diffAB, """
            Two instances with the same seed diverged at sample \(diffAB ?? -1). Without \
            determinism no failure in this file can be reproduced, and the grain pattern is \
            untestable.
            """)
        XCTAssertLessThanOrEqual(maxA, EchoelGranular.maxGrains, """
            \(maxA) grains were live at once against a pool of \(EchoelGranular.maxGrains). \
            The scheduler must DROP a launch when the pool is full — growing it would \
            allocate on the audio thread.
            """)
        XCTAssertGreaterThan(maxA, 0, "No grain ever became active; the run proves nothing.")
        a.reset()
        let (outC, _) = render(a)
        let diffAC = zip(outA, outC).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        XCTAssertNil(diffAC, """
            After `reset()` the stage diverged from a fresh instance at sample \(diffAC ?? -1). \
            The RNG, the spawn accumulator or the delay lines survived the reset, which means \
            a preset recall would inherit the previous take's texture.
            """)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)
    //
    // ⛔ #687 CALLED `source(_:)` THREE TIMES WITHOUT DECLARING IT. In this repo the helper is
    // a per-file `private func`, re-pasted in every scanning guard — there is no shared
    // extension. The blocking bundle would have died on "cannot find 'source' in scope", and
    // neither local check catches it: `Xcode Compile Check` builds `Sources/` only, and
    // SwiftPM's test target resolves to `Tests/EchoelmusicTests`, not this directory.
    // Restoring it also restores `SourceText.codeOnly`, which #687's hand-rolled scan had
    // dropped — without it a ⛔ block QUOTING a needle would have satisfied it (a false green).

    private struct DiagAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The same file WITHOUT the stripper, for needles aimed at prose. Kept as a separate
    /// entry point rather than a flag, so every call site says which one it wanted.
    private func rawSource(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: "\(relativePath) is missing while the tree is present.")
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
