// ArrangementPlayer.swift
// Echoel — plays an Arrangement back over the live transport. It does NOT own a
// clock: it rides the one shared PatternEngine (16 steps = 1 bar). The host (the
// single-view EchoelStudioView) feeds every transport step into `transportStep(_:)`;
// the player detects each bar boundary (the 15→0 wrap), advances the pure
// ArrangementCursor, and at each section change LOADS that section's clip into
// the live pattern + piano roll — exactly the launch path the Session grid uses.
//
// Loading happens the instant currentStep becomes 0, BEFORE step 0's triggers
// fire on the next tick, so a new section plays cleanly from its first step (no
// one-step seam). The arrangement deliberately overwrites the live pattern while
// it plays, same as launching a Session clip.

import Foundation
import Observation

@MainActor
@Observable
public final class ArrangementPlayer {

    /// Whether the arrangement is currently chaining sections.
    public private(set) var isPlaying = false
    /// Index of the section sounding now (drives the timeline playhead).
    public private(set) var currentIndex = 0
    /// Loop the whole song when it reaches the end (vs. stop).
    public var loopEnabled = true

    @ObservationIgnored private var cursor = ArrangementCursor()
    /// Section list snapshotted at play() — stable for the whole playthrough.
    @ObservationIgnored private var sectionSnapshot: [ArrangementSection] = []
    @ObservationIgnored private var lastStep = 0

    @ObservationIgnored private weak var pattern: PatternEngine?
    @ObservationIgnored private weak var pianoRoll: PianoRollModel?
    @ObservationIgnored private weak var clips: ClipStore?

    public init() {}

    // MARK: - Transport

    /// Start playing `store`'s arrangement from the top. No-op if it is empty.
    public func play(
        store: ArrangementStore,
        clips: ClipStore,
        pattern: PatternEngine,
        pianoRoll: PianoRollModel
    ) {
        let sections = store.sections
        guard !sections.isEmpty else { return }
        self.clips = clips
        self.pattern = pattern
        self.pianoRoll = pianoRoll
        self.sectionSnapshot = sections
        self.cursor = ArrangementCursor()
        self.lastStep = 0
        self.currentIndex = 0
        isPlaying = true
        loadCurrentSection()
        if !pattern.isPlaying { pattern.play(cause: .arrangement) }
    }

    /// Stop arrangement-follow and the transport.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        pattern?.stop()
        pianoRoll?.allNotesOff()
    }

    /// Reset follow-state when the transport is stopped from OUTSIDE the arrangement —
    /// e.g. the global transport bar's Stop calls `PatternEngine.stop()` directly, not
    /// `ArrangementPlayer.stop()`. Without this, `isPlaying` would stay stuck `true`: the
    /// song would look like it's still playing while the clock is stopped, and its
    /// "Play song"/Stop button would show the wrong state. A no-op when already stopped,
    /// so the arrangement's own stop()/finish path (which sets `isPlaying=false` BEFORE
    /// calling `pattern.stop()`) neither recurses nor double-clears.
    public func handleTransportStopped() {
        guard isPlaying else { return }
        isPlaying = false
        pianoRoll?.allNotesOff()
    }

    /// Fed every transport step by the host. Detects bar boundaries (15→0) and
    /// advances the song. Idempotent while stopped.
    public func transportStep(_ step: Int) {
        guard isPlaying else { return }
        defer { lastStep = step }
        // A bar completes only on a real wrap back to step 0.
        guard step == 0, lastStep != 0 else { return }

        let lengths = sectionSnapshot.map { max(1, $0.lengthBars) }
        let advance = cursor.completeBar(sectionLengths: lengths, loop: loopEnabled)
        currentIndex = cursor.index
        if advance.finished {
            isPlaying = false
            pattern?.stop()
            pianoRoll?.allNotesOff()
            return
        }
        if advance.enteredNewSection {
            loadCurrentSection()
        }
    }

    /// Tap-to-seek: jump the playing song straight to `index`, loading that
    /// section's clip immediately so it plays from its first step. No-op when
    /// stopped or the index is out of range — the timeline list stays the editor.
    public func jump(to index: Int) {
        guard isPlaying, sectionSnapshot.indices.contains(index) else { return }
        cursor.seek(to: index, sectionCount: sectionSnapshot.count)
        currentIndex = cursor.index
        loadCurrentSection()
    }

    // MARK: - Loading

    /// Load the section at the cursor into the live pattern + piano roll.
    private func loadCurrentSection() {
        guard sectionSnapshot.indices.contains(cursor.index) else { return }
        let section = sectionSnapshot[cursor.index]

        guard let clipID = section.clipID, let clip = clips?.clip(id: clipID) else {
            // A silent gap: clear both surfaces + the clip automation layer.
            pattern?.clear()
            pianoRoll?.allNotesOff()
            pianoRoll?.load([])
            pianoRoll?.setClipAutomation([])
            return
        }
        if let drums = clip.drums {
            pattern?.load(steps: drums.steps, accents: drums.accents)
        } else {
            pattern?.clear()
        }
        pianoRoll?.allNotesOff()
        pianoRoll?.load(clip.melody?.notes ?? [])
        pianoRoll?.setClipAutomation(clip.automation)   // this section's clip lanes (cycle 4)
    }
}
