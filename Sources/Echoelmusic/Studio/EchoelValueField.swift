//
//  EchoelValueField.swift
//  Echoelmusic — Studio
//
//  The one control: a NUMERIC VALUE, no permanent slider/knob (saves space, reads
//  science-first). Interaction:
//   • Press the value and drag in ANY direction — UP or RIGHT increases, DOWN or
//     LEFT decreases (founder 2026-07-12: "nicht nur hoch und runter sondern auch
//     links und rechts"). The box ITSELF becomes the fader while dragging: filled
//     from the bottom to the current value, with a line at the top of the fill.
//     Drag FAST to sweep the whole range, SLOWLY to dial a value in — speed decides
//     precision (see `ScrubPrecision`). (Superseded twice: the pull-sideways FINE
//     mode is gone — horizontal now ADJUSTS — and so is the floating slider that
//     used to sit beside the box, which got cut off by the surfaces it hung out of;
//     `faderTrack` names which ones, and which one it is NOT.)
//   • TAP the value to open the EchoelNumberPad — our own keypad with − / + at the
//     bottom-left (the iOS decimal pad can't carry a sign key). Same pad everywhere.
//   • VoiceOver: adjustable by swipe, speaks the real value + unit.
//
//  Everything scales with Dynamic Type / the app zoom (EchoelTheme.font relativeTo +
//  the studio pinch-zoom). Website CI tokens only. Pure UI — no audio-thread work.
//

// `ScrubPrecision` sits OUTSIDE the SwiftUI guard deliberately: it is pure arithmetic
// with no import at all, and `Tests/CISmoke` reaches it. Today that bundle is built
// only by the Xcode gate (iOS, so SwiftUI is always importable), but #208 is about
// wiring CISmoke into SwiftPM as well — and on a platform without SwiftUI the guard
// would turn this into a missing symbol, i.e. a hard error rather than a warning.
// Costing nothing to hoist, it is hoisted.
/// How fast a drag travels, as a function of how fast the finger moves.
///
/// WHY THIS EXISTS (founder 2026-07-29, "besser funktionieren"). The scrub used to be
/// strictly linear: 200 pt of travel always covered the full range. That is fine for a
/// sweep and useless for dialling in a value — on a 40…18000 Hz cutoff, one point of
/// finger movement was 89 Hz, so the smallest movement a hand can make already overshot
/// anything precise. The escape hatch was tap-to-type, which is the wrong answer for a
/// performer with one hand on the instrument.
///
/// So the same gesture carries both: move quickly and you sweep, move slowly and each
/// point is worth ~a fifth as much. There is no mode to remember and nothing to hold —
/// the intent is already in how the hand moves.
///
/// Pure and dependency-free ON PURPOSE, so the thresholds are tested rather than argued
/// about; the values below are the whole design surface.
enum ScrubPrecision {
    /// At or below this finger speed the drag is at its finest.
    static let fineSpeed: Double = 60          // pt/s
    /// At or above this speed the drag runs at full range travel.
    ///
    /// 320 and not something larger, and the number was CHOSEN rather than guessed: an
    /// ordinary parameter drag runs around 300 pt/s, and with the window ending at 700 that
    /// landed at scale ≈ 0.5 — i.e. the everyday gesture would have become HALF as fast,
    /// which is how "more precise" turns into "it got sluggish". Ending the window at 320
    /// puts a normal drag at ≈ 0.94 (indistinguishable from before) and reserves the fine
    /// range for a deliberately slow finger, which is the only place it was ever wanted.
    static let fullSpeed: Double = 320         // pt/s
    /// Travel multiplier at `fineSpeed`. NOT zero — a control that can stop responding
    /// to a slow finger reads as broken, which is the opposite of the ask.
    static let fineScale: Double = 0.22

