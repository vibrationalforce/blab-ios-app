// StudioNavigator.swift
// Echoel — one source of truth for which Studio tab is showing, so the app can
// drive navigation in code (not just on a tab tap). The production loop crosses
// tabs — capture a clip in Clips, arrange it in the song, then jump back to
// Tools to edit its sound — and that "jump back" should actually move the user,
// not silently mutate a tab they can't see. Pure @Observable, no SwiftUI.

import Foundation
import Observation

@MainActor
@Observable
public final class StudioNavigator {

    public enum Tab: Hashable, Sendable {
        case tools   // BeatTab — sequencer, pads, piano roll, synth
        case clips   // ClipsTab — Session grid + Arrangement
        case works   // WorksView — bio session recorder
        case sync    // ModulationView — bio→param routing + immersive out
        case well    // WellView — coherence, breath pacer
    }

    public var selected: Tab = .tools

    public init() {}

    /// Show the Tools tab — used after "Edit clip" loads a clip into the live
    /// editor, so the user lands where the change is visible.
    public func editInTools() {
        selected = .tools
    }
}
