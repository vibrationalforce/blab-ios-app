#if canImport(SwiftUI)
import SwiftUI

// MasterLoudnessGrid.swift
// Echoel — the live EBU R128 loudness numbers (short-term + gated-integrated LUFS, max
// true-peak in dBTP, loudness range in LU), computed on the master tap in `AudioEngine`.
// Kept in its own view so the 60 Hz meter refresh re-renders only this small grid, not
// the whole studio. Science-first: the legible number leads, the unit follows.
//
// ⭐ READ THIS FIRST — THE DEFECT THE REST OF THIS HEADER DESCRIBES IS FIXED (#316b,
// 2026-08-01). The tap now sits on `AutoMixChain.chainOutputNode` (the limiter's output),
// the four values are published as `masterOutput…` and carry `AudioEngine.outputTrimDb`
// for the one gain still downstream. The two LEVEL BARS are the exception and stay
// pre-chain on purpose — `masterLevel` is the auto-gain's input, see the ⭐ note at the bars.
//
// Everything below is the HISTORY of how the readout came to be honest. Read the tenses as
// past tense; the property names it cites are the OLD ones. Kept because a header that
// deleted its own diagnosis would leave the next reader unable to check it — NOT because it
// still justifies the verdict colours. It cannot: both of its arguments against a verdict
// (the auto-gain reads the same signal, the true peak is read before the limiter) rest on
// the pre-chain premise #316b removed. The colours stay off because turning them back on is
// a decision nobody has taken, which is a weaker and more honest reason. Two paragraphs
// below carry a `→` correction inline where a live INSTRUCTION, not just a tense, went stale.
//
// ⛔ THIS HEADER SAID "of the master OUTPUT" UNTIL 2026-08-01 (#316), AND THAT WAS FALSE
// AT THE TIME. The numbers were then measured at the master chain's INPUT:
// `AudioEngine.installMeterTap()` tapped `masterMixer` bus 0, precisely the node
// `AutoMixChain.insert` takes as its `from:` — so everything the chain does happened
// AFTER the measurement:
//
//     masterMixer ──[tap: these numbers]──▶ EQ ▶ auto-gain ▶ PeakLimiter ▶ mainMixerNode
//                                                                          (×0.89 ≈ −1 dB)
//
// The number itself is still worth showing — it is the loudness of the mix you are making,
// which is exactly what you act on when you move a fader. What it is NOT is the loudness
// of the file/stream that leaves the device. A comment claiming otherwise is how a session
// (or a founder tuning voice levels) ends up trusting a meter to answer a question it is
// pointed away from.

