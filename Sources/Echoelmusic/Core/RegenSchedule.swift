// RegenSchedule.swift
// Echoel — when may the music re-seed? One arithmetic, two facts, no overloaded date.
//
// WHY THIS IS ITS OWN FILE. The rule used to live inline in `EchoelStudioView.scheduleGenerate`
// and it kept ONE `Date` (`lastSeedAt`) meaning two different things: "when a take was actually
// generated" and "the earliest instant the next automatic re-seed may run". Those are not the
// same fact, and writing the second into the variable that holds the first produced two defects
// that contradicted the function's own comment:
//
//  1. ⛔ CO-FIRING AUTO TRIGGERS PUSHED THE RE-SEED AWAY INSTEAD OF COLLAPSING INTO IT. The
//     comment promised "the next auto trigger compute[s] a full gap and collapse[s] into it — no
//     rapid burst of re-seeds". The code computed `minAutoSeedGap - (now - claimedFloor)`, and
//     with the floor in the FUTURE that subtraction ADDS the remaining claim to a full fresh gap.
//     The named case — lock-snap and evolve tick landing together — moved a re-seed claimed for
//     t+5 s out to t+11 s. Every further trigger inside the window added another ~6 s, with no
//     bound. That is not anti-flood, it is an anti-seed lockout, and it is the opposite of what
//     the comment says the line is for.
//
//  2. ⛔ A USER EDIT INHERITED A FLOOR THAT BELONGED TO A TRIGGER IT HAD JUST CANCELLED.
//     `scheduleGenerate` cancels the pending task on its FIRST line, so by the time the user
//     branch runs, the automatic re-seed whose floor stands in `lastSeedAt` will never happen.
//     The branch still measured against it: `minUserGap - (now - futureFloor)` = 2 s PLUS the
//     whole unspent claim. Change the genre one second into a 6 s claim and the sound followed
//     SEVEN seconds later — while `scheduleGenerate`'s own doc block promised "a user edit stays
//     instant". (⛔ The first version wrote "six seconds" here and in two other files, while the
//     test pinning it computes `minUserGap + 5` = 7 and prints that number in its failure
//     message. A comment that disagrees with its own test by a second is the same defect as an
//     overstated one, running the other way — and this repo strikes overstatement by name, so it
//     has to strike understatement too. The same edit removed "the doc two lines up", which
//     pointed at nothing: the doc it means lives in `EchoelStudioView`, not two lines above.)
//
//  3. ⚠️ AND THE DIAGNOSTIC INHERITED IT TOO. `generate(…)` prints `sinceLast=` from the same
//     variable (#390). With a claimed floor in it that field reported the distance to a re-seed
//     that had not happened. ⭐ THE PRECISE SHAPE MATTERS, because it is what makes the symptom
//     recognisable in a device log: an automatic re-seed runs at exactly the instant it claimed,
//     so `now - lastSeedAt` is ≈ 0 and EVERY automatic generate printed `sinceLast=0.0s`. A
//     NEGATIVE value was reachable only from the direct `generate(…)` callers (Start, the
//     variation maze) firing while a claim stood. The first version said "negative, or far too
//     small" — true but unusable: a reader scanning a log for a minus sign would have found none
//     and concluded the field was fine.
//     ⭐ CONFIRMED ON DEVICE (v10.79.368 build 2485, i.e. the build BEFORE this fix): five of
//     twelve printed intervals were wrong, and all four `evolve` lines read `sinceLast=0.0s`
//     where the real gaps were 6.0 · 6.0 · 13.8 · 15.6 s. One `user-edit` printed 2.0 s for a
//     real 8.8 s gap — consequence 2, in the wild. The founder is asked for exactly that log to
//     settle whether the "unharmonisch" verdict is re-seed overlap; a field that can lie is
//     worse than no field. Splitting the two facts is what makes the next log readable.
//
// THE SPLIT: `lastSeedAt` is written ONLY by `generate(…)`, at run time, and means "a take was
// produced". `seedFloor` is written only by the automatic branch here and means "an automatic
// re-seed is already claimed for this instant". Neither can answer the other's question.
//
// Pure, `Date`-free (callers pass relative seconds), NaN-safe. No audio thread involvement — this
// is control plane only, called from `@MainActor` UI code.

import Foundation

/// The one place that decides how long a pending `generate()` waits.
enum RegenSchedule {

    /// Quiet window every request waits, automatic or not. Scrolling a Picker fires `onChange`
    /// per highlighted option; this coalesces the sweep into one recompose after the hand
    /// settles (device log 1783177585: five generates in four seconds while browsing genres).
    static let quietWindow: TimeInterval = 0.45

    /// The music may not re-seed faster than a musical phrase, no matter how many AUTOMATIC
    /// triggers fire (evolve tick, lock-snap). A user edit is not held to this — it is a
    /// deliberate act, not a flood.
    static let minAutoSeedGap: TimeInterval = 6.0

    /// A user's own floor, and a gentler one: taps 0.7–1.5 s apart (browsing options) slip past
    /// `quietWindow` alone — the same device log shows they did. The LAST edit still wins,
    /// because every call cancels the pending task, so the sound lands on what the user chose.
    static let minUserGap: TimeInterval = 2.0

