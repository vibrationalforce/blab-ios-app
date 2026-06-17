// SequencerAccessibility.swift
// Echoel — VoiceOver label/value builders for the Clips + Arrange surfaces.
// Pure String functions (no SwiftUI, cross-platform) so the spoken text is
// unit-tested in CI rather than only eyeballed in the view. A blind musician
// navigates the whole DAW through these strings, so they carry identity,
// content, position and live state — not just a control name.
//
// Rebuilt onto the stable core (accessibility-first is a brand non-negotiable);
// the clips/arrange UI that consumes these is the next rebuild step.

import Foundation

public enum SequencerA11y {

    /// "1 bar" / "4 bars" — shared, correctly pluralized.
    public static func bars(_ n: Int) -> String {
        let count = max(1, n)
        return "\(count) bar\(count == 1 ? "" : "s")"
    }

    /// "8 notes" / "1 note" / "no notes".
    public static func notes(_ n: Int) -> String {
        switch max(0, n) {
        case 0: return "no notes"
        case 1: return "1 note"
        default: return "\(n) notes"
        }
    }

    /// Content summary shared by clip cells and section blocks.
    /// drums+melody → "beat and 8 notes"; drums → "beat"; melody → "8 notes";
    /// neither → "empty".
    public static func content(hasDrums: Bool, noteCount: Int) -> String {
        let hasNotes = noteCount > 0
        switch (hasDrums, hasNotes) {
        case (true, true):   return "beat and \(notes(noteCount))"
        case (true, false):  return "beat"
        case (false, true):  return notes(noteCount)
        case (false, false): return "empty"
        }
    }

    // MARK: - Session grid

    /// VoiceOver label for a launchable Session clip cell.
    public static func clipLabel(
        name: String,
        hasDrums: Bool,
        noteCount: Int,
        isQueued: Bool
    ) -> String {
        var label = "Clip \(name), \(content(hasDrums: hasDrums, noteCount: noteCount))"
        if isQueued { label += ", queued to launch on the next bar" }
        return label
    }

    /// The hint depends on whether a launch is already queued (re-tapping cancels
    /// is not wired; tapping always (re)launches), so keep it action-accurate.
    public static func clipHint(isPlaying: Bool, quantizeEnabled: Bool) -> String {
        if isPlaying && quantizeEnabled {
            return "Double tap to launch at the next bar"
        }
        return "Double tap to launch"
    }

    /// VoiceOver value for the quantize toggle.
    public static func quantizeValue(_ enabled: Bool) -> String {
        enabled ? "on" : "off"
    }

    // MARK: - Arrangement timeline

    /// VoiceOver label for one section block on the song timeline.
    public static func sectionLabel(
        name: String,
        clipName: String?,
        lengthBars: Int,
        position: Int,
        total: Int,
        isPlaying: Bool
    ) -> String {
        let pos = "Section \(position) of \(max(position, total))"
        let clip = clipName.map { "clip \($0)" } ?? "silent gap"
        var label = "\(pos), \(name), \(clip), \(bars(lengthBars))"
        if isPlaying { label += ", now playing" }
        return label
    }

    public static let sectionHint = "Double tap to select and edit this section"

    /// VoiceOver label for the arrangement transport button.
    public static func arrangementTransportLabel(isPlaying: Bool, isEmpty: Bool) -> String {
        if isEmpty { return "Play song, no sections yet" }
        return isPlaying ? "Stop song" : "Play song"
    }

    /// VoiceOver label for the loop toggle.
    public static func loopLabel(_ enabled: Bool) -> String {
        enabled ? "Loop song, on" : "Loop song, off"
    }
}
