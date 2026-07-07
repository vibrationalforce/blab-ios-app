//
//  MoodPads.swift
//  Echoelmusic — Studio
//
//  XY mood pads — ultra-light control for deep states (founder 2026-07-06D:
//  "Alles auf tiefe Bewusstseinszustände mit ultraleichter Steuerung ausgelegt …
//  Ein XY Pad für den Sound, damit man intuitiv die richtige Stimmung findet,
//  und für visuals auch"). One finger, two axes, no numbers in the way.
//
//  Design (Uncodixfy): solid surface, 1px border, a plain accent dot and a
//  hairline axis cross — position/opacity only, no glow, no scale animation.
//
//  Render safety: the drag keeps its position in LOCAL @State; bindings are
//  written through only when `live` (visual pad — the floating window must
//  follow the finger) or on release (sound pad — one recompose per gesture).
//  Writes are delta-gated (>1%) so a resting finger never spams invalidations.
//

#if canImport(SwiftUI)
import SwiftUI

struct MoodXYPad: View {
    let title: String
    /// Axis captions, shown small + dim under the pad ("dark · bright").
    let xCaption: String
    let yCaption: String
    /// live = write the bindings during the drag (throttled); otherwise only on release.
    var live: Bool = false
    /// Normalized position, 0…1 each; y is UP (1 = top).
    @Binding var x: Double
    @Binding var y: Double
    var onChanged: ((Double, Double) -> Void)? = nil
    var onEnded: ((Double, Double) -> Void)? = nil

    @State private var dragging = false
    @State private var localX = 0.5
    @State private var localY = 0.5

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(EchoelTheme.font(12, .medium))
                .foregroundStyle(EchoelTheme.text)
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let h = max(1, geo.size.height)
                let px = (dragging ? localX : x) * w
                let py = (1 - (dragging ? localY : y)) * h
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(EchoelTheme.surface)
                    // Hairline axis cross — orientation, not decoration.
                    Path { p in
                        p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h))
                        p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                    }
                    .stroke(EchoelTheme.border.opacity(0.6), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 12).stroke(EchoelTheme.border, lineWidth: 1)
                    Circle()
                        .fill(EchoelTheme.accent)
                        .frame(width: 14, height: 14)
                        .position(x: px, y: py)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !dragging { dragging = true; localX = x; localY = y }
                            let nx = min(1, max(0, v.location.x / w))
                            let ny = min(1, max(0, 1 - v.location.y / h))
                            // Delta gate: ignore sub-1% jitter so a resting finger
                            // doesn't spam UserDefaults/invalidations.
                            guard abs(nx - localX) > 0.01 || abs(ny - localY) > 0.01 else { return }
                            localX = nx; localY = ny
                            // onChanged fires on EVERY (delta-gated) drag move so a
                            // linked consumer (sound pad → visual) can follow the
                            // finger live; the BINDINGS write through only when
                            // `live` (the pad's own committed value).
                            if live { x = nx; y = ny }
                            onChanged?(nx, ny)
                        }
                        .onEnded { _ in
                            dragging = false
                            x = localX; y = localY
                            onEnded?(localX, localY)
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            Text("↔ \(xCaption)   ↕ \(yCaption)")
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) mood pad")
        .accessibilityValue("\(Int(x * 100)) percent across (\(xCaption)), \(Int(y * 100)) percent up (\(yCaption))")
        .accessibilityHint("Adjust with the named actions")
        .accessibilityAction(named: "More \(xCaption.components(separatedBy: " · ").last ?? "right")") { nudge(dx: 0.1, dy: 0) }
        .accessibilityAction(named: "More \(xCaption.components(separatedBy: " · ").first ?? "left")") { nudge(dx: -0.1, dy: 0) }
        .accessibilityAction(named: "More \(yCaption.components(separatedBy: " · ").last ?? "up")") { nudge(dx: 0, dy: 0.1) }
        .accessibilityAction(named: "More \(yCaption.components(separatedBy: " · ").first ?? "down")") { nudge(dx: 0, dy: -0.1) }
    }

    private func nudge(dx: Double, dy: Double) {
        x = min(1, max(0, x + dx))
        y = min(1, max(0, y + dy))
        onChanged?(x, y)
        onEnded?(x, y)
    }
}

/// One shared sound-mood → visual-mood mapping (founder 2026-07-07: "Xy Sound
/// und visuals verknüpfen"): the SOUND pad drives these too, live during the
/// drag, so one gesture moves the whole atmosphere. Piecewise-neutral: centre =
/// today's defaults, X away from 0 sweeps the palette off the physical colours.
enum VisualMoodMap {
    static func hue(forX x: Double) -> Double { x }
    static func motion(forY y: Double) -> Double {
        y <= 0.5 ? 0.3 + 1.4 * y : 1.0 + 1.0 * (y - 0.5)
    }
    static func intensity(forY y: Double) -> Double {
        y <= 0.5 ? 0.4 + 1.2 * y : 1.0 + 1.0 * (y - 0.5)
    }

    /// Write the full mapping (and the visual pad's own dot position, so the two
    /// pads visibly agree) straight into the shared UserDefaults keys.
    static func apply(x: Double, y: Double) {
        let d = UserDefaults.standard
        d.set(x, forKey: "mood.visual.x")
        d.set(y, forKey: "mood.visual.y")
        d.set(hue(forX: x), forKey: "visual.hue")
        d.set(motion(forY: y), forKey: "visual.motion")
        d.set(intensity(forY: y), forKey: "visual.intensity")
    }
}

/// The VISUAL mood pad — a self-contained leaf that owns the @AppStorage writes,
/// so the floating visual follows the finger live while ancestors stay still.
/// X sweeps the palette away from the physical-colour default (hue 0); Y sets
/// the energy (motion + intensity together), neutral exactly at centre so the
/// pad's resting middle reproduces today's defaults.
struct VisualMoodPadLeaf: View {
    @AppStorage("mood.visual.x") private var vx = 0.0   // 0 = natural palette
    @AppStorage("mood.visual.y") private var vy = 0.5   // centre = today's motion/intensity
    @AppStorage("visual.hue") private var visualHue = 0.0
    @AppStorage("visual.motion") private var visualMotion = 1.0
    @AppStorage("visual.intensity") private var visualIntensity = 1.0

    var body: some View {
        MoodXYPad(title: "Visual",
                  xCaption: "natural · spectrum",
                  yCaption: "calm · energy",
                  live: true,
                  x: $vx, y: $vy,
                  onChanged: { apply($0, $1) },
                  onEnded: { apply($0, $1) })
    }

    /// Piecewise-neutral mapping (shared with the sound-pad link): centre (0.5) =
    /// exactly 1.0 (today's default), bottom eases to a resting minimum, top
    /// reaches the panel's own 1.5 cap.
    private func apply(_ x: Double, _ y: Double) {
        visualHue = VisualMoodMap.hue(forX: x)
        visualMotion = VisualMoodMap.motion(forY: y)
        visualIntensity = VisualMoodMap.intensity(forY: y)
    }
}
#endif
