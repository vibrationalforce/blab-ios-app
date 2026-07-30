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
// `phrygianDominant` sit on the Middle Eastern shelf because they are the 12-TET readings
// of Maqām Ḥijāz-kār and Ḥijāz. That was the point of the slice — those two were reachable
// only under Western names — so a later reshuffle that quietly moves them back is the
// regression, not a cleanup.

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

        XCTAssertEqual(listed.count, Scale.allCases.count)
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

    /// Raw values are the stable identity of a family. They are not persisted TODAY, and
    /// this test says so rather than implying otherwise — but `Identifiable.id` is the raw
    /// value and SwiftUI diffs `ForEach` on it, so a rename still re-identifies every
    /// section at runtime.
    func testFamilyRawValuesAreStable() {
        XCTAssertEqual(Scale.Family.allCases.map(\.rawValue),
                       ["modes", "minorAndAltered", "pentatonicAndBlues", "symmetric",
                        "europeanFolk", "middleEast", "eastAsia", "india"])
    }

    /// The reason the grouping was worth doing. Both are the 12-TET reading of a maqām and
    /// neither display name says so; the shelf is what makes them findable by a player
    /// from that tradition. Pinned so a later "tidy the sections" edit has to be deliberate.
    func testTheMaqamReadingsAreOnTheMiddleEasternShelf() {
        let middleEast = Scale.Family.middleEast.scales
        XCTAssertTrue(middleEast.contains(.doubleHarmonic),
                      "doubleHarmonic is Maqām Ḥijāz-kār and its label never says so")
        XCTAssertTrue(middleEast.contains(.phrygianDominant),
                      "phrygianDominant IS Maqām Ḥijāz and its label never says so")

        // And the restraint: the contested attributions stayed European. Widening this
        // shelf buys breadth with a claim a reader could falsify.
        XCTAssertFalse(middleEast.contains(.hungarianMinor))
        XCTAssertFalse(middleEast.contains(.romanianMinor))
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
