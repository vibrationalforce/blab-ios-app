// BioTrustLatch.swift
// Echoel — #566, cycle C2 of the 2026-08-13 handover ("kill the 0↔1 body flap").
//
// WHAT IT IS. Time hysteresis around an instantaneous trust predicate: engage only after the
// evidence has held for `engageSeconds`, release only after it has been absent for
// `releaseSeconds`. Pure, deterministic, no clock inside — `now` is passed in, so the whole
// behaviour is unit-testable and the caller owns the clock (the same discipline
// `AlwaysOnBioRow` had to learn about `TimelineView`: a type that reads its own time cannot
// be driven by a test).
//
// ⚠️ THE INPUT IS A TRUST BOOLEAN, NOT A CONFIDENCE, AND THAT IS A DELIBERATE DEPARTURE FROM
// THE HANDOVER'S WORDING. C2 specifies "engage after conf >= 0.6 sustained 3 s, release after
// conf < 0.3 sustained 5 s" — confidence alone. This repo's trust rule is deliberately NOT
// confidence alone: `CameraRPPGBioPublisher.pulseTrustworthy` is
// `(conf >= displayThreshold && acf >= trustAutoFloor) || acf >= strongAutoFloor`, a
// TWO-EVIDENCE rule that exists because a device log (build 10.79.352) caught the peak counter
// self-agreeing at conf 0.62 with acf 0.30 — high confidence on junk — and because the mirror
// case is also real and also device-logged (log 1783420026: acf 0.59–0.72 at conf 0.01, a
// rock-stable 56 bpm). A confidence-only latch would re-open the first case and drop the
// second. So the SHAPE the handover asked for is implemented exactly; only the evidence term
// is the repo's own, and the timing constants are its numbers.
//
// ⛔ AND THE HONEST LIMIT, WHICH IS BIGGER THAN THIS TYPE: HYSTERESIS ALONE CANNOT MEET C2's
// ACCEPTANCE BAR. The handover asks for "no 0↔1 flap faster than 5 s in a 3-min finger-held
// log". Measured on this tree, `body=` is `bus.usableBio() != nil`, and `usableBio()` compares
// the frame's OWN timestamp against `BioSource.cameraPPG.freshnessWindow` = **6 s**. The
// publisher's dropout hold re-emits the last good frame CARRYING ITS ORIGINAL TIMESTAMP —
// deliberately, with the reason written at the call site: re-stamping would make a held frame
// indistinguishable from a live one and strip every consumer of its own staleness policy.
// So a body reading structurally cannot survive more than 6 s of real dropout, no matter what
// this latch decides. Seven flips in three minutes therefore means at least seven dropouts
// LONGER than six seconds — a signal-quality fact (C3's territory: exposure drift, motion
// artifact), not a gating fact. What this latch removes is the OTHER half of the flap, which
// is real and is fixable here: today a SINGLE trustworthy tick opens the bus, so one good
// sample inside a bad stretch produces a 0→1→0 blip. Sustained evidence is now required.

import Foundation

/// Hysteresis over a boolean evidence signal, driven by an externally supplied clock.
///
/// Both directions are RUN-BASED, not integrating: any interruption restarts the run. That is
/// the conservative reading and the one that matches what a flap is — a signal that cannot
/// hold a state deserves neither state until it can.
public struct BioTrustLatch: Sendable, Equatable {

    /// How long the evidence must hold before a disengaged latch engages.
    public let engageSeconds: TimeInterval
    /// How long the evidence must be ABSENT before an engaged latch releases.
    public let releaseSeconds: TimeInterval

    /// Whether the latch currently trusts the signal.
    public private(set) var isEngaged: Bool

    /// When the current run of "evidence disagrees with `isEngaged`" began, or nil when the
    /// evidence currently agrees with the latched state (nothing is pending).
    private var pendingSince: TimeInterval?

    /// Defaults are the handover's numbers (C2): 3 s to engage, 5 s to release. The release
    /// side is the longer one on purpose — releasing early is what a flap IS, while engaging
    /// early merely admits a reading a moment sooner.
    public init(engageSeconds: TimeInterval = 3, releaseSeconds: TimeInterval = 5) {
        // A non-finite or negative window would make every comparison below meaningless; a
        // zero window is legal and means "no hysteresis in that direction", which is a
        // reasonable thing for a caller to ask for.
        self.engageSeconds = engageSeconds.isFinite ? Swift.max(0, engageSeconds) : 3
        self.releaseSeconds = releaseSeconds.isFinite ? Swift.max(0, releaseSeconds) : 5
        self.isEngaged = false
        self.pendingSince = nil
    }

    /// Feed one observation. Returns the latched trust AFTER this observation.
    ///
    /// - Parameters:
    ///   - trustworthy: the instantaneous evidence verdict (for the camera path,
    ///     `CameraRPPGBioPublisher.shouldPublish`).
    ///   - now: a monotonically non-decreasing time in seconds. A `now` that moves BACKWARDS
    ///     (a wall-clock correction — the same hazard `BioSource.futureSkewTolerance` exists
    ///     for) restarts the pending run rather than completing it instantly, which is the
    ///     safe direction: a clock step may delay a transition, never manufacture one.
    @discardableResult
    public mutating func step(trustworthy: Bool, now: TimeInterval) -> Bool {
        guard now.isFinite else { return isEngaged }   // a NaN clock decides nothing
        if trustworthy == isEngaged {
            pendingSince = nil                          // evidence agrees — nothing pending
            return isEngaged
        }
        guard let since = pendingSince else {
            pendingSince = now
            return isEngaged
        }
        if now < since {                                // clock stepped backwards
            pendingSince = now
            return isEngaged
        }
        let needed = isEngaged ? releaseSeconds : engageSeconds
        if now - since >= needed {
            isEngaged = trustworthy
            pendingSince = nil
        }
        return isEngaged
    }

    /// Drop to disengaged and forget any pending run — for a genuine session boundary (a new
    /// take, a camera restart), where carrying a latch across the gap would assert trust in a
    /// body the instrument is no longer looking at.
    public mutating func reset() {
        isEngaged = false
        pendingSince = nil
    }
}