    /// What to do with one `scheduleGenerate` request.
    struct Decision: Equatable {
        /// Seconds to wait before running `generate()`.
        let delay: TimeInterval
        /// Seconds from NOW at which the automatic floor should be re-claimed, or `nil` when this
        /// request must not touch the floor. Only the automatic branch claims — a user edit
        /// leaves the automatic invariant exactly as it found it, and `generate(…)` re-stamps
        /// `lastSeedAt` on its own when it runs.
        let claimFloorIn: TimeInterval?
    }

    /// - Parameters:
    ///   - auto: `true` for the evolve tick and the lock-snap; `false` for a user edit.
    ///   - sinceLastSeed: `now − lastSeedAt` — how long ago a take was ACTUALLY generated.
    ///     Never negative in practice (`lastSeedAt` is only ever stamped at run time); a
    ///     negative or non-finite value is treated as "no useful measurement" and yields the
    ///     full floor rather than a wait computed from nonsense.
    ///   - untilFloor: `seedFloor − now` — seconds until an already-claimed automatic re-seed.
    ///     `≤ 0` means no claim stands.
    ///
    /// ⭐ THE INVARIANT WORTH KEEPING IN MIND WHILE EDITING THIS: for `auto`, a standing claim is
    /// an UPPER bound to collapse into, never something to add to. `max(gapWait, untilFloor)`
    /// says exactly that — whichever constraint is later wins, and neither is ever summed with
    /// the other. The removed code summed them, which is defect 1 in this file's header.
    ///
    /// ⭐ AND THE PROPERTY THAT ACTUALLY KILLS THE LOCKOUT, which the `max` shape alone does not
    /// give you: **`delay ≤ minAutoSeedGap`, always.** `elapsed ≥ 0` ⇒ `gapWait ≤ gap`; a floor
    /// is only ever set to `now + delay`, so by induction `claim ≤ gap` too (the ceiling on
    /// `claim` above closes the one way an outside value could break that induction). The old
    /// code had no such bound, which is why each co-firing trigger could add another gap without
    /// limit. Any future edit that can produce a `delay` above the gap re-opens defect 1.
    ///
    /// ⭐ AND THE COROLLARY THAT EXPLAINS WHY NOTHING EVER CLEARS `seedFloor` — worth writing
    /// down, because it is exactly what a later reader would otherwise "fix" by adding a reset
    /// on stop: **a claim placed before the last real take can never govern.** If a claim was
    /// placed at `t_c` with `d ≤ gap`, and a generate then actually ran at `t_gen ≥ t_c`, then
    /// `floor ≤ t_c + gap ≤ t_gen + gap`, so `untilFloor ≤ gapWait` at every later instant. A
    /// stale claim is dominated, not obeyed. That is also why honouring a claim whose task was
    /// cancelled is harmless on the automatic path.
    static func decide(auto: Bool,
                       sinceLastSeed: TimeInterval,
                       untilFloor: TimeInterval) -> Decision {
        // NaN-safe by construction: a non-finite input becomes the conservative full gap rather
        // than propagating through `max` (where argument order decides NaN behaviour — see the
        // `clamped(to:)` note in CLAUDE.md). This has caused shipped silence bugs elsewhere.
        let elapsed = sinceLastSeed.isFinite && sinceLastSeed >= 0 ? sinceLastSeed : 0
        // ⛔ THE CEILING IS NOT BELT-AND-BRACES, AND THE FIRST VERSION OMITTED IT WHILE ITS OWN
        // TEST ASSERTED THE PROPERTY IT PROVIDES ("never an unbounded pause"). Sanitising only
        // NaN/±inf leaves a large FINITE claim intact, and one is reachable: `seedFloor` is a
        // wall-clock `Date`, and `Date()` does not advance monotonically. An NTP or timezone
        // correction that steps the clock BACKWARDS by an hour makes `untilFloor` 3600, and the
        // evolve loop then waits an hour — silently, for the rest of the session, with nothing
        // on screen to explain it. (The `elapsed` side was already immune: its `>= 0` guard
        // clamps a backwards jump to 0.) Under normal operation this changes nothing, because a
        // claim is only ever `now + delay` and `delay <= minAutoSeedGap` by the line below.
        let claim = untilFloor.isFinite ? Swift.min(untilFloor, minAutoSeedGap) : 0

        if auto {
            // Two independent constraints, and the LATER one governs:
            //  · a full gap must have passed since a take was actually produced, and
            //  · a re-seed already claimed for a later instant must not be pulled forward.
            let gapWait = minAutoSeedGap - elapsed
            let delay = Swift.max(quietWindow, Swift.max(gapWait, claim))
            return Decision(delay: delay, claimFloorIn: delay)
        }

        // A user edit answers only to the last ACTUAL generate. The standing claim belongs to an
        // automatic trigger that this very call has already cancelled, so letting it add to the
        // wait would delay the user on behalf of something that will never run.
        return Decision(delay: Swift.max(quietWindow, minUserGap - elapsed), claimFloorIn: nil)
    }
}
