// HeaderMonitors.swift
// Echoel — the persistent header's two live monitors (founder idea, 2026-06-23):
// LEFT a small EKG-style control trace of the live pulse, RIGHT a monitor of the
// immersive visualisation. Both live in WorkspaceView.topBar (above every surface)
// and tap-expand to full screen — the first building block of the DMMW multiscreen /
// livestream / projection-mapping output.
//
// Design: the EKG is pure SwiftUI Canvas (no GPU, flash-safe); the immersive monitor
// reuses the REAL MetalBioView (not a placeholder), rendered only while a bio session
// is live to bound GPU cost. Uncodixfy: solid fills, 1px borders, ≤12px radius, no
// glow, opacity-only feedback. Fully VoiceOver-labelled.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - EKG pulse trace (left)

/// The EKG line: normalized [-1,1] samples drawn as a centred trace. Cheap vector
/// drawing; a flat baseline shows when there is no signal yet.
@MainActor
struct PulseTrace: View {
    let samples: [Float]
    var color: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            guard samples.count > 1 else {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: midY))
                base.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(base, with: .color(color.opacity(0.45)), lineWidth: 1)
                return
            }
            let n = samples.count
            let amp = midY - 1
            var path = Path()
            for (i, s) in samples.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let clamped = CGFloat(Swift.max(-1, Swift.min(1, s)))
                let y = midY - clamped * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
}

/// Compact header pulse monitor: live EKG trace + BPM. Accessible as one element.
@MainActor
struct PulseMonitorMini: View {
    let waveform: [Float]
    let bpm: Double
    let locked: Bool

    var body: some View {
        HStack(spacing: 6) {
            PulseTrace(samples: waveform, color: locked ? EchoelTheme.accent : EchoelTheme.dim)
                .frame(width: 50, height: 24)
            Text(locked && bpm > 0 ? "\(Int(bpm))" : "—")
                .font(EchoelTheme.font(11, .semibold)).monospacedDigit()
                .foregroundStyle(locked ? EchoelTheme.text : EchoelTheme.dim)
                .frame(minWidth: 22, alignment: .leading)
        }
        .padding(.horizontal, 6).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.border, lineWidth: 1))
        // This leaf owns the pulse element (it reads the live BPM; WorkspaceView can't,
        // per the freeze rule). The enclosing button provides the tap; keep ONE element
        // here so VoiceOver doesn't get two competing descriptions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live pulse")
        .accessibilityValue(locked && bpm > 0 ? "\(Int(bpm)) beats per minute" : "No pulse lock")
        .accessibilityHint("Opens the Bio page")
        .accessibilityAddTraits(.isButton)
    }
}

#if canImport(AVFoundation)
/// Live wrapper that reads the ~10 Hz pulse publisher in ITS OWN body, so the churn
/// stays in this leaf. Reading `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly
/// in `WorkspaceView.topBar` subscribed `WorkspaceView` — the PARENT of every surface —
/// to a 10 Hz signal, so the whole surface tree (including the active surface's Compose/
/// Mood/Effects `.menu` Pickers) rebuilt 10×/s during biofeedback and tore down any open
/// dropdown ("kann nicht mehr auswählen während Biofeedback", 10.76.50). Confining the
/// reads here keeps WorkspaceView still; only this 30 pt monitor refreshes.
@MainActor
struct PulseMonitorMiniLive: View {
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    var body: some View {
        PulseMonitorMini(waveform: cameraRPPG.waveform,
                         bpm: cameraRPPG.detectedBPM,
                         locked: cameraRPPG.isLocked)
    }
}
#endif

// MARK: - Immersive monitor (right)

/// Compact header monitor of the immersive visual. Deliberately a LIGHTWEIGHT
/// SwiftUI preview (radial bio-colour that pulses at the heart rate, hue following
/// coherence) — NOT a second MetalBioView. Running two MTKViews at once (this tile
/// + the full-screen immersive) starved the GPU and made the full immersive render
/// black for seconds (device video, 2026-06-23). Tapping opens the real Metal
/// immersive, so only ONE MetalBioView ever renders at a time.
@MainActor
struct ImmersiveMonitorMini: View {
    let active: Bool
    @Environment(EngineBus.self) private var bus

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    let bio = bus.freshBio()
                    let coh = Double(bio?.coherence ?? 0.4)
                    let hr = max(40.0, Double(bio?.heartRateBPM ?? 60))
                    // Smooth heartbeat pulse from the wall clock at the live HR.
                    let phase = (tl.date.timeIntervalSinceReferenceDate * hr / 60.0)
                        .truncatingRemainder(dividingBy: 1.0)
                    let pulse = 0.5 - 0.5 * cos(phase * 2 * .pi)           // 0…1 per beat
                    let hue = 0.66 - 0.33 * min(max(coh, 0), 1)           // blue→green with coherence
                    let color = Color(hue: hue, saturation: 0.85, brightness: 0.45 + 0.45 * pulse)
                    RadialGradient(colors: [color, .black], center: .center,
                                   startRadius: 1, endRadius: 28)
                }
            } else {
                ZStack {
                    EchoelTheme.fill
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                }
            }
        }
        .frame(width: 54, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Immersive visual monitor")
        .accessibilityValue(active ? "Live" : "Idle")
        .accessibilityHint("Shows or hides the floating visual window")
        .accessibilityAddTraits(.isButton)
    }
}

// The immersive visual now opens as a FLOATING, resizable window (FloatingVisualWindow,
// toggled from the header monitor), not a fullscreen cover — so the earlier
// `ExpandedMonitor` enum + `ExpandedMonitorView` (a second, now-unreachable MetalBioView
// path) were removed (founder pivot 2026-07-02: one visual path, fewer surfaces).
#endif
