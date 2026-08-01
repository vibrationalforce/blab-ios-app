#if canImport(SwiftUI)
import SwiftUI

// AnalysisPoincareView.swift
// Echoel — #347 Slice 3b. The BODY half of the founder's 2026-08-01 ask: "sei kreativ, wie
// können wir die visuals noch erweitern … aber achte auch auf den evidenzbasierten
// gesundheitlichen benefit". The scope and the spectrum are craft instruments about the
// SOUND; this is the one picture in the panel that is about the PERSON, and it is the one
// with published grounding — the Poincaré plot is the standard non-linear HRV picture and
// its two descriptors have accepted definitions (`PoincareMetrics`).
//
// WHAT IT DRAWS: each accepted beat interval against the NEXT one. A relaxed, coherent state
// scatters into a wide comet along the diagonal; a tense or shallow-breathing one collapses
// into a tight ball. The ellipse is not decoration — its two semi-axes ARE the two numbers in
// the caption (SD1 across the diagonal, SD2 along it), so the picture and its label cannot
// drift apart.
//
// ⛔ WHAT IT IS NOT: a diagnosis, and not a coherence score. It is descriptive statistics of
// an interval series for self-observation (CLAUDE.md safety section). No shape here means a
// health state and no caller may add that reading.
//
// ONE SOURCE TODAY — THE CAMERA, said plainly because the omission would otherwise look like
// an oversight. `CameraAnalyzer.rawIntervalsMs` is observable, so a leaf that reads it redraws
// when a beat lands. (`rawIntervalsMs` and NOT `rrIntervals`: the latter is twice-compacted —
// a `continue` past out-of-band differences, then an IQR filter, both into fresh arrays — so
// its neighbours are not neighbours. Reading it here reintroduced the fabricated-pair defect
// one layer above the hygiene meant to prevent it; see that property's own doc.)
// `PolarH10BioPublisher.rrIntervals` is `@ObservationIgnored` and appended
// PER BEAT, and the studio root reads that publisher — un-ignoring it would make every beat
// rebuild an ancestor body and tear down any open Picker (the 10.76.50 freeze law). The strap
// is the more accurate source and it deserves this plot; it needs a snapshot published at the
// publish tick rather than a per-beat notification, which is its own slice, not a one-liner.
//
// LEAF BY CONSTRUCTION (the freeze law). Every read of the publisher lives in THIS struct's
// body. It must never be inlined into `visualPanel` or any ancestor.

@MainActor
struct AnalysisPoincareView: View {

    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG

    /// Grows with Dynamic Type instead of a fixed frame (#292). Taller than the scope and the
    /// spectrum because this one is drawn SQUARE inside its box — equal scale on both axes is
    /// what makes the 45° line actually 45°, and a squashed Poincaré plot misreads as a
    /// different shape entirely.
    @ScaledMetric(relativeTo: .caption) private var plotHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // No `TimelineView`: this picture changes when a BEAT lands (~1 Hz), not on a
            // clock. Observation delivers exactly those redraws and no more — a 20 fps
            // schedule here would redraw the same dots twenty times per beat. Reduce Motion
            // therefore needs no special case: there is no animation to freeze.
            Canvas { ctx, size in draw(ctx, size) }
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
                .frame(height: plotHeight)
                // The picture is its own element with a summary label; the caption below keeps
                // its own. `children: .combine` would fold them into one and DISCARD the
                // caption's label — the same defect the scope shipped and had to fix.
                .accessibilityElement()
                .accessibilityLabel("Poincaré plot")
                .accessibilityHint("Each heartbeat interval drawn against the next one. A wide cloud along the diagonal means variable timing.")
            // SCIENCE-FIRST: the numbers, then the picture (Uncodixfy).
            PoincareReadoutLabel()
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard size.width > 2, size.height > 2 else { return }

        // A SQUARE drawing region, centred. Both axes are the same quantity in the same unit,
        // so they must have the same scale or the ellipse's orientation lies.
        let side = Swift.min(size.width, size.height) - 8
        guard side > 8 else { return }
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2

        // The line of identity, always drawn: an empty box cannot be told apart from a view
        // that failed to render, and this line is what the whole picture is read against.
        var identity = Path()
        identity.move(to: CGPoint(x: originX, y: originY + side))
        identity.addLine(to: CGPoint(x: originX + side, y: originY))
        ctx.stroke(identity, with: .color(EchoelTheme.border), lineWidth: 1)

        guard let analysis = PoincareMetrics.analyse(rrMs: cameraRPPG.rrWindowMs),
              !analysis.points.isEmpty else { return }

        // Centre and span. The centre is the cloud's own centroid; the half-span is scaled
        // from SD2 so a tight cloud still fills the box, with a floor so a nearly flat series
        // does not blow a few milliseconds of jitter up into a full-frame scatter.
        var sumX = 0.0
        var sumY = 0.0
        for p in analysis.points {
            sumX += p.rr
            sumY += p.next
        }
        let n = Double(analysis.points.count)
        let cx = sumX / n
        let cy = sumY / n
        // The descriptors may be absent while points are not — one surviving pair draws a dot
        // and has no spread. Then there is no ellipse and the span falls back to the floor;
        // the dot is still the truth about that beat, and drawing it beats an empty box.
        let d = analysis.descriptors
        let spread = d.map { Swift.max($0.sd1, $0.sd2) } ?? 0
        let half = Swift.max(Self.minimumHalfSpanMs, 3.0 * spread)

