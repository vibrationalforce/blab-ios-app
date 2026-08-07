//
//  BioSimulator.swift
//  Echoelmusic
//
//  Explicit, user-initiated DEMO bio source. Publishes a slowly-walking
//  BioSampleFrame onto EngineBus once per second so the instrument is
//  playable without paired hardware (Oura, HealthKit, BLE) — essential
//  for evaluating the bio-reactive synth, modulation matrix, and OSC out
//  on a device that has no sensor connected.
//
//  Honesty: the frame's source is `.fallback`, and it only runs when the user
//  explicitly enables it. It defers to any real bio publisher already on the bus.
//
//  ⛔ "(or, in DEBUG, auto-on for development)" STOOD HERE AND WAS FALSE — found by two
//  independent #464 reviewers, verified: `start(publishing:)` has exactly ONE call site in
//  `Sources/`, `EchoelStudioView`'s `case .sim:` in the pulse-pill source picker, with no
//  `#if DEBUG` anywhere near it (`git grep -n "demoSource\." -- Sources` → start + stop, two
//  hits). Nothing auto-starts it. The claim mattered because it read as "this is a dev-only
//  toy", which is exactly the sentence that stops a session from asking whether a SHIPPED,
//  user-selectable source is marked as synthetic on the wire (#462). The same falsehood was
//  published on `docs/architecture.html` ("in DEBUG builds only") and is struck there too —
//  striking a word in one place is not striking it.
//
//  ⛔ THIS BLOCK USED TO CLAIM "the bio strip always labels it 'Demo'". THAT IS
//  FALSE, and it was false seventy lines above a comment block asserting honesty.
//  There is no user-facing "Demo" string anywhere in `Sources/` — every hit is a
//  comment. (⛔ The first version of this retraction said "the two hits", counted from
//  a grep run BEFORE it added three more of its own. `git grep -nw Demo -- Sources`
//  is the check; the count is not worth restating, the property is.) The strip:
//  `BioStripView.sourceLabel(.fallback)` returns "—" and `sourceText` returns
//  "No signal" for `.fallback`, while `hrString`/`hrvString` render `bus.latestBio`
//  with NO source filter. So a demo session shows a confident heart rate and
//  "HRV 50 ms" beside a source cell reading "No signal" — which reads as ABSENCE,
//  not as SYNTHETIC. #215's principle ("a constant 0 is indistinguishable from a
//  still performer") applies on the screen too, not only on the wire. Whether to
//  add a Demo label on the strip and a synthetic marker on the OSC egress is a
//  founder question (#462), not something to decide inside an arithmetic fix — but
//  the claim that it is ALREADY flagged had to go, because it is the sentence that
//  stops the next session from looking.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class BioSimulator {

    /// Resting **SDNN / RMSSD** ratio, used to derive the Demo source's SDNN from the RMSSD it
    /// publishes so the pair keeps the direction a resting body actually shows (SDNN above RMSSD).
    ///
    /// ⛔ THIS REPLACES A BARE `* 90` (#464). That constant was derived nowhere and was
    /// **inverted**: 90 sits below the 100 ms house ceiling, so the demo published SDNN BELOW
    /// RMSSD at every point of its walk band, while every resting reference runs the other way.
    /// The previous slice (#461) left it standing on a reason that undermined itself — "changing
    /// it means choosing a ratio, i.e. inventing physiology" — while the incumbent WAS a chosen
    /// ratio, and an inverted one. Replacing an invented, inverted number with a cited,
    /// direction-correct one is not a new invention; it is the smaller of two fictions, and it is
    /// labelled as fiction here rather than dressed up as a measurement.
    ///
    /// ⚠️ WHY 1.25, AND WHAT IT IS AND IS NOT SOURCED ON. The DIRECTION is robust across every
    /// normative set, and it has a structural reason: SDNN is a spread over the whole NN series
    /// and absorbs slow components, RMSSD reads only successive differences. The RATIO is not
    /// robust, and 1.25 is a CHOSEN round number inside a bracket, not a cited figure.
    ///
    /// ⛔ THE FIRST VERSION CALLED IT "the smallest separation any of the cited work supports"
    /// AND THAT OVERSTATED THE SOURCING TWICE, in the sentence that defines the constant — both
    /// #464 reviewers flagged it independently. (a) Exactly ONE end of the bracket is actually
    /// attributed: Task Force 1996's **SDNN index** (mean of the 5-minute SDNNs computed WITHIN a
    /// 24-hour recording), 54±15 ms against RMSSD 27±12 ms, ≈2.0. ⚠️ The qualifier in bold is the
    /// one #461 had already restored eighty lines below and this doc dropped — and THIS is the
    /// line a future session reads. (b) The low end was written here as "short-term resting
    /// studies, order 50 vs 40 ms" with NO study, year or table named. A reviewer puts the usual
    /// short-term norm (Nunan/Sandercock/Brodie 2010) at SDNN 50 / RMSSD 42, i.e. ≈1.19 — which
    /// would make 1.25 sit slightly ABOVE the low end rather than on it. **Not verified here:**
    /// the egress proxy blocks the journals, so that figure is second-hand and is recorded as a
    /// reason to stop calling 1.25 "cited", not as a citation to lean on.
    ///
    /// The defensible statement is the narrow one: 1.25 is near the bottom of a 1.2…2.0 bracket,
    /// chosen low because a demo must not overstate a spread nobody measured. A plausible resting
    /// pair, not a claim about any person, and not a measurement.
    ///
    /// ⚠️ IT MUST STAY > 1, and that is the one property a guard can actually defend:
    /// `TheDemoSourceAgreesWithItsOwnKnobTests` asserts it, because a ratio of exactly 1 makes
    /// demo SDNN bit-identical to demo RMSSD — a pair no body produces, and one that makes the
    /// Demo source useless to a receiver plotting the two against each other.
    ///
    /// ⚠️ NOT a resurrection of the retired `* 120`: that was a divisor on RMSSD contradicting the
    /// house ceiling (#461). This is a multiplier on a DIFFERENT field, derived FROM that ceiling,
    /// and it happens to land on 125 ms — numeric neighbourhood, not restoration.
    nonisolated static let restingSDNNOverRMSSD: Double = 1.25

    public private(set) var isRunning = false

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var heartRateBPM: Float = 72

    @ObservationIgnored
    private var hrvNormalized: Float = 0.5

    @ObservationIgnored
    private var breathPhase: Float = 0

    @ObservationIgnored
    private var coherence: Float = 0.6

    public init() {}

    /// Begin publishing one frame per second to the given bus.
    /// No-op if already running.
    public func start(publishing bus: EngineBus) {
        guard !isRunning else { return }
        isRunning = true
        task = Task { @MainActor [weak self, weak bus] in
            while !Task.isCancelled {
                guard let self, let bus else { break }
                // Defer to any real bio publisher already on the bus.
                if let latest = bus.latestBio, latest.source != .fallback {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                bus.publish(bio: self.nextFrame())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func nextFrame() -> BioSampleFrame {
        heartRateBPM = clamp(heartRateBPM + Float.random(in: -1.5...1.5), in: 58...92)
        hrvNormalized = clamp(hrvNormalized + Float.random(in: -0.02...0.02), in: 0.2...0.9)
        // 12 bpm ≈ phase += 0.2 per second
        breathPhase = (breathPhase + 0.2).truncatingRemainder(dividingBy: 1.0)
        coherence = clamp(coherence + Float.random(in: -0.03...0.03), in: 0.2...0.9)

        return BioSampleFrame(
            timestamp: CFAbsoluteTimeGetCurrent(),
            heartRateBPM: heartRateBPM,
            hrvNormalized: hrvNormalized,
            breathRate: 12,
            breathPhase: breathPhase,
            coherence: coherence,
            motionEnergy: 0,
            source: .fallback,
            // Synthetic but plausible HRV metrics for the Demo source so the precise
            // readouts have believable values to show. (⛔ "the labeled Demo source"
            // until the #461 reviewer pass — the retraction 85 lines above was written
            // and this restatement of the retracted claim was left standing in the SAME
            // file. Second place, every time.)
            //
            // ⛔ RMSSD USED TO BE `hrvNormalized * 120`, AND THAT IS THE COPY-DRIFT DEFECT
            // #97 ALREADY FIXED — surviving here because #97 audited the LIVE sources and
            // nobody looked at the demo. `HRVNormalization` exists to be the ONE ceiling
            // ("was ÷200 on the camera, ÷100 on the strap, ÷100 on HealthKit"), and this file
            // quietly carried a fourth divisor.
            //
            // Why it is a real inconsistency and not just an arbitrary constant: every producer
            // of a `BioSampleFrame` satisfies `hrvNormalized == HRVNormalization.normalize(
            // <that source's ms metric>)` to representation — camera (`hrvNormalized =
            // normalize(analyzer.rmssd)`, `hrvRMSSDms = analyzer.rmssd`), Polar (same two
            // lines), HealthKit (against SDNN, since it has no beat-to-beat RR), and
            // `FaceExpressionBioPublisher`, which satisfies it VACUOUSLY (it publishes
            // `hrvNormalized: 0` and no ms metric at all — `normalize(0) == 0`). ⛔ The first
            // version of this block said "the three LIVE sources" and "EVERY real source";
            // the second said "there are FOUR producers" and was off by one in the sentence
            // fixing an enumeration. `git grep -n "BioSampleFrame(" -- Sources` finds SIX
            // construction sites across FIVE producer types — the four named above plus THIS
            // file, and the camera builds one twice (the dropout hold-repeat copies the held
            // frame's fields, so it preserves the invariant rather than deriving it). One of
            // the four passes only trivially. The conclusion survived both miscounts; the
            // enumeration did not, twice — and an enumeration is exactly what a later session
            // greps, which is why the command is written next to it now.
            //
            // The demo published a pair no converter in this app can reconcile: at
            // `hrvNormalized` 0.5 it shipped 60 ms, while the house rule says 60 ms IS 0.60.
            // Measured, each number carrying its setup (#448): a flat **+20 % relative** over
            // 0.2…5/6, worst absolute **1/6 ≈ 0.16667 (analytic supremum, at h = 5/6)** — the
            // 701-point sweep in the guard never lands on 5/6 and reaches **0.16660**. Above
            // 5/6 the relative error falls to +11 %, which looks like improvement and is really
            // `normalize` clamping. ⛔ "several consumers do" stood here and is CUT: there are
            // exactly three `HRVNormalization.normalize` call sites in `Sources/`, and all three
            // are on the PRODUCTION side — two publishers plus `EchoelBioEngine`, which writes
            // the snapshot `HealthKitBioPublisher` later publishes. ("all three are PUBLISHERS"
            // was the loose second version; the load-bearing part is that none of them recomputes
            // the knob from a wire value.) No in-app consumer recomputes it: the two CONSUMERS of
            // `hrvRMSSDms` (`BioStripView`'s readout, `OSCSender`'s egress) read it directly, and
            // the only other read in `Sources/` is the camera's dropout hold-repeat carrying
            // `held.hrvRMSSDms` forward — a carry, not a consumer. The defensible claim is about
            // an EXTERNAL OSC receiver, which is hypothetical; inventing a supporting fact inside
            // the sentence that carries the severity argument is the class this repo retracts
            // everywhere else.
            //
            // The anchor is RMSSD, not SDNN, because that is the RR-source convention and the
            // demo imitates an RR source (it publishes RMSSD and pNN50, which only an RR
            // source has).
            hrvRMSSDms: hrvNormalized * Float(HRVNormalization.ceilingMs),
            // ⚠️ SDNN AND pNN50 DELIBERATELY DO **NOT** ROUND-TRIP, and the symmetrical-looking
            // tidy-up is still the trap it always was — #464 did not soften it. On the camera and
            // the strap `normalize(hrvSDNNms)` does not equal `hrvNormalized` either (the knob is
            // anchored on RMSSD there too), so dropping the ratio and letting SDNN take the
            // ceiling NEAT would not be consistency: it would make demo SDNN bit-identical to
            // demo RMSSD, a pair no body produces and one that makes the demo useless to a
            // receiver plotting the two against each other. Read the line below as
            // "ceiling TIMES A RATIO" — the ratio is the whole point, and `> 1` is asserted in
            // `TheDemoSourceAgreesWithItsOwnKnobTests`. With 1.25 the round trip stays broken by
            // construction: `normalize(1.25·h)` is `1.25·h` below the clamp and `1.0` above it,
            // and neither equals `h` anywhere in the 0.2…0.9 walk band. pNN50 is a percentage and
            // no source ties it to the knob at all.
            //
            // ⭐ THE INVERSION IS FIXED (#464) — it was registered here as "still wrong and NOT
            // fixed", and that entry was the whole point of writing it down. `* 90` sat BELOW the
            // 100 ms ceiling, so the demo shipped SDNN under RMSSD at every point of the walk
            // band while every resting reference runs the other way. Attribution, corrected in
            // #461 and kept: Task Force 1996's headline pair (SDNN 141±39 ms, RMSSD 27±12 ms) is
            // from **24-hour** recordings; the short-term figure in that same document is the
            // **SDNN index** (mean of the 5-minute SDNNs), 54±15 ms against RMSSD 27±12 ms
            // (≈2.0), and short-term resting studies put the pair closer, order 50 vs 40 ms
            // (≈1.25). The DIRECTION is robust across all of them; the RATIO is not — see
            // `restingSDNNOverRMSSD` for why the conservative end is the one taken.
            //
            // ⚠️ WHY IT IS A SEPARATE SLICE FROM #461 AND NOT A CARRY-ALONG: #461 was pure
            // arithmetic consistency (a number that contradicted its own knob). This CHANGES
            // SHIPPED OUTPUT — `OSCSender` puts it on `/echoelmusic/bio/heart/sdnn` for a
            // foreign console, in Release, from a user-selectable source (`BioEgressPolicy`
            // admits `.fallback`). Measured before writing: the published band moves
            // 18…81 ms → 25…112.5 ms, and the OSC gate is `hrvSDNNms > 0`, which 25 clears as
            // surely as 18 did. Nothing downstream compares the two metrics, so the only
            // observable change is that the pair now points the right way.
            //
            // ⛔ AND THE FIRST VERSION OF THAT SENTENCE NAMED A SURFACE THAT DOES NOT SHOW THIS
            // NUMBER. It said "the value `BioStripView` renders and `OSCSender` puts on …", and
            // added "both ends still inside `BioStripView`'s 3…300 plausibility window". Neither
            // holds: `git grep -n hrvSDNNms -- Sources/Echoelmusic/Studio` returns NOTHING, the
            // strip's "HRV" cell IS RMSSD (`hrvString` reads `hrvRMSSDms`, and `plausibleHRVms`
            // is applied to that field only), and `BioMetricInfo` says so out loud — SDNN is a
            // sub-measure of the HRV cell, never a cell of its own. **There is NO plausibility
            // window on `hrvSDNNms` anywhere in `Sources/`**; the only gate the value ever meets
            // is the `> 0` sentinel above. The reassurance was therefore empty, and it was empty
            // in FIVE artifacts at once (here, the guard, the commit body, CLAUDE.md,
            // decisions.csv).
            //
            // ⭐ The lesson is sharper than the usual stale-number one, because the CORRECT
            // sentence was already in this file: forty lines up, "the two CONSUMERS of
            // `hrvRMSSDms` (`BioStripView`'s readout, `OSCSender`'s egress)" — true, about
            // RMSSD. The new sentence reused its SHAPE for a different field and kept the
            // consumer list. **A sentence copied from a neighbouring, true sentence inherits its
            // credibility and not its subject**; the field it talks about has to be re-checked
            // even when — especially when — the prose beside it is already right.
            hrvSDNNms: hrvNormalized * Float(HRVNormalization.ceilingMs * Self.restingSDNNOverRMSSD),
            hrvPNN50: hrvNormalized * 40
        )
    }

    private func clamp(_ x: Float, in range: ClosedRange<Float>) -> Float {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
