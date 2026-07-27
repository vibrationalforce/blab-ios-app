// LaunchQuantizer.swift
// Echoel — bar-quantized clip launching for the Session grid. Tapping a clip
// while the transport runs shouldn't cut the groove mid-bar; with quantize on
// the launch is queued and fires on the next bar boundary (the 15→0 wrap),
// exactly like Ableton's global quantize. When stopped, a tap launches and
// starts the transport immediately.
//
// It rides the one shared PatternEngine clock (no second timer): the host feeds
// every transport step into transportStep(_:), same pattern as ArrangementPlayer.
// The launch-now-vs-defer decision is a pure static function so it is testable
// without a clock.

import Foundation
import Observation

@MainActor
@Observable
public final class LaunchQuantizer {

    /// Snap launches to the next bar while playing (default on, 1-bar grid).
    public var quantizeEnabled = true

    /// The clip waiting to fire on the next bar (drives the cell's "queued"
    /// highlight). `nil` when nothing is pending.
    public private(set) var pendingClipID: UUID?

    @ObservationIgnored private var pendingClip: Clip?
    @ObservationIgnored private weak var pattern: PatternEngine?
    @ObservationIgnored private weak var pianoRoll: PianoRollModel?
    @ObservationIgnored private var lastStep = 0

    public init() {}

    /// Pure decision: a launch is deferred to the next bar only while the
    /// transport is running and quantize is enabled.
    public static func shouldDefer(isPlaying: Bool, quantizeEnabled: Bool) -> Bool {
        isPlaying && quantizeEnabled
    }

    /// Request a clip launch. Fires immediately (and starts the transport if
    /// stopped) unless it must be quantized, in which case it is queued.
    public func request(_ clip: Clip, pattern: PatternEngine, pianoRoll: PianoRollModel) {
        self.pattern = pattern
        self.pianoRoll = pianoRoll
        if Self.shouldDefer(isPlaying: pattern.isPlaying, quantizeEnabled: quantizeEnabled) {
            pendingClip = clip
            pendingClipID = clip.id
        } else {
            fire(clip)
            if !pattern.isPlaying { pattern.play(cause: .launchQuantized) }
        }
    }

    /// Fed every transport step by the host. Fires a queued launch on the bar
    /// boundary (real 15→0 wrap). No-op when nothing is pending.
    public func transportStep(_ step: Int) {
        defer { lastStep = step }
        guard step == 0, lastStep != 0 else { return }
        guard let clip = pendingClip else { return }
        fire(clip)
        pendingClip = nil
        pendingClipID = nil
    }

    /// Drop a queued launch (e.g. the user tapped the queued cell again).
    public func cancelPending() {
        pendingClip = nil
        pendingClipID = nil
    }

    private func fire(_ clip: Clip) {
        if let drums = clip.drums {
            pattern?.load(steps: drums.steps, accents: drums.accents)
        }
        pianoRoll?.allNotesOff()
        pianoRoll?.load(clip.melody?.notes ?? [])
        pianoRoll?.setClipAutomation(clip.automation)   // clip lanes travel with the clip (cycle 4)
    }
}
