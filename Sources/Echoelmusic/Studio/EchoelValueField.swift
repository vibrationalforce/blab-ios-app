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
    /// In both, `apply` wrote the same number back and the field then ran `onChange()`. One KIND
    /// of its ten `onChange` sites destroys user work with an unchanged value:
    /// `applyArticulation()` overwrites hand-tuned A/D/S/R. (There was a second until #379 —
    /// `visualPresetID = ""` on four of the ten sites; those rows now go through
    /// `visualPresetDiverged()`, which is a no-op for a write that moved nothing.)
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
    ///
    /// ⛔ IT USED TO CLAMP AND THEN GRID, AND THOSE TWO ORDERS ARE NOT THE SAME PROMISE (#442).
    /// Gridding rounds to NEAREST, so it can move a value OUTWARD: clamping into a `0…0.995` row
    /// gives `0.995`, which at two places grids to `1.00` — a committed value half a grid step
    /// ABOVE the row's declared maximum, written into a binding whose type is the range. Swapping
    /// the order does not fix it, it only moves the lie: grid-then-clamp lands exactly ON an
    /// off-grid bound, and the readout formats the GRIDDED value (#432), so the row would show one
    /// number and keep another — the defect #432 closed. Neither order satisfies both promises, so
    /// this rounds toward the INTERIOR: nearest grid point, stepped one unit back inside if that
    /// landed outside. What is given up is reaching an off-grid bound EXACTLY, which the row
    /// cannot display anyway.
    ///
    /// ⛔ AND THE FIRST VERSION OF THAT STEP WOULD HAVE TAKEN `0.95` OFF FIVE SHIPPED ROWS — the
    /// reason the comparison carries a `slack` and is not a bare `>`. A bound reaches here as
    /// `Double(range.upperBound)`, and for a `Float` row that is not the literal: `Float(0.95)` is
    /// `0.9499999880790710`. #430 measured 11 of 86 bounds in that state. A bare `landed >
    /// upperBound` reads `0.95 > 0.94999998…` as a real overshoot and steps the row's maximum down
    /// to `0.94`. The OLD order was immune by accident (it clamped first, so it never produced a
    /// grid point above the bound at all) — which is exactly why "just swap the two lines" is not
    /// the safe-looking change it appears to be. `slack` is one hundredth of a grid step: orders of
    /// magnitude above any `Float` round-trip error at these magnitudes, orders of magnitude below
    /// the half-step a genuinely off-grid bound sits at.
    ///
    /// ⚠️ MEASURED SCOPE, because this repo strikes fixes that oversell themselves: on today's
    /// tree it changes NOTHING. Every bound reachable from a literal in `Sources/` — 74 checks
    /// across both `EchoelValueField(` and `EchoelFXView.field(` call sites, plus the named
    /// constants they use (`TrackFXStore.cutoffRange` 40…18000, `RoleRhythm.minGate` 0.05 /
    /// `maxPush` 0.45, `EchoelDDSP.cutoffRange` 20…18000, the Patchbay universes) — is already on
    /// its own row's grid, and where the bound is on the grid, monotone rounding cannot cross it.
    /// This buys the NEXT row, in a file that already ships an 80…18000 Hz cutoff at `decimals: 0`.
    ///
    /// ⚠️ THE PROMISE IS THEREFORE "on the grid, and inside the range to within `slack`" — not an
    /// exact containment. And when a range holds NO grid point at all (`0.4…0.6` at whole numbers)
    /// neither neighbour fits and the clamped raw value is returned instead: IN-RANGE wins over
    /// ON-GRID, because an out-of-range number reaches an engine while an off-grid one can only
    /// misdisplay. Unreachable today by the same measurement, and stated rather than left to be
    /// discovered.
    static func snapped(_ raw: Double, lowerBound: Double, upperBound: Double,
                        decimals: Int) -> Double {
        let step = pow(10.0, -Double(decimals))
        let slack = step * 1e-2
        let inRange = clamped(raw, lowerBound: lowerBound, upperBound: upperBound)
        let nearest = gridded(inRange, decimals: decimals)
        if nearest >= lowerBound - slack, nearest <= upperBound + slack { return nearest }
        // Re-grid after the step: `nearest ± step` is only approximately a grid point in binary,
        // and several callers compare this result for exact equality.
        let inward = gridded(nearest > upperBound ? nearest - step : nearest + step,
                             decimals: decimals)
        if inward >= lowerBound - slack, inward <= upperBound + slack { return inward }
        return inRange
    }

    /// The GRID half of `snapped`, without the clamp — and the app's ONE definition of what
    /// rounding a parameter to `decimals` places means.
    ///
    /// It exists because the number a row SHOWS and the number a row KEEPS were rounded by two
    /// different rules (#432). The commit path has always used `.rounded()`, which is
    /// half-away-from-zero. The readout went through `EchoelDecimalText.string` →
    /// `String(format: "%.Nf", …)`, which is C `printf` and rounds HALF-TO-EVEN on the exact
    /// binary value. They agree everywhere except at an exact dyadic tie — and there they
    /// disagree half the time, because half of all ties have an even neighbour below:
    ///
    ///   · 2 places: `0.125` read "0.12" and committed `0.13`; `0.625` read "0.62" → `0.63`.
    ///     (`0.375` and `0.875` agreed — their even neighbour is the upper one.)
    ///   · 0 places: `2400.5` read "2400" and committed `2401`. Measured over the Cutoff row's
    ///     own span, **8990 of the 17980 half-integers in 20…18000 diverge** — this is not an
    ///     exotic corner, it is every other one.
    ///
    /// A tie is only reachable for a value nothing has snapped yet, which is exactly the
    /// interesting case: a shipped patch literal, a bio- or prompt-written value, or a DERIVED
    /// binding like `EchoelStudioView.visualEnergy`, whose getter recomputes and lands off-grid
    /// by construction. The player then reads one number and the first touch keeps another —
    /// the #135/#416/#427/#431 condition, on the last path where it survived.
    ///
    /// NOT the clamp: the readout must never claim a value is inside a range it is outside of.
    /// Gridding alone is safe for display because it moves a number by less than half a step;
    /// clamping can move it by any amount at all.
    ///
    /// NaN and the infinities pass through as they did (`(NaN).rounded()` is NaN, `±∞ * f` is
    /// `±∞`), so `printf` still prints "nan"/"inf" exactly as before — this is a no-op for every
    /// input that is not an exact tie. A negative zero also survives: `.rounded()` is
    /// `toNearestOrAwayFromZero`, which preserves the sign of a zero result, so the six rows that
    /// go below zero (Transpose, Detune, Trim, pan) still read "-0" where they always did.
    ///
    /// ⚠️ NO `decimals ≥ 0` GUARD, unlike `EchoelDecimalText.string`, which clamps with
    /// `Swift.max(0, decimals)`. A negative `decimals` here would grid to tens or hundreds and the
    /// readout would print "0" for a 7. No call site passes one (the only computed `decimals` in
    /// the app is `bio.hrvRMSSDms < 10 ? 1 : 0`) and `snapped` has always had the same hole, so
    /// this is written down rather than closed — closing it silently would make a nonsense input
    /// look handled instead of impossible.
    static func gridded(_ raw: Double, decimals: Int) -> Double {
        let f = pow(10.0, Double(decimals))
        return (raw * f).rounded() / f
    }

    /// The range clamp on its own — the half of `snapped` a scrub in progress needs WITHOUT the
    /// grid, so the drag can hold an intent finer than the field can display.
    static func clamped(_ raw: Double, lowerBound: Double, upperBound: Double) -> Double {
        Swift.min(Swift.max(raw, lowerBound), upperBound)
    }

    /// Does the running scrub target still describe the number on screen?
    ///
    /// THE PREDICATE THE DRAG RE-SEEDS ON. A scrub carries its own un-snapped target (#376) so
    /// travel below half a grid unit accumulates instead of being thrown away every frame. That
    /// target may only be trusted while it still names the value the field is showing — a keypad
    /// entry or any other foreign write must win, or an abandoned drag teleports the number back
    /// on the next event (#375/#377).
    ///
    /// ⛔ IT COMPARED THE SNAPPED TARGET TO THE RAW STORED VALUE AND THAT WAS TOO STRICT FOR A
    /// DERIVED BINDING (#427 review). A stored binding holds exactly what `apply` wrote, so raw
    /// equality held on every event. A binding whose getter RECOMPUTES — `EchoelStudioView`'s
    /// `visualEnergy`, the one visual control (#228), reads back through
    /// `VisualEnergy.position(matching:motion:)` — returns the same number only to within
    /// rounding: measured over the 101 two-decimal positions, the round trip is bit-exact on
    /// **39** of them, worst residual 2.2e-16. So on 62 of 101 positions the check failed EVERY
    /// event, the target was discarded, and the row fell back into the exact pre-#376 regime this
    /// file exists to describe — whose measured dead zone for a `0…1, decimals: 2` row is
    /// **≈135 pt/s at 60 Hz**. Simulated against the shipped constants, a 3 s drag from 0 reached
    /// 0.01 and stopped at 10, 40, 60 and 120 pt/s, then jumped to 1.00 at 135: the one visual
    /// control became a two-state control under the finger. At `decimals: 4` the same threshold
    /// is ≈2.7 pt/s, which is why it was invisible until #427 coarsened the grid.
    ///
    /// The fix is to compare what the two sides SHOW, not what they store: snap both, then map
    /// both through `V` exactly as before. Both halves are load-bearing.
    ///  • Snapping the stored side is what admits a getter that round-trips within a grid cell.
    ///  • Mapping through `V` is what keeps `Float` fields working, and dropping it would be the
    ///    subtler regression: `Double(Float(17999.9)) = 17999.900390625` snaps to `17999.9004`
    ///    at 4 decimals while the target snaps to `17999.9`, so a Double-side comparison would
    ///    re-seed every event on the cutoff row. `V` collapses both to the same `Float`.
    ///
    /// This is strictly more permissive than raw equality and never less: a pair that was equal
    /// before is a snapped, `V`-mapped number already, so snapping it again returns it unchanged.
    /// What it gives up is precision the field cannot show — a foreign write landing INSIDE the
    /// running target's grid cell no longer re-seeds. That write displays the same number, which
    /// is the condition this predicate is written to test. Verified bit-identical on a stored
    /// `0…1.5, decimals: 2` row at 10 / 60 / 120 / 300 pt/s.
    ///
    /// NaN is still healed rather than carried: it fails the equality against anything, including
    /// itself, so the drag re-seeds from the stored value exactly as before.
    static func carriesTarget<V: BinaryFloatingPoint>(_ running: Double, value: V,
                                                      lowerBound: Double, upperBound: Double,
                                                      decimals: Int) -> Bool {
        let onScreen = V(snapped(Double(value), lowerBound: lowerBound,
                                 upperBound: upperBound, decimals: decimals))
        return V(snapped(running, lowerBound: lowerBound,
                         upperBound: upperBound, decimals: decimals)) == onScreen
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

    /// The user's chosen text size. Read HERE, in the control itself, never in an ancestor
    /// (10.76.50 law) — and it is cheap for a different reason than that law is about: it is a
    /// settings-driven environment value, so it changes when the user changes it, not ~10×/s.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// True when the row gives up its single line and puts the label ABOVE the box (#353e).
    ///
    /// THE DEFECT IT ANSWERS, measured rather than assumed. The labelled row is
    /// `HStack { Text(label) ; Spacer(minLength: 8) ; valueBox }`, and `valueBox` is PINNED to
    /// `valueWidth` — 150 pt at the default text size, but `@ScaledMetric(relativeTo: .body)`,
    /// so it tracks body text: 17 pt → 53 pt at `.accessibility5` is a factor of ~3.1, i.e. a
    /// box of ~468 pt on a 375 pt phone. A `.frame(width:)` is a pin and does not compress, so
    /// the box takes the whole row and more, the label is squeezed to its
    /// `minimumScaleFactor(0.7)` floor and then truncates to nothing, and the box itself runs
    /// past the screen edge. This is the ONE parameter control in the app —
    /// **57 CALL SITES.** That is the only figure worth writing down here, and the raw
    /// `git grep -c "EchoelValueField(" -- Sources` total is deliberately NOT quoted any more.
    /// ⛔ Four editions of this paragraph quoted it — "65 / THREE", then "64 / TWO", then
    /// "61 / FOUR" — and the #475 review's own correction of the FOUR pushed it to SEVEN in the
    /// act of writing the correction, because the fix had to spell the searched string out three
    /// more times. The `EchoelModalBank` law CLAUDE.md records, demonstrated on itself twice in
    /// one commit: a note that quotes a grep corrupts its own evidence, and here the corruption
    /// was CAUSED by correcting it. A total that any prose edit moves is not a measurement.
    /// The call-site count does not move when someone writes about it. To re-derive either:
    ///   `git grep -n 'EchoelValueField(' -- Sources | grep -vE ':[0-9]+: *(//|///)' | wc -l`
    /// ⚠️ The retired enumeration is worth one line, because it was wrong in a way a re-count
    /// would not have caught: it double-counted this paragraph (as both "THIS one" and one of the
    /// four) and named a fourth that has never contained the string — `stacksLabel`'s doc.
    /// Enumerate the comment hits, never recall them. **57 call sites** now, down from 62
    /// because #475 deleted the five rows inside the unreachable piano-roll view; the REACHABLE
    /// figure did not move. Exactly ONE of them renders label-less unconditionally (the chrome A4 box
    /// in `WorkspaceView`) with one more doing so only in its compact form (`BodyTempoField`).
    /// So at accessibility sizes essentially every parameter row in the instrument reads as an
    /// unlabelled overflowing box. (The count is call SITES; `EchoelStudioView`'s `param`/`knob`
    /// helpers each render many rows from one site, so the number of affected ROWS is larger.)
    ///
    /// ⚠️ THE SAFETY PROPERTY, and it is why the slice is cut at a threshold: below an
    /// accessibility size NOTHING here changes — same `HStack`, same pin, byte for byte. There
    /// is no simulator in this repo; a layout change nobody can run is a wager, one that only
    /// fires above a threshold and leaves the default path alone is not.
    ///
    /// The label-less callers (one today: the chrome's compact BPM box) are deliberately NOT
    /// covered. They render the box alone, so there is no label to rescue, and dropping their
    /// pin would make a chrome field greedy inside a bar whose geometry other guards pin
    /// (#365/#382). Their own width story is `boxWidth` + `compactWidthProbe`, already scaled.
    private var stacksLabel: Bool { !label.isEmpty && dynamicTypeSize.isAccessibilitySize }

    /// The box's fixed width, or nil once the label has stepped out of its way. nil is not
    /// "unbounded": the number inside already carries `.frame(maxWidth: .infinity)`, so the box
    /// takes exactly what the parent proposes — the full row it now has to itself.
    private var pinnedBoxWidth: CGFloat? {
        if stacksLabel { return nil }
        return boxWidth.map { $0 * compactWidthProbe / 100 } ?? valueWidth
    }

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

    /// Whether a SIDEWAYS drag adjusts this field. Default `true` — the founder's 2026-07-12
    /// "both axes" decision, and correct for every field that lives in a vertical panel, where
    /// nothing else wants the horizontal direction.
    ///
    /// ⛔ SET IT `false` FOR ANY FIELD INSIDE A HORIZONTALLY SCROLLING CONTAINER, and #391 is
    /// why. The header chip strip is a `ScrollView(.horizontal)` (`WorkspaceView.swift`), and
    /// the Concert-pitch A4 field sits in it. Scrolling that strip with a finger that happens to
    /// land on the field fed the scroll's own travel into `dxStep` — so the gesture that moves
    /// the strip sideways ALSO raised the global tuning reference. On the founder's 2026-08-02
    /// screen recording (v10.79.366) A4 went 440 → 483.4352 → 500.0000 Hz, the range ceiling,
    /// without the keypad ever opening. `onCommit` then posts "a4", which retunes every voice
    /// and recomposes the running take, and the value is persisted — so it survives relaunch.
    ///
    /// This is not a bug in the "both axes" decision. It is that decision meeting a later layout
    /// choice: when it was made, no `EchoelValueField` lived inside a horizontal scroll. The
    /// axis is opted out per call site rather than removed, because in a vertical panel it is
    /// still the faster gesture the founder asked for.
    ///
    /// ⭐ IT IS NOW TWO MECHANISMS, NOT ONE, and reading this flag as "zeroes `dxStep`" is how a
    /// future edit removes half of it without noticing. #391 zeroed the x contribution; #392 made
    /// the same fields also DECLINE to anchor while a gesture is dominantly sideways (the anchor
    /// branch in `scrubGesture` carries the reasoning). The first alone left the residual named
    /// here before: a sideways sweep carries vertical jitter, and on a 380…500 Hz range that is
    /// still a handful of Hz per swipe on the one value that retunes every voice. The second is
    /// the axis-dominance test that residual asked for — deliberately not a bigger dead zone,
    /// which would tax the deliberate drag too.
    ///
    /// ⚠️ WHAT IS STILL NOT CLAIMED: a gesture that begins dominantly VERTICAL and then travels
    /// sideways anchors and keeps adjusting on the y axis alone. That is correct — it is a
    /// deliberate drag — but it means "the number cannot move while the strip scrolls" is a
    /// statement about how the sweep STARTS, not a guarantee over the whole gesture.
    var horizontalScrub: Bool = true

    /// Presents the shared numeric keypad (tap-to-type path).
    @State private var showPad = false

    // Drag state (incremental deltas, so the value never jumps mid-gesture).
    @State private var scrubbing = false
    /// The value when this gesture began — the reference `onEnded` measures the commit against,
    /// and the value a cancelled gesture is put back to (#378).
    ///
    /// ⛔ IT OUTLIVES THE FALLING EDGE BY ONE MAIN-ACTOR TURN, AND THAT IS DELIBERATE. Everything
    /// else a gesture latches is dropped synchronously when `dragActive` falls; this one is not,
    /// because a normal `onEnded` delivered after the falling edge still has to measure `moved`
    /// against it. Nilling it there is what would silently drop a legitimate `onCommit()`. The
    /// deferred cancellation task nils it — but only on the branch where it has established that
    /// no `onEnded` came and no new drag started, i.e. where nobody else owns it.
    @State private var scrubStartValue: V?
    /// The gesture's UN-SNAPPED running target (#376). The stored `value` is snapped to the
    /// display grid, so accumulating into it throws away everything finer than half a grid unit
    /// on every event; this keeps the intent. nil while no drag is in flight — cleared
    /// synchronously at the falling edge, so a drag starting in the same turn cannot inherit it.
    @State private var scrubTarget: Double?
    @State private var lastY: CGFloat = 0
    @State private var lastX: CGFloat = 0
    /// Timestamp of the previous drag event — the basis for the speed measurement that
    /// decides fine vs. full travel (see `ScrubPrecision`). Comes from the gesture itself,
    /// never from a clock read, so it stays in step with the events it describes.
    @State private var lastTime: Date = .distantPast

    /// Counts gestures. Stamped once per drag, in the anchor branch.
    ///
    /// ⛔ ITS FIRST VERSION COULD NOT FIRE IN THE WINDOW ITS OWN DOC CLAIMED TO COVER, and both
    /// #378 reviewers found it independently. The stamp lives inside `if !scrubbing`, and that
    /// commit's watcher left `scrubbing` standing until the deferred task ran — so a drag
    /// starting inside the hop skipped the anchor branch, never bumped the counter, and the task
    /// happily reverted the new drag's value under the user's finger. The guard was not weak, it
    /// was unreachable. It works now because the falling edge unlatches `scrubbing`
    /// SYNCHRONOUSLY: a drag starting in that turn re-anchors, bumps this, and the task sees a
    /// number it does not recognise. Only equality across one main-actor hop is ever asked of it.
    @State private var gestureSeq: Int = 0

    /// The `gestureSeq` of the last drag whose `onEnded` actually ran.
    ///
    /// ⭐ THIS IS WHAT REPLACED AN ORDERING ASSUMPTION WITH AN OBSERVATION. #378 first argued that
    /// after one main-actor hop, `scrubbing` still being true "PROVES" `onEnded` did not run —
    /// which is not a proof but a claim about SwiftUI's dispatch, and the penalty for it being
    /// wrong had just grown from nothing to destructive (a late `onEnded` would find the value
    /// already reverted, compute `moved == false`, and drop the user's finished edit). `onEnded`
    /// now says so itself, first thing it does. The task asks a recorded fact instead of
    /// inferring one — for every order in which `onEnded` arrives BEFORE the deferred task. The
    /// remaining order (task first, `onEnded` late) is covered by `revertedGesture` below, not by
    /// this. Two mechanisms, because one of them cannot see the other's case.
    @State private var endedSeq: Int = 0

    /// The receipt a deferred cancellation leaves: which gesture it reverted, the number it took
    /// away (`from`), and the number it put back (`to`). `onEnded` tears it up — see the long
    /// note at that call site.
    ///
    /// ⚠️ IT IS NOT NIL WHENEVER NO REVERT IS OUTSTANDING, which is what this line claimed. After
    /// a TRUE cancellation nothing tears the receipt up — `onEnded` never comes — so it holds a
    /// `V` and an `Int` until some later gesture's `onEnded` clears it. Harmless (the `r.seq ==
    /// gestureSeq` check makes a stale receipt unreadable), but the precise statement is "nil
    /// whenever no revert is UNANSWERED", and the difference is what a reader debugging this
    /// would trip over.
    ///
    /// ⚠️ `from` AND `to` ARE BOTH `V`, so a future edit that writes the receipt positionally —
    /// `(gestureSeq, lastWritten, start)`, which compiles, Swift does not enforce labels when
    /// they are omitted — could swap them, invert the undo, and type-check clean. Today the only
    /// thing standing in the way is that `ScrubNotifiesOnlyOnRealChangeTests` pins the LABELLED
    /// literal. If this ever stops being a tuple, a memberwise `private struct` is the reason.
    ///
    /// ⛔ IT EXISTS BECAUSE `endedSeq` IS ONLY HALF AN ANSWER, and the first #378 Nachlese said
    /// otherwise ("both orders are correct again"). `endedSeq` can only be read if `onEnded`
    /// already ran; for the order where it has NOT run yet, the task cannot distinguish "never
    /// coming" from "not here yet", and no amount of guarding changes that. Making the revert
    /// reversible is what removes the question instead of re-asking it.
    @State private var revertedGesture: (seq: Int, from: V, to: V)?

    /// True for exactly as long as SwiftUI considers a drag to be in flight (#377).
    ///
    /// ⛔ THE ONLY PIECE OF GESTURE STATE HERE THAT SURVIVES A CANCELLATION CORRECTLY, and that
    /// is the whole reason it exists. SwiftUI does NOT call `onEnded` when a gesture is
    /// cancelled — which is precisely what the surrounding `ScrollView` does when it decides a
    /// drag was a scroll — so every `@State` latch above stays standing, and the NEXT drag skips
    /// the anchor branch and inherits the abandoned gesture's references. `@GestureState` is the
    /// one property wrapper SwiftUI resets by itself in that case; watching it fall back to
    /// `false` is therefore the cancellation signal the gesture callbacks cannot give us.
    @GestureState private var dragActive = false

    /// Drag distance (points) that covers the FULL range at normal speed — small, so
    /// the fader feels fast/direct (the old velocity-scrub felt stiff).
    private let fullRangePoints: Double = 200

    var body: some View {
        // With a label, the caption sits left and the box trails (aligned columns) — BELOW an
        // accessibility text size. Above it the label steps ABOVE the box and the box drops its
        // width pin; see `stacksLabel`. Three branches, and the middle one is the newest.
        // With an EMPTY label (compact strips — e.g. the timeline lane gain) render
        // JUST the box: the leading Text + expanding Spacer would otherwise reserve
        // ~30 pt of dead width and blow the box past its host column. One caller uses
        // label:"" today (the lane mix strip); this keeps that field as small as its box.
        Group {
            if label.isEmpty {
                valueBox
            } else if stacksLabel {
                // Label ABOVE the box at accessibility text sizes (see `stacksLabel`). The
                // label loses `lineLimit(1)`/`minimumScaleFactor` on purpose: on its own line
                // it has the whole row, so it should WRAP rather than shrink — shrinking is the
                // behaviour that made the row unreadable to the person who asked for bigger
                // text. `fixedSize(vertical:)` is what lets it claim the second line; without
                // it a tight parent proposal still truncates to one.
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(EchoelTheme.font(14))
                        .foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    valueBox
                }
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
        // (10 argument sites — 4× `visualPresetDiverged()` [the visual-preset chip; a bare
        // `visualPresetID = ""` until #379], 5× `applySoundLive()`,
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
            // clamps, so the value is unchanged — and one of the ten closures still does
            // something destructive with an unchanged value: `applyArticulation()` overwrites
            // hand-tuned Attack/Decay/Sustain/Release from an articulation that did not move.
            // Swiping past the top must not undo work. (The other one, `visualPresetID = ""` on
            // four sites, was closed at its owner by #379.) (This was the ONLY guarded path until #375; the drag and keypad paths tested
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
                // THE CANCELLATION PATH (#377 + #378). `onEnded` is not called when the
                // surrounding ScrollView claims the drag, so this is the only place a cancelled
                // gesture can be handled at all.
                //
                // ⛔ TWO HALVES, AND SPLITTING THEM IS THE WHOLE #378 NACHLESE. The falling edge
                // must do two different things at two different times:
                //
                //   UNLATCH — synchronously, right here. `scrubbing` and `scrubTarget` are what a
                //   NEXT drag would inherit, so they cannot be allowed to outlive this turn. The
                //   first #378 deferred this too and thereby re-opened the very stale-latch window
                //   #377 was written to close: a drag starting inside the hop skipped the anchor
                //   branch and measured its first delta against the abandoned gesture's
                //   translation — the #375/#376 teleport class, back again.
                //
                //   REVERT — one main-actor turn later, because "was this a cancel or a normal
                //   end" genuinely cannot be answered synchronously. `onEnded` may be delivered
                //   after this closure (`TimelineAutomationRow.handleEnded` documents the same
                //   wrapper resetting before its callback), so a synchronous revert would undo an
                //   edit the user finished.
                //
                // ⭐ THE HOP IS NOT THE ANSWER, AND NEITHER IS `endedSeq` ALONE. The two guards
                // here ask a recorded fact — did a new drag take over (`gestureSeq`), did THIS
                // gesture end normally (`endedSeq`) — instead of assuming a dispatch order. The
                // first #378 asked `scrubbing` and called that a proof; it is not, and being
                // wrong would have cost a legitimate `onCommit()` silently and intermittently.
                //
                // ⛔ AN EARLIER VERSION OF THIS BLOCK SAID THE TWO GUARDS SETTLE IT ("only when
                // all three say no is this a cancellation nobody else has spoken for" — it also
                // counted `value == wrote`, which lives in `revertCancelled`, not here). They do
                // not settle it, and the declaration of `revertedGesture` says so in capitals:
                // `endedSeq` is only READABLE once `onEnded` has run, so for the order where it
                // has not, the task cannot tell "never coming" from "not here yet". That order is
                // covered by making the revert REVERSIBLE (the receipt `onEnded` tears up), not
                // by any guard on this line.
                //
                // This paragraph outlived its own retraction by one commit — it is the block a
                // maintainer reads first, and it was still teaching the rule the file elsewhere
                // withdrew. When a claim is retracted, grep the file for the places that repeat
                // it; a doc contradicting itself across three hundred lines is the exact defect
                // #378's Nachlese fixed for `unlatchScrub`/`resetScrubState`.
                //
                // ⚠️ ONE HOP PER GESTURE END, WHICH IS NOT THE THING THE LAW FORBIDS. CLAUDE.md
                // bans `Task { @MainActor }` PER FRAME from a high-rate producer (10.76.48, the
                // camera flood that starved the SwiftUI executor). `dragActive` has exactly one
                // falling edge per gesture, so this is one task per drag.
                //
                // ⚠️ HONEST LIMIT (unchanged): if SwiftUI ever stops re-evaluating this view
                // when it resets a `@GestureState` — documented behaviour, and this repo already
                // depends on it in `TimelineAutomationRow`, but not something a test here can
                // execute — this closure never runs. That leaves the value moved and the latch
                // standing, i.e. exactly the pre-#377 state, not a new failure.
                //
                // The parameter is `inFlight`, NOT `active`: `valueBox` binds `let active =
                // scrubbing || showPad` in this same file. Shadowing it compiles, and if anyone
                // ever shortens this closure to `{ _, _ in }` the guard would silently bind the
                // OUTER `active` and invert into a condition that is never true — a dead
                // cancellation path with both guards still green.
                .onChange(of: dragActive) { _, inFlight in
                    guard !inFlight, scrubbing else { return }
                    let seq = gestureSeq
                    let start = scrubStartValue
                    let wrote = value
                    unlatchScrub()
                    Task { @MainActor in
                        guard gestureSeq == seq, endedSeq != seq else { return }
                        revertCancelled(to: start, lastWritten: wrote)
                    }
                }
        }
        // nil once the label has stepped above the box — see `pinnedBoxWidth`. A pin that
        // scales is right while the box shares a line with a label; once it has the line to
        // itself the pin can only overflow it.
        .frame(width: pinnedBoxWidth)
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
            // The ONLY purpose of this `.updating` is that SwiftUI owns the reset (#377): it
            // puts `dragActive` back to `false` on a normal end AND on a cancellation, and the
            // cancellation is the case no gesture callback is called for. Nothing reads the
            // value inside the gesture; the watcher on the drag layer does. It is a pure state
            // side-channel — recognition, the 8 pt `minimumDistance` and arbitration against the
            // parent ScrollView are untouched.
            .updating($dragActive) { _, active, _ in active = true }
            .onChanged { g in
                if !scrubbing {
                    // ⭐ THE OTHER HALF OF #391 (#392). Zeroing the x contribution stopped the
                    // header scroll from DRIVING the A4 field; it did not stop the field from
                    // reading that gesture's vertical wobble. A thumb sweeping a chip strip
                    // wanders several points up and down, and on a 380…500 Hz range over
                    // `fullRangePoints` that is still a handful of Hz per swipe — the same
                    // defect, quieter, on the one value that retunes every voice.
                    //
                    // So a field that has opted OUT of the sideways axis also declines to
                    // anchor while the gesture LOOKS like the scroll it opted out of. This is
                    // the axis-dominance test the `horizontalScrub` doc named as the next step,
                    // and it is deliberately not a bigger dead zone: a dead zone taxes the
                    // deliberate drag too.
                    //
                    // ⚠️ NO NEW LATCH, BY DESIGN — `resetScrubState`'s doc asks for exactly that
                    // ("a future seventh latch belongs in the anchor branch first"). Declining
                    // simply leaves `scrubbing` false, so this branch re-runs on the NEXT event,
                    // and when it does anchor it seeds `lastY`/`lastX`/`lastTime` from the SAME
                    // cumulative translation the next event measures against — so the first
                    // post-anchor delta is one frame's worth and there is no teleport.
                    //
                    // ⛔ WHAT THIS COMPARISON IS, SAID EXACTLY, because the first version of this
                    // block said something else and it is the failure class this repo keeps
                    // paying for (`3ac7f3b`: "its own doc described a check it did not
                    // implement"). It claimed "a sweep that turns into a deliberate vertical drag
                    // anchors AT THAT MOMENT". It does not. `g.translation` is CUMULATIVE from
                    // the gesture's start, so anchoring needs the total vertical travel to
                    // overtake the total sideways travel — sweep 120 pt right, then drag 60 pt
                    // straight down, and the field is still declining. Only past 120 pt of
                    // downward travel does it take over.
                    //
                    // ⭐ AND THAT IS THE RIGHT COMPARISON, not a limitation to fix later. The
                    // per-EVENT alternative — comparing this frame's dx and dy — reopens the very
                    // defect: a wobbling sweep has individual frames at the turn of each wobble
                    // where |dy| exceeds |dx|, so it would anchor mid-scroll and start reading
                    // the jitter again. Cumulative is what makes "this gesture is a scroll" a
                    // property of the gesture rather than of one frame. The cost is that
                    // adjusting after a sweep wants a lift and a fresh press — cheap, and the
                    // gesture that does it is not one anybody performs by accident.
                    //
                    // (Exact ties anchor rather than decline: 45° is not "dominantly sideways",
                    // and (0,0) cannot occur behind the 8 pt `minimumDistance`.)
                    //
                    // ⛔ `revertedGesture` MUST BE DROPPED HERE, and missing it would have been
                    // a silent regression rather than a missing feature. `onEnded` DOES fire for
                    // a drag this branch declined, and a decline leaves `gestureSeq` untouched —
                    // so a receipt left by the PREVIOUS gesture's cancellation would still match
                    // `r.seq == gestureSeq`, and `onEnded` would undo that revert and re-apply
                    // the value #378 just took back. For a normally anchored drag the `&+= 1`
                    // below is what makes the stale receipt unreadable; a decline has to say it
                    // outright.
                    //
                    // ⚠️ NARROWER THAN IT SOUNDS, and worth stating so the guard is not read as
                    // covering more than it does: when the ScrollView actually CLAIMS the sweep —
                    // the ordinary case this flag exists for — the gesture is cancelled and
                    // `onEnded` is never called (see the three places this file says so). The
                    // sequence above therefore needs a dominantly-sideways drag that ends
                    // NORMALLY: a sideways wiggle that stays inside the field, or a sweep the
                    // ScrollView loses arbitration over. Reachable, and cheap to close.
                    //
                    // ⚠️ RE-RUNNING THIS ASSIGNMENT IS VALUE-IDEMPOTENT, NOT FREE — the first
                    // version of this note called it "idempotent" full stop, which invites the
                    // next reader to assume the write costs nothing. `revertedGesture` is a
                    // `@State` holding a non-`Equatable` tuple, so whether SwiftUI elides the
                    // invalidation is not something this repo can answer. Bounded either way: the
                    // state belongs to this leaf, so any churn stays inside it (the 10.76.50
                    // ancestor law is not engaged), and the path it replaces wrote SIX `@State`
                    // vars per event on the same gesture — strictly cheaper than before.
                    if !horizontalScrub,
                       abs(g.translation.width) > abs(g.translation.height) {
                        revertedGesture = nil
                        return
                    }
                    scrubbing = true
                    gestureSeq &+= 1               // identifies THIS drag to the cancel check
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
                // …unless the field sits in a horizontally scrolling container, where the
                // sideways direction already belongs to the scroll (#391 — see the
                // `horizontalScrub` doc; the A4 field rode a header scroll to 500 Hz).
                let dyStep = Double(lastY - g.translation.height)
                let dxStep = horizontalScrub ? Double(g.translation.width - lastX) : 0
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
                //
                // ⛔ AND IT MUST SNAP THE STORED SIDE TOO (#427 review). Raw equality held for a
                // stored binding and failed on 62 of 101 positions for a DERIVED one, which put
                // the one visual control back in the pre-#376 dead zone. The whole argument,
                // with the measurements, is on `ScrubPrecision.carriesTarget`.
                let base: Double
                if let running = scrubTarget,
                   ScrubPrecision.carriesTarget(running, value: value,
                                                lowerBound: lo, upperBound: hi,
                                                decimals: decimals) {
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
                // the screen), which is why that was a doc correction and not an open defect.
                //
                // AND THE REST HAS A HANDLER SINCE #377 — stated as a mechanism, not a tick,
                // because the same file carries an "⚠️ HONEST LIMIT" about it and two tenses for
                // one fact is how a doc starts lying: `dragActive` is a `@GestureState`, the one
                // wrapper SwiftUI resets by itself on cancellation, and `.onChange(of:)` on the
                // drag layer unlatches when it falls back to `false` — and, one main-actor turn
                // later, puts the value BACK unless this callback got there first (#378). This
                // callback was ALWAYS the normal end only — what changed is that the cancelled
                // case stopped having no handler at all. It must NOT restore anything itself:
                // here the edit is finished.
                //
                // ⭐ THE STAMP IS THE FIRST STATEMENT. It is the only record that this gesture
                // ended legitimately, and the deferred cancellation task reads it. Written after
                // `resetScrubState()` it would still be correct today, but the lines below are
                // about the commit and this one is about a different reader entirely.
                // (⛔ An earlier version of this note claimed being first makes it "impossible"
                // for a later edit to put an early `return` in front of it. Position is not a
                // barrier — nothing prevents that, and no guard here checks it. Kept first
                // because it is clearer, not because it is enforced.)
                endedSeq = gestureSeq

                // ⭐ THE UNDO OF AN UNDO — the last ordering assumption in this file, closed.
                //
                // Both #378 reviewers found the same residual hole and I could not talk it away:
                // if the deferred task runs BEFORE a late `onEnded`, the revert has already put
                // `start` on screen and nilled `scrubStartValue`, so the `moved` line below
                // computes `false` and the user's FINISHED edit is dropped — reverted on screen,
                // never committed. That is verbatim the failure `6046db7` refused in writing and
                // the failure #378's Nachlese claimed to have removed. `endedSeq` alone does not
                // remove it: it is only READABLE if `onEnded` got there first, which is the same
                // dispatch assumption in a new coat.
                //
                // So the revert is no longer final. It leaves a receipt, and this callback tears
                // it up: the gesture ended, therefore the cancellation was a misreading, therefore
                // the number goes back to what the user actually dragged it to — and commits.
                // `value == r.to` yields to anyone who wrote in between, same rule as the revert.
                //
                // ⚠️ HONEST SCOPE: neither reviewer could construct an interleaving on iOS that
                // reaches this branch — a `Task` enqueued from the main actor drains after the
                // current run-loop callout, and `onEnded` is delivered inside it. This is
                // insurance against an assumption, not a fix for an observed bug. It is worth its
                // twelve lines because the assumption is the one thing three commits in a row got
                // wrong here, and because being wrong costs a finished edit silently.
                //
                // ⚠️ AND IT IS NARROWER THAN "THE EDIT IS SAFE NOW" — named by the #378 reviewer,
                // recorded rather than fixed. When `value == r.to` YIELDS (a foreign writer moved
                // the number between the revert and this callback), we fall through to the `moved`
                // line — but `revertCancelled` has already nilled `scrubStartValue`, so `moved`
                // computes false and the finished edit is dropped anyway. So this covers
                // "revert → late onEnded" and NOT "revert → foreign write → late onEnded". The
                // remaining case is one interleaving deeper inside a branch nobody could reach in
                // the first place, and closing it would mean tracking this gesture's own last
                // write. Stated so the next reader does not mistake the insurance for a proof.
                //
                // ⚠️ ONE SIDE EFFECT OF THE UNDO, also from that review: in the covered order the
                // number goes v1 → v0 → v1 with TWO `onChange()` fires, so a normally-ended
                // gesture can run the live-apply closures twice. Harmless for a pure apply; the
                // one closure for which it would not be harmless is `applyArticulation()` (see
                // `revertCancelled`'s doc), and it is idempotent in the value, so re-running it
                // costs the same hand-tuned envelope once rather than twice.
                if let r = revertedGesture, r.seq == gestureSeq, value == r.to {
                    revertedGesture = nil
                    value = r.from
                    onChange()
                    resetScrubState()
                    onCommit()
                    return
                }
                revertedGesture = nil

                let moved = scrubStartValue.map { $0 != value } ?? false
                resetScrubState()
                if moved { onCommit() }
            }
    }

    /// A drag SwiftUI took away, undone (#378).
    ///
    /// ⭐ THE DECISION, delegated by the founder 2026-08-01 ("Du bist souveräner entscheider")
    /// and made here: a cancelled gesture puts the number BACK. A cancellation means SwiftUI
    /// reassigned the drag to the surrounding ScrollView, so every event this field processed
    /// before that ruling was a misattribution — the honest response to "that was a scroll" is
    /// to leave nothing behind. It is also the direct answer to the founder's #360 report (four
    /// weather mixers found reading 0.00 after scrolling), and #376 made it more pressing rather
    /// than less: before #376 an accidental scroll-drag below the display grid could not write
    /// at all, and now it can.
    ///
    /// It re-fires `onChange()` because the live-applies already pushed the moved value into the
    /// engine; restoring the number without telling them would leave the screen and the sound
    /// disagreeing, which is worse than either state alone. It does NOT fire `onCommit()` —
    /// nothing was finished.
    ///
    /// ⛔ IT YIELDS TO ANY OTHER WRITER, AND THE FIRST VERSION DID NOT — which broke the rule the
    /// commit one before it had just established. `544ac8f` is titled "die Geste darf ihr Ziel
    /// nicht behalten, wenn ein anderer den Wert geschrieben hat" and added exactly this check to
    /// the per-event branch. Real writers exist — `AutomationPlayer` rewrites `masterVolume` and
    /// the tempo every tick, and the tempo write additionally cancels an in-flight glide.
    ///
    /// ⚠️ THE CHECK COVERS THE HOP, NOT THE GESTURE, and the first version of this doc claimed
    /// more than that ("`lastWritten` is what this gesture last put on screen"). It is not: it is
    /// simply `value` AT THE FALLING EDGE. If another writer moved the number DURING the drag,
    /// `lastWritten` is already their number, the check passes, and the revert takes the field
    /// back to `start` — undoing them. Narrowing that would mean tracking this gesture's own last
    /// write; it is not tracked today, and the window it would close is a whole gesture rather
    /// than one main-actor turn. Written down rather than fixed, so the next reader knows which.
    ///
    /// ⚠️ IT RESTORES THIS FIELD'S NUMBER, NOT THE WORLD. `EchoelStudioView` has 10 `onChange`
    /// closures spread over 25 fields (two of the ten are the `param`/`knob` helpers, which fan
    /// out to 17 rows). ONE KIND of them still destroys user work when re-run with an unchanged
    /// number: `applyArticulation()` re-derives Attack/Decay/Sustain/Release from the macro,
    /// overwriting a hand-tuned envelope.
    ///
    /// ⛔ TWO DIFFERENT ERRORS LIVED IN THIS PARAGRAPH. Keep them apart — one is arithmetic, the
    /// other is judgment, and only the second is interesting.
    ///
    /// (1) THE COUNT. It read "TWO of them", meaning two KINDS, in a sentence whose other numbers
    /// are SITES. `visualPresetID = ""` sat on FOUR sites and `applyArticulation()` on one: five
    /// sites, two kinds. The sibling `ScrubNotifiesOnlyOnRealChangeTests` had it right the whole
    /// time ("(4×)", "(1×)"). Mixing the two units inside one sentence, in a file that lectures
    /// twenty lines further up about never quoting an unmeasured number, is the same defect one
    /// size smaller.
    ///
    /// (2) THE RETRACTION OF A RETRACTION, which is the part worth keeping. The first #378
    /// Nachlese "corrected" two to one, arguing that `applyArticulation()` is a pure function of
    /// the restored number and therefore comes back with it. Pure it is — but its four outputs
    /// are INDEPENDENTLY EDITABLE rows (`param("Attack", $currentPatch.attack, …)` and its three
    /// neighbours in `EchoelStudioView`), so re-deriving them restores the macro's envelope, not
    /// the one the user shaped by hand. One reviewer asked me to propagate the "one" to three
    /// more places; the other refuted it outright. The source settled it. The lesson is not
    /// "trust the second reviewer" — it is that a retraction needs the same evidence a claim
    /// does, and mine had none.
    ///
    /// #379 CLOSED THE OTHER KIND, WHERE IT BELONGED. The four visual-energy rows now call
    /// `visualPresetDiverged()`, which takes the cleared preset id into a memo and hands it
    /// straight back when the four values still match that preset — so a re-run with an unchanged
    /// number is a no-op BY CONSTRUCTION rather than by this field's guard. That fix is in the
    /// owner (`EchoelStudioView`), not here, because a control with 62 call sites has no business
    /// knowing what a preset is. `applyArticulation()` is untouched and belongs to its own row.
    // The block below leaves a receipt (`revertedGesture`) that a late `onEnded` uses to undo
    // this revert — see that call site. The note sits ABOVE the block on purpose: the guard in
    // `ScrubNotifiesOnlyOnRealChangeTests` matches whitespace-squashed source that still contains
    // comments, so an inline `//` inside a pinned block reddens the blocking gate for prose.
    private func revertCancelled(to start: V?, lastWritten: V) {
        if let start, start != lastWritten, value == lastWritten {
            value = start
            onChange()
            revertedGesture = (seq: gestureSeq, from: lastWritten, to: start)
        }
        // Safe unconditionally: the two guards at the call site have already established that no
        // `onEnded` ran for this gesture and no new drag anchored, so nobody else owns it.
        scrubStartValue = nil
    }

    /// Ends the gesture as far as a NEXT drag is concerned. Called synchronously at the falling
    /// edge of `dragActive`.
    ///
    /// ⭐ `scrubbing = false` IS THE CORRECTNESS-BEARING LINE; `scrubTarget = nil` IS HYGIENE.
    /// (⛔ The first version of this doc said it "drops what a NEXT drag could inherit — and
    /// nothing else", which is wrong in both halves and would mislead the next maintainer twice.
    /// `lastY`/`lastX`/`lastTime` are equally inheritable and are NOT dropped here; and the
    /// reason a hop-drag inherited anything at all was that `scrubbing` stayed true, so the
    /// anchor branch was skipped. Clear `scrubbing` and the anchor branch re-seeds all six —
    /// which is exactly what `resetScrubState`'s doc says, and the two must not teach opposite
    /// rules about the same field. Do not "complete" this by moving the other three in.)
    ///
    /// ⛔ `scrubStartValue` IS DELIBERATELY NOT IN HERE, AND THAT ASYMMETRY IS THE POINT.
    /// `onEnded` may still be delivered after this runs, and it measures `moved` against
    /// `scrubStartValue` — nilling it here is what would silently drop a finished edit's
    /// `onCommit()`. So: unlatch now, drop the reference only on the branch that proves nobody
    /// else wants it.
    private func unlatchScrub() {
        scrubTarget = nil
        scrubbing = false
    }

    /// The NORMAL end's cleanup: drops the two references a gesture holds and unlatches.
    ///
    /// ⛔ IT DOES NOT CLEAR EVERYTHING A GESTURE ACCRUES, and the first version of this doc said
    /// it did. Six things accrue — `scrubbing`, `scrubStartValue`, `scrubTarget`, `lastY`,
    /// `lastX`, `lastTime` — and this clears three. That is harmless for one reason worth
    /// stating: THE ANCHOR BRANCH IS THE AUTHORITY. `onChanged` re-seeds all six unconditionally
    /// whenever it finds `scrubbing == false`, so nothing stale can ever be READ; clearing is
    /// hygiene, not correctness. A future seventh latch belongs in the anchor branch first — if
    /// it is seeded there, it needs nothing here.
    ///
    /// ⚠️ ONE CALLER AGAIN. For one commit (#378's first version) the cancellation path called
    /// this too, from inside a deferred task, justified by "after one hop, `scrubbing` still
    /// being true is PROOF that `onEnded` did not run". That was not a proof but an assumption
    /// about SwiftUI's dispatch, and if it were ever wrong the late `onEnded` would find
    /// `scrubStartValue` already nil, compute `moved == false`, and drop a legitimate commit —
    /// silently and intermittently. The cancellation path now unlatches synchronously
    /// (`unlatchScrub`) and drops the reference itself only after `endedSeq` says no normal end
    /// happened. Do not re-merge the two.
    private func resetScrubState() {
        scrubStartValue = nil
        scrubTarget = nil
        scrubbing = false
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
    ///
    /// GRIDDED FIRST (#432). `EchoelDecimalText.string` is `printf`, which rounds half-to-even;
    /// `apply` rounds half-away. Formatting the raw value let this row print "0.12" for a
    /// stored `0.125` that the very next touch would write as `0.13`. One rounding rule per
    /// control: the readout describes the grid cell the row would keep. No clamp — see
    /// `ScrubPrecision.gridded`; a readout must not claim a value is inside a range it is not.
    private var numberString: String {
        EchoelDecimalText.string(ScrubPrecision.gridded(Double(value), decimals: decimals),
                                 decimals: decimals)
    }
}
#endif
