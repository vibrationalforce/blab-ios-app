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

    /// Where a requested value actually LANDS: clamped into the range, then snapped to the
    /// `10^-decimals` grid the field displays.
    ///
    /// ⛔ IT IS HOISTED HERE BECAUSE "the drag asked for a change" AND "the value changed" ARE
    /// NOT THE SAME PREDICATE, and the field notified its callers on the first one (#375).
    /// Two cases where a real, non-zero drag delta lands on the number it started at:
    ///  • BELOW THE GRID. "Detail" is `8…90, decimals: 0`, so one point of finger travel is
    ///    ~0.41 and a deliberately slow drag scales that to ~0.09 — a tenth of the smallest
    ///    representable step. The number cannot move, and the drag can go on producing those
    ///    deltas for as long as the finger does.
    ///  • AT A RANGE EDGE. A field already at its maximum, dragged further up, clamps.
    /// In both, `apply` wrote the same number back and the field then ran `onChange()`. Two of
    /// its ten `onChange` sites destroy user work with an unchanged value — `visualPresetID = ""`
    /// drops the chosen visual look and `applyArticulation()` overwrites hand-tuned A/D/S/R —
    /// and `onCommit` was worse still: `moodKnob` commits `recomposeIfRunning()`, so a drag that
    /// moved nothing re-rolled the composition (when the transport is running — the method name
    /// says so and the first draft of this line dropped the condition). A mood knob parked at 0
    /// and dragged DOWNWARD — the direction of a scroll — is exactly that gesture.
    ///
    /// ⚠️ THE BELOW-GRID CASE WAS ONLY HALF FIXED BY #375 — it made the dead zone SILENT, not
    /// gone — and #376 closed the other half one cycle later by giving the scrub an un-snapped
    /// running target (`ScrubPrecision.advanced`). The measurement is kept because it is the
    /// reason the field is shaped this way: adding each event's delta to the SNAPPED stored
    /// value meant a `0…1, decimals: 2` row (every FX parameter, master volume, the weather
    /// mixers) needed ≈135 pt/s at 60 Hz before it responded at all, ≈193 at 120 Hz. So
    /// `ScrubPrecision.fineScale > 0` — pinned in `ScrubPrecisionSmokeTests` as "a zero-travel
    /// control reads as broken" — was satisfied in the arithmetic and defeated by the grid one
    /// step later. A guard can only hold the layer it can see.
    ///
    /// This paragraph still matters after the fix: `snapped` is what makes the grid visible, and
    /// the next person tempted to snap somewhere else in the chain needs to know what that cost
    /// the last time.
    ///
    /// ⛔ THE 60 Hz FIGURE READ "≈140" IN THREE PLACES FOR ONE COMMIT and the solved value is
    /// ≈135 — `v · scale(v) = ½ · 10^-decimals · fullRangePoints`, i.e. `v · scale(v) = 60` for
    /// this row. Four percent, in the direction that made the defect look worse than it was.
    /// Small, and worth the line anyway: this file strikes unmeasured numbers by name elsewhere,
    /// and a figure that has been copied into three files is exactly the kind that stops being
    /// re-derived. The other two were right (≈193 at 120 Hz, ≈150 for `8…90, decimals: 0`).
    ///
    /// Pure so the landing rule is tested rather than reasoned about; the field's `apply`
    /// compares this result to the current value IN `V`'s OWN PRECISION, because a `Float` field
    /// holding 0.1 is not bit-equal to the `Double` 0.1 and comparing across the two would report
    /// a move on every single event.
    ///
    /// ⛔ NON-FINITE INPUT, STATED CORRECTLY ON THE SECOND ATTEMPT. The first version of this
    /// paragraph said "non-finite `raw` is passed through unchanged", which is wrong for the
    /// infinities: with Swift's ordering (`max(x,y) = y >= x ? y : x`), `+∞` clamps to
    /// `upperBound` and `−∞` to `lowerBound`, exactly as a finite out-of-range value would.
    /// Only NaN survives — `lo >= NaN` and `hi < NaN` are both false, so it passes both
    /// comparisons and `(NaN).rounded()` stays NaN. That behaviour is inherited from the
    /// previous inline code and deliberately not changed here (a second change riding along),
    /// but note what it costs `apply`: `next != value` is TRUE for NaN against anything,
    /// including NaN, so a field that ever holds NaN reports "moved" on every event and the
    /// guard this whole commit installs is defeated for it. The binding-level `isFinite` checks
    /// are what keep that unreachable today.
    static func snapped(_ raw: Double, lowerBound: Double, upperBound: Double,
                        decimals: Int) -> Double {
        let f = pow(10.0, Double(decimals))
        return (clamped(raw, lowerBound: lowerBound, upperBound: upperBound) * f).rounded() / f
    }

    /// The range clamp on its own — the half of `snapped` a scrub in progress needs WITHOUT the
    /// grid, so the drag can hold an intent finer than the field can display.
    static func clamped(_ raw: Double, lowerBound: Double, upperBound: Double) -> Double {
        Swift.min(Swift.max(raw, lowerBound), upperBound)
    }

    /// Advances a scrub in progress by one event's travel.
    ///
    /// ⛔ WHY A SCRUB NEEDS ITS OWN TARGET AT ALL (#376). The drag used to add each event's delta
    /// to the STORED value, which is already snapped — so everything below half a grid unit was
    /// thrown away every frame instead of accumulating. That does not make a slow drag slow; it
    /// makes it IMPOSSIBLE. Measured against the app's own fields at 60 Hz: a `0…1, decimals: 2`
    /// row — every FX parameter, the master volume, the weather mixers — needed ≈135 pt/s before
    /// it responded at all, and `8…90, decimals: 0` needed ≈150. Below that the row was inert for
    /// as long as the finger moved, which is precisely the "dead control" that
    /// `ScrubPrecisionSmokeTests` pins `fineScale > 0` to prevent: the guard was satisfied in the
    /// arithmetic and defeated by the grid one step later. It also made the travel depend on the
    /// display: at 120 Hz each event carries half as much, so the same physical drag lost MORE to
    /// rounding — undoing the frame-rate independence the speed measurement is built for.
    ///
    /// The target is CLAMPED but not snapped. Clamped, so a drag that runs past the top and comes
    /// back responds immediately instead of unwinding an invisible overshoot first; un-snapped,
    /// so the intent survives between events.
    ///
    /// ⚠️ THIS ALSO CHANGES DRAGS THAT WERE NEVER STUCK, AND MY FIRST DESCRIPTION OF HOW WAS
    /// WRONG. It said "±half a grid per event … nobody will feel it above the dead zone", as if
    /// the old rounding were symmetric jitter that averages out. It was not. For a steady finger
    /// speed the per-event error had a CONSTANT SIGN — `grid · round(δ/grid) − δ`, the same
    /// amount every event — so it accumulated instead of cancelling. Just above the old dead
    /// zone, where δ is a hair over half a grid, the old code advanced a WHOLE grid step per
    /// event against a requested half: on "Detail" (8…90, whole numbers) at ≈150 pt/s it moved
    /// about TWICE as fast as the exact travel does now. The error decays with speed (~14 % at
    /// 200 pt/s, ~10 % at normal fast-drag speeds), so the honest summary is: the fast end is
    /// nearly unchanged, and the band just above the old dead zone is now SLOWER — correctly so,
    /// because it finally travels the distance the finger asks for. If a slow-to-moderate drag
    /// reads as sluggish after this, that is this paragraph, not a regression to hunt.
    ///
    /// (Found by review, one commit after the claim shipped. The lesson is narrow and worth
    /// keeping: "it averages out" is a statement about a DISTRIBUTION, and a constant input
    /// does not have one.)
    static func advanced(target: Double, by delta: Double,
                         lowerBound: Double, upperBound: Double) -> Double {
        clamped(target + delta, lowerBound: lowerBound, upperBound: upperBound)
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
    /// The value when this gesture began — the reference `onEnded` measures the commit against.
    /// nil while no drag is in flight.
    @State private var scrubStartValue: V?
    /// The gesture's UN-SNAPPED running target (#376). The stored `value` is snapped to the
    /// display grid, so accumulating into it throws away everything finer than half a grid unit
    /// on every event; this keeps the intent. nil while no drag is in flight.
    @State private var scrubTarget: Double?
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
                        .font(EchoelTheme.font(14))
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
        // `apply(_:)` writes the binding and reports whether it moved — the WORK lives in the
        // caller's closures, and the two are not interchangeable: `onChange` is live-apply
        // (10 argument sites — 4× clearing the visual preset, 5× `applySoundLive()`,
        // 1× `applyArticulation()`; 8 of the 10 are a rendered row and 2 are the `param`/`knob`
        // helpers, which render 17 more — `grep -c 'param("' / 'knob("' EchoelStudioView.swift`
        // → 4 + 13 — so 25 rows carry one), `onCommit` is persist/settle (4 sites:
        // `recomposeIfRunning()` on every mood knob, the A4 `.echoelCompositionEdited` post,
        // the tempo lock, and the weather mixers' take re-push). This action called only
        // `onCommit`, so every VoiceOver
        // adjustment moved the number, saved it, and never reached the engine. The whole timbre
        // editor behind the Sound chip — ship-gate 2 — was therefore REACHABLE AND INERT for a
        // non-sighted performer: the spoken value changed and the instrument did not.
        //
        // ⛔ AND THE SENTENCE THAT USED TO CLOSE THIS PARAGRAPH WAS WRONG: "the drag path and the
        // keypad path were always correct; only this one was half-wired." They fired their
        // closures on a NON-ZERO REQUEST rather than on a value that moved, which is a different
        // and worse defect than the one this comment was written about — see
        // `ScrubPrecision.snapped` (#375). Both are guarded the same way now. The lesson is the
        // reason it is kept: this comment declared two sibling paths correct while auditing only
        // the third, and being right about the third made the claim about the other two sound
        // checked.
        //
        // (The counts above are argument sites verified line by line. The FIRST draft of this
        // comment said "7 / 3" and the draft before that "10 / 5 / 15" from a bare `grep -c`,
        // which also counts the two property declarations above, an unrelated
        // `SignalRouter.onChange`, and a line of prose. Three attempts, three numbers — quote
        // these only next to the grep that produced them.)
        //
        // Fires both ONCE, like the keypad — a swipe is a discrete completed edit — and only if
        // the value actually moved. (#232)
        .accessibilityAdjustableAction { dir in
            let step = ScrubPrecision.adjustmentStep(
                span: Double(range.upperBound - range.lowerBound), decimals: decimals)
            let moved: Bool
            switch dir {
            case .increment: moved = apply(Double(value) + step)
            case .decrement: moved = apply(Double(value) - step)
            // `return`, not `break`: an unhandled direction changed NOTHING, so announcing a
            // change and a commit for it would push a phantom edit through every live-apply and
            // persist closure. Falling through was harmless only while the value could not move
            // without them.
            @unknown default: return
            }
            // Same principle one step further, and it is NOT cosmetic: at a range edge `apply`
            // clamps, so the value is unchanged — and two of the ten closures do something
            // destructive with an unchanged value. `visualPresetID = ""` drops the user's chosen
            // visual look, and `applyArticulation()` overwrites hand-tuned Attack/Decay/Sustain/
            // Release from an articulation that did not move. Swiping past the top must not undo
            // work. (This was the ONLY guarded path until #375; the drag and keypad paths tested
            // the requested delta rather than the landed value and are now guarded the same way,
            // by `apply`'s return. The parenthetical that stood here — "the drag path … still has
            // this hole — noted, not silently inherited" — is retired by that commit.)
            guard moved else { return }
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
                        .font(EchoelTheme.font(13))
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
                // Same rule as the other two paths (#375): confirming the number that was already
                // there is not an edit. Typing 440 into a concert pitch that reads 440 used to
                // post `.echoelCompositionEdited`, which re-tunes every voice and recomposes.
                if apply(newVal) { onChange(); onCommit() }
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
                    scrubStartValue = value        // what a commit at the end is measured against
                    scrubTarget = Double(value)    // the un-snapped intent this gesture accrues
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
                let lo = Double(range.lowerBound)
                let hi = Double(range.upperBound)

                // THE BASE THIS EVENT BUILDS ON. Normally the gesture's own running target — but
                // ONLY while that target still describes the number on screen.
                //
                // ⛔ WHY THE CHECK EXISTS AND WHY IT IS NOT PARANOIA (#376 Reviewer-Nachlese).
                // Before #376 the drag read the live `value` every event, so any divergence
                // between "what the drag asked for" and "what is stored" self-corrected within
                // one frame. Carrying a target removed that feedback loop, and a reviewer found
                // the sequence that turns the loss into destroyed work: SwiftUI does NOT call
                // `onEnded` on a CANCELLED gesture (#377), and these fields sit in a
                // `ScrollView` that cancels them, so the latch and the target both stay standing.
                // The user then taps the same field and TYPES a number — the keypad writes
                // `value` and knows nothing about `scrubTarget` — and the next drag's FIRST event
                // would have thrown that entry away and teleported back to where the abandoned
                // drag ended, up to a full range width on the 20…18000 Hz cutoff row, with
                // `onChange()` firing for a move the user never made. That is the exact class
                // #375 exists to prevent, arrived at from the other side.
                //
                // COMPARE IN `V`'s OWN PRECISION, as `apply` does — this is load-bearing, not
                // style: `Double(Float(0.57)) != 0.57`, so a Double-side comparison would fail on
                // every event of every `Float` field, re-seed from the stored value each frame
                // and silently restore the #376 dead zone this file was written to remove.
                // A NaN target also fails the test and is therefore healed rather than carried
                // for the rest of the gesture.
                let base: Double
                if let running = scrubTarget,
                   V(ScrubPrecision.snapped(running, lowerBound: lo, upperBound: hi,
                                            decimals: decimals)) == value {
                    base = running
                } else {
                    base = Double(value)
                }
                // The scrub advances its OWN un-snapped target and the field snaps that for the
                // write (#376) — adding the delta to the stored value discarded everything below
                // half a grid unit every frame, which made a slow drag impossible rather than
                // slow. See `ScrubPrecision.advanced`.
                let target = ScrubPrecision.advanced(target: base,
                                                     by: delta,
                                                     lowerBound: lo,
                                                     upperBound: hi)
                scrubTarget = target
                // `apply` reports whether the number MOVED — the old guard was `delta != 0`,
                // which is a different question (see `ScrubPrecision.snapped`). At a range edge,
                // and on any event whose accumulated target still rounds to the same number, a
                // real delta lands on the value it started from, and firing `onChange()` there
                // ran destructive live-applies for an edit that never happened. (#375)
                if delta != 0, apply(target) { onChange() }
            }
            .onEnded { _ in
                // The commit is judged over the WHOLE gesture, not per event: a drag can move
                // the value away and back, and either way the question a commit closure asks is
                // "is this different from what you had". `recomposeIfRunning()` — every mood
                // knob's commit — re-rolls the composition, so an unmoved drag was an unexplained
                // new take. `nil` start means the anchor branch never ran, i.e. nothing moved.
                //
                // ⚠️ THE REFERENCE CAN BE STALE, AND NEITHER #375 NOR #376 CLOSES THAT (#377).
                // SwiftUI does not call `onEnded` when a gesture is CANCELLED — which is exactly
                // what a parent `ScrollView` claiming the drag does, and these fields live in
                // one. `scrubbing` then stays true, the next gesture skips the anchor branch, and
                // this line compares the NEW gesture's end against the OLD gesture's start.
                //
                // ⛔ THIS PARAGRAPH SAID "the latch is pre-existing … what is new is that a stale
                // reference can now produce a wrong COMMIT" AND THAT UNDER-RATED IT. Three
                // things go stale, not two, and the third is not a commit DECISION but a VALUE:
                // `scrubTarget` survives cancellation the same way, and the per-event branch
                // above would have built on it — teleporting the field and destroying any
                // keypad or VoiceOver edit made in between. That half is contained AT THE POINT
                // OF USE (the base check above re-seeds whenever the target no longer describes
                // the screen), which is why this is a doc correction and not an open defect.
                // What remains genuinely open is what a containment cannot reach: `scrubbing`
                // itself, so a cancelled gesture's successor still skips the anchor branch and
                // carries the old `lastY`/`lastX` (the long-standing first-event jump), and
                // `scrubStartValue`, so THIS line can still judge the wrong span. The real cure
                // is `@GestureState`, which SwiftUI resets on cancellation and would clear all
                // three at once. That needs a device check, so it stays its own slice.
                let moved = scrubStartValue.map { $0 != value } ?? false
                scrubStartValue = nil
                scrubTarget = nil
                scrubbing = false
                if moved { onCommit() }
            }
    }

    /// Writes the clamped/snapped value and reports whether it actually MOVED.
    ///
    /// The comparison happens in `V` — not in `Double` — for the reason spelled out on
    /// `ScrubPrecision.snapped`: a `Float` field holding 0.1 widens to 0.10000000149…, which is
    /// never equal to the `Double` 0.1 the snap produces, so a Double-space comparison would
    /// report a move on every event and this guard would be decorative.
    ///
    /// Returning `false` also skips the write, and the honest version of that sentence is longer
    /// than "it saves a redundant persist". Some setters do ENGINE work, not storage:
    /// `BodyTempoField.lockedBinding` calls `player.pattern.setTempo` (documented there as
    /// cancelling an in-flight glide) and the mix bindings push gains. Skipping the write skips
    /// those re-pushes too. Correct today — there is nothing to push when the number is the same
    /// — but it is a behaviour change, not a pure saving, and one caller's comment is now
    /// conditional because of it (`unisonVoicesBinding`, whose "the first edit WRITES the value"
    /// note only holds for an edit that moves the number).
    // No `@discardableResult`: all FOUR call sites consume the answer — two in the VoiceOver
    // switch, one in the keypad, one in the drag, across three edit paths. (#374 spent a commit
    // removing a modifier whose stated reason had gone away; this one has no reason to exist.)
    private func apply(_ raw: Double) -> Bool {
        let next = V(ScrubPrecision.snapped(raw,
                                            lowerBound: Double(range.lowerBound),
                                            upperBound: Double(range.upperBound),
                                            decimals: decimals))
        guard next != value else { return false }
        value = next
        return true
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

    /// Locale-aware since #232 G — a German player reads "0,50", not "0.50". Feeds BOTH the
    /// drawn value and `accessibleValue`, so VoiceOver speaks the same string the eye sees
    /// (a mismatch there is the #263 defect, one layer down).
    private var numberString: String {
        EchoelDecimalText.string(Double(value), decimals: decimals)
    }
}
#endif
