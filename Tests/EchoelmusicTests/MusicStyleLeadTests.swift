// MusicStyleLeadTests.swift
// Echoel — guards the genre lead-timbre identity so genres never collapse onto
// one lead again (founder 2026-07-20: "die Genres klingen teilweise gleich"),
// and so a lead never resolves to a shrill/real-instrument patch (founder
// 2026-07-07: warm synth only). These are pure invariants over MusicStyle.

import XCTest
@testable import Echoelmusic

final class MusicStyleLeadTests: XCTestCase {

    /// The only lead patches a genre may name — the founder-approved WARM set.
    /// Excludes every bright ("Bright Lead", "Glass Bell", "Vapor Lead") and every
    /// plastic real-instrument emulation ("Violin", "Clarinet", "Trumpet", …).
    private let warmLeadSet: Set<String> = [
        "Soft Keys", "Warm Strings", "Hollow Reed", "Pluck", "Choir Vox", "Deep Sub"
    ]

    /// Genres that carry a LEAD VOICE identity — a warm timbre a user can play
    /// their own melody on (touch/MPE/piano roll), as opposed to a pure sustained
    /// Fläche with no lead voice at all. Since founder 2026-07-21 ("Melodien
    /// sollen die Leute selbst machen") no genre auto-generates lead NOTES
    /// anymore (leadDensity is 0 everywhere — see MusicStyleTests.swift), but the
    /// per-genre lead PATCH assignment (leadPatchName → EchoelStudioView applies
    /// it to the piano roll's lead voice) still matters for whatever the user
    /// plays themselves — hence filtering on `!sustained` alone now, not
    /// `leadDensity > 0` (which would be vacuously empty).
    private var leadBearing: [MusicStyle] {
        MusicStyle.allCases.filter { !$0.harmonicProfile.sustained }
    }

    func testEveryLeadPatchIsInTheWarmSet() {
        // No genre may resolve to a bright or real-instrument lead — including via
        // the "Bright Lead" fallback if the name were missing from the factory.
        for s in MusicStyle.allCases {
            XCTAssertTrue(warmLeadSet.contains(s.leadPatchName),
                          "\(s) lead '\(s.leadPatchName)' is outside the approved warm set")
        }
    }

    func testEveryLeadPatchExistsInTheFactory() {
        // A name absent from SynthPatch.factory silently falls back to the banned
        // "Bright Lead" at apply time — assert every name resolves.
        let factoryNames = Set(SynthPatch.factory.map(\.name))
        for s in MusicStyle.allCases {
            XCTAssertTrue(factoryNames.contains(s.leadPatchName),
                          "\(s) lead '\(s.leadPatchName)' is not a factory patch (would fall back to Bright Lead)")
        }
    }

    func testLeadTimbresAreSpreadNotCollapsed() {
        // The core "klingen gleich" guard: lead-bearing genres must not pile onto one
        // patch. Before 2026-07-20 nine shared "Soft Keys".
        //
        // ⚠️ THE CEILING IS DERIVED, NOT THE LITERAL 3 THAT STOOD HERE, and the reason is
        // arithmetic rather than taste. The old assertion was `maxShared <= 3`, which was
        // simply a description of the spread at the time (17 lead-bearing genres over 6
        // warm patches). #254 added two lead-bearing genres → 19, and 6 × 3 = 18, so
        // "no more than three" became UNSATISFIABLE: every possible assignment fails it.
        // A test that cannot pass is not a strict test, it is a broken one — and this
        // suite is non-blocking (#208), so it would have gone red in silence.
        //
        // `ceil(count / patches)` is the pigeonhole floor: the smallest max any
        // assignment can achieve. It evaluates to 3 at 17 genres (nothing was loosened
        // to let #254 through) and 4 at 19, and it still forbids exactly what the guard
        // exists for — a pile-up on one patch while others sit nearly empty.
        let leads = leadBearing.map(\.leadPatchName)
        XCTAssertFalse(leads.isEmpty, "there must be lead-bearing genres to guard")

        let counts = Dictionary(grouping: leads, by: { $0 }).mapValues(\.count)
        let maxShared = counts.values.max() ?? 0
        let ceiling = Int(ceil(Double(leads.count) / Double(warmLeadSet.count)))
        XCTAssertLessThanOrEqual(maxShared, ceiling,
            "the leads are not spread as evenly as \(leads.count) genres over "
            + "\(warmLeadSet.count) warm patches allows: no patch may carry more than "
            + "\(ceiling), got \(counts)")

        XCTAssertGreaterThanOrEqual(Set(leads).count, 5,
            "lead-bearing genres must use at least 5 distinct warm leads (got \(Set(leads).sorted()))")
    }
}