// ⛔ THE TARGET VERDICT COLOURS WERE REMOVED HERE, and the removal is the point of #316 —
// not the wording above. `integratedColor` switched on `LoudnessTarget.compliance`, and
// `truePeakColor` on `LoudnessTarget.truePeakExceeds`; both are pure and correct, and both
// were being fed the pre-chain signal. That makes the colour a verdict about the master
// OUTPUT computed from the chain's INPUT, which is wrong in a SYSTEMATIC direction — the
// worst kind, because a systematic error reads as a stable, trustworthy indication:
//
// · INTEGRATED. `AutoMixChain.connectMeter` feeds its auto-gain from `masterLevel`, i.e.
//   the SAME pre-chain tap, and `steadyGainDB` drives `gain ≈ target − reading` (clamped
//   ±6 dB). So the verdict reports precisely the deviation the chain is about to REMOVE.
//   Target −14, raw mix −20: painted `dim` ("too quiet") while the auto-gain adds +6 and
//   the output lands at ≈ −15. Raw mix −8: painted `danger` ("too loud") while the gain
//   cuts 6 and the output lands at ≈ −15 again. Inside that ±6 dB window the colour raises
//   an alarm exactly where the output has no deviation at all.
//   (I first wrote "anti-correlated" here. That overstates it — the sign of the RAW mix's
//   deviation is reported correctly; what is wrong is that the raw mix is not the thing the
//   target describes. The defect is a category error, not an inverted sign, and the weaker
//   claim is the true one.) With "No target" chosen the compliance was already `.unknown`
//   and the auto-gain already inert, so this only ever misfired with a target set — which
//   is every fresh install, `.streaming` being the default.
//   ⛔ AND THE SENTENCE THAT USED TO FOLLOW — "outside it, where the gain saturates, the
//   colour understates by up to 6 dB" — was wrong three ways, all caught in review: a
//   COLOUR is categorical and cannot understate a magnitude (outside the window its
//   DIRECTION is simply right); the error is not symmetric; and it dropped the −1 dB trim
//   the two examples above both apply. At target −14: raw −25 → gain +6 → output −20, the
//   number sits 5 dB LOW; raw −3 → gain −6 → output −10, the number sits 7 dB HIGH.
//   ⚠️ AND THE ARITHMETIC ABOVE IS A MODEL, NOT A DERIVATION. The auto-gain does not read
//   the number being coloured. The grid colours `masterLUFSIntegrated` (gated, K-weighted
//   EBU R128 from `EchoelLoudnessMeter`). `AutoMixChain.updateLUFS` builds its OWN
//   `lufsReading` out of `masterLevel`, which is: left channel only; a peak-HELD envelope
//   (`max(raw, previous × 0.92)` at 60 Hz, not a windowed RMS); saturated in the tap by
//   `min(rms × 3, 1)`, so after the `/ 3.0` un-scaling it can never read above ≈ −9.6 dBFS
//   — which caps the CUT side to ≈ 4.4 dB for the default −14 target rather than the
//   nominal 6; and K-weighted by a flat −0.1 dB stand-in. The EQ is not unity either
//   (−1.5 low shelf at 140 Hz, +1.5 presence, +2.5 air) and sits inside the same "after the
//   measurement" bracket. Every one of those makes the two numbers diverge FURTHER, so they
//   strengthen the conclusion while weakening the demonstration. Do not quote the ≈ −15
//   figures as measurements; they are an illustration of the mechanism.
// · TRUE PEAK. Measured before the brick-wall limiter — i.e. before the one stage whose
//   job is to stop that peak from reaching the output.
//   ⛔ THIS SAID "peaks that PROVABLY never leave the device". Not provable, and false for
//   one shipped target. (a) `LoudnessTarget.cinema`'s ceiling is −2 dBTP while the output
//   ceiling after the limiter and the ×0.89 trim is ≈ −1 dBFS — a peak at −1.5 dBTP does
//   leave the device and does exceed that ceiling, so the removed `danger` would have been
//   RIGHT there. (b) The limiter is attached with no parameters configured at all, so it
//   runs Apple's `PeakLimiter` defaults (~12 ms attack, no look-ahead) and bounds SAMPLE
//   peak — while `masterTruePeakMaxDb` is oversampled INTER-SAMPLE true peak, which a
//   sample-peak limiter does not bound. The supportable claim, and the one that justifies
//   removing the verdict just as well: a pre-limiter dBTP over the ceiling is not evidence
//   that the delivered signal exceeds it.
//
// So the numbers stay (with the measurement point now stated on screen) and the verdicts
// go. That is this repo's #135/#164/#227 rule applied to a colour: a control or an
// indication may be absent, but it may not lie. The Target picker in the Master panel is
// NOT affected — it still drives the auto-gain and the export normalisation, so it does
// something real and stays.
//
// ⚠️ ONE UNKNOWN, deliberately not asserted either way: whether this tap observes
// `masterMixer.outputVolume` (the "Master volume" field two views up, `AudioEngine`'s
// `masterVolume` didSet). `installTap(onBus:)` documents the node's output bus but not its
// position relative to `outputVolume`, and there is no local toolchain to settle it — it
// needs a device run. Do not write a comment here that claims to know.
//   → SETTLED BY #316b, and the settlement is structural rather than empirical, which is
//     why it is allowed to override the sentence above: the R128 meter now taps a node
//     DOWNSTREAM of `masterMixer` entirely, so whatever `outputVolume` does at that node's
//     output is inside what the four numbers see. The instruction was right for a tap ON
//     `masterMixer` and is simply no longer the situation. The level BARS still are that
//     situation, and for them the unknown stands unchanged.
//
// WHAT THIS DEFERRED, and why it was a separate task (#316b) rather than that commit: moving
// the measurement to the true output. The obvious move — re-point `installMeterTap` at
// `mainMixerNode` — drags two unrelated passengers with it, because that one tap is also
// the SOLE writer of `_outputRing` (the FFT visual) and the host of the #193 audio-path
// timing instrument.
//   → WHAT #316b ACTUALLY DID, because this paragraph guessed and the guess mattered: it
//     MOVED the whole detailed tap to the limiter's output (passengers included — the ring
//     is arguably better placed there) and duplicated only the cheap RMS pair back onto
//     `masterMixer`. The split is not aesthetic: `masterLevel` is the AUTO-GAIN's input via
//     `connectMeter`, and the auto-gain acts upstream of the new tap, so leaving it on the
//     moved tap closed a control loop that has no integrator and permanently halved the
//     stage's correction. That regression shipped for one commit and was caught in review.
//     A second EBU/true-peak/FFT block was never needed; a second `vDSP_rmsqv` was.
//
// ⭐ THE CONTRACT THE BLOCKING GUARD ACTUALLY KEYS ON, because the obvious version of it was
// wrong: `Tests/CISmoke/LoudnessReadoutMeasurementPointTests.swift` does NOT test where the
// tap sits. Its first draft did — it looked for `masterMixer.installTap(` — and review
// showed that predicate fires RED on the very fix recommended two paragraphs up: a SECOND
// tap on the limiter's output leaves `masterMixer.installTap(` in place, deliberately,
// because `_outputRing` and the #193 instrument must stay there. A guard that goes red on
// the correct fix is worse than none, so the predicate is now the thing that actually
// matters: **does `AudioEngine` publish a POST-CHAIN measurement at all?**
//
// #316b MUST therefore name its post-chain publisher with a symbol containing
// `masterOutputLUFS` (e.g. `masterOutputLUFSIntegrated`). Until that string exists in
// `AudioEngine.swift` the guard requires: no target verdict anywhere in this file, every
// `readout(` call painted `EchoelTheme.text`, and the on-screen disclosure present. Once it
// exists those three fall silent and the verdicts MAY come back — `LoudnessTarget`'s two
// functions are kept callerless for exactly that. "May", not "do": re-enabling them is a
// separate decision, and the guard file grew live tests for the post-chain state instead of
// going quiet (see its ⭐ block).
//
// ⛔ AND THE NAME-ONLY PREDICATE HAS A HOLE THE REVIEW OF #316b FOUND, recorded here because
// this is where the contract is written down: `masterOutputLUFS` is a STRING in
// `AudioEngine.swift`, and reverting `installMeterTap` to `masterMixer` does not remove it.
// The three pre-chain guards would therefore NOT re-arm on such a revert, contrary to what
// #316b's commit message claimed. The guard file now also asserts the tap's node directly —
// which only became safe once #316b chose MOVE over DUPLICATE, i.e. the objection recorded
// in the ⭐ block above (a `masterMixer.installTap(` check fires red on the correct fix) is
// no longer live for the DETAILED tap. Note it still is for a bare `masterMixer.installTap(`
// check, because the cheap level tap deliberately sits there.

