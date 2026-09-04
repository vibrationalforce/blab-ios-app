//
//  BassGrammar.swift
//  Echoelmusic — Sequencer
//
//  ONE AUTHORED BASS FIGURE PER GENRE (founder 2026-09-04: "Ich will richtig gute Bass und Pad
//  etc Loops für Deep tech, dark minimal, deep house, psy prog House etc haben").
//
//  ⛔ WHY THIS EXISTS — measured before it was written (`PLAN_GENRE_BASS_PAD_LOOPS_2026-09-04.md`):
//  the pad side of a genre is built five ways (profile · articulation · patch · FX · mix) and the
//  BASS side had no genre axis at all. `BioComposer.appendBass` is one genre-blind walk — root on
//  the section downbeat, root/fifth on 8ths or quarters when the body has drive, ONE held root
//  when it does not. A house bass that lands on the "&", a psy bass that rolls three 16ths under
//  a free downbeat, a dark-minimal sub that holds — none of those could be composed, whatever the
//  genre said. This type is the missing axis: a fixed 16-step figure the genre OWNS, the way
//  `MusicStyle.chordArticulation` already owns the pad's grid.
//
//  THE FIGURE IS THE GENRE, NOT THE BODY. Like `.skank` for the pad ("the offbeat IS the genre, at
//  rest or aroused"), a grammar applies at a resting body too — the body keeps its say through
//  the section VELOCITY (`bassVelocity` in `composeHarmonic`, which carries breath depth and the
//  low-end tilt) and through `hVel`'s humanising. What the body no longer decides for these
//  genres is WHERE the bass lands; that was the defect.
//
//  PRECEDENCE, decided here so `appendBass` does not have to discover it: a user's Bass-rhythm
//  Picker choice (`Input.bassRhythm`, non-nil) WINS over the grammar and takes the walking path
//  exactly as before — the person asked for a character by name, the genre only offered one. With
//  the Picker on "Genre" (`nil`), the grammar plays. A genre WITHOUT a grammar (`nil` from
//  `MusicStyle.bassGrammar`) is byte-identical to the pre-grammar walk: the `#253 A3` Golden law
//  (`BassRhythmOverrideTests`) is untouched because the new branch is entered only where a genre
//  sets a value.
//
//  Pure Foundation value type, no RNG of its own (the caller humanises), so a figure is assertable
//  in CI — `Tests/CISmoke/GenreBassGrammarTests.swift`. Whether it GROOVES is a device question
//  and is filed as one (NEEDS-FOUNDER-VERIFY in the plan).
//

import Foundation

/// A fixed one-bar bass figure, in the composer's 16-step bar.
public enum BassGrammar: String, CaseIterable, Sendable, Codable {
    /// House: the bass on every "&" (phases 2 · 6 · 10 · 14), an 8th long, the downbeat FREE.
    /// Where a kick would sit the low end leaves a hole on purpose — that hole is the house pump.
    case offbeatEighths
    /// Psy: downbeat free, then three 16ths under every beat (phases 1-2-3 · 5-6-7 · …), each one
    /// step long. Twelve hits a bar, the rolling bass. The third of each three is the accent so the
    /// figure leans INTO the next beat rather than away from it.
    case rollingSixteenths
    /// Tech: every 8th, on-beats held to the "&", off-beats a 16th; the fifth on the last "&" of
    /// the bar (phase 14) so the loop turns around instead of treadmilling.
    case drivingEighths
    /// Dark minimal: ONE root held half the bar, then the fifth short on "3&" (phase 10) and
    /// nothing else. Weight, not a line.
    case sparseSub

    /// One hit of a figure. `phase` is the 16-step bar position; `length` in steps (≥ 1, the
    /// #205/#176 no-zero-length law); `level` scales the section velocity (1 = the section's own);
    /// `fifth` plays the chord's fifth instead of its root — always in key via `MusicalKey.degree`.
    public struct Hit: Equatable, Sendable {
        public let phase: Int
        public let length: Int
        public let level: Float
        public let fifth: Bool

        public init(phase: Int, length: Int, level: Float, fifth: Bool = false) {
            self.phase = phase
            self.length = length
            self.level = level
            self.fifth = fifth
        }
    }

    /// The figure, in ascending phase order, never overlapping (pinned by the guard).
    public var hits: [Hit] {
        switch self {
        case .offbeatEighths:
            return [Hit(phase: 2, length: 2, level: 1.0),
                    Hit(phase: 6, length: 2, level: 0.9),
                    Hit(phase: 10, length: 2, level: 1.0),
                    Hit(phase: 14, length: 2, level: 0.9)]
        case .rollingSixteenths:
            var out: [Hit] = []
            out.reserveCapacity(12)
            for beat in 0..<4 {
                let base = beat * 4
                out.append(Hit(phase: base + 1, length: 1, level: 0.85))
                out.append(Hit(phase: base + 2, length: 1, level: 0.80))
                out.append(Hit(phase: base + 3, length: 1, level: 1.0))
            }
            return out
        case .drivingEighths:
            var out: [Hit] = []
            out.reserveCapacity(8)
            for beat in 0..<4 {
                let base = beat * 4
                out.append(Hit(phase: base, length: 2, level: 1.0))
                out.append(Hit(phase: base + 2, length: 1, level: 0.85, fifth: beat == 3))
            }
            return out
        case .sparseSub:
            return [Hit(phase: 0, length: 8, level: 1.0),
                    Hit(phase: 10, length: 2, level: 0.8, fifth: true)]
        }
    }
}

public extension MusicStyle {
    /// The bass figure this genre owns, or `nil` = the pre-grammar walking bass, byte-identical.
    ///
    /// Opt-in by design, so `default: nil` is the honest arm here and NOT the exhaustiveness
    /// dodge the rest of `MusicStyle` avoids: a genre that has not been given a figure keeps the
    /// walk it always had. S3–S5 of the plan add `deepTech` / `darkMinimal` / `psyProgHouse` with
    /// their own arms (`drivingEighths` / `sparseSub` / `rollingSixteenths`). ⚠️ `rollingSixteenths`
    /// has NO genre yet — it is authored ahead of S5 and pinned as a figure, not as a sound.
    var bassGrammar: BassGrammar? {
        switch self {
        case .deepHouse:     return .offbeatEighths
        case .techHouse:     return .drivingEighths
        case .deepTech:      return .drivingEighths   // #983 S3: shares the figure, not the patch
        case .minimalTechno: return .sparseSub
        default:             return nil
        }
    }
}
