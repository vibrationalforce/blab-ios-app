// ScaleFamilyTests.swift
// Echoel — the Scale picker stopped iterating `Scale.allCases` and started iterating
// `Family.allCases` → `family.scales` (#232, grouped picker). That swap moves the list of
// what is REACHABLE out of the compiler's hands and into a hand-written literal.
//
// THE FAILURE THAT MAKES THIS FILE NECESSARY: a new `Scale` case still compiles, still
// persists, still decodes, still sounds — and is simply absent from the picker. Nothing
// warns. That is this repo's most expensive recurring defect ("built but doorless": the
// whole Tools-grid generation of views, `PatchEditorView`, `SpectralDonutView`, the MIDI
// import), and the grouped picker is a fresh way to manufacture it. So the partition is
// asserted here, in `Tests/CISmoke` — the only bundle that can redden a merge (#208).
//
// It also pins the ONE cultural claim the grouping makes: `doubleHarmonic` and
// `phrygianDominant` sit on the Near East shelf because they are the 12-TET readings of
// Maqām Ḥijāz-kār and Ḥijāz. That was the point of the slice — those two were reachable
// only under Western names — so a later reshuffle that quietly moves them back is the
// regression, not a cleanup.
//
// ⚠️ WHAT THIS FILE CANNOT GUARD, stated because the header above reads like a complete
// contract and is not: nothing here proves the PICKER iterates families. Revert
// `WorkspaceView` to `ForEach(Scale.allCases)` and every test below still passes. That is
// inherent without a UI test, and the failure direction is the safe one (reverting
// restores completeness rather than hiding a scale), so no machinery is built for it — but
// do not read a green run as proof the grouping is still mounted.

import Foundation
import XCTest
@testable import Echoelmusic

final class ScaleFamilyTests: XCTestCase {

    private var allListed: [Scale] { Scale.Family.allCases.flatMap(\.scales) }

    /// The whole contract in one assertion pair: total (nothing unreachable) and disjoint
    /// (nothing offered twice).
    func testTheFamiliesPartitionEveryScaleExactlyOnce() {
        let listed = allListed
        XCTAssertEqual(Set(listed).count, listed.count,
                       "a scale is listed in two families, so the picker offers it twice: "
                       + duplicates(in: listed).map(\.displayName).sorted()
                                               .joined(separator: ", "))

        let missing = Set(Scale.allCases).subtracting(listed)
        XCTAssertTrue(missing.isEmpty,
                      "UNREACHABLE: \(missing.map(\.displayName).sorted()) exist, persist and "
                      + "decode, but no family lists them, so the picker can never offer "
                      + "them. Add each to exactly one `Family.scales`.")

        // No third `listed.count == allCases.count` assertion: once the two above pass it
        // follows necessarily, so it could never fail on its own (#140's lesson).
        //
        // AND THE STAKE IS HIGHER THAN "one picker looks wrong": `git grep Scale.allCases`
        // over Sources/ returns only a doc comment. `WorkspaceView`'s is the app's ONLY
        // Scale door. A scale missing here is unreachable app-wide, with no second way in —
        // and it degrades silently: no crash, the collapsed row just renders a blank value,
        // the stored scale keeps driving composer, retune and MIDI export, and the player
        // cannot get back to it because picking anything else is one-way.
    }

    /// Empty shelf = a header with nothing under it. The picker deliberately has no
    /// `isEmpty` guard (unlike Genre, where curation can empty a category), because a
    /// guard would hide the mistake instead of showing it.
    func testNoFamilyIsEmpty() {
        for family in Scale.Family.allCases {
            XCTAssertFalse(family.scales.isEmpty,
                           "\(family.title) would render as a header with no rows")
        }
    }

    /// Headers are user-facing text in the permanent chrome. English (the bundle's
    /// `CFBundleDevelopmentRegion`, and the String Catalog will freeze whatever is here as
    /// the source text), distinct, non-empty.
    func testHeadersAreUsableAsSectionTitles() {
        let titles = Scale.Family.allCases.map(\.title)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
        XCTAssertEqual(Set(titles).count, titles.count, "two sections share a header")
        for title in titles {
            XCTAssertFalse(title.contains(where: { "äöüÄÖÜß".contains($0) }),
                           "\"\(title)\" looks German — base language is English "
                           + "(BaseLanguageIsEnglishTests guards the same rule broadly)")
        }
    }

