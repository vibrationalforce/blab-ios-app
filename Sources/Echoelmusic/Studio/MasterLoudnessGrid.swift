#if canImport(SwiftUI)
import SwiftUI

// MasterLoudnessGrid.swift
// Echoel — the live EBU R128 loudness numbers of the master output (short-term +
// gated-integrated LUFS, max true-peak in dBTP, loudness range in LU). These were
// already computed on the master tap (AudioEngine) but never surfaced. Kept in its
// own view so the 60 Hz meter refresh re-renders only this small grid, not the
// whole studio. Science-first: the legible number leads, the unit follows.

@MainActor
struct MasterLoudnessGrid: View {

    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                readout("Short-term", lufsText(audioEngine.masterLUFSShortTerm), "LUFS")
                readout("Integrated", lufsText(audioEngine.masterLUFSIntegrated), "LUFS")
            }
            HStack(spacing: 10) {
                readout("True peak", dbText(audioEngine.masterTruePeakMaxDb), "dBTP")
                readout("Range", lraText(audioEngine.masterLRA), "LU")
            }
        }
    }

    private func readout(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(EchoelTheme.font(18, .semibold).monospacedDigit()).foregroundStyle(EchoelTheme.text)
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