    /// How far ONE VoiceOver adjustment swipe moves the value, for a range of width `span`
    /// displayed to `decimals` places.
    ///
    /// ⛔ WHY IT IS NOT JUST `span / 50` (found 2026-07-29, in review of the fix that wired
    /// this path to the engine at all). `EchoelValueField.apply(_:)` snaps to the `10^decimals`
    /// grid, so a step smaller than half that grid rounds back to where it started — the value
    /// never moves and the swipe does nothing. Every `decimals: 0` field with a span under 25
    /// was in that state, which is not an edge case: "Beats per bar" (1…12), the Field's
    /// "Voices" (1…8), the FX "Bits" (1…16) and both Harmonizer intervals (−12…12) could not be
    /// changed by VoiceOver at all, while the field's own hint promised "Swipe up or down to
    /// adjust". Wiring the callback without this would have fixed the silence and left the
    /// paralysis — a lying hint is the same defect class either way (#227).
    ///
    /// So the step is at least one grid unit. Fields whose fiftieth is already coarser than the
    /// grid (a 20…18000 Hz cutoff moves ~360 Hz) are untouched — 50 swipes across a range stays
    /// the design for everything that could already move.
    static func adjustmentStep(span: Double, decimals: Int) -> Double {
        let grid = pow(10.0, -Double(decimals))
        let fiftieth = span / 50
        // A non-finite or non-positive span (a degenerate `a...a` range) falls back to the grid
        // rather than to zero: a control that cannot move is the thing being fixed here.
        guard fiftieth.isFinite, fiftieth > 0 else { return grid }
        return Swift.max(fiftieth, grid)
    }

    /// Travel multiplier in `fineScale…1` for a finger speed in points per second.
    ///
    /// Non-finite input returns 1 (full travel), never 0 or a fine value: speed is
    /// derived from a division by the gesture's time delta, and a zero delta — two
    /// events in the same instant — yields infinity. Slowing the control down in that
    /// case would punish the user for a timing artefact, so an unusable measurement
    /// means "no opinion", i.e. behave exactly as the old linear scrub did.
    static func scale(speedPointsPerSecond speed: Double) -> Double {
        guard speed.isFinite else { return 1 }
        if speed <= fineSpeed { return fineScale }
        if speed >= fullSpeed { return 1 }
        let t = (speed - fineSpeed) / (fullSpeed - fineSpeed)
        return fineScale + (1 - fineScale) * t
    }
}


#if canImport(SwiftUI)
import SwiftUI
import Foundation

