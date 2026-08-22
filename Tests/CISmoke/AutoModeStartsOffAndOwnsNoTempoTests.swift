// AutoModeStartsOffAndOwnsNoTempoTests.swift
// Echoel — #608 Scheibe 1 (Founder 2026-08-15: „optionaler Automodus … sanft
// intervenieren … Kohärenz herstellen"). `Tests/CISmoke` is the blocking bundle.
//
// WHAT THIS GUARDS. The Auto mode is the first feature since the ModulationEngine
// lesson (#541) whose failure mode is not "wrong" but "machine without a door" or
// "door without honesty". Its contract, each half pinned here: (1) it ships OFF —
// steering the user's mood dials unasked is the one thing it must never do first;
// (2) the door EXISTS in `bioPanel`, beside the other body-driven switch, and its
// caption promises only channels a producer actually feeds (#496 — no "trend", no
// breath depth, no LF/HF); (3) OFF/neutral/paused is byte-identical (the Golden law
// `WeatherMood.blend` already earned — intensity 0 is the exact identity); (4) the
// steering is hysteretic and slow — a single-window threshold crossing cannot flip
// it, a fresh policy holds one full evolve tick before reversing; (5) Auto mode
// owns NO tempo: the fold and the decision core contain zero tempo calls, provable
// by scan because there is no engine file where one could hide (the AutoAttune
// invariant header names this as the structural guarantee).
//
// ⚠️ TEMPO-COUNT DELEGATION (#416): `PatternEngine.TempoSource.allCases.count == 5`
// is pinned by `TempoInvariantTests` (with the case names). This file deliberately
// does NOT restate that count — a sixth case would red the existing guard; here we
// pin only the ABSTINENCE (zero tempo call sites in the auto path).
//
// ⚠️ LIMITS (§1), labeled per test below: the behavioral tests drive shipped pure
// types (`AutoAttune`, `WeatherMood.blend`, `StudioDefaultKeys`) — the strong kind.
// The door/caption/fold tests are SOURCE-TEXT SCANS: they prove where text sits,
// not that the row renders. Whether the steering is AUDIBLE and feels gentle, and
// whether the disabled-state caption reads right, are DEVICE PROBES — registered
// as open, not implied covered. Reachability of `bioPanel` itself is the sibling
// `TheBreathVoiceHasADoorTests`' premise and is not re-proven here.
//
// ⚠️ HONEST GRADING (#433/#464) — transcribed in Python against the parent
// (99e371e) and this tree. 49 verdicts in 9 tests, hand-counted per named needle
// (a numeric sweep counts as ONE): ships-off (2) + identity/Golden (3) +
// hysteresis (5 — the fifth is #608b's neutral-entry exemption, review finding 4)
// + non-finite (2) + darkness-switch (2) + door/caption (10, source: decl +
// mount count + window order + slice non-empty + caption positive + 5 named dead
// words) + fold/core (14, source: non-empty + 3 tempo needles + hoist order +
// no-let + 8 named core needles) + #609/#609b visual half (10 behavioral:
// pulse/hue/spread identity + 2 gentleness bounds + nil-identity + 2 autoTerm +
// 2 direction; 7 source: from-flag hand-off + autoTerm call + 2 look-product
// folds + 3 host threads). Total 55 verdicts in 9 tests: 24 behavioral + 31
// source, all transcribed green on this tree. The #609 rows are FORWARD against
// d9f707f (one finding, #486); everything earlier grades as before.
// ⛔ #609b RETRACTION, the expensive kind: the first #609 modified vp.intensity/
// vp.complexity — the two fields with ZERO renderer consumers (the shipped shader
// reads vp.pulseHz only) — and its claims 8/9 were GREEN while the feature changed
// no pixel: green for a reason that never existed (§2's #367 mirror), despite the
// wired-but-dead warning standing verbatim at the call site. The consumer now
// exists (the look-product folds) and is pinned by three needles above.
// Against the PARENT this file does NOT COMPILE: `AutoAttune` and
// `StudioDefaultKeys.autoMode` do not exist there, so per §3 NO assertion has a
// verdict on the parent — the behavioral claims are FORWARD by construction (one
// finding, #486), and the source scans hand-transcribed against the parent are
// red as the SAME single absence (door + fold + hoist born with this commit; the
// `#else let` shape the no-let scan forbids WAS the parent's). The fold's three
// tempo-needle scans and the caption dead-word scans are the COUNTERWEIGHT kind:
// green on both trees, and the point of the file. ZERO regressions claimed,
// because zero exist. `SourceText.codeOnly` is TRAGEND here, MEASURED (#453,
// re-measured at #609b with the new denominator — #448): 3 of 31 source verdicts
// flip raw-vs-stripped on this tree — fold `transport` (an OLD comment in
// `makeComposerInput` says "the downstream transport tempo"), core `@Observable`
// and core `EngineBus` (the AutoAttune header quotes its own forbidden words:
// "NO @Observable", "EngineBus EU-AI-Act framing"). The 7 #609b needles are
// PROPHYLAKTISCH (0 flips — each lives in code, none is quoted whole in prose).
// ⛔ And the transcription caught a live #408 before first run: the hoist-order
// claim first anchored on `#if canImport(WeatherKit)`, which occurs TWICE in
// `makeComposerInput` (structure-seed salt above the blend) — it matched the
// wrong site and was red on correct code. Re-anchored to the unique blend gate.
//
// ⚠️ #614 (slice 4a) GRADING, appended — transcribed against the parent 6ef8767
// and this tree (94 checks total, claims 6/7/9 re-driven on the edited files):
// claim 10 adds 17 source verdicts, claim 11 adds 4 behavioral. On the parent all
// 17 claim-10 verdicts are red as ONE anchor absence (#486): the wiring is born
// with this commit — FORWARD, no regression claimed. Claim 11 is the COUNTERWEIGHT
// kind: GREEN on BOTH trees (the pause registry and the steer-side pins shipped
// with slice 1) — it is what makes claim 10's wiring mean something. Claims 6/7/9
// stay green on both trees. Stripper measurement (#453/#448): TRAGEND, 1 of 17
// claim-10 verdicts flips raw-vs-stripped — `.onChange(of: autoMode)` counts 2 raw
// (the `moodKnob` doc block cites it) vs 1 stripped; the other 16 needles are
// PROPHYLAKTISCH (0 flips). ⛔ And the transcription caught a second live #408
// before first run: `autoAttuneState = AutoAttune.State()` is CONTAINED in the
// @State declaration's initializer, so a first draft asserting ==1 file-wide was
// red on its own tree; the shipped assertion counts 2 and names both sites.
// ⚠️ #615, appended: ONE caption needle added to claim 6 ("Auto lets that dial
// go" — the pause becomes discoverable at the door). FORWARD against 54818a1
// (the sentence is born with #615); the dead-word scans stay the counterweight.
// Raw==stripped for this needle (it lives in a string literal; the nearby test
// comment paraphrases, never quotes it whole) — PROPHYLAKTISCH, measured.
// ⚠️ #648, appended — and this paragraph exists because the slice INTRODUCED a
// symbol into a pre-existing guard, which §3 says must be stated rather than left
// to read as "graded as before". Against #648's parent (1f51ee9) this file no
// longer compiles: `BioPanelRowCopy` is born with that commit, so NO assertion in
// it has a verdict on that parent (#486 — one absence, not three). The three
// re-anchored assertions in claim 6 are therefore **FORWARD**, not regressions:
// they could never have been red there. What they replaced was worse than red —
// two scanned `AutoModeRow`'s own text for a caption #648 moved OUT of the row
// (red on a correct tree, #364), and the dead-word ban would have stayed **GREEN
// over text it no longer sees**, the §4 failure this file's own comment names.
// The ban also grew from 5 verdicts to **15** (5 words × 3 render states: body,
// demo, nothing-measured) — the two extra states are #648's new caption forms,
// and a ban checking one of three covers a third of the renders. All three now
// DRIVE the pure static instead of scanning source, which upgrades them from
// SOURCE-TEXT SCAN to END-TO-END BEHAVIOUR (§1) and makes them immune to the
// sentence moving again. ⛔ The first repair spelled the static
// `autoModeCaption(synthetic: Bool)`, which is the #644 Bool defect returning: a
// Bool cannot express "nothing is measured yet", so that third state would have
// had to be spelled a second way somewhere else (#416). It takes the FRAME.

