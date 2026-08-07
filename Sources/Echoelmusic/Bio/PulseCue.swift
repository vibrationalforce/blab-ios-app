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
    /// Checked instead of assumed — THREE independent checks, not four:
    ///   · the "exposure locked on finger" line is an `EchoelCrashLog.breadcrumb`, so it is
    ///     not on the measurement surface at all. ⛔ The first version of this line said
    ///     "log file only, NEVER RENDERED", which is false: `EchoelStudioView`'s reachable
    ///     "Diagnostics" row renders `EchoelCrashLog.currentLog()`, and `SafeModeView`
    ///     renders the previous session's. The sharper reading is that the opt-in
    ///     Diagnostics sheet is plausibly HOW that line reached a human and misled one.
    ///   · `signalQuality` has zero UI consumers — its one consumer is the 2 s breadcrumb.
    ///     ⛔ "zero consumers" was too strong.
    ///   · `displayBPM` never advanced. ⛔ The first version listed `isLocked` as a FOURTH
    ///     check; it is the SAME fact — both are `pulseTrustworthy` byte-for-byte, so they
    ///     cannot disagree, and a corroboration list containing a duplicate corroborates
    ///     less than it looks like it does.
    /// Every shown thing was honest. What was missing was not truth but TIME — no surface
    /// knows how long the honest message has been the same one.
    ///
    /// `hasRhythmlessSignal` splits the two failures, because they need OPPOSITE advice:
    ///   · `true` — at least one channel has something: confidence at display grade, or
    ///     autocorrelation at the corroboration floor, without the pair clearing
    ///     `pulseTrustworthy`. The in-repo, device-logged shape of this is
    ///     `CameraAnalyzer.isUncorroboratedRipple` (amp 0.05…0.20 with acf < 0.15, device
    ///     log 2026-07-03, "the peak-count drifted 54→69→82 … `agreement` pushed confidence
    ///     to 0.78"): sub-threshold movement the peak counter agrees with itself about.
    ///     Something IS coupling to the lens and it isn't a heartbeat — re-placing the
    ///     finger fixes it.
    ///     ⛔ The first version of this line said "a moving or VENOUS contact" and cited
    ///     "#308, conf 0.82–0.86 vs acf 0.09–0.16, device log 2479". "Venous" occurred
    ///     exactly once in the whole repo — here — an uncited mechanism standing next to a
    ///     cited one; and neither #308 nor that conf/acf pair has a second witness anywhere
    ///     in the tree. The supported mechanism was one file over and went uncited. **A
    ///     mechanism you cannot point at is not evidence, however plausible it reads.**
    ///   · `false` — NEITHER channel has anything, above the `pressGently` amplitude floor.
    ///     Re-gripping the same finger is the LEAST likely fix here; perfusion is.
    ///
    /// ⚠️ THAT SECOND BULLET IS WHY THE SPLIT IS AN `||` AND NOT AN `&&`. The first version
    /// tested `conf ≥ 0.6 && acf < 0.4`, so `false` was the COMPLEMENT — a catch-all that
    /// swept up conf 0.5 / acf 0.5, i.e. genuine corroborated periodicity that merely had
    /// not cleared the strong-only clause. That is precisely the band `strongAutoFloor`
    /// exists for (device-observed at acf 0.59–0.72 with confidence near zero), and those
    /// users were told to warm their hands. Both reviewers found it independently.
    ///
    /// ⚠️ NOT a verdict, and the wording is chosen so it cannot read as one. A take that
    /// would have locked at 50 s shows this at 45 s and then locks anyway. That is not a
    /// false statement — at 45 s waiting has demonstrably not worked yet — but it is advice
    /// with a real false-alarm rate, so neither string claims the pulse is unreadable.
    ///
    /// ⚠️ THE SUBJECT OF BOTH SENTENCES IS THE SIGNAL, NEVER THE BODY — and the first
    /// version got this wrong in the one place it costs something. It read "Signal, but no
    /// steady rhythm" with the short label "No rhythm", rendered inside a tile whose
    /// accessibility label is *Heart rate*: VoiceOver spoke "Heart rate. Signal, but no
    /// steady rhythm." That is one parse from "your heartbeat is irregular" — and low
    /// autocorrelation with a still-firing peak counter is *also* what an irregular rhythm
    /// looks like on a PPG trace, so the sentence could be misread as a cardiac observation
    /// AND be accidentally correct as one. That is the worst combination available to a
    /// non-medical instrument. Nothing in the design needed the word "rhythm".
    ///
    /// ⚠️ WHAT THIS DELIBERATELY DOES NOT SAY: "switch to a chest strap". `bioPanel` already
    /// carries that route verbatim and correctly ("touch and hold the pulse display and
    /// pick …"), and #416's law plus that panel's own comment — "Saying it three times is
    /// not thoroughness" — make a second copy here a defect, not helpfulness. ⛔ The first
    /// version called `bioPanel` "the panel that hosts the measurement card" and said a
    /// VoiceOver user reaches the route "immediately BEFORE the card": both wrong. The panel
    /// hosts `BioStripView`; the strap sentence comes AFTER it, and "immediately before" was
    /// borrowed from a comment about the Open Routing button. The chain that gets a stuck
    /// user there is `isActionable` → the header tile goes amber and shows a label at all;
    /// TAPPING the tile opens the panel (the colour only draws the eye to it).
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
                ? "The signal isn't steady enough to read — lift your finger and place it again"
                : "Still nothing to read — try another finger, or warm your hand first"
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
        // waiting: "Unsteady" says the lens has something and it is the wrong shape,
        // "Nothing yet" says it has nothing. Deliberately NOT "Weak signal" — that would
        // collide with `.pressGently`, whose whole trigger is the amplitude floor this case
        // has already cleared. And deliberately NOT "No rhythm"/"No pulse yet": this tile's
        // accessibility label is *Heart rate*, so either would compose into a sentence about
        // the user's heartbeat (see the ⚠️ SUBJECT block on the case).
        case .stalled(let rhythmless): return rhythmless ? "Unsteady" : "Nothing yet"
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
    /// Bounded from BOTH sides by measurement rather than taste — but the three numbers are
    /// NOT equally checkable, and the first version of this block claimed they were:
    ///   · from BELOW by real acquisitions that succeed — #415's ~19 s re-acquire after a
    ///     stop is IN-REPO and corroborated in four independent places
    ///     (`CameraRPPGBioPublisher`, `BreathHold`, `PianoRollView`,
    ///     `AFreshTakeStartsWithNoHeldFrameTests`); device log 2490's ~32 s from cold is
    ///     recorded HERE FOR THE FIRST TIME, from a log a later reader cannot open, and is
    ///     n = 1. A threshold at or under ~32 s would call a NORMAL acquisition stalled.
    ///   · from ABOVE by the failure this exists to name — the same log ran 97 s with no
    ///     lock. Also n = 1, and "with no change of message" is an INFERENCE, not a logged
    ///     fact: the 2 s breadcrumb prints `finger/R/bright/amp/pk/acf/…` and carried no cue
    ///     string, so the cue was derived from those fields rather than read off. #484 adds
    ///     `cue=` to that breadcrumb precisely so the NEXT log does not need the inference.
    /// ⛔ The first version wrote "bounded from BOTH sides by measurements ALREADY IN THIS
    /// REPO, which is the only reason it is a number and not a guess". Two of the three were
    /// in the repo only because that same commit put them there. **A number this commit
    /// introduces cannot corroborate the commit.**
    /// 45 s sits above the slowest observed success and well below the observed failure. The
    /// tighter bound is 32 s → a 1.4× margin over ONE observation of a process this repo
    /// elsewhere calls fragile (#304/#410), so "with margin" was an overstatement too. It is
    /// a CHOICE inside that window, not a derived optimum, and it is one line to move.
    ///
    /// ⚠️ Deliberately not tied to `bioHoldTicks` or any freshness window. Those answer "is
    /// this frame still worth using"; this answers "has waiting stopped being the advice",
    /// which is a human-patience question and shares no invariant with them. Chaining it to
    /// one of them would look tidy and would couple a coaching string to a signal deadline.
    public static let stalledAfterSeconds: Double = 45
}
