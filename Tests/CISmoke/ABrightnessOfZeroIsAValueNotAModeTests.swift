// ABrightnessOfZeroIsAValueNotAModeTests.swift
// Echoel — #564. The darkest brightness a player can set was a SENTINEL, and reaching it did not
// darken the sound: it switched `applyBioReactive` to a different algorithm for the rest of the
// take.
//
// THE DEFECT, stated once. `EchoelDDSP.bioBaseBrightness` is the patch-level centre the always-on
// bio path modulates around. It used `0` for "no patch anchor set" and was read behind `> 0`.
// But `SynthPatch.Bounds.brightness` is `0...1` and `apply(to:)` writes the patch's `brightness`
// straight into that anchor — so a player dragging the Brightness field in `soundPanel` to its
// bottom wrote the sentinel. `applyBioReactive` then read "no patch" and took its LEGACY absolute
// branch, which computes brightness from coherence and heart rate alone (~0,43 at neutral
// readings). The darkest setting in the instrument produced a mid-bright sound — and only while a
// bio source was running, which is the half that makes it hard to attribute: with bio off the
// value is honoured, so it reads as "the patch changes when biofeedback is on".
//
// ⭐ WHY IT SURVIVED THREE SLICES THAT LOOKED STRAIGHT AT IT. #557 found the same comparison and
// drew the right conclusion for the wrong scope: it held `ddsp.osc.brightness` OUT of
// `PolySynthVoice.automatableBases` so no automation lane could pass through zero. That is
// correct and insufficient — the hazard was never automation's. A guard scoped to one subsystem
// sees the hazard only where it looked, and the exclusion made the surface it protected look
// safe while the field two panels over reached the same value by hand. The repair is the
// sentinel (−1, read `>= 0` — the discipline the vibrato trio already carried, #558/#279), and
// binding brightness is then a consequence rather than the point.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–4 are END-TO-END BEHAVIOUR. `EchoelDDSP` and `SynthPatch` are public,
//     Foundation-only value/reference types with no engine dependency, so these drive the
//     shipped code rather than describing it — including the patch→anchor write itself.
//   · claim 5 is END-TO-END on a sibling anchor: the discipline this fix copied must stay put.
//   · DEVICE PROBE, open and NOT covered here: whether a patch at brightness 0 now SOUNDS like
//     the darkest setting rather than merely measuring like it, and whether the change is
//     audible on any existing patch (it must not be — every shipped patch is at 0,1 or above).
//
// ⚠️ HONEST GRADING, transcribed in Python against the parent (`8a62849`) and this tree — the
// smoother and both branches re-implemented and run for the same 800 calls. The file compiles
// against both; every symbol it names already existed, only their VALUES moved:
//   · **THREE RED ASSERTIONS ON THE PARENT, ONE FINDING** (#486): claim 1, claim 2's third
//     assertion, and claim 3's first. All three are the single sentinel collision seen from three
//     ends — the engine's branch choice, the patch that reaches it, and the default that defines
//     it. Reporting them as three defects would be the flattering direction of #433.
//   · MEASURED, not derived: an anchored voice at brightness 0 under a resting body settles at
//     **0,4300** on the parent (the legacy branch: 0,08 + 0,5·0,35 + 0,5·0,2 + 0,075) and at
//     **0,0500** here (the anchored branch's floor). My draft of this line wrote 0,4297 from
//     arithmetic in my head before the run; the run says 0,4300, and a number in a guard header
//     is exactly the kind that gets quoted onward.
//   · ⛔ AND THE DRAFT NAMED THE WRONG ASSERTION — it called claim 2's SECOND assertion the
//     second red. Measured, claim 2's first two are green on the parent (the patch really did
//     write 0, and 0 really was not −1 there); it is the THIRD, the settle, that goes red. The
//     distinction matters because "the patch reached the sentinel" was TRUE on the parent — that
//     is the bug, not a broken assertion.
//   · claims 4 and 5, and claim 3's remaining two, are COUNTERWEIGHTS green on both trees, and
//     they are what makes the fix a fix rather than a deletion: the patch-less voice must still
//     take the legacy branch (0,6050 at high coherence, identical on both trees), a normal patch
//     must be untouched (0,1 / 0,3 / 0,55 / 0,8 all settle exactly on their anchor, both trees),
//     and the vibrato sentinel must stay −1. A tree that "simplified" the legacy branch away
//     would satisfy claim 1 and fail claim 3.
//   · STRIPPER: not used. Every assertion here is behavioural; there is no source-text scan in
//     this file, so `SourceText.codeOnly` never runs and the load-bearing question does not
//     arise. (The source-text half of this change lives in `TheAutomatableSetHasOneWriterTests`
//     claim 5, which #564 rewrote and re-drove in full per §3.)

import Foundation
import XCTest
@testable import Echoelmusic

final class ABrightnessOfZeroIsAValueNotAModeTests: XCTestCase {

    /// Long enough for the one-pole smoother (α = 0,6065 per call) to settle: 800 calls is the
    /// same figure the older brightness-anchor tests use, so a reader comparing them is not
    /// comparing two different convergence claims (#416).
    private static let settleCalls = 800

    /// A resting body: every channel at its neutral reading, so the anchored branch's deviations
    /// are all exactly zero and the result is the anchor itself (clamped). Neutral is what makes
    /// the two branches distinguishable by a single number instead of by a curve.
    private func settle(_ dsp: EchoelDDSP, coherence: Float = 0.5) {
        for _ in 0..<Self.settleCalls {
            dsp.applyBioReactive(coherence: coherence, hrvVariability: 0.5, heartRate: 0.5)
        }
    }

    // MARK: - claim 1 (REGRESSION, END-TO-END) — the bottom of the range is a sound, not a branch

