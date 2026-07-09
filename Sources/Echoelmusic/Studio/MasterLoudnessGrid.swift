#if canImport(SwiftUI)
import SwiftUI

// MasterLoudnessGrid.swift
// Echoel — the live EBU R128 loudness numbers of the master output (short-term +
// gated-integrated LUFS, max true-peak in dBTP, loudness range in LU). These were
// already computed on the master tap (AudioEngine) but never surfaced. Kept in its
// own view so the 60 Hz meter refresh re-renders only this small grid, not the
// whole studio. Science-first: the legible number leads, the unit follows.

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
    /// Shared with the Master panel's target picker — both read/write this key so
    /// the colour-coding matches the user's chosen delivery target everywhere.
    @AppStorage("studio.loudnessTarget") private var targetRaw = LoudnessTarget.streaming.rawValue
    private var target: LoudnessTarget { LoudnessTarget(rawValue: targetRaw) ?? .off }

    private static let floor = EchoelLoudnessMeter.floorLUFS

    var body: some View {
        VStack(spacing: 10) {
            // Instantaneous stereo output level (L/R) — the moving meter every mixer
            // has, complementing the R128 numbers. Reads the published meter levels.
            VStack(spacing: 3) {
                levelBar(audioEngine.masterLevel)
                levelBar(audioEngine.masterLevelR)
            }
            HStack(spacing: 10) {
                readout("Short-term", lufsText(audioEngine.masterLUFSShortTerm), "LUFS", EchoelTheme.text)
                readout("Integrated", lufsText(audioEngine.masterLUFSIntegrated), "LUFS", integratedColor)
            }
            HStack(spacing: 10) {
                readout("True peak", dbText(audioEngine.masterTruePeakMaxDb), "dBTP", truePeakColor)
                readout("Range", lraText(audioEngine.masterLRA), "LU", EchoelTheme.text)
            }
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

    /// Colour the integrated LUFS against the chosen target (over = warning).
    private var integratedColor: Color {
        switch target.compliance(integratedLUFS: audioEngine.masterLUFSIntegrated, floor: Self.floor) {
        case .onTarget: return EchoelTheme.accent
        case .tooLoud:  return EchoelTheme.danger
        case .tooQuiet: return EchoelTheme.dim
        case .unknown:  return EchoelTheme.text
        }
    }

    private var truePeakColor: Color {
        target.truePeakExceeds(audioEngine.masterTruePeakMaxDb, floor: EchoelMeter.floorDb)
            ? EchoelTheme.danger : EchoelTheme.text
    }

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
        v <= EchoelLoudnessMeter.floorLUFS + 1 ? "—" : String(format: "%.1f", v)
    }
    private func dbText(_ v: Float) -> String {
        v <= EchoelMeter.floorDb + 1 ? "—" : String(format: "%.1f", v)
    }
    private func lraText(_ v: Float) -> String {
        v <= 0.05 ? "—" : String(format: "%.1f", v)
    }
}
#endif
