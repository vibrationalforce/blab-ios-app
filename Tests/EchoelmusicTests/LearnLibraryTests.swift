// LearnLibraryTests.swift
// Echoel — the unified "Learn" index. Asserts it covers all sources, has unique
// ids, and carries the safety scope honestly.

import XCTest
@testable import Echoelmusic

final class LearnLibraryTests: XCTestCase {

    func testSectionsCoverEverySource() {
        XCTAssertEqual(LearnLibrary.bodyEntries.count, BioMetric.allCases.count)
        XCTAssertEqual(LearnLibrary.bodyScienceEntries.count, BioScienceTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.musicEntries.count, MusicTheoryTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.lightEntries.count, LightScienceTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.safetyEntries.count, 1)
    }

    func testAllIsSectionOrderedAndComplete() {
        let all = LearnLibrary.all
        XCTAssertEqual(all.count,
                       BioMetric.allCases.count + BioScienceTopic.allCases.count
                       + MusicTheoryTopic.allCases.count
                       + LightScienceTopic.allCases.count + 1)
        // Body entries come first; safety stays last.
        let sections = all.map { $0.section }
        XCTAssertEqual(sections.first, .body)
        XCTAssertEqual(sections.last, .safety)
    }

    func testBodyScienceMakesNoMedicalClaim() {
        // Same red line as light science: cited FACTS + self-observation, never
        // treatment. The scope entry is exempt because it explicitly DENIES it.
        let banned = ["cure", "treat ", "therapy", "heals", "diagnos", "remedy", "pain", "wound"]
        for e in LearnLibrary.bodyScienceEntries where e.id != "bodyScience.scope" {
            let text = (e.title + " " + e.summary + " " + e.detail).lowercased()
            for term in banned {
                XCTAssertFalse(text.contains(term), "\(e.id) contains medical term '\(term)'")
            }
        }
        // The scope entry explicitly denies medical/treatment use.
        let scope = LearnLibrary.bodyScienceEntries.first { $0.id == "bodyScience.scope" }?.detail.lowercased()
        XCTAssertNotNil(scope)
        XCTAssertTrue(scope?.contains("not a medical device") ?? false)
        XCTAssertTrue(scope?.contains("treats no condition") ?? false)
    }

    func testBodyScienceCitesResonanceAndResearch() {
        // The point of the surface: the strongest-evidence science is present + cited.
        let ids = Set(LearnLibrary.bodyScienceEntries.map(\.id))
        XCTAssertTrue(ids.contains("bodyScience.resonanceFrequency"))
        XCTAssertTrue(ids.contains("bodyScience.hrvResearch"))
        let research = LearnLibrary.bodyScienceEntries
            .first { $0.id == "bodyScience.hrvResearch" }?.detail ?? ""
        XCTAssertTrue(research.contains("meta-analysis"), "research entry must cite the evidence")
        XCTAssertTrue(research.contains("self-reported"), "must frame as self-report, not treatment")
    }

    func testLightScienceMakesNoMedicalClaim() {
        // Brand red line: light science is FACTS + self-observation, never therapy.
        // The medical VERBS below are not enough on their own — the pre-Echoel healing
        // theme (red-light therapy) slips past them as NOUNS ("photobiomodulation",
        // "mitochondrial cytochrome-c-oxidase", light "into tissue") while appending a
        // "no health claim" disclaimer. Those nouns have no creative-light reason to
        // appear, so they are banned outright — the framing is the violation, not just
        // the claim.
        let banned = ["cure", "treat ", "therapy", "heals", "diagnos", "remedy",
                      "photobiomod", "mitochond", "cytochrome", "tissue"]
        for e in LearnLibrary.lightEntries where e.id != "light.scope" {
            let text = (e.title + " " + e.summary + " " + e.detail).lowercased()
            for term in banned {
                XCTAssertFalse(text.contains(term), "\(e.id) contains medical term '\(term)'")
            }
        }
        // The scope entry explicitly DENIES therapy/medical use.
        let scope = LearnLibrary.lightEntries.first { $0.id == "light.scope" }?.detail.lowercased()
        XCTAssertNotNil(scope)
        XCTAssertTrue(scope?.contains("not light therapy") ?? false)
    }

    func testIdsAreUnique() {
        let ids = LearnLibrary.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicate entry ids")
    }

    func testEveryEntryFullyPopulated() {
        for e in LearnLibrary.all {
            XCTAssertFalse(e.title.isEmpty, e.id)
            XCTAssertFalse(e.summary.isEmpty, e.id)
            XCTAssertGreaterThan(e.detail.count, 40, e.id)
        }
    }

    func testSafetyEntryStatesScope() {
        let d = LearnLibrary.safetyEntries[0].detail.lowercased()
        XCTAssertTrue(d.contains("diagnos"))
        XCTAssertTrue(d.contains("not"))
    }

    func testNoEsotericClaimsAnywhere() {
        let banned = ["healing", "chakra", "solfeggio", "quantum", "akasha", "planetary", "aura"]
        for e in LearnLibrary.all {
            let text = (e.title + " " + e.summary + " " + e.detail).lowercased()
            for term in banned { XCTAssertFalse(text.contains(term), "\(e.id) contains '\(term)'") }
        }
    }
}
