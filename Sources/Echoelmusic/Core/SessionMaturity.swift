// SessionMaturity.swift
// Echoel — #568, cycle C4 of the 2026-08-13 handover ("FIRST RUN = f(engineState)").
//
// WHAT IT IS. One pure, testable answer to "how much of the instrument should be on screen
// right now?", derived from how often this install has actually reached the studio. The
// handover's C4 asks for the first runs to show *transport + BodyTempoField + waveform + ONE
// panel (Sound)* and nothing else, with the hidden panels staying in code — reversible, the
// calm-shell precedent (#157). The policy lives here rather than inside `EchoelStudioView`
// so it can be driven end-to-end by a guard; the view owns only the storage and the mapping.
//
// ⚠️ NOT THE `Session*` FAMILY. `SessionContext`, `SessionRecorder`, `SessionNaming` and the
// parked `SessionView`/`SessionEngine` experiment are all about ONE take. This type is about
// the INSTALL — how many times the instrument has been opened at all. The name comes from the
// handover; the distinction is written here so nobody wires it to a take counter by analogy.
//
// ⚠️ WHAT "APPEARANCE" MEANS, stated once, because the honest word is not the flattering one.
// The handover says "session counter". What is actually counted is a LAUNCH THAT REACHED THE
// STUDIO — `EchoelStudioView`'s root `onAppear`, once per process. A user who opens the app
// three times and never presses anything is treated as experienced. The stronger definition
// ("three takes were generated") is more faithful and is deliberately NOT used yet: it needs a
// producer inside the generate path, which is a second slice, and a counter with two writers
// is how a threshold quietly stops meaning what it says. The property is therefore named
// `appearances`, not `sessions` — if the stronger definition ever lands, the rename is the
// signal that the meaning changed.
//
// ⛔ WHAT THIS MUST NEVER DO: strand a capability. The reduced strip removes CHIPS, i.e.
// settings surfaces. It does not touch `quickActionRow` (record · keep-last · MIDI · save),
// `quickDoorRow`, the pulse pill (`.bio`) or the header clips tile (`.video`) — those are
// chrome doors and stay mounted at every maturity. A first-run user can still record, keep and
// save a take; what is withheld is loop length, the place toggle, Reset sound and Diagnostics.
// `visibleChipIDs(from:)` also FAILS OPEN: if the keep-list ever matches nothing (a case
// renamed without this file), it returns the full strip rather than an empty navigation bar.

import Foundation

/// How far along this install is, and what the front plate should therefore show.
///
/// Pure value type, Foundation only, no clock and no storage inside — the caller supplies the
/// count. That is what makes the whole policy drivable from a test bundle that cannot
/// instantiate a `View`.
public struct SessionMaturity: Sendable, Equatable {

    /// `UserDefaults` key for the appearance counter. Declared HERE and read by the view's
    /// `@AppStorage` (#416: one definition per decision — a second spelling of this string is
    /// the defect, whether or not the two agree today).
    public static let defaultsKey = "firstRun.studioAppearances"

    /// Below this many appearances the front plate is simplified. Three is the handover's
    /// number: enough to have heard the instrument answer the body, few enough that the
    /// reduced surface is not what a returning user lives with.
    public static let simplifiedBelow = 3

    /// The chip identifiers (`StudioMenu.rawValue`) that survive the first runs.
    ///
    /// Exactly one: Sound. The transport, the tempo field and the waveform are not chips —
    /// they sit above the plate and are unaffected — so this single entry is the whole of
    /// C4's "ONE panel (Sound)".
    public static let firstRunChipIDs = ["sound"]

    /// Launches that reached the studio. Clamped at zero: a negative count would make
    /// `isLearning` true forever, which is the one direction that cannot self-heal.
    public let appearances: Int

    public init(appearances: Int) {
        self.appearances = Swift.max(0, appearances)
    }

    /// Whether the instrument should present its reduced first-run surface.
    public var isLearning: Bool { appearances < Self.simplifiedBelow }

    /// The chip strip for this maturity, in the caller's order.
    ///
    /// Order is preserved by filtering the caller's array rather than returning
    /// `firstRunChipIDs`: the strip order is the signal chain and a founder-facing decision,
    /// so this policy is allowed to REMOVE entries and never to re-sort them.
    public func visibleChipIDs(from all: [String]) -> [String] {
        guard isLearning else { return all }
        let kept = all.filter { Self.firstRunChipIDs.contains($0) }
        // FAIL OPEN. An empty strip is a broken instrument; a full strip is merely an
        // un-simplified one. If a future rename makes the keep-list match nothing, the user
        // gets everything rather than nothing, and the guard over this says so by name.
        return kept.isEmpty ? all : kept
    }

    /// The next counter value, saturating rather than trapping. An `Int` overflow here is
    /// unreachable in practice and a crash on launch is the worst possible way to be wrong
    /// about a cosmetic threshold.
    public static func next(after appearances: Int) -> Int {
        appearances >= Int.max - 1 ? Int.max : Swift.max(0, appearances) + 1
    }

    /// ⭐ THE UPGRADE CASE, and it is the one #568 shipped without and #571 had to add before a
    /// deploy could be honest. The counter is NEW, so on every device that already has this app
    /// it reads zero — and a zero means "never opened the instrument". Without this, the update
    /// that introduced the first-run surface would have taken SEVEN CHIPS AWAY from every
    /// existing user for three launches. To a person who has been using the app for months that
    /// does not read as onboarding; it reads as a broken update, and it would have burned the
    /// one thing this loop cannot buy back — a founder device round-trip.
    ///
    /// - Parameters:
    ///   - stored: the value already in `UserDefaults`, or nil when the key has NEVER been
    ///     written. Nil is the whole signal — `UserDefaults.integer(forKey:)` answers 0 for both
    ///     "fresh install" and "opened twice", so the caller must ask `object(forKey:)`.
    ///   - hasPriorState: whether this install shows any evidence of earlier use.
    /// - Returns: the counter to start from.
    public static func seed(stored: Int?, hasPriorState: Bool) -> Int {
        if let stored { return Swift.max(0, stored) }   // already counting — never re-seed
        return hasPriorState ? simplifiedBelow : 0
    }

    /// Keys whose PRESENCE proves the instrument was used before the counter existed.
    ///
    /// A prefix rather than a list, and that is safe here for a measured reason: nothing calls
    /// `UserDefaults.register(defaults:)` for any `studio.*` key — the only three registrations
    /// in the app are feature flags — so a `studio.` key exists if and only if something WROTE
    /// it, which only ordinary use does. A hand-written list of individual keys would have to be
    /// maintained forever and would silently under-report the day a key was renamed.
    public static let priorStatePrefix = "studio."
}