/// The master-volume parameter field in its OWN view so the read of
/// `audioEngine.masterVolume` is confined here. That value is rewritten by the
/// AutomationPlayer on every tick when a master-level automation lane plays; read inline
/// in `masterPanel` it invalidated the whole studio body (and tore down any open
/// Tonart/Genre `.menu` Picker — the "menus freeze while playing" report). Isolated, only
/// this field re-renders on an automation tick.
@MainActor
struct MasterVolumeField: View {
    @Environment(AudioEngine.self) private var audioEngine
    var body: some View {
        EchoelValueField(label: "Master volume", value: Binding(
            get: { Double(audioEngine.masterVolume) },
            set: { audioEngine.masterVolume = Float($0) }),
            range: 0...1, unit: "", decimals: 2)
    }
}

@MainActor
struct MasterLoudnessGrid: View {

    @Environment(AudioEngine.self) private var audioEngine

    // ⛔ THE `@AppStorage(StudioDefaultKeys.loudnessTarget.key)` READ WENT WITH THE VERDICTS
    // (#316) — it had no other consumer here. Its comment carried a lesson worth keeping
    // even though its code is gone: the fallback must be `.streaming`, never `.off`,
    // because nothing calls `UserDefaults.register(defaults:)` and `@AppStorage` defaults
    // are per-declaration, never written to the store. Until 2026-07-27 this view fell back
    // to `.off` while the export path fell back to −14, so ONE unreadable stored string made
    // the readout claim "no target in effect" while the export still normalised. One key
    // must not have two fallbacks. There are THREE remaining reader files, not the two an
    // earlier version of this comment listed: `EchoelStudioView` (the Master panel's picker,
    // plus its export resolve), `AutoMixChain` (auto-gain target), and `FloatingVisualWindow`
    // (the export path — i.e. the very half the two-fallbacks lesson is about, and the one
    // the first draft omitted). All three route through `LoudnessTarget.resolvedLUFS`, which
    // falls back to `.streaming`; keep it that way.