struct EchoelValueField<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var unit: String = ""
    /// Decimals shown and the snap grid (default 4 → exact to 0.0001).
    var decimals: Int = 4
    var onChange: () -> Void = {}
    var onCommit: () -> Void = {}

    // The value box + label grow with Dynamic Type / app zoom. Wide enough for a
    // 4-decimal value with a large integer part plus its unit ("18000.0000 Hz").
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 150
    /// Optional box width for COMPACT contexts (e.g. the transport bar's BPM), where the
    /// default 150 is far wider than a short value needs. When nil the box keeps the
    /// Dynamic-Type-scaled default. The one control still — just narrower.
    ///
    /// ⚠️ IT SCALES (see `compactWidthProbe`). It did not until 2026-07-30, and that was a
    /// real defect the moment the chrome's Dynamic Type ceiling was raised: the number
    /// carries `.minimumScaleFactor(0.5)` and the unit label does NOT, so in a fixed box the
    /// growing unit steals width from the number until the number hits its floor and
    /// TRUNCATES. Measured on the worst case in the app — Concert pitch A4, `440.0000 Hz` in
    /// a 104 pt box — the shrink-to-fit demand at `.accessibility1` is ≈0.39, below the 0.5
    /// floor. Giving the box the same growth factor as its text keeps the ratio, so the
    /// number reads at the size the user asked for instead of being cut.
    var boxWidth: CGFloat? = nil

    /// The factor Dynamic Type is currently applying to body text, obtained by scaling a
    /// probe. `relativeTo: .body` matches `EchoelTheme.font`, which lays every label out
    /// against `.body` — so the box grows exactly as fast as what is inside it.
    ///
    /// The base is 100 and not 1 ON PURPOSE: `@ScaledMetric` returns point values, and asking
    /// it to scale a single point invites quantisation to land on 1 or 2 and turn a smooth
    /// ratio into a step function. A 100 pt probe divided back out is stable.
    @ScaledMetric(relativeTo: .body) private var compactWidthProbe: CGFloat = 100
    /// Optional fixed box HEIGHT for DENSE rows (e.g. the timeline lane strip, where the
    /// value box must read the SAME size as the neighbouring M/S/record buttons — founder
    /// 2026-07-15 "Die Felder sollen gleichgroß sein"). nil = the natural padded height.
    var boxHeight: CGFloat? = nil

    /// Presents the shared numeric keypad (tap-to-type path).
    @State private var showPad = false

    // Drag state (incremental deltas, so the value never jumps mid-gesture).
    @State private var scrubbing = false
    @State private var lastY: CGFloat = 0
    @State private var lastX: CGFloat = 0
    /// Timestamp of the previous drag event — the basis for the speed measurement that
    /// decides fine vs. full travel (see `ScrubPrecision`). Comes from the gesture itself,
    /// never from a clock read, so it stays in step with the events it describes.
    @State private var lastTime: Date = .distantPast

    /// Drag distance (points) that covers the FULL range at normal speed — small, so
    /// the fader feels fast/direct (the old velocity-scrub felt stiff).
    private let fullRangePoints: Double = 200

    var body: some View {
        // With a label, the caption sits left and the box trails (aligned columns).
        // With an EMPTY label (compact strips — e.g. the timeline lane gain) render
        // JUST the box: the leading Text + expanding Spacer would otherwise reserve
        // ~30 pt of dead width and blow the box past its host column. One caller uses
        // label:"" today (the lane mix strip); this keeps that field as small as its box.
        Group {
            if label.isEmpty {
                valueBox
            } else {
                HStack(spacing: 12) {
                    Text(label)
                        .font(EchoelTheme.font(14, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    valueBox
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibleValue)
        .accessibilityHint("Swipe up or down to adjust, or double-tap to type")
        // ⛔ BOTH CALLBACKS, and `onChange` is the one that was missing (found 2026-07-29).
        // `apply(_:)` writes the binding and nothing else — the WORK lives in the caller's
        // closures, and the two are not interchangeable: `onChange` is live-apply (7 argument
        // sites — `applySoundLive()`, `applyArticulation()`, clearing the visual preset —
        // reaching ~22 rendered rows through the `param`/`knob` helpers), `onCommit` is
        // persist/settle (3 sites). This action called only `onCommit`, so every VoiceOver
        // adjustment moved the number, saved it, and never reached the engine. The whole timbre
        // editor behind the Sound chip — ship-gate 2 — was therefore REACHABLE AND INERT for a
        // non-sighted performer: the spoken value changed and the instrument did not. The drag
        // path (`onChange` per event, `onCommit` on end) and the keypad path (both, once) were
        // always correct; only this one was half-wired.
        //
        // (Those counts were "10 / 5 / 15" in the first draft. That was `grep -c` on
        // `onChange:` / `onCommit:`, which also counts the two property declarations above, an
        // unrelated `SignalRouter.onChange`, and one line of prose. Ergrepped, cited, wrong.)
        //
        // Fires both ONCE, like the keypad — a swipe is a discrete completed edit — and only if
        // the value actually moved. (#232)
        .accessibilityAdjustableAction { dir in
            let step = ScrubPrecision.adjustmentStep(
                span: Double(range.upperBound - range.lowerBound), decimals: decimals)
            let before = value
            switch dir {
            case .increment: apply(Double(value) + step)
            case .decrement: apply(Double(value) - step)
            // `return`, not `break`: an unhandled direction changed NOTHING, so announcing a
            // change and a commit for it would push a phantom edit through every live-apply and
            // persist closure. Falling through was harmless only while the value could not move
            // without them.
            @unknown default: return
            }
            // Same principle one step further, and it is NOT cosmetic: at a range edge `apply`
            // clamps, so the value is unchanged — and two of the seven closures do something
            // destructive with an unchanged value. `visualPresetID = ""` drops the user's chosen
            // visual look, and `applyArticulation()` overwrites hand-tuned Attack/Decay/Sustain/
            // Release from an articulation that did not move. Swiping past the top must not undo
            // work. (The drag path guards the requested delta rather than the snapped value, so
            // it still has this hole — noted, not silently inherited.)
            guard value != before else { return }
            onChange()
            onCommit()
        }
    }

    private var valueBox: some View {
        // Number + unit read as ONE cohesive field ("440.0000  Hz"), trailing-aligned
        // so values line up in a column. Website CI: solid fill, 1px muted border, 8px
        // radius; bio-green while scrubbing or while the pad is open.
        let active = scrubbing || showPad
        return ZStack {
            HStack(spacing: 5) {
                Text(numberString)
                    .font(EchoelTheme.font(17).monospacedDigit())
                    .foregroundStyle(active ? EchoelTheme.accent : EchoelTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(EchoelTheme.font(13, .medium))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }

            // A transparent layer turns the value into a vertical fader: drag = adjust,
            // tap = open the keypad.
            //
            // ⚠️ A BARE `Rectangle()` ACCEPTS ANY PROPOSED HEIGHT, so this ZStack — and
            // therefore the whole field — is vertically GREEDY. That was invisible while the
            // dense callers pinned `.frame(height: boxHeight)`; it is not invisible now that
            // the pin is a minimum. A parent VStack ranks children by flexibility, so a bar
            // hosting this field would report ∞ and start splitting free space with the
            // instrument below it. The three chrome bars therefore carry an explicit
            // `.fixedSize(horizontal: false, vertical: true)` (`WorkspaceView`), which
            // proposes nil downward and lets this Rectangle fall back to its ideal.
            // Do not remove that without removing this greediness at the source.
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(scrubGesture)
                .onTapGesture { showPad = true }
        }
        .frame(width: boxWidth.map { $0 * compactWidthProbe / 100 } ?? valueWidth)
        // Dense rows pin the height (vertical padding shrinks) so the box matches its
        // neighbour buttons; default keeps the roomy 9 pt padding + natural height.
        .padding(.horizontal, 12).padding(.vertical, boxHeight == nil ? 9 : 3)
        // minHeight, NOT height. `boxHeight` says "match the neighbouring buttons", which is
        // a FLOOR — a dense row wants the box no SMALLER than its neighbours. As a fixed
        // height it was also a ceiling, and at accessibility text sizes the taller content
        // then OVERFLOWED it. (Overflowed, not clipped: a `.frame` does not clip, SwiftUI
        // lets the child draw outside. What the eye reads as cropping is the next bar's
        // opaque `.background(EchoelTheme.bg)` painting over the overspill, plus collision
        // inside the bar. The wording matters — "clipped" sends the next reader looking for
        // a `.clipped()` that does not exist.) The chrome strip is the case that made it
        // visible (its A4 field is 104×30 inside a bar that now grows with Dynamic Type), but
        // every dense caller carried the same latent overflow. Nothing shrinks: at normal
        // sizes the content is smaller than `boxHeight`, so the frame still decides.
        .frame(minHeight: boxHeight)
        // BACKGROUND, not overlay, and that is a correctness choice rather than a taste one:
        // the value text turns `accent` while scrubbing, and the indicator's line is also
        // `accent`, so drawn on TOP it struck straight through the digits in the same colour
        // at any mid-range value. Layered here it sits in front of the box fill and behind
        // the number — visible, and never in the way of the thing being read.
        .background { if scrubbing { faderTrack } }
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            // borderStrong, not border: this box IS the app's one parameter control, so
            // its boundary is a control boundary (WCAG 1.4.11, 3:1). The 0.10 `border`
            // measured 1.07:1 against this box's own `fill` — the value read fine and the
            // box it sits in did not.
            .strokeBorder(active ? EchoelTheme.accent : EchoelTheme.borderStrong, lineWidth: 1))
        // (The position indicator is layered above, as a `.background` — see `faderTrack`.)
        .animation(.easeOut(duration: 0.12), value: scrubbing)
        .sheet(isPresented: $showPad) {
            EchoelNumberPad(title: label, initial: Double(value), decimals: decimals,
                            unit: unit, range: Double(range.lowerBound)...Double(range.upperBound)) { newVal in
                apply(newVal)
                onChange()
                onCommit()
            }
            .presentationDetents([.height(440), .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// The position reference shown while dragging: the value box ITSELF becomes the fader,
    /// filled from the bottom to the current value with a crisp line at the top of the fill.
    ///
    /// WHY IT IS NOT THE OLD FLOATING SLIDER (founder 2026-07-29, "der slider soll nicht
    /// verschwinden sondern überlappen und besser funktionieren"). The previous version was a
    /// 180 pt tall capsule placed `.offset(x: -22)` beside the box. Two things were wrong:
    ///  1. It DISAPPEARED. 180 pt centred on a ~40 pt row leaves ~70 pt hanging above and
    ///     below, and there IS a clipping ancestor — but naming the right one matters,
    ///     because the first draft of this comment blamed "the panel card" and a review
    ///     showed that is false: `EchoelPanel` uses `.background`/`.overlay` with no clip
    ///     modifier at all, and a SwiftUI `.background(RoundedRectangle…)` does not clip its
    ///     content. Do not "fix" the panel. The real clippers are the FX sheet, which is a
    ///     `Form` whose inset-grouped section clips to its card (`EchoelFXView`), and the
    ///     studio panels' scroll VIEWPORT (`EchoelStudioView`, the `ScrollView` around
    ///     `dropdownContent`), which cuts rows near the top and bottom edge. In the founder's
    ///     screenshot of the FX sheet the capsule is cut at the card boundary, which is the
    ///     first of those two.
    ///  2. It was SQUEEZED, not overlapping — with `alignment: .leading` and a 13 pt frame
    ///     the capsule's centre lands 22 pt left of the box, i.e. inside the
    ///     `Spacer(minLength: 8)` between label and box, so on a narrow row it drew on top of
    ///     the label text.
    /// Drawing inside the box fixes both: the indicator can no longer be cut by the ancestors
    /// that cut the old one, and it lies across the value instead of fighting for space next
    /// to it. It also scales itself — the same code reads correctly in a dense lane strip and
    /// in the compact BPM box, where a fixed 180 pt never could.
    ///
    /// The fill is deliberately faint. This sits behind the value, and the number staying
    /// legible matters more than the indicator being loud; the crisp line carries the
    /// reading. No glow, no shadow, opacity only — house UI law.
    private var faderTrack: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let lineHeight: CGFloat = 2
            ZStack(alignment: .bottom) {
                Color.clear
                Rectangle().fill(EchoelTheme.accent.opacity(0.12))
                    .frame(height: Swift.max(0, h * frac))
                Rectangle().fill(EchoelTheme.accent)
                    .frame(height: lineHeight)
                    .offset(y: -Swift.max(0, h - lineHeight) * frac)
            }
            .frame(width: geo.size.width, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Current value as a 0…1 fraction of the range — drives `faderTrack`'s fill height
    /// and the position line. (There is no thumb any more; the old floating capsule had one.)
    private var frac: CGFloat {
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        guard hi > lo else { return 0 }
        return CGFloat(Swift.min(Swift.max((Double(value) - lo) / (hi - lo), 0), 1))
    }

    private var scrubGesture: some Gesture {
        // 8 pt slop so a TAP (which always carries ~1–3 pt of jitter) reliably opens the
        // keypad instead of being claimed as a near-zero scrub. Deliberate drags still
        // adjust. (The old 1 pt threshold made tap-to-type flaky.)
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if !scrubbing {
                    scrubbing = true
                    lastY = g.translation.height   // anchor; no jump on the first move
                    lastX = g.translation.width
                    lastTime = g.time
                    return
                }
                let span = Double(range.upperBound - range.lowerBound)
                // BOTH axes adjust (founder 2026-07-12): up = increase, right = increase.
                // The deltas ADD, so a diagonal drag is simply faster — never a fight.
                let dyStep = Double(lastY - g.translation.height)
                let dxStep = Double(g.translation.width - lastX)
                lastY = g.translation.height
                lastX = g.translation.width

                // Velocity-dependent precision (founder 2026-07-29 "besser funktionieren").
                // Speed is measured in points per SECOND from the gesture's own timestamps,
                // NOT in points per event: an event is one display frame, so a per-event
                // measure would mean the identical physical drag behaves differently on a
                // 120 Hz device than on a 60 Hz one.
                let step = dyStep + dxStep
                let dt = g.time.timeIntervalSince(lastTime)
                lastTime = g.time
                let scale = ScrubPrecision.scale(speedPointsPerSecond: abs(step) / dt)

                let delta = ((step * scale) / fullRangePoints) * span
                if delta != 0 {
                    apply(Double(value) + delta)
                    onChange()
                }
            }
            .onEnded { _ in scrubbing = false; onCommit() }
    }

    private func apply(_ raw: Double) {
        let clamped = Swift.min(Swift.max(raw, Double(range.lowerBound)), Double(range.upperBound))
        // Snap to the decimal grid so the displayed number is exact.
        let f = pow(10.0, Double(decimals))
        value = V((clamped * f).rounded() / f)
    }

    private var accessibleValue: String {
        let n = numberString
        switch unit {
        case "Hz":  return "\(n) hertz"
        case "s":   return "\(n) seconds"
        case "BPM": return "\(n) beats per minute"
        case "":    return n
        default:    return "\(n) \(unit)"
        }
    }

    /// The unit suffix shown after the value (Hz, s, BPM, …). Empty for dimensionless
    /// values, whose meaning is carried by the label.
    private var unitLabel: String { unit }

    private var numberString: String { String(format: "%.\(decimals)f", Double(value)) }
}
#endif
