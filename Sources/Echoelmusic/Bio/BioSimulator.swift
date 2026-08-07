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
//  explicitly enables it (or, in DEBUG, auto-on for development). It defers to
//  any real bio publisher already on the bus.
//
//  ⛔ THIS BLOCK USED TO CLAIM "the bio strip always labels it 'Demo'". THAT IS
//  FALSE, and it was false seventy lines above a comment block asserting honesty.
//  There is no user-facing "Demo" string anywhere in `Sources/` — the two hits are
//  both doc comments (this file and `EchoelmusicApp`). What the strip actually does:
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
            // Synthetic but plausible HRV metrics for the labeled Demo source so
            // the precise readouts have believable values to show.
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
            // version of this block said "the three LIVE sources" and "EVERY real source":
            // there are FOUR producers, and one of them only passes trivially. The conclusion
            // survived the miscount; the enumeration did not, and an enumeration is exactly
            // what a later session greps.
            //
            // The demo published a pair no converter in this app can reconcile: at
            // `hrvNormalized` 0.5 it shipped 60 ms, while the house rule says 60 ms IS 0.60.
            // Measured, each number carrying its setup (#448): a flat **+20 % relative** over
            // 0.2…5/6, worst absolute **1/6 ≈ 0.16667 (analytic supremum, at h = 5/6)** — the
            // 701-point sweep in the guard never lands on 5/6 and reaches **0.16660**. Above
            // 5/6 the relative error falls to +11 %, which looks like improvement and is really
            // `normalize` clamping. ⛔ "several consumers do" stood here and is CUT: there are
            // exactly three `HRVNormalization.normalize` call sites in `Sources/` and all three
            // are PUBLISHERS. No in-app consumer recomputes the knob — the two readers of
            // `hrvRMSSDms` (`BioStripView`, `OSCSender`) read it directly. The defensible claim
            // is about an EXTERNAL OSC receiver, which is hypothetical; inventing a supporting
            // fact inside the sentence that carries the severity argument is the class this
            // repo retracts everywhere else.
            //
            // The anchor is RMSSD, not SDNN, because that is the RR-source convention and the
            // demo imitates an RR source (it publishes RMSSD and pNN50, which only an RR
            // source has).
            hrvRMSSDms: hrvNormalized * Float(HRVNormalization.ceilingMs),
            // ⚠️ SDNN AND pNN50 DELIBERATELY DO **NOT** ROUND-TRIP, and the symmetrical-looking
            // tidy-up is the trap. On the camera and the strap `normalize(hrvSDNNms)` does not
            // equal `hrvNormalized` either — the knob is anchored on RMSSD there too — so
            // giving SDNN the same ceiling would not be consistency, it would make demo SDNN
            // EXACTLY equal to demo RMSSD, a pair no body produces and one that makes the demo
            // useless for a receiver plotting the two against each other. pNN50 is a percentage
            // and no source ties it to the knob at all.
            //
            // ⚠️ WHAT IS STILL WRONG HERE AND IS **NOT** FIXED, named rather than left for the
            // next reader: 90 < 100, so the demo publishes SDNN BELOW RMSSD at every point,
            // while at rest the relationship runs the other way. Attribution, corrected —
            // the first version cited the wrong table: Task Force 1996's headline normative
            // pair (SDNN 141±39 ms, RMSSD 27±12 ms) is from **24-hour** recordings; the
            // short-term figure in that same document is the **SDNN index** (mean of the
            // 5-minute SDNNs), 54±15 ms, against RMSSD 27±12 ms. Short-term resting studies
            // put the two closer (order 50 vs 40 ms). The DIRECTION is robust across all of
            // them; the ratio is not, and only the direction is needed here.
            //
            // ⛔ AND THE REASON THIS SLICE LEAVES IT ALONE WAS SELF-UNDERMINING AS FIRST
            // WRITTEN. It said changing `* 90` "means choosing a ratio, i.e. inventing
            // physiology to make a demo prettier". But `* 90` IS a chosen ratio — invented by
            // nobody-knows-who, never derived anywhere, and inverted against every reference
            // above. Refusing to move a fabricated constant on the grounds that moving it
            // would fabricate treats the incumbent as evidence-free-neutral when it is exactly
            // as invented as any replacement, and the evidence the decision supposedly lacks
            // is cited two lines up. The honest statement is narrower: **the incumbent is also
            // invented and it is inverted; replacing it is cheap and the evidence is above,
            // but it changes shipped output and belongs in its own slice.** Keeping this fix
            // to arithmetic is scope discipline, not an evidentiary verdict — do not read it
            // as "there is no evidence" and leave the inverted pair standing forever.
            hrvSDNNms: hrvNormalized * 90,
            hrvPNN50: hrvNormalized * 40
        )
    }

    private func clamp(_ x: Float, in range: ClosedRange<Float>) -> Float {
        min(max(x, range.lowerBound), range.upperBound)
    }
}
