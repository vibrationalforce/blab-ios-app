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
//     six seconds later — while the doc two lines up promised "a user edit stays instant".
//
//  3. ⚠️ AND THE DIAGNOSTIC INHERITED IT TOO. `generate(…)` prints `sinceLast=` from the same
//     variable (#390). With a claimed floor in it that field reported the distance to a re-seed
//     that had not happened — negative, or far too small. The founder is asked to send that log
//     to settle whether the "unharmonisch" verdict is re-seed overlap; a field that can lie is
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
    static func decide(auto: Bool,
                       sinceLastSeed: TimeInterval,
                       untilFloor: TimeInterval) -> Decision {
        // NaN-safe by construction: a non-finite input becomes the conservative full gap rather
        // than propagating through `max` (where argument order decides NaN behaviour — see the
        // `clamped(to:)` note in CLAUDE.md). This has caused shipped silence bugs elsewhere.
        let elapsed = sinceLastSeed.isFinite && sinceLastSeed >= 0 ? sinceLastSeed : 0
        let claim = untilFloor.isFinite ? untilFloor : 0

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
