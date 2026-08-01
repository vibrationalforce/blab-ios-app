#if canImport(SwiftUI)
import SwiftUI

// MasterLoudnessGrid.swift
// Echoel — the live EBU R128 loudness numbers (short-term + gated-integrated LUFS, max
// true-peak in dBTP, loudness range in LU), computed on the master tap in `AudioEngine`.
// Kept in its own view so the 60 Hz meter refresh re-renders only this small grid, not
// the whole studio. Science-first: the legible number leads, the unit follows.
//
// ⛔ THIS HEADER SAID "of the master OUTPUT" UNTIL 2026-08-01 (#316), AND THAT WAS FALSE.
// The numbers are measured at the master chain's INPUT. `AudioEngine.installMeterTap()`
// taps `masterMixer` bus 0, and `masterMixer` is precisely the node `AutoMixChain.insert`
// takes as its `from:` — so everything the chain does happens AFTER the measurement:
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
//   an alarm exactly where the output has no deviation at all — and outside it, where the
//   gain saturates and the output really is off, the colour understates by up to 6 dB.
//   (I first wrote "anti-correlated" here. That overstates it — the sign of the RAW mix's
//   deviation is reported correctly; what is wrong is that the raw mix is not the thing the
//   target describes. The defect is a category error, not an inverted sign, and the weaker
//   claim is the true one.) With "No target" chosen the compliance was already `.unknown`
//   and the auto-gain already inert, so this only ever misfired with a target set — which
//   is every fresh install, `.streaming` being the default.
// · TRUE PEAK. Measured before the brick-wall limiter — i.e. before the one stage whose
//   entire job is to stop that peak from reaching the output. `danger` therefore fires on
//   peaks that provably never leave the device.
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
//
// WHAT THIS DEFERS, and why it is a separate task (#316b) rather than this commit: moving
// the measurement to the true output. The obvious move — re-point `installMeterTap` at
// `mainMixerNode` — drags two unrelated passengers with it, because that one tap is also
// the SOLE writer of `_outputRing` (the FFT visual) and the host of the #193 audio-path
// timing instrument. Tapping the limiter's output and applying the known ×0.89 in software
// sidesteps the `outputVolume` unknown above, at the cost of a second tap's per-buffer
// work. Either way it is an audio-graph change, and this one deliberately is not: nothing
// below alters a sample.
//
// Restoring the verdicts is pinned to the tap move by
// `Tests/CISmoke/LoudnessReadoutMeasurementPointTests.swift` — bring one back without the
// other and the blocking bundle goes red.

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
    // must not have two fallbacks. The remaining readers — the Master panel's picker and
    // `AutoMixChain.resolvedTarget` — both fall back to `.streaming`; keep it that way.

    var body: some View {
        VStack(spacing: 10) {
            // Instantaneous stereo mix level (L/R) — the moving meter every mixer has,
            // complementing the R128 numbers. Reads the published meter levels, which come
            // from the same pre-chain tap as everything else here (#316) — so "output"
            // would have been the wrong word for these two bars as well.
            VStack(spacing: 3) {
                levelBar(audioEngine.masterLevel)
                levelBar(audioEngine.masterLevelR)
            }
            HStack(spacing: 10) {
                readout("Short-term", lufsText(audioEngine.masterLUFSShortTerm), "LUFS", EchoelTheme.text)
                readout("Integrated", lufsText(audioEngine.masterLUFSIntegrated), "LUFS", EchoelTheme.text)
            }
            HStack(spacing: 10) {
                readout("True peak", dbText(audioEngine.masterTruePeakMaxDb), "dBTP", EchoelTheme.text)
                readout("Range", lraText(audioEngine.masterLRA), "LU", EchoelTheme.text)
            }
            // The measurement point, stated where the numbers are read rather than only in
            // the file header (#316). It lives INSIDE the grid on purpose, so it travels with
            // it — this view is used from the Master panel and from `BroadcastView`, and a
            // caption written into one of those callers would leave the other unlabelled.
            Text("Measured before the master chain — EQ, auto-gain, limiter and the −1 dB trim come after.")
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