    var body: some View {
        VStack(spacing: 10) {
            // Instantaneous stereo mix level (L/R) — the moving meter every mixer has,
            // complementing the R128 numbers.
            //
            // ⭐ THESE TWO BARS ARE STILL PRE-CHAIN, and after #316b that is a DELIBERATE
            // split rather than the leftover it looks like. `masterLevel` is not only a bar:
            // `AudioEngine.start()` hands it to `AutoMixChain.connectMeter`, so it is the
            // auto-gain's measurement — and the auto-gain acts upstream of where the R128
            // meter now sits. Moving this reading too would have made that stage measure its
            // own output through a proportional law and permanently deliver half its
            // correction. So the R128 numbers moved and the levels stayed, each where it is
            // right. The caption below says so; keep the two in step.
            //
            // ⛔ FOR ONE COMMIT THIS COMMENT CLAIMED THE BARS WERE POST-CHAIN. They briefly
            // were, and that was the regression — recorded here rather than deleted, because
            // "make the bars agree with the numbers" is exactly the tidy-up that would
            // reintroduce it.
            VStack(spacing: 3) {
                levelBar(audioEngine.masterLevel)
                levelBar(audioEngine.masterLevelR)
            }
            HStack(spacing: 10) {
                readout("Short-term", lufsText(audioEngine.masterOutputLUFSShortTerm), "LUFS", EchoelTheme.text)
                readout("Integrated", lufsText(audioEngine.masterOutputLUFSIntegrated), "LUFS", EchoelTheme.text)
            }
            HStack(spacing: 10) {
                readout("True peak", dbText(audioEngine.masterOutputTruePeakMaxDb), "dBTP", EchoelTheme.text)
                readout("Range", lraText(audioEngine.masterOutputLRA), "LU", EchoelTheme.text)
            }
            // The measurement point, stated where the numbers are read rather than only in
            // the file header (#316). It lives INSIDE the grid on purpose, so any future
            // caller inherits it instead of having to remember the caption.
            // ⛔ THE FIRST VERSION JUSTIFIED THAT WITH A CALLER THAT DOES NOT EXIST: "this
            // view is used from the Master panel and from `BroadcastView`". `BroadcastView`
            // has ZERO instantiation sites in `Sources/` — it is doorless while HaishinKit is
            // unlinked, which CLAUDE.md says plainly. The placement is still right; the
            // reason was a comment describing a caller that cannot be opened, in a file whose
            // whole subject is a comment that outlived its truth. (The commit message of
            // 6a6bb81 leans on the same non-existent page and cannot be edited — recorded
            // here instead.)
            // ⚠️ LATENT, not introduced here: `.onAppear`/`.onDisappear` below flip GLOBAL
            // metering state. Two simultaneously mounted grids would fight — the second to
            // disappear silently freezes the first's numbers. Unreachable today precisely
            // because there is only one caller; if #316b or a broadcast door ever mounts two,
            // that ownership needs a refcount.
            // #316b MOVED THE POINT, so this sentence moved with it. It names the FOUR
            // NUMBERS specifically, not "this panel", because the bars above are a separate
            // measurement on purpose (see the ⭐ note at the bars). An earlier draft said
            // "Measured at the output of the master chain" flat, which read as a claim about
            // everything on screen and was wrong about half of it.
            Text("The four numbers are measured at the output of the master chain — after EQ, auto-gain and the limiter, with the −1 dB output trim included. The bars above are the pre-chain mix level.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Run the expensive R128/true-peak metering ONLY while this readout is on
        // screen. Off elsewhere it saved that per-buffer DSP during play (a load
        // contributor to the occasional crackle). The cheap RMS level bars above
        // stay live regardless — they read the always-on meter levels.
        .onAppear {
            audioEngine.setDetailedMetering(true)
            // Fresh integration window each open (the meters were paused while hidden,
            // so the held integrated/true-peak-max would otherwise show stale numbers).
            audioEngine.resetMastering()
        }
        .onDisappear { audioEngine.setDetailedMetering(false) }
    }

    /// One channel's level bar — fill proportional to level, turning warning near clip.
    private func levelBar(_ level: Float) -> some View {
        let v = CGFloat(min(max(level, 0), 1))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(EchoelTheme.fill)
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.9 ? EchoelTheme.danger : EchoelTheme.accent)
                    .frame(width: geo.size.width * v)
            }
        }
        .frame(height: 5)
    }

    // ⛔ `integratedColor` and `truePeakColor` LIVED HERE and were deleted by #316; the file
    // header holds the full reasoning. `LoudnessTarget.compliance(integratedLUFS:floor:)` and
    // `truePeakExceeds(_:floor:)` are UNTOUCHED and still covered by
    // `Tests/EchoelmusicTests/LoudnessTargetTests.swift` — they were the correct functions on
    // the wrong signal. They now have zero callers in `Sources/`, which is deliberate: they
    // are the ready-made verdict for whoever moves the tap, not dead weight to clean up.
    //
    // `readout`'s `color:` parameter is kept for the same reason and is NOT dead: every call
    // passes `EchoelTheme.text` today, but it is the seam the two verdicts plug back into,
    // and folding it away would make restoring them a signature change instead of an
    // argument change. Uncoloured is a deliberate state here, not an absent feature.

    private func readout(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(EchoelTheme.font(18, .semibold).monospacedDigit()).foregroundStyle(color)
                Text(unit).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
    }

    /// "—" while at the meter floor (silence); else one decimal.
    private func lufsText(_ v: Float) -> String {
        v <= EchoelLoudnessMeter.floorLUFS + 1 ? "—" : EchoelDecimalText.string(v, decimals: 1)
    }
    private func dbText(_ v: Float) -> String {
        v <= EchoelMeter.floorDb + 1 ? "—" : EchoelDecimalText.string(v, decimals: 1)
    }
    private func lraText(_ v: Float) -> String {
        v <= 0.05 ? "—" : EchoelDecimalText.string(v, decimals: 1)
    }
}
#endif