    func testAPatchAtZeroBrightnessStaysOnTheAnchoredPath() {
        let dsp = EchoelDDSP()
        dsp.brightness = 0
        dsp.bioBaseBrightness = 0
        settle(dsp)
        XCTAssertLessThan(dsp.brightness, 0.10, """
            A voice anchored at brightness 0 settled at \(dsp.brightness) under a resting body. \
            The anchored branch's floor is 0,05; anything near 0,43 is the LEGACY absolute branch, \
            which means `applyBioReactive` read the anchor as "no patch applied" and switched \
            algorithms. Zero is inside `SynthPatch.Bounds.brightness` (0…1) and the `soundPanel` \
            Brightness field reaches it, so this is not a theoretical value — it is the darkest \
            setting the instrument offers, and it must darken the sound rather than change the \
            path. The sentinel is −1 and the gate is `>= 0` (#564); if either was reverted, this \
            is where it shows.
            """)
    }

    // MARK: - claim 2 (REGRESSION, END-TO-END) — and the patch really does write that value

    /// Claim 1 sets the anchor by hand, which proves the ENGINE's behaviour and not that anything
    /// reaches it. This drives the actual path a player takes: a patch carrying brightness 0
    /// through `apply(to:)`. Without it, claim 1 guards a state the app might never produce.
    func testAPatchCarriesZeroBrightnessIntoTheAnchor() {
        let dsp = EchoelDDSP()
        SynthPatch(name: "darkest", brightness: 0).apply(to: dsp)
        XCTAssertEqual(dsp.bioBaseBrightness, 0, accuracy: 1e-6, """
            `SynthPatch.apply(to:)` no longer writes brightness 0 into `bioBaseBrightness` \
            (it wrote \(dsp.bioBaseBrightness)). Either the write was removed — in which case the \
            anchored branch is unreachable and every patch now sounds like the legacy sweep — or \
            the value is being clamped away from the bottom of its own declared range.
            """)
        XCTAssertNotEqual(dsp.bioBaseBrightness, -1, """
            The patch wrote the UNSET sentinel. A patch is by definition an anchor being set, so \
            it may never produce the value that means "no patch" — that is exactly the collision \
            #564 removed, reintroduced from the other side.
            """)
        settle(dsp)
        XCTAssertLessThan(dsp.brightness, 0.10, """
            The full path — patch at brightness 0 → `apply(to:)` → a resting body → \
            \(dsp.brightness). This is claim 1 driven end to end from the surface a player \
            actually touches.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the patch-less voice still takes the legacy branch

    /// The assertion that blocks the cheap repair. Deleting the legacy branch, or making the gate
    /// unconditional, satisfies claims 1 and 2 and silently changes the RAW bio voice — the one
    /// that never receives a patch (`BioReactiveSynthVoice`). Its character is a shipped sound,
    /// not a fallback nobody hears.
    func testTheVoiceWithoutAPatchKeepsTheLegacySweep() {
        let dsp = EchoelDDSP()           // default anchor = the unset sentinel
        XCTAssertLessThan(dsp.bioBaseBrightness, 0, """
            `bioBaseBrightness` no longer defaults to a value OUTSIDE its parameter range. A \
            default inside 0…1 makes a voice that never got a patch indistinguishable from a \
            patch asking for that brightness, and the legacy branch below becomes unreachable.
            """)
        settle(dsp, coherence: 1.0)
        XCTAssertGreaterThan(dsp.brightness, 0.4, """
            The patch-less bio voice settled at \(dsp.brightness) under high coherence; the legacy \
            absolute sweep puts it above 0,4. If the legacy branch was removed while fixing the \
            sentinel, this voice quietly changed character — a different bug in the same lines.
            """)
        XCTAssertLessThanOrEqual(dsp.brightness, 0.8,
                                 "the legacy branch keeps its own 0,8 clamp")
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — every ordinary patch is untouched

    /// The whole point of the change is that it moves ONE case. A patch at a normal brightness
    /// must settle where it always did, or the "byte-identical for everything that ships" claim
    /// in the anchor's own doc is false.
    func testANormalPatchStillSettlesAtItsOwnBrightness() {
        for value: Float in [0.1, 0.3, 0.55, 0.8] {
            let dsp = EchoelDDSP()
            dsp.brightness = value
            dsp.bioBaseBrightness = value
            settle(dsp)
            XCTAssertEqual(dsp.brightness, value, accuracy: 0.08, """
                A patch anchored at \(value) settled at \(dsp.brightness). At neutral readings the \
                anchored branch's deviations are all zero, so a resting body must sound like the \
                patch. This is the invariant task #81 bought and #564 must not spend.
                """)
        }
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the discipline this copied stays where it is

    /// #564 made brightness match the vibrato trio. If someone later "unifies" the sentinels the
    /// other way — back to 0 — the three patches that legitimately ship `vibratoDepth: 0` get a
    /// vibrato they asked not to have (#279), which is the same defect in a parameter where it is
    /// even easier to mistake for a preset choice.
    func testTheVibratoAnchorsKeepTheirOutOfRangeSentinel() {
        let dsp = EchoelDDSP()
        XCTAssertEqual(dsp.bioBaseVibratoDepth, -1, accuracy: 1e-6, """
            `bioBaseVibratoDepth` no longer defaults to −1. Zero is a musical vibrato depth — the \
            majority of shipped patches ask for exactly that — so 0-as-unset routes them into the \
            absolute path that hands them a vibrato (#279).
            """)
        XCTAssertEqual(dsp.bioBaseVibratoRate, -1, accuracy: 1e-6,
                       "`bioBaseVibratoRate` no longer defaults to −1 — see the depth above")
    }
}