    /// SECTION ORDER, which is what a player actually sees — not the raw spellings.
    ///
    /// ⚠️ THIS PINNED `map(\.rawValue)` FIRST, and that was over-tight in one direction and
    /// under-stated in the other. Family raw values are NOT persisted (verified: no
    /// `Codable`, no `@AppStorage`, no encoder touches `Scale.Family` anywhere), so pinning
    /// the spelling would have reddened a blocking merge over a rename with zero
    /// user-visible effect. What genuinely matters is the ORDER `allCases` yields, because
    /// that is the order the eight shelves appear in — Modes first because it is where most
    /// players start, the cultural shelves last because they are destinations, not
    /// defaults. Pinning the titles pins the order AND stays honest about which fact has a
    /// consumer.
    func testTheSectionOrderIsTheOneAPlayerReads() {
        XCTAssertEqual(Scale.Family.allCases.map(\.title),
                       ["Modes", "Minor & Altered", "Pentatonic & Blues", "Symmetric",
                        "European Folk", "Maqām & Near East", "East & Southeast Asia",
                        "Hindustani & Carnatic"])
    }

    /// Headers must stay short. They render inside chrome clamped to `.accessibility1`,
    /// and a `UIMenu` group title tail-truncates — so an over-long header at AX1 silently
    /// drops its own tail. That is not hypothetical here: these headers carried
    /// "(maqām, 12-TET)" and "(thāt & rāga, 12-TET)" for exactly one commit, at 30
    /// characters against a 20-character longest header in the shipping Genre picker. A
    /// truncated qualifier is worse than none — it drops the caveat and keeps the claim.
    func testHeadersStayShortEnoughNotToTruncateAtAccessibilitySizes() {
        for family in Scale.Family.allCases {
            XCTAssertLessThanOrEqual(family.title.count, 22,
                                     "\"\(family.title)\" (\(family.title.count) chars) is "
                                     + "longer than any header shipping today and will "
                                     + "tail-truncate at accessibility text sizes")
        }
    }

    /// The reason the grouping was worth doing. Both are the 12-TET reading of a maqām and
    /// neither display name says so; the shelf is what makes them findable by a player
    /// from that tradition. Pinned so a later "tidy the sections" edit has to be deliberate.
    func testTheMaqamReadingsAreOnTheNearEastShelf() {
        let nearEast = Scale.Family.middleEast.scales
        XCTAssertTrue(nearEast.contains(.doubleHarmonic),
                      "doubleHarmonic is Maqām Ḥijāz-kār and its label never says so")
        XCTAssertTrue(nearEast.contains(.phrygianDominant),
                      "phrygianDominant IS Maqām Ḥijāz and its label never says so")

        // `persian` is on the shelf and is NOT a maqām — which is why the header reads
        // "Maqām & Near East" and not "Maqām". Persian classical music is dastgāh/radif,
        // and [0,1,4,5,6,8,11] is a Western catalogue construct rather than dastgāh theory
        // at all. It sits here because that is where a player looks for the colour.
        XCTAssertTrue(nearEast.contains(.persian))
        XCTAssertEqual(Scale.Family.middleEast.title, "Maqām & Near East",
                       "the header must not narrow to \"Maqām\" while persian is on it")

        // The restraint — but NOT for the reason first written here. `romanianMinor` IS
        // Nikrīz (well established, not contested) and `hungarianMinor` reads as Nawa
        // Athar; the earlier comment had the pair backwards and called the solid
        // equivalence disputed. The decision stands anyway: a scale lives on one shelf,
        // and both are European folk material far more often than they are maqām.
        XCTAssertFalse(nearEast.contains(.hungarianMinor))
        XCTAssertFalse(nearEast.contains(.romanianMinor))
    }

    /// The seven from #232 J stay together — a grouping that scattered them would undo the
    /// visibility the previous slice bought.
    func testTheIndianShelfHoldsAllSevenAndOnlyThose() {
        XCTAssertEqual(Set(Scale.Family.india.scales),
                       [.marwa, .purvi, .todi, .malkauns, .charukeshi, .hamsadhwani,
                        .shanmukhapriya])
    }

    private func duplicates(in scales: [Scale]) -> [Scale] {
        var seen = Set<Scale>()
        var twice = Set<Scale>()
        for s in scales where !seen.insert(s).inserted { twice.insert(s) }
        return Array(twice)
    }
}