import Foundation
import XCTest
@testable import Echoelmusic

final class AutoModeStartsOffAndOwnsNoTempoTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let core = "Sources/Echoelmusic/Sequencer/AutoAttune.swift"

    // MARK: - claim 1 (BEHAVIOUR) — Auto mode ships OFF

    func testAutoModeShipsOff() {
        XCTAssertEqual(StudioDefaultKeys.autoMode.value, false, """
            Auto mode's fresh-install default is no longer OFF. Steering the user's \
            mood dials without being asked is the one thing this feature must never \
            do first — flipping this default is a founder call, not a tune-up.
            """)
        XCTAssertEqual(StudioDefaultKeys.autoMode.key, "studio.autoMode", """
            The storage key string changed. It is the on-disk contract with every \
            shipped install — a rename silently resets the preference for everyone.
            """)
    }

    // MARK: - claim 2 (BEHAVIOUR) — off/neutral/paused is byte-identical

    func testNeutralAndPausedAreTheExactIdentity() {
        // The Golden law this feature inherits by reuse: intensity 0 through the
        // blend is bit-identical for any base/target.
        for base in stride(from: Float(0), through: 1, by: 0.125) {
            XCTAssertEqual(WeatherMood.blend(base: base, target: 1 - base, intensity: 0),
                           base, """
                `WeatherMood.blend` at intensity 0 moved a value. Auto mode OFF and \
                Auto mode neutral both rely on this exact identity — if the mixer \
                drifts, "off" quietly stops meaning off for weather AND auto alike.
                """)
        }
        // Neutral body (mid coherence, mid arousal) → no steering at all.
        let (steer, _) = AutoAttune.decide(calm: 0.5, arousal: 0.5,
                                           baseDarkness: 0.4, baseLiveliness: 0.6,
                                           baseTension: 0.2,
                                           previous: AutoAttune.State())
        XCTAssertEqual(steer.intensity, 0, """
            A neutral body produced steering (intensity \(steer.intensity)). Between \
            the hysteresis bands Auto mode must LISTEN, not nudge — otherwise it is \
            always-on modulation wearing an opt-in label.
            """)
        // A paused parameter is pinned to its base even while a policy is active.
        var paused = AutoAttune.State(policy: .settled, ticksInPolicy: 3)
        paused.pausedTension = true
        let (activeSteer, _) = AutoAttune.decide(calm: 0.9, arousal: 0.1,
                                                 baseDarkness: 0.4, baseLiveliness: 0.6,
                                                 baseTension: 0.2, previous: paused)
        XCTAssertEqual(activeSteer.tensionTarget, 0.2, """
            A session-paused parameter got a moved target. "Your own edits keep \
            priority" is the door's literal promise — a paused dial's target must \
            equal its base (identity through the blend), whatever the policy does.
            """)
    }

    // MARK: - claim 3 (BEHAVIOUR) — hysteresis: bands hold, fresh policies hold

    func testASingleWindowCrossingCannotFlipThePolicy() {
        // Enter settled from a held neutral.
        let neutral = AutoAttune.State(policy: .neutral, ticksInPolicy: 2)
        let (_, entered) = AutoAttune.decide(calm: 0.7, arousal: 0.2,
                                             baseDarkness: 0.5, baseLiveliness: 0.5,
                                             baseTension: 0.3, previous: neutral)
        XCTAssertEqual(entered.policy, .settled, """
            calm 0.7 from a held neutral did not enter `settled` — the enter band \
            (\(AutoAttune.enterCalm)) moved or the policy machine broke.
            """)
        // Between exit (0.50) and enter (0.65): the PREVIOUS policy holds.
        let held = AutoAttune.State(policy: .settled, ticksInPolicy: 2)
        let (_, between) = AutoAttune.decide(calm: 0.55, arousal: 0.2,
                                             baseDarkness: 0.5, baseLiveliness: 0.5,
                                             baseTension: 0.3, previous: held)
        XCTAssertEqual(between.policy, .settled, """
            calm 0.55 — BETWEEN the exit and enter bands — flipped the policy. The \
            gap between the bands is the whole anti-flicker mechanism: jitter around \
            one threshold must never oscillate the steering.
            """)
        let (_, exited) = AutoAttune.decide(calm: 0.45, arousal: 0.2,
                                            baseDarkness: 0.5, baseLiveliness: 0.5,
                                            baseTension: 0.3, previous: held)
        XCTAssertEqual(exited.policy, .neutral, """
            calm 0.45 — below the exit band — did not leave `settled`. The exit half \
            of the hysteresis is gone; the steering would latch forever.
            """)
        // A policy entered THIS tick (ticksInPolicy 0) may not reverse yet, even on
        // a hard opposite reading: the steering moves in bars, not single windows.
        let fresh = AutoAttune.State(policy: .settled, ticksInPolicy: 0)
        let (_, stillFresh) = AutoAttune.decide(calm: 0.1, arousal: 0.9,
                                                baseDarkness: 0.5, baseLiveliness: 0.5,
                                                baseTension: 0.3, previous: fresh)
        XCTAssertEqual(stillFresh.policy, .settled, """
            A policy entered on the previous tick reversed immediately. The minimum \
            hold (one full evolve tick) is what makes the founder's "sanft" a \
            structural property instead of a hope — without it one noisy window \
            whipsaws the whole character.
            """)
        // #608b (review finding 4): the hold governs REVERSALS between opposing
        // policies only. Leaving `neutral` is an entry — a body that is already
        // clearly settled when Auto turns on must steer on the FIRST consult, not
        // wait an unexplained extra tick.
        let (_, fromRest) = AutoAttune.decide(calm: 0.7, arousal: 0.2,
                                              baseDarkness: 0.5, baseLiveliness: 0.5,
                                              baseTension: 0.3,
                                              previous: AutoAttune.State())
        XCTAssertEqual(fromRest.policy, .settled, """
            A fresh `State()` (neutral, ticks 0) with a clearly settled body did not \
            enter `settled` on the first consult. The neutral-entry exemption from \
            the minimum hold is gone — the first audible steering now needs two \
            consults for no stated reason.
            """)
    }

    // MARK: - claim 4 (BEHAVIOUR) — a broken signal neither steers nor advances

    func testNonFiniteInputIsIdentityAndFreezesTheState() {
        let before = AutoAttune.State(policy: .settled, ticksInPolicy: 2)
        let (steer, after) = AutoAttune.decide(calm: Float.nan, arousal: 0.2,
                                               baseDarkness: 0.5, baseLiveliness: 0.5,
                                               baseTension: 0.3, previous: before)
        XCTAssertEqual(steer.intensity, 0, """
            A NaN coherence produced steering. Non-finite bio input at any boundary \
            is an edge case, not an impossibility (engineering.md) — it must yield \
            the identity, never a computed nudge.
            """)
        XCTAssertEqual(after, before, """
            A NaN input advanced the hysteresis state. A frozen or broken signal \
            must not count toward holds — otherwise a stalled sensor "earns" policy \
            changes the body never made.
            """)
    }

    // MARK: - claim 5 (BEHAVIOUR) — darkness never crosses the composer switch

    func testDarknessStaysOnItsBasesSideOfTheComposerSwitch() {
        // Base below the switch, settled policy pushes darkness UP (+0.10): the
        // target must cap AT the switch, and the blended value stays strictly below.
        let held = AutoAttune.State(policy: .settled, ticksInPolicy: 2)
        let (steer, _) = AutoAttune.decide(calm: 0.9, arousal: 0.1,
                                           baseDarkness: 0.55, baseLiveliness: 0.5,
                                           baseTension: 0.3, previous: held)
        XCTAssertLessThanOrEqual(steer.darknessTarget, AutoAttune.composerDarknessSwitch, """
            A base darkness of 0.55 got a target past the composer's `darkness > 0.6` \
            character switch. Auto mode must never flip the take's character as a \
            side effect — the target caps at the switch value.
            """)
        let blended = WeatherMood.blend(base: 0.55, target: steer.darknessTarget,
                                        intensity: steer.intensity)
        XCTAssertLessThanOrEqual(blended, AutoAttune.composerDarknessSwitch, """
            The BLENDED darkness crossed the composer switch even though the target \
            was capped — the intensity is no longer < 1, or the blend changed. Same \
            law, one step later in the chain.
            """)
    }

    // MARK: - claim 6 (SOURCE-TEXT) — the door exists in bioPanel, honestly captioned

    func testTheDoorExistsBesideTheOtherBodySwitch() throws {
        let code = try source(Self.studio)
        XCTAssertTrue(code.contains("private struct AutoModeRow: View {"), """
            `AutoModeRow` is no longer declared. The Auto mode would be a machine \
            without a door — the exact #541 register entry this slice exists to not \
            repeat. If the row moved files, move this needle in the same commit.
            """)
        let mounts = code.components(separatedBy: "AutoModeRow()").count - 1
        XCTAssertEqual(mounts, 1, """
            `AutoModeRow()` is mounted \(mounts) time(s); exactly one is expected — \
            in `bioPanel`, between `BreathVoiceRow()` and the Routing button. Zero \
            is the doorless machine; two means a second surface began steering \
            expectations without this guard being widened.
            """)
        // The mount sits in the bioPanel window: after the breath-voice row, before
        // the Routing door (both anchors verified single-occurrence as CODE — the
        // struct DECLARATION of BreathVoiceRow spells `: View`, not `()`).
        if let breath = code.range(of: "BreathVoiceRow()"),
           let auto = code.range(of: "AutoModeRow()"),
           let routing = code.range(of: "showRouting = true", range: breath.upperBound..<code.endIndex) {
            XCTAssertTrue(breath.upperBound <= auto.lowerBound && auto.upperBound <= routing.lowerBound, """
                `AutoModeRow()` is mounted outside the `bioPanel` window (between the \
                breath-voice row and the Routing button). A door in another panel is \
                a different decision — re-judge the placement, then move this scan.
                """)
        } else {
            XCTFail("bioPanel anchors missing — BreathVoiceRow()/showRouting moved; re-anchor this scan (#454).")
        }
        // Caption honesty (#496): promise only channels a producer feeds today.
        let row = slice(code, from: "private struct AutoModeRow: View {", to: "\n}")
        XCTAssertFalse(row.isEmpty, "AutoModeRow slice empty — re-anchor (#454).")
        // ⛔ THE NEXT THREE CLAIMS SCANNED THE ROW'S OWN TEXT AND #648 MOVED THE CAPTION OUT
        // OF THE ROW into `BioPanelRowCopy.autoModeCaption(for:)` — so two went red on a
        // correct tree and the third (the dead-channel ban below) would have stayed GREEN over
        // text it no longer sees, which is the §4 failure this file's own comment names. All
        // three now DRIVE the pure static instead of scanning: strictly stronger, and immune to
        // the sentence moving again.
        // ⛔ AND THE FIRST REPAIR TOOK `synthetic: Bool`, WHICH IS THE #644 DEFECT RETURNING:
        // a Bool cannot say "nothing is measured yet", so the no-frame state would have had to
        // be spelled a second way somewhere else. The static takes the FRAME, like its three
        // siblings; this needle picks the real-body form because that is the sentence the
        // founder wrote.
        let caption = BioPanelRowCopy.autoModeCaption(for: Self.bodyFrame)
        XCTAssertTrue(caption.contains("coherence, HRV and heart rate"), """
            The door's caption no longer names the three channels the decision core \
            actually reads. The caption is the user's only statement of WHAT steers \
            — if the inputs changed, change the sentence and this needle together.
            """)
        // #615 — the pause is DISCOVERABLE at the door: the caption states what a
        // dial edit does and how to hand the dial back. Without this sentence the
        // #614 pause is invisible mechanics (the review's UX gap). The VISUAL
        // fine-tune deliberately has NO pause (Council 2026-08-16, decisions.csv;
        // the term contests no user-owned dial) — do not read this needle as the
        // half-built version of that.
        XCTAssertTrue(caption.contains("Auto lets that dial go"), """
            The door's caption no longer explains the gesture-pause (#614): a \
            player must be able to DISCOVER that editing a steered dial frees it \
            and that the Auto toggle hands it back. Reword freely, but keep a \
            sentence that says both, and move this needle with it.
            """)
        // ⚠️ ALL THREE render states, because #648 gave the caption two more forms and a ban
        // that only checks one of them covers a third of the renders. The nil state is the one
        // the Bio panel is in most often (before Play, before a source is chosen).
        let states: [BioSampleFrame?] = [Self.bodyFrame, Self.demoFrame, nil]
        for dead in ["trend", "valence", "emotion", "breath depth", "LF/HF"] {
            for frame in states {
                XCTAssertFalse(
                    BioPanelRowCopy.autoModeCaption(for: frame).contains(dead), """
                    The door's caption says "\(dead)" — a channel or estimate with NO \
                    producer today (#496 class). TheAlwaysOnBioPathIsNamedTests covers \
                    only the AlwaysOnBioChannel sentences, so this caption is the second \
                    surface that could over-claim; it may name a new channel only in the \
                    commit that ships its real producer.
                    """)
            }
        }
    }

    // MARK: - claim 7 (SOURCE-TEXT) — the fold owns no tempo, and exists on every config

    func testTheFoldOwnsNoTempoAndTheHoistHolds() throws {
        let studio = try source(Self.studio)
        let fold = slice(studio, from: "private func makeComposerInput", to: "\n    }")
        XCTAssertFalse(fold.isEmpty, "makeComposerInput slice empty — re-anchor (#454).")
        for needle in ["setTempo(", "glideTempo(", "transport"] {
            XCTAssertFalse(fold.contains(needle), """
                `makeComposerInput` now contains `\(needle)`. The auto fold lives \
                here, and its tempo abstinence is the T1/T2 compliance of the whole \
                feature — tempo belongs to the Flow-Servo alone. If a legitimate \
                tempo path must pass here, that is a Tempo-Invariant amendment: \
                move TempoInvariantTests, the T1 list in CLAUDE.md and this scan in \
                the same commit.
                """)
        }
        // The hoist law: ONE `var moodForInput` declaration, ABOVE the weather
        // BLEND, so the auto fold exists on every config. The parent's shape —
        // `var` inside the `#if`, `let` in the `#else` — silently drops the fold
        // where WeatherKit is absent.
        // ⛔ #408, caught by this file's own transcription before it ever ran:
        // `#if canImport(WeatherKit)` occurs TWICE in `makeComposerInput` (the
        // structure-seed weather salt sits above the blend), so the `#if` is NOT a
        // usable anchor — the ordering must pin against the unique blend gate line.
        if let decl = fold.range(of: "var moodForInput = mood"),
           let blendGate = fold.range(of: "if weatherEnabled, let wx = weatherContribution {") {
            XCTAssertTrue(decl.upperBound <= blendGate.lowerBound, """
                `var moodForInput` sits below the weather blend again. On a \
                non-WeatherKit config the auto fold then mutates a `let` (compile \
                error) or a declaration that does not exist (silent no-op) — the \
                trap the #608 review named before the first line was written.
                """)
        } else {
            XCTFail("hoist anchors missing in makeComposerInput — re-anchor this scan (#454).")
        }
        XCTAssertFalse(fold.contains("let moodForInput"), """
            A `let moodForInput` is back in `makeComposerInput` — the parent's \
            `#else` shape. One `var`, hoisted, is the whole law; a second spelling \
            reintroduces the config split.
            """)
        // The decision core keeps its structural invariants: no clock, no engine.
        let core = try source(Self.core)
        for needle in ["setTempo(", "glideTempo(", "transport", "Timer", "DispatchQueue",
                       "@Observable", "import SwiftUI", "EngineBus"] {
            XCTAssertFalse(core.contains(needle), """
                `AutoAttune.swift` now contains `\(needle)`. The file's own header \
                names this as the invariant that makes the evolve-tick cadence \
                STRUCTURAL: no timer, no bus, no view, no tempo. Growing an engine \
                here converts the guarantee into convention (#398 double-writer \
                class) — build the engine as its own doored type instead, and move \
                this scan deliberately.
                """)
        }
    }

    // MARK: - claim 8 (BEHAVIOUR) — #609: the visual half is bounded, off-identical,
    // and never touches the flash path

    private func bioFrame(coherence: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1, heartRateBPM: 70, hrvNormalized: 0.5,
                       breathRate: 0, breathPhase: 0.5, coherence: coherence,
                       motionEnergy: 0, source: .cameraPPG)
    }

    func testTheVisualHalfIsBoundedAndFlashNeutral() {
        let frames: [BioSampleFrame?] = [nil, bioFrame(coherence: 0.9),
                                         bioFrame(coherence: 0.1), bioFrame(coherence: 0.5)]
        for f in frames {
            let off = BioVisualParams.from(f)
            let on = BioVisualParams.from(f, autoAttuned: true)
            XCTAssertEqual(on.pulseHz, off.pulseHz, """
                Auto mode changed `pulseHz`. The flash-safety path (FlashGuard ≤3 Hz, \
                0 under Reduce Motion) must be byte-identical under auto — a mood \
                feature may never renegotiate the epilepsy ceiling.
                """)
            XCTAssertEqual(on.hue, off.hue, """
                Auto mode moved the hue. Tone→light physical colour is the \
                science-first promise; the auto term owns complexity/intensity ONLY.
                """)
            XCTAssertEqual(on.spread, off.spread, """
                Auto mode moved the breath spread. The inhale owns that axis; auto \
                riding it would double-drive one visual dimension from two signals.
                """)
            XCTAssertLessThanOrEqual(abs(on.complexity - off.complexity),
                                     Double(AutoAttune.maxTargetDelta) + 1e-9, """
                The visual auto term exceeds the sound half's gentleness cap on \
                complexity — `AutoAttune.maxTargetDelta` is the ONE definition (#416) \
                both halves share; a bigger visual push needs that constant moved, \
                deliberately, for both.
                """)
            XCTAssertLessThanOrEqual(abs(on.intensity - off.intensity),
                                     Double(AutoAttune.maxTargetDelta) + 1e-9, """
                The visual auto term exceeds the gentleness cap on intensity — same \
                one-definition law as the complexity bound above.
                """)
        }
        XCTAssertEqual(BioVisualParams.from(nil, autoAttuned: true),
                       BioVisualParams.from(nil), """
            An UNMEASURED body steered the visual. `coherenceForSound`'s 0.5 fallback \
            centres the auto term at exactly zero — if these differ, auto is inventing \
            a body state where none was measured (#496 class, visual edition).
            """)
        // #609b — the shared signed term itself: zero when unmeasured, capped always.
        XCTAssertEqual(BioVisualParams.autoTerm(nil, enabled: true), 0, """
            `autoTerm` steers on an unmeasured body. Its zero-at-0.5 centring is the \
            mechanism every other identity claim in this test rests on.
            """)
        XCTAssertLessThanOrEqual(abs(BioVisualParams.autoTerm(bioFrame(coherence: 0.9),
                                                              enabled: true)),
                                 Double(AutoAttune.maxTargetDelta) + 1e-9, """
            `autoTerm` exceeds the gentleness cap. It is the ONE definition both the \
            field mapping and the renderer's look products consume — a bigger term \
            moves BOTH halves at once, which is exactly why it must stay capped here.
            """)
        // Direction: a clearly settled body calms the figure and fills it slightly.
        let calmOn = BioVisualParams.from(bioFrame(coherence: 0.9), autoAttuned: true)
        let calmOff = BioVisualParams.from(bioFrame(coherence: 0.9))
        XCTAssertLessThan(calmOn.complexity, calmOff.complexity, """
            A settled body no longer CALMS the figure (complexity did not drop). The \
            visual half's whole claim is "the environment matches the vibe" — settled \
            must read calmer, not busier.
            """)
        XCTAssertGreaterThanOrEqual(calmOn.intensity, calmOff.intensity, """
            A settled body dimmed the picture. The settled pole fills slightly \
            (+0.5·auto); dimming would read as the app disapproving of calm.
            """)
    }

    // MARK: - claim 9 (SOURCE-TEXT) — the flag reaches the renderer from all three hosts

    func testTheVisualFlagIsThreadedNotObserved() throws {
        let metal = try source("Sources/Echoelmusic/Views/MetalBioView.swift")
        XCTAssertTrue(metal.contains("autoAttuned: lookAutoAttuned"), """
            The renderer no longer hands the auto flag to `BioVisualParams.from`. The \
            field mapping then loses its flag while the look products below may still \
            carry theirs — the two halves of one definition drifting apart.
            """)
        // ⛔ #609b — THE CONSUMER, the assertion the first #609 version lacked. The
        // shipped shader reads `vp.pulseHz` ONLY (TheVoiceTintsTheVisualTests
        // documents it at this very call site), so writing vp fields alone is
        // wired-but-dead: the review found the whole visual half changed no pixel.
        // These three needles pin the LIVE path — the term entering the look
        // products the shader actually consumes.
        XCTAssertTrue(metal.contains("BioVisualParams.autoTerm(bio, enabled: lookAutoAttuned)"), """
            The renderer no longer computes the shared auto term. Without it the \
            look-product folds below have no input and the visual half is dead again \
            — the exact wired-but-dead trap the #609 review caught.
            """)
        XCTAssertTrue(metal.contains("* (1 + 0.5 * autoTerm)"), """
            The intensity look-product no longer folds the auto term. The settled \
            body's "fills slightly" half of the visual claim is then a no-op — the \
            shader reads THIS product, not `vp.intensity`.
            """)
        XCTAssertTrue(metal.contains("* (1 - 0.5 * autoTerm)"), """
            The ring-density look-product no longer folds the auto term. The settled \
            body's "calms the figure" half of the visual claim is then a no-op — the \
            shader reads THIS product, not `vp.complexity`.
            """)
        for (host, needle) in [
            ("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift", "autoAttuned: autoMode"),
            ("Sources/Echoelmusic/Studio/ExternalDisplayScene.swift", "autoAttuned: autoMode"),
            // #609b (review finding 3): the third host. It was pinned while UNREACHABLE
            // (#270, `showVisual` had no true-writer) so the flag could not silently rot out
            // of the copy that would wake up with a door. #747 built that door, so this host
            // is live and the pin is now an ordinary one — the foresight paid off rather than
            // expiring.
            ("Sources/Echoelmusic/Studio/EchoelStudioView.swift", "autoAttuned: autoMode"),
        ] {
            let code = try source(host)
            XCTAssertTrue(code.contains(needle), """
                \(host) no longer passes `autoAttuned: autoMode` into `MetalBioView`. \
                For the floating window that kills the feature; for the beamer scene it \
                means plugging in a projector silently strips the Auto look mid-show — \
                every instance must draw the same picture.
                """)
        }
    }

    // MARK: - claim 10 (SOURCE-TEXT) — #614: the user gesture wins, and only the
    // Auto toggle un-pauses

    func testTheUserGestureWinsWiring() throws {
        let studio = try source(Self.studio)
        // (a) EXACTLY the three steered dials carry `pausing:`. Each needle once —
        // and three total, so a fourth dial adopting the parameter (which nothing
        // in the decision core would read) turns this red before it ships as a
        // silently dead pause.
        for needle in ["pausing: \\.pausedLiveliness",
                       "pausing: \\.pausedDarkness",
                       "pausing: \\.pausedTension"] {
            XCTAssertEqual(studio.components(separatedBy: needle).count - 1, 1, """
                `\(needle)` no longer appears exactly once in EchoelStudioView. The \
                three STEERED mood dials each wire their own session pause — if a \
                dial was renamed or the wiring moved, move this needle in the same \
                commit; if a dial stopped being steered, its `pausing:` goes WITH \
                the steering (a pause nothing reads is the #135-class lying wire).
                """)
        }
        XCTAssertEqual(studio.components(separatedBy: "pausing: \\.").count - 1, 3, """
            The `pausing:` parameter is passed at a different number of call sites \
            than the three dials `AutoAttune` steers. A new steered parameter adds \
            its flag to `AutoAttune.State`, its steer-side pin, its `pausing:` call \
            site AND this count together — any subset is a half-wired gesture law.
            """)
        // (b) the write is gated: Auto ON, not already paused — an edit while Auto
        // is OFF must not leave a stale exemption behind.
        let knob = slice(studio, from: "private func moodKnob", to: "\n    }")
        XCTAssertFalse(knob.isEmpty, "moodKnob slice empty — re-anchor (#454).")
        XCTAssertEqual(knob.components(separatedBy:
            "if let pause, autoMode, !autoAttuneState[keyPath: pause] {").count - 1, 1, """
            The pause write in `moodKnob` lost its gate (Auto ON + not already \
            paused). Ungated, a mood edit while Auto is OFF writes a pause that \
            silently exempts the dial when Auto is later invited — the stale-consent \
            shape. If the gate was legitimately reshaped, move this needle with it.
            """)
        // (c) ordering INSIDE the knob body: pause first, recompose second — the
        // debounced regenerate this gesture schedules must already read the paused
        // registry. Both anchors asserted unique in the slice (#408).
        let write = "autoAttuneState[keyPath: pause] = true"
        XCTAssertEqual(knob.components(separatedBy: write).count - 1, 1,
                       "pause-write anchor not unique in moodKnob — re-anchor (#408).")
        XCTAssertEqual(knob.components(separatedBy: "recomposeIfRunning()").count - 1, 1,
                       "recompose anchor not unique in moodKnob — re-anchor (#408).")
        if let w = knob.range(of: write), let r = knob.range(of: "recomposeIfRunning()") {
            XCTAssertTrue(w.upperBound <= r.lowerBound, """
                `moodKnob` recomposes BEFORE registering the pause. The regenerate \
                scheduled by this very gesture then steers the take the user just \
                claimed — the first un-steered take arrives one edit late.
                """)
        }
        // (d) the ONE un-pause gesture: the Auto toggle going OFF resets the whole
        // state — and it is the ONLY writer of a fresh State() outside the
        // declaration (a second reset site would be a second lifecycle owner, the
        // BLE-3 class).
        XCTAssertEqual(studio.components(separatedBy: ".onChange(of: autoMode)").count - 1, 1, """
            `.onChange(of: autoMode)` no longer appears exactly once. Zero means \
            turning Auto off leaks the steering state and the session pauses into \
            the next opt-in (the only reset left is an app relaunch, which no user \
            can discover); two means two lifecycle owners for one @State.
            """)
        let reset = slice(studio, from: ".onChange(of: autoMode)", to: "\n        }")
        XCTAssertTrue(reset.contains("autoAttuneState = AutoAttune.State()"), """
            The Auto-toggle handler no longer resets `autoAttuneState`. The toggle \
            is the ONE sanctioned un-pause gesture ("nothing comes back unbidden, \
            but an explicit toggle is fresh consent") — without the reset, a paused \
            dial stays exempt for the whole app run with no visible reason.
            """)
        // ⛔ #408, caught by this slice's own transcription before first run: the
        // @State DECLARATION (`@State private var autoAttuneState = AutoAttune.State()`)
        // CONTAINS this needle, so the honest count is TWO — declaration initializer
        // + toggle reset. A first draft asserted 1 and was red on its own tree.
        XCTAssertEqual(studio.components(separatedBy:
            "autoAttuneState = AutoAttune.State()").count - 1, 2, """
            `autoAttuneState = AutoAttune.State()` no longer appears exactly twice \
            (the @State declaration's initializer + the toggle-off reset). A THIRD \
            site is a competing lifecycle owner (the BLE-3 class); one means the \
            reset or the declaration changed shape — re-anchor deliberately.
            """)
        // (e) three breadcrumbs, all on the automation category: pause / evolve
        // decision / toggle-off. The count is the honest inventory — a fourth log
        // site (or a lost one) changes what a device log can prove about Auto.
        XCTAssertEqual(studio.components(separatedBy: "Auto attune:").count - 1, 3, """
            The "Auto attune:" breadcrumb count changed. Three are the contract — \
            dial paused / evolve decision / toggle-off reset — and the device-log \
            triage of the open 2519 audibility probe reads exactly these lines. \
            Add or remove one deliberately, with this count and the SESSION_LOG \
            probe note in the same commit.
            """)
        XCTAssertEqual(studio.components(separatedBy: "category: .automation").count - 1, 3, """
            The Auto breadcrumbs left the `.automation` log category (or a stranger \
            joined it). One category is what makes the triage grep-able — \
            `log show --predicate` on one subsystem/category, not a scavenger hunt.
            """)
        // (f) the evolve breadcrumb sits INSIDE the advanceEvolution gate, BEFORE
        // the state write — the audition path stays silent, and the line describes
        // the state that is about to be committed. The multi-line gate spelling is
        // unique (#408: the one-line `if advanceEvolution { evolution &+= 1 }` and
        // the `, let f = frame` variant do not match it).
        let fold = slice(studio, from: "private func makeComposerInput", to: "\n    }")
        XCTAssertFalse(fold.isEmpty, "makeComposerInput slice empty — re-anchor (#454).")
        XCTAssertEqual(fold.components(separatedBy: "if advanceEvolution {\n").count - 1, 1,
                       "multi-line advanceEvolution gate not unique in the fold — re-anchor (#408).")
        let gated = slice(fold, from: "if advanceEvolution {\n", to: "\n            }")
        XCTAssertFalse(gated.isEmpty, "gated evolve block empty — re-anchor (#454).")
        XCTAssertEqual(gated.components(separatedBy: "Auto attune: %@").count - 1, 1, """
            The evolve-decision breadcrumb left the `advanceEvolution` gate (or \
            duplicated). Outside the gate it would narrate maze AUDITIONS — takes \
            nobody kept — and the device log would show phantom Auto decisions.
            """)
        XCTAssertEqual(gated.components(separatedBy: "autoAttuneState = nextState").count - 1, 1, """
            The state commit left the gated evolve block. #608b's whole point is \
            that ONLY a real take ages the hold counters — an ungated write lets a \
            dial twiddle satisfy a hold specified as a full evolve tick.
            """)
        if let l = gated.range(of: "Auto attune: %@"),
           let s = gated.range(of: "autoAttuneState = nextState") {
            XCTAssertTrue(l.upperBound <= s.lowerBound, """
                The evolve breadcrumb logs AFTER the state write. It must describe \
                the state being committed, and reordering usually means the log \
                moved out of the decision path — re-judge, then move this scan.
                """)
        }
    }

    // MARK: - claim 11 (BEHAVIOUR) — a fully paused state is the exact identity
    // even inside an active policy (green on both trees: the registry and the
    // steer-side pins shipped with slice 1 — this is the counterweight that makes
    // claim 10's wiring mean something)

    func testAFullyPausedStateIsTheIdentityInAnActivePolicy() {
        var s = AutoAttune.State(policy: .settled, ticksInPolicy: 3)
        s.pausedDarkness = true
        s.pausedLiveliness = true
        s.pausedTension = true
        let (steer, _) = AutoAttune.decide(calm: 0.95, arousal: 0.05,
                                           baseDarkness: 0.3, baseLiveliness: 0.7,
                                           baseTension: 0.4, previous: s)
        XCTAssertEqual(steer.darknessTarget, 0.3, """
            A session-paused darkness got a moved target inside an active settled \
            policy. The pause is the user's edit outranking the machine — its \
            target must equal its base whatever the policy wants.
            """)
        XCTAssertEqual(steer.livelinessTarget, 0.7, """
            A session-paused liveliness got a moved target — same law as darkness: \
            paused means base, means identity through the blend.
            """)
        XCTAssertEqual(steer.tensionTarget, 0.4, """
            A session-paused tension got a moved target — same law as darkness.
            """)
        // And through the shared mixer: byte-identity, not merely "close".
        XCTAssertEqual(WeatherMood.blend(base: 0.3, target: steer.darknessTarget,
                                         intensity: steer.intensity), 0.3, """
            The blend moved a fully paused dial. base == target must be the exact \
            identity at ANY intensity — if this drifts, "paused" quietly becomes \
            "steered a little", which is the one thing the promise forbids.
            """)
    }

    // MARK: - helpers (§0/§2 — the ONE stripper, skip on no tree, FAIL on moved anchors)

    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    // MARK: - #648 fixtures

    /// A real-body frame — the caption form carrying the founder's own wording.
    private static let bodyFrame = BioSampleFrame(
        timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4, breathRate: 12,
        breathPhase: 0.25, coherence: 0.7, motionEnergy: 0, source: .cameraPPG)

    /// The same reading stamped `.fallback` — the demo generator, not a body.
    private static let demoFrame = BioSampleFrame(
        timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4, breathRate: 12,
        breathPhase: 0.25, coherence: 0.7, motionEnergy: 0, source: .fallback)
}
