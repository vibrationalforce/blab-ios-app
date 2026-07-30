// LeadRoleAbsenceTests.swift
// Echoel — THERE IS NO LEAD MELODY IN THIS PRODUCT. In the BLOCKING bundle, on purpose (#255).
//
// ⭐ THIS FILE EXISTS TO STOP A DISCOVERY FROM ROTTING. On 2026-07-30, building #253 A5 (a rhythm
// character for the lead, the fourth role in the founder's *"Alle Soundrubriken von Pads, Bass bis
// arp etc."*), the row turned out to be unshippable: ALL 25 curated genres carry
// `HarmonicProfile.leadDensity == 0`, nothing mutates it, and the three bespoke melody functions
// (`dubMelody`, `trapMelody`, `ambientMelody`) have no caller. So the `.lead` branch of
// `composeHarmonic` — ~170 lines of motif contour, chord-tone anchoring, grace notes and octave
// lifts — never runs, and no `.lead`-role note is ever composed. A "Lead rhythm" Picker would have
// been a control that does nothing on every genre: the #135 / #164 / #227 defect class, added by
// the person who has been closing it.
//
// The founder removed those melodies himself on 2026-07-09 ("die Melodie in den Genres war zu laut
// und zu unnatürlich … besser wenn die komplett weg sind"), so their absence is a DECISION, not a
// bug. What was a bug is that four live surfaces still behave as though a lead plays — see the
// failure messages below, which name each one.
//
// ⚠️ IF THIS FILE FAILS, IT IS PROBABLY RIGHT AND YOU ARE PROBABLY MID-WAY THROUGH A GOOD CHANGE.
// A failure means some genre grew a lead again. That is allowed — it is a founder call — but it
// must be a DELIBERATE one, because it wakes four dormant code paths at once. Do not "fix" this
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
            That is a legitimate founder decision — and it wakes FOUR dormant paths that have had
            nothing to act on. Check each before shipping:
              1. The Mixer's LEAD fader (`MixerStore.lead`, the "Lead" EchoelValueField in
                 EchoelStudioView) — until now it scaled a role nothing emitted. It becomes live.
              2. `IntroAttenuation.leadFactor` (0.72) softens bar 0 of the lead. Never yet heard.
              3. `BioComposer.tameLeadPitch` folds leads above MIDI 84 down an octave — the founder's
                 "piepsig künstlich" fix from 2026-07-11, also never yet heard.
              4. #253 A5, the Lead rhythm character, was BUILT and REVERTED on 2026-07-30 precisely
                 because there was no lead. It becomes shippable; the diff is in that commit's body.
            Then update THIS file to pin which genres sing and which do not.
            """)
    }

    /// The fact as a LISTENER meets it: composing any genre, at any body state, yields no lead note.
    ///
    /// Three bio states rather than one, so the result cannot be a lucky snapshot: the lead's note
    /// count is a product of `leadDensity`, `liveliness`, `busy` and the tempo thinner, and only the
    /// FIRST of those is zero. A future non-zero `leadDensity` would surface first at high arousal.
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
