// LeadRoleAbsenceTests.swift
// Echoel — THERE IS NO LEAD MELODY IN THIS PRODUCT. In the BLOCKING bundle, on purpose (#255).
//
// ⭐ THIS FILE EXISTS TO STOP A DISCOVERY FROM ROTTING. On 2026-07-30, building #253 A5 (a rhythm
// character for the lead, the fourth role in the founder's *"Alle Soundrubriken von Pads, Bass bis
// arp etc."*), the row turned out to be unshippable: ALL curated genres carry
// (27 today, 25 when this was written — the count is deliberately not repeated below, because
// it drifts with every genre batch while the invariant does not)
// `HarmonicProfile.leadDensity == 0`, nothing mutates it (`harmonicProfile` is a computed `var`
// returning a fresh struct, so even a local copy could not leak), and the three bespoke melody
// functions have no caller — of those, `trapMelody` and `ambientMelody` emit `.lead`, `dubMelody`
// emits harmony and bass; being callerless is the load-bearing half for all three. So the `.lead`
// branch of `composeHarmonic` — ~120 lines of motif contour, chord-tone anchoring, grace notes and
// octave lifts — never runs, and no `.lead`-role note is ever composed. A "Lead rhythm" Picker would
// have been a control that does nothing on every genre: the #135 / #164 / #227 defect class, added by
// the person who has been closing it.
//
// The founder removed those melodies himself on 2026-07-09 ("die Melodie in den Genres war zu laut
// und zu unnatürlich … besser wenn die komplett weg sind"), so their absence is a DECISION, not a
// bug. What was a bug is that four live surfaces still behave as though a lead plays — see the
// failure messages below, which name each one.
//
// ⚠️ IF THIS FILE FAILS, IT IS PROBABLY RIGHT AND YOU ARE PROBABLY MID-WAY THROUGH A GOOD CHANGE.
// A failure means some genre grew a lead again. That is allowed — it is a founder call — but it
// must be a DELIBERATE one, because it wakes FIVE dormant code paths at once. Do not "fix" this
// file by loosening the assertion; re-read the checklist in the failure message, wire what it
// names, then update this file to pin the new truth (which genres sing, which do not).
//
// ⛔ WHAT THIS FILE IS NOT: it is not an argument for deleting the lead code. `tameLeadPitch`,
// `IntroAttenuation.leadFactor` and the melody block encode real founder tuning decisions from
// 2026-07-07/07-11, and #196 is an open task about the lead's own output gain. Deleting them would
// throw that away; documenting them as dormant keeps it. That call stays with the founder.

import XCTest
@testable import Echoelmusic

final class LeadRoleAbsenceTests: XCTestCase {

    /// The fact at its SOURCE: no curated genre asks for a lead.
    ///
    /// Asserted separately from the composed-output test below, because the two fail for different
    /// reasons and a reader needs to know which. This one failing means a curation pass changed a
    /// `HarmonicProfile`; the other failing means a code path started emitting `.lead` notes
    /// regardless of the profile (a reachability change, e.g. one of the three unused melody
    /// functions being wired back in).
    func testNoCuratedGenreAsksForALead() {
        var singing: [String] = []
        for style in MusicStyle.allCases where style.harmonicProfile.leadDensity > 0 {
            singing.append("\(style.rawValue) (leadDensity \(style.harmonicProfile.leadDensity))")
        }
        XCTAssertTrue(singing.isEmpty, """
            A genre now asks for a lead melody: \(singing.joined(separator: ", ")).
            That is a legitimate founder decision (#255) — and it wakes FIVE dormant paths that have
            had nothing to act on. Check each before shipping:
              1. `leadVoice` — a LIVE PolySynthVoice(maxVoices: 3), attached to the audio engine and
                 polling the bus every 100 ms since launch while receiving zero notes
                 (EchoelmusicApp.swift). It is the voice that would actually sound, and the one #196
                 (per-role output gain) and #243 (its FX chain) are really about. Start here.
              2. The Mixer's LEAD fader (`MixerStore.lead`, the "Lead" EchoelValueField in
                 EchoelStudioView) — until now it scaled a role nothing emitted. It becomes live.
              3. `IntroAttenuation.leadFactor` (0.72) softens bar 0 of the lead. Never yet heard —
                 and its own file header still describes the softening in the present tense.
              4. `BioComposer.tameLeadPitch` folds leads above MIDI 84 down an octave — the founder's
                 "piepsig künstlich" fix from 2026-07-11, also never yet heard.
              5. #253 A5, the Lead rhythm character, was BUILT and REVERTED on 2026-07-30 precisely
                 because there was no lead. It becomes shippable; the code is GONE (verified
                 unrecoverable), the spec is scratchpads/PLAN_LEAD_RHYTHM_A5_2026-07-30.md.
            Then update BOTH this file and its non-blocking twin
            (Tests/EchoelmusicTests/MusicStyleTests) to pin which genres sing and which do not.
            """)
    }

    /// The fact as a LISTENER meets it: composing any genre, at any body state, yields no lead note.
    ///
    /// ⚠️ WHY THREE STATES, corrected — the first version of this note gave the wrong mechanism and
    /// would have had a future reader reasoning from it. It said the note count is a product of
    /// `leadDensity`, liveliness, `busy` and the tempo thinner so "a non-zero leadDensity would
    /// surface FIRST at high arousal". It would not: the count is `max(3, …)`, so ANY
    /// `leadDensity > 0` yields at least three lead notes at EVERY body state, and one state would
    /// already be sufficient. The three are kept for a different and weaker reason — they make the
    /// assertion independent of that particular floor surviving a future refactor.
    ///
    /// ⚠️ WHAT THE NAME OVERSTATES: "any body state" is three heart/coherence points, at one mode
    /// (`.studioLocked`, though four genres default to `.flowFree`), one key, one seed and the default
    /// mood. That is enough for THIS invariant, per the `max(3, …)` argument above; it would not be
    /// enough for a claim about note CONTENT.
    ///
    /// The second assertion in the loop is a different invariant living under a lead-named test —
    /// deliberate: a lead-absence test that passes on a composer returning nothing would be
    /// worthless. Read its message, not the test name, if it is the one that fails.
    func testNoGenreComposesALeadNoteAtAnyBodyState() {
        let states: [(String, Float, Float)] = [
            ("settled", 54, 0.9),      // low arousal — the calm Flächen
            ("moderate", 96, 0.5),
            ("aroused", 168, 0.1)      // high arousal — where a lead would be busiest
        ]
        for style in MusicStyle.allCases {
            for (label, bpm, coherence) in states {
                let input = BioComposer.Input(heartRateBPM: bpm, hrvNormalized: 0.5,
                                              coherence: coherence,
                                              breathPhase: 0.25, breathDepth: 0.7,
                                              key: MusicalKey(root: 0, scale: .minor),
                                              style: style, mode: .studioLocked,
                                              lockedTempo: Double(bpm), seed: 0xA50E)
                let composition = BioComposer.compose(input)
                XCTAssertFalse(composition.notes.contains { $0.role == .lead },
                               "\(style.rawValue) composed a .lead note at \(label) — see the "
                               + "four-point checklist in testNoCuratedGenreAsksForALead")
                // A take with no lead must still have SOMETHING to hear, or this test would pass
                // for the wrong reason (a composer returning nothing at all).
                XCTAssertFalse(composition.notes.isEmpty,
                               "\(style.rawValue) composed nothing at \(label) — this test would "
                               + "then be asserting the absence of a lead in an absence of music")
            }
        }
    }
}