        let scale = Double(side) / (2 * half)
        let mid = Double(side) / 2
        // Sub-expressions hoisted out of the `CGPoint` call on purpose: arithmetic inside an
        // argument list is what makes an expression expensive to type-check, and this repo has
        // taken the blocking gate down for exactly that (#287).
        func project(_ x: Double, _ y: Double) -> CGPoint {
            let dx: Double = (x - cx) * scale + mid
            // Y grows DOWNWARD in a Canvas and upward in the plot, hence the flip.
            let dy: Double = mid - (y - cy) * scale
            return CGPoint(x: originX + CGFloat(dx), y: originY + CGFloat(dy))
        }

        // The ellipse: semi-axis SD1 across the identity line, SD2 along it — i.e. the two
        // numbers in the caption, drawn. Sampled as a polyline rather than transformed with a
        // rotation matrix, because a rotated `Path` in a `Canvas` also rotates the stroke and
        // this repo has no need for either the transform stack or its surprises.
        if let d, d.sd2 > 0 || d.sd1 > 0 {
            let root2 = 2.0.squareRoot()
            var ellipse = Path()
            for step in 0...Self.ellipseSteps {
                let t = 2 * Double.pi * Double(step) / Double(Self.ellipseSteps)
                let along = d.sd2 * cos(t)          // coordinate on the identity line
                let across = d.sd1 * sin(t)         // perpendicular to it
                let x = cx + (along - across) / root2
                let y = cy + (along + across) / root2
                let p = project(x, y)
                if step == 0 { ellipse.move(to: p) } else { ellipse.addLine(to: p) }
            }
            ctx.stroke(ellipse, with: .color(EchoelTheme.dim), lineWidth: 1)
        }

        // The beats themselves, on top of the ellipse so no dot is hidden by it.
        for p in analysis.points {
            let c = project(p.rr, p.next)
            guard c.x.isFinite, c.y.isFinite else { continue }
            let r = Self.dotRadius
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(EchoelTheme.text))
        }
    }

    /// Floor for the plotted half-span, in milliseconds. Without it, a nearly constant pulse
    /// (SD1 and SD2 both around a millisecond) would be magnified until ordinary quantisation
    /// noise filled the frame and read as wild variability — the picture would say the
    /// opposite of the measurement beside it.
    private static let minimumHalfSpanMs = 40.0
    private static let ellipseSteps = 48
    private static let dotRadius: CGFloat = 1.8
}

/// The numbers. Its own leaf for the same reason every readout in this panel is: the
/// observation boundary belongs at the value, not at whatever view happens to host it today.
///
/// ⚠️ IT CAN REFUSE TO STATE A FIGURE, and that is the point of `acceptedFraction`. Artifact
/// rejection is not free — what survives had its LARGEST successive differences preferentially
/// removed, so below `RRIntervalHygiene.minAcceptedFractionForHRV` (0.8) an SD1 in
/// milliseconds would be a confident-looking number derived from a spliced record. The repo
/// already made that call for HRV and coherence (`RRIntervalHygiene.canStateHRV`); this
/// obeys the same bar rather than inventing a friendlier one. The CLOUD is still drawn in that
/// state, because every plotted point is a real consecutive pair — it is the summary
/// STATISTIC that stops being meaningful, not the beats.
@MainActor
private struct PoincareReadoutLabel: View {
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG

    var body: some View {
        // Computed ONCE. Calling `readout()` again for the accessibility label would run the
        // whole analysis a second time per rebuild and, worse, could disagree with the shown
        // text if a beat landed in between.
        let text = readout()
        return Text(text)
            .font(EchoelTheme.font(11).monospacedDigit())
            .foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }

    private func readout() -> String {
        let raw = cameraRPPG.rrWindowMs
        // `nil` means nothing arrived AT ALL — not "what arrived was unusable". Keeping those
        // two apart is the whole reason `analyse` stopped returning `nil` for the second case:
        // a shredded record and a sensor that is off used to print the same sentence, so the
        // refusal line below was unreachable exactly when it was warranted.
        guard let a = PoincareMetrics.analyse(rrMs: raw) else {
            return "Waiting for beats"
        }
        let clean = Int((a.acceptedFraction * 100).rounded())
        guard a.acceptedFraction >= RRIntervalHygiene.minAcceptedFractionForHRV else {
            // The same "—" convention as `MasterLoudnessGrid.dbText`: an absent measurement
            // is stated as absent, never rounded into a plausible one.
            return "SD1 — · SD2 — · only \(clean)% of beats usable"
        }
        // Clean beats, just not enough of them yet — that is waiting, not refusing.
        guard let d = a.descriptors else { return "Waiting for beats" }
        // #267: no user-visible readout formats its own decimals.
        let sd1 = EchoelDecimalText.string(d.sd1, decimals: 1)
        let sd2 = EchoelDecimalText.string(d.sd2, decimals: 1)
        return "SD1 \(sd1) ms · SD2 \(sd2) ms · \(d.pairs) beat pairs"
    }
}
#endif
