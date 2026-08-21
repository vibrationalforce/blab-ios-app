//
//  PulseMeasurementView.swift
//  Echoelmusic — Studio
//
//  The live camera-pulse acquisition readout: status light · coaching hint · BPM ·
//  waveform · confidence bar.
//
//  ⛔ THIS LINE SAID "shown above the controls while a take is playing" AND THAT HAS NOT BEEN
//  TRUE SINCE THE TOOLS-GRID REMOVAL (2026-07-02). Measured, not assumed:
//  `git grep -n 'PulseMeasurementView(' -- Sources` returns exactly ONE construction site,
//  `BioSourceView.swift`; `git grep -n 'BioSourceView(' -- Sources` returns ZERO. The chain
//  terminates one hop up. Nothing in the app mounts this view, during a take or otherwise.
//
//  ⭐ WHY THAT SENTENCE WAS THE EXPENSIVE KIND OF STALE, rather than a tidy-up: it is a claim
//  about WHERE a reader will find this on screen, written in the file's first paragraph — the
//  place a session reads before deciding whether a fix here can be device-verified. It cannot.
//  And it is the second half of the same defect #523 hit from the other end: `coachingHint`
//  (= `acquisitionCue.fullHint`) has exactly ONE reader, and that reader is this view. A file
//  that says it is on screen is precisely what stops someone noticing that.
//
//  ⛔ THAT PARAGRAPH ONCE ENDED "so the rPPG remedy reached a sighted user nowhere", AND THAT
//  HALF IS NO LONGER TRUE (#703). #523/#569 gave the remedy a reachable surface: `BioStripView`
//  banners the SAME STRING via `acquisitionCue.fullHint` in `bioPanel`, behind the Bio chip,
//  gated by `cueWarrantsFullHintOnScreen`. The measurement above stands — one reader of the
//  PROPERTY — but the conclusion drawn from it does not: what is dead is the property, not the
//  capability. Left as a retraction rather than deleted because CLAUDE.md and
//  `ThePulseReadoutHasNoDoorTests` both inherited the wrong half and had to be pulled along in
//  the same commit (#456), and a silent edit here would have hidden why.
//
//  ⚠️ DOORLESS IS NOT A DEFECT HERE AND THIS FILE MUST NOT BE "CLEANED UP" INTO ONE. The block
//  below is the canonical statement of the 10.76.41/50 freeze law for this shape, and three
//  other files plus CLAUDE.md cite this view BY NAME as the worked example. Deleting the file
//  takes the law's home with it — the #472 trap, where a doorless VIEW and a load-bearing
//  neighbour share one file. Re-dooring it is welcome work; see the guard for what to update
//  in the same commit.
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
                // The pulse NUMBER lives in EXACTLY ONE place — the bio strip's HR cell
                // (founder 2026-07-03: "zu viele BPM-Anzeigen, eine reicht"). This card
                // deliberately shows only the ACQUISITION feedback (status light · coaching ·
                // waveform · confidence bar), never a second copy of the bpm value that the
                // strip right above already shows. Clean split: card = "getting a lock",
                // strip = "the value".
            }
            pulseWaveform
                .accessibilityHidden(true)   // decorative waveform — not a VoiceOver control
            ProgressView(value: locked ? 1 : min(max(cameraRPPG.confidence, 0), 1))
                .tint(locked ? EchoelTheme.accent : EchoelTheme.warning)
                .accessibilityLabel("Pulse signal confidence")
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
