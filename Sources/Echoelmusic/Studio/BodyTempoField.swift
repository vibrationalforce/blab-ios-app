// BodyTempoField.swift
// Echoel — THE tempo control (founder 2026-07-04: "Das mit den zwei Anzeigen irritiert
// immernoch … Beim BPM-Lock, wo auch der Kammerton eingestellt werden kann, geht einfach
// eine Anzeige mit, die gesynct ist mit der Biofeedback-BPM-Rate. Vier Stellen nach dem
// Komma und lockbar.")
//
// One row in the Composition panel, styled like the Kammerton field (4 decimals):
//   • UNLOCKED — the number RUNS ALONG with the live biofeedback BPM (trust-gated calm
//     display value; falls back to the clock tempo when no pulse is live).
//   • Tap the lock — the number FREEZES: the shown body value becomes the musical tempo
//     (the clock GLIDES to it, never jumps) and is then editable to 0.0001 BPM via the
//     Echoel number pad. Unlock → it follows the body again.
// The chrome (transport bar) shows NO tempo number anymore — the pulse in the bio strip
// is the one live number on screen; this field is the one musical-tempo control.
//
// RENDER SAFETY (freeze rule): `cameraRPPG.displayBPM` updates ~10 Hz. This is a LEAF
// view — the read lives HERE, so only this row rebuilds; the Picker-hosting Composition
// panel / root body never subscribe to the 10 Hz churn.

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BodyTempoField: View {

    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player
    @Environment(MetronomeVoice.self) private var metronome

    // Shared with the transport-bar lock button + tap tempo (same keys + defaults).
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    /// Parent hook (recompose after a lock change) — called on lock/unlock/edit.
    var onLockChanged: () -> Void = {}

    /// The live body rate when a trustworthy pulse is on screen, else 0.
    private var liveBodyBPM: Double {
        #if canImport(AVFoundation)
        if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 { return cameraRPPG.displayBPM }
        #endif
        return 0
    }

    /// What the unlocked display shows: the body rate, or the clock as honest fallback.
    private var followingValue: Double { liveBodyBPM > 0 ? liveBodyBPM : transport.tempo }

    var body: some View {
        HStack(spacing: 10) {
            if lockBPM {
                // Locked: exact, editable to 0.0001 BPM (Echoel number pad), like Kammerton.
                EchoelValueField(label: "Tempo", value: lockedBinding,
                                 range: Transport.minTempo...Transport.maxTempo, unit: "BPM",
                                 onCommit: onLockChanged)
            } else {
                // Following: the number runs along with the live biofeedback rate.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Tempo")
                        .font(EchoelTheme.font(13, .medium))
                        .foregroundStyle(EchoelTheme.text)
                    Spacer(minLength: 8)
                    Text(String(format: "%.4f", followingValue))
                        .font(EchoelTheme.font(15, .semibold).monospacedDigit())
                        .foregroundStyle(liveBodyBPM > 0 ? EchoelTheme.accent : EchoelTheme.text)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    Text("BPM")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tempo, following your pulse")
                .accessibilityValue(String(format: "%.1f beats per minute", followingValue))
            }

            Button { toggleLock() } label: {
                Image(systemName: lockBPM ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lockBPM ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 34, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(lockBPM ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lockBPM ? "Tempo locked — tap to follow your pulse again"
                                        : "Lock tempo at this value")
        }
    }

    /// Locking adopts the SHOWN value (the body rate, 4-decimal exact) as the musical
    /// tempo — the clock GLIDES to it (never jumps; the glide engine eases stopped or
    /// playing). Unlocking lets the clock resume its gentle body-follow.
    private func toggleLock() {
        if lockBPM {
            lockBPM = false
        } else {
            let v = min(max(followingValue, Transport.minTempo), Transport.maxTempo)
            lockedBPM = (v * 10_000).rounded() / 10_000
            player.pattern.glideTempo(to: lockedBPM)
            metronome.bpm = lockedBPM
            lockBPM = true
        }
        onLockChanged()
    }

    /// Locked edits are precise + instant (setTempo cancels any in-flight glide).
    private var lockedBinding: Binding<Double> {
        Binding(get: { lockedBPM },
                set: { v in
                    lockedBPM = min(max(v, Transport.minTempo), Transport.maxTempo)
                    player.pattern.setTempo(lockedBPM)
                    metronome.bpm = transport.tempo
                })
    }
}
#endif
