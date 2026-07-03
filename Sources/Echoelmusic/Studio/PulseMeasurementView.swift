//
//  PulseMeasurementView.swift
//  Echoelmusic — Studio
//
//  The live camera-pulse acquisition readout (status light · coaching hint · BPM ·
//  waveform · confidence bar) shown above the controls while a take is playing.
//
//  WHY ITS OWN VIEW (not a computed `var` on EchoelStudioView): every property it reads
//  on `CameraRPPGBioPublisher` — `fingerDetected`, `confidence`, `waveform`, `detectedBPM`,
//  `coachingHint`, `isLocked` — is rewritten ~10 Hz while reading. As a computed `var` on
//  the root view those reads registered the WHOLE `EchoelStudioView.body` as a 10 Hz
//  observer (an `AnyView` wrapper does NOT create an observation boundary — only a distinct
//  `View` struct does). That re-evaluated the body 10×/s while playing and tore down any
//  open Tonart/Genre `.menu` Picker popover hosted in the same body — the founder's "can't
//  select anymore" freeze. As a separate struct the high-frequency invalidation is confined
//  here (no Picker), so the selection menus stay open.
//

#if canImport(SwiftUI) && canImport(AVFoundation)
import SwiftUI

@MainActor
struct PulseMeasurementView: View {
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG

    var body: some View {
        let locked = cameraRPPG.isLocked
        let lightColor: Color = !cameraRPPG.fingerDetected ? EchoelTheme.dim
            : (locked ? EchoelTheme.accent : EchoelTheme.warning)
        // Specific, live coaching ("Press lighter" / "Hold still…") instead of a
        // flat "Acquiring…", so a placed-but-unlockable finger gets actionable help.
        let statusText = cameraRPPG.coachingHint
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(lightColor).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(EchoelTheme.border, lineWidth: 1))
                Text(statusText).font(.caption.weight(.semibold)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                // ONLY the calm, slew-limited displayBPM — never the raw per-reading value.
                // Before the first confident lock displayBPM is 0, so we show no number at all
                // (the coaching hint already says "Acquiring…"); this stops the readout from
                // bouncing on the noisy warmup estimates. .isFinite guard: Int() traps on NaN/+Inf.
                let shownBPM = cameraRPPG.displayBPM
                if shownBPM > 0, shownBPM.isFinite {
                    Text("\(Int(shownBPM)) bpm")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(EchoelTheme.text)
                }
            }
            pulseWaveform
                .accessibilityHidden(true)   // decorative waveform — not a VoiceOver control
            ProgressView(value: locked ? 1 : min(max(cameraRPPG.confidence, 0), 1))
                .tint(locked ? EchoelTheme.accent : EchoelTheme.warning)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private var pulseWaveform: some View {
        Canvas { ctx, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height / 2))
            base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(base, with: .color(EchoelTheme.border), lineWidth: 1)
            let w = cameraRPPG.waveform
            guard w.count > 1 else { return }
            let dx = size.width / CGFloat(w.count - 1)
            let amp = size.height / 2 - 3
            var path = Path()
            for (i, v) in w.enumerated() {
                let x = CGFloat(i) * dx
                // A NaN/Inf sample (rPPG can emit one before lock) would feed a NaN
                // point to CoreGraphics → hard crash. Clamp non-finite to the centre
                // line and bound the sample so the path is always drawable.
                let sample = v.isFinite ? CGFloat(min(max(v, -1), 1)) : 0
                let y = size.height / 2 - sample * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)
        }
        .frame(height: 52).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(EchoelTheme.bg.opacity(0.35)))
    }
}
#endif
