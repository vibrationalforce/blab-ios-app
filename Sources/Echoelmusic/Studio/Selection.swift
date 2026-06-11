//
//  Selection.swift
//  Echoelmusic — Studio (cohesion)
//
//  The single source of truth for "what is selected" across every editor. The
//  research (RESEARCH_BIO_UX_2026-06-11.md §A3) found that a shared transport +
//  a shared selection — NOT the navigation container — are what make many
//  editors feel like one instrument. Today each editor keeps its own ad-hoc
//  selection (e.g. PianoRoll's local `selectedID`); this model unifies them so a
//  single contextual inspector (a later cycle) can react to any selection.
//
//  This cycle introduces the model only — app-wide injected, not yet consumed,
//  so it changes no existing behavior (the same staged pattern as BioNormalizer).
//

import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Target

/// One selectable entity, spanning the current editors. Identifiers match the
/// real models: notes/patches/routes carry a `UUID`, sequencer cells a
/// (track, step) pair, pads and clip slots an index.
public enum SelectionTarget: Equatable, Hashable, Sendable {
    case step(track: Int, step: Int)
    case pad(Int)
    case note(id: UUID)
    case clip(slot: Int)
    case route(id: UUID)
    case patch(id: UUID)
}

// MARK: - Selection

/// App-wide current selection. Single-select for now (an inspector shows one
/// thing at a time); multi-select can extend this without changing call sites.
@MainActor
@Observable
public final class Selection {

    /// The currently selected target, or `nil` when nothing is selected.
    public private(set) var current: SelectionTarget?

    public init() {}

    /// True when nothing is selected.
    public var isEmpty: Bool { current == nil }

    /// Replaces the selection.
    public func select(_ target: SelectionTarget) {
        current = target
    }

    /// Clears the selection.
    public func clear() {
        current = nil
    }

    /// Selects `target`, or clears it if it was already selected (tap-to-toggle).
    public func toggle(_ target: SelectionTarget) {
        current = (current == target) ? nil : target
    }

    /// Whether `target` is the current selection.
    public func isSelected(_ target: SelectionTarget) -> Bool {
        current == target
    }
}
