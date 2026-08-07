// PulseCue.swift
// The typed classification behind the rPPG acquisition coaching: ONE source of
// truth for "why isn't the pulse locking", so the full measurement-screen hint and
// the compact header signal never drift. Pure value logic (Foundation only) → the
// full-hint / short-label / actionable mapping is unit-tested on every platform;
// the device publisher decides WHICH case holds from its live analyzer signals.
//
// Motivated by device log 2026-07-14 (v202): the pulse locked (conf 0.83) then the
// finger scene brightened to saturation (bright 0.94) and the lock was lost — but
// while playing, the founder only sees the compact header monitor, which gave NO
// hint the pulse was washing out. `isActionable` lets the header go amber for a
// correctable placement issue so the drop is visible and self-correctable, while
// the exposure state machine itself is left untouched (device-tuned, not blind-fixed).

import Foundation

/// Why the camera pulse is / isn't locking — the coaching state, typed.
public enum PulseCue: Equatable, Sendable {
    /// Camera access is denied/restricted in Settings — no placement coaching can
    /// help; the ONLY fix is re-enabling access there. Without this case the UI
    /// kept saying "Cover camera" forever (UX-1: a silent dead end).
    case cameraDenied
    /// A clean pulse is locked.
    case locked
    /// No finger on the rear camera + flash.
    case coverLens
    /// The lit finger scene is saturated/too bright to extract a pulse.
    case tooBright
    /// The finger is moving / changing pressure (motion swamps the pulse).
    case holdStill
    /// Contact too light — almost no signal.
    case pressGently
    /// Finger placed, dark enough, just still accruing beats (normal warmup).
    case finding
    /// Contact looks FINE by every correctable test above — placed, dark enough, steady,
    /// firm enough — and still nothing has locked for far longer than an acquisition takes.
    /// `.finding` says "wait"; after long enough that stops being true, and repeating it is
    /// the duration blindness device log 2490 exposed: 97 s of "Hold still — finding your
    /// pulse…" with no lock and no suggestion that waiting was no longer the answer.
    ///
    /// ⭐ THE SURFACE DID NOT LIE, AND THAT IS WHY THIS CASE IS SHAPED THIS WAY. My first
    /// reading of that log said the app showed encouraging progress while nothing worked.
    /// Checked instead of assumed: the "exposure locked on finger" line is an
    /// `EchoelCrashLog.breadcrumb` (log file only, never rendered), `signalQuality` has zero
    /// consumers, `displayBPM` never advanced and `isLocked` was false throughout. Every
    /// shown thing was honest. What was missing was not truth but TIME — no surface knows
    /// how long the honest message has been the same one.
    ///
    /// `hasRhythmlessSignal` splits the two failures, because they need OPPOSITE advice:
    ///   · `true` — confidence is at display grade while autocorrelation is not (the band
    ///     `pulseTrustworthy` exists to reject: a peak counter agreeing with itself on a
    ///     signal that is not periodic; #308 carries conf 0.82–0.86 against acf 0.09–0.16
    ///     on device log 2479). Something IS coupling to the lens, it just isn't a heartbeat —
    ///     a moving or venous contact, which re-placing the finger fixes.
    ///   · `false` — neither channel has anything, above the `pressGently` amplitude floor.
    ///     Re-gripping the same finger is the LEAST likely fix here; perfusion is.
    ///
    /// ⚠️ NOT a verdict, and the wording is chosen so it cannot read as one. A take that
    /// would have locked at 50 s shows this at 45 s and then locks anyway. That is not a
    /// false statement — at 45 s waiting has demonstrably not worked yet — but it is advice
    /// with a real false-alarm rate, so neither string claims the pulse is unreadable.
    ///
    /// ⚠️ WHAT THIS DELIBERATELY DOES NOT SAY: "switch to a chest strap". The panel that
    /// hosts the measurement card already carries that route verbatim and correctly
    /// (`EchoelStudioView.bioPanel`: "touch and hold the pulse display and pick …"), and
    /// #416's law plus that panel's own comment — "Saying it three times is not
    /// thoroughness" — make a second copy here a defect, not helpfulness. The chain that
    /// gets a stuck user there is `isActionable`: the header tile goes amber, which is what
    /// opens the panel, which is where the route is written once.
    case stalled(hasRhythmlessSignal: Bool)

