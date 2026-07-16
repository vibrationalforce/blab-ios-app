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
        }
    }

    /// True when the user can DO something to fix it right now (place/press/lighten) —
    /// the header goes amber for these so a silent wash-out becomes visible. `.finding`
    /// is normal warmup (just wait) and `.locked` is fine, so neither is actionable.
    public var isActionable: Bool {
        switch self {
        case .cameraDenied, .coverLens, .tooBright, .holdStill, .pressGently: return true
        case .locked, .finding: return false
        }
    }
}
