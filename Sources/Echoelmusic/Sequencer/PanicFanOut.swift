// PanicFanOut.swift
// Echoel — the performance panic, as a value that can be tested.
//
// THE DEFECT IT COMES FROM (#160). The panic button released three of eight
// note-producing voices while its accessibility hint promised "every sounding note on
// every voice". A stuck note on the lead or on a play surface is a *more* likely reason
// to reach for panic than one on the composer's synth, so the control failed precisely
// in the case it exists for.
//
// WHY THIS FILE EXISTS ON TOP OF THAT FIX (#168, review-HIGH on #160). The corrected
// fan-out was a `private func` on a `View` struct: XCTest cannot reach it, so nothing
// failed if a release were dropped from the list again. The only enforcement was a
// comment saying so. This moves the list into a plain value with an `internal` entry
// point, so a test can hand it spies and assert every one of them was released.
//
// ⚠️ HONEST SCOPE — what this does NOT catch. A voice that is never PASSED IN is still
// invisible to any test here; the seam pins the release of what it is given, not the
// completeness of the caller's inventory. Catching that needs the view to hold its
// voices in one array that both note routing and panic read, which is a real refactor
// of `EchoelStudioView` and not this slice. So the comment at the call site remains the
// enforcement for "a new voice belongs here too" — this file narrows the untested
// surface from the whole fan-out to that one line.

import Foundation

/// Something that can release every note it is currently sounding.
///
/// Deliberately a NEW name rather than reusing `allNotesOff()`: the eight targets do not
/// share one spelling — `BioReactiveSynthVoice` releases via `panic()`, which also clears
/// every latch a controller can strand: the held-key stack (#943), the press gain (#939), the
/// slide scale (#942) and — since #945 — the PITCH. Mapping each type onto this one requirement is exactly
/// the part worth pinning, because getting that mapping wrong is silent (the call
/// compiles, the note keeps sounding).
@MainActor
public protocol NoteReleasable: AnyObject {
    func releaseAllNotes()
}

/// The panic list, in order.
///
/// ORDER IS LOAD-BEARING and not merely cosmetic. `PianoRollModel` must come first: its
/// `allNotesOff()` also CLEARS the roll's `active` note table. Without that, the roll
/// still believes those notes are held and its next tick issues a pitch-matched
/// `noteOff(pitch:)` — which on the monophonic `SubBassVoice` releases whatever is
/// sounding at that pitch, i.e. it can cut a note the performer retriggered AFTER the
/// panic. So a "release everything" that ran in the wrong order would leave a live
/// instrument that swallows the next note.
@MainActor
public struct PanicFanOut {

    private let targets: [NoteReleasable?]

    /// `nil` entries are expected, not defensive padding: `leadSynth` and `touchSynth` are
    /// optional environment values that are genuinely absent until their surfaces exist.
    public init(_ targets: [NoteReleasable?]) {
        self.targets = targets
    }

    /// Release every non-nil target, in order. Returns how many were released — the count
    /// is what lets a caller (or a diagnostic line) distinguish "panic reached six voices"
    /// from "panic reached none because the environment was empty".
    @discardableResult
    public func releaseAll() -> Int {
        var released = 0
        for target in targets {
            guard let target else { continue }
            target.releaseAllNotes()
            released += 1
        }
        return released
    }
}

// MARK: - Conformances (the mapping, one line each)
//
// Each `#if` MIRRORS the guard on the type's own file — `PianoRollModel` lives inside
// `#if canImport(SwiftUI)`, `LaneVoiceRack` inside `#if canImport(AVFoundation) &&
// canImport(Accelerate)`. An extension of a type that does not exist on a platform is a
// hard error, so these are not decoration. (All compiled targets are macOS/iOS today, so
// none of them currently excludes anything — they exist so the file stays correct if a
// Linux-buildable core target is ever added, which is the direction this repo keeps
// moving in.)

extension PolySynthVoice: NoteReleasable {
    public func releaseAllNotes() { allNotesOff() }
}

extension SubBassVoice: NoteReleasable {
    public func releaseAllNotes() { allNotesOff() }
}

extension BioReactiveSynthVoice: NoteReleasable {
    /// NOT `allNotesOff()` — this voice is monophonic and driven by incoming MIDI
    /// note-on/off, so its release also has to clear everything a controller can strand: the
    /// held-key stack (#943), the press gain (#939), the slide scale (#942) and the PITCH
    /// (#945). That is what `panic()` does and what a plain note release would miss.
    ///
    /// ⚠️ #945b — READ THAT LIST AS A LIVE INVENTORY, not as history. This is the line a
    /// reader consults to learn what `releaseAllNotes()` MEANS for this voice, and it has
    /// silently under-described the method once already: it said "a stuck controller-held
    /// latch", singular, after three more had been added to `panic()`. When a latch joins or
    /// leaves that method, this sentence moves in the same commit (#456).
    public func releaseAllNotes() { panic() }
}

extension MIDIOutput: NoteReleasable {
    public func releaseAllNotes() { allNotesOff() }
}

#if canImport(SwiftUI)
extension PianoRollModel: NoteReleasable {
    /// Releases poly/lead/sub/kind/MIDI AND clears the roll's `active` table — see the
    /// order note on `PanicFanOut`.
    public func releaseAllNotes() { allNotesOff() }
}
#endif

#if canImport(AVFoundation) && canImport(Accelerate)
extension LaneVoiceRack: NoteReleasable {
    public func releaseAllNotes() { allNotesOff() }
}
#endif