    /// The full guidance shown on the measurement screen (unchanged wording).
    public var fullHint: String {
        switch self {
        case .cameraDenied: return "Camera access is off — enable it in Settings to read your pulse"
        case .locked:      return "Locked"
        case .coverLens:   return "Cover the rear camera + flash"
        case .tooBright:   return "Press a little lighter"
        case .holdStill:   return "Hold still — keep your finger steady"
        case .pressGently: return "Press gently and hold still"
        case .finding:     return "Hold still — finding your pulse…"
        case .stalled(let rhythmless):
            return rhythmless
                ? "Signal, but no steady rhythm — lift your finger and place it again"
                : "Still no pulse — try another finger, or warm your hand first"
        }
    }

    /// A 1–2 word form for the compact header monitor (no room for the full line).
    public var shortLabel: String {
        switch self {
        case .cameraDenied: return "Camera off"
        case .locked:      return "Locked"
        case .coverLens:   return "Cover lens"
        case .tooBright:   return "Too bright"
        case .holdStill:   return "Hold still"
        case .pressGently: return "Press gently"
        case .finding:     return "Finding…"
        // Two labels, not one, because the header is where a user decides whether to keep
        // waiting: "No rhythm" says the lens has something and it is the wrong shape,
        // "No pulse yet" says it has nothing. Deliberately NOT "Weak signal" — that would
        // collide with `.pressGently`, whose whole trigger is the amplitude floor this case
        // has already cleared.
        case .stalled(let rhythmless): return rhythmless ? "No rhythm" : "No pulse yet"
        }
    }

    /// True when the user can DO something to fix it right now (place/press/lighten) —
    /// the header goes amber for these so a silent wash-out becomes visible. `.finding`
    /// is normal warmup (just wait) and `.locked` is fine, so neither is actionable.
    public var isActionable: Bool {
        switch self {
        case .cameraDenied, .coverLens, .tooBright, .holdStill, .pressGently: return true
        case .locked, .finding: return false
        // ⭐ THE ONLY VISIBLE CONSEQUENCE OUTSIDE THE MEASUREMENT CARD. `.finding` and
        // `.stalled` differ in nothing the header renders EXCEPT this bool: it is what
        // turns the tile amber and shows a label at all (`HeaderMonitors.showCue`). While
        // playing, the header is the only pulse surface on screen — so without this the
        // whole case would be invisible to the person it was written for.
        case .stalled: return true
        }
    }

    /// How long a placed, steady, well-lit finger may fail to produce a trustworthy reading
    /// before `.finding` becomes `.stalled`. SECONDS, wall clock.
    ///
    /// Bounded from BOTH sides by measurements already in this repo, which is the only
    /// reason it is a number and not a guess:
    ///   · from BELOW by real acquisitions that succeed — #415 measured ~19 s to re-acquire
    ///     after a stop, and device log 2490 took ~32 s from cold. A threshold at or under
    ///     ~32 s would call a NORMAL acquisition stalled.
    ///   · from ABOVE by the failure this exists to name — the same log ran 97 s with no
    ///     lock and no change of message.
    /// 45 s sits above the slowest observed success with margin and well below the observed
    /// failure. It is a CHOICE inside that window, not a derived optimum, and it is one line
    /// to move.
    ///
    /// ⚠️ Deliberately not tied to `bioHoldTicks` or any freshness window. Those answer "is
    /// this frame still worth using"; this answers "has waiting stopped being the advice",
    /// which is a human-patience question and shares no invariant with them. Chaining it to
    /// one of them would look tidy and would couple a coaching string to a signal deadline.
    public static let stalledAfterSeconds: Double = 45
}
