// LearnLibraryTests.swift
// Echoel — the unified "Learn" index. Asserts it covers all sources, has unique
// ids, and carries the safety scope honestly.

import XCTest
@testable import Echoelmusic

final class LearnLibraryTests: XCTestCase {

    func testSectionsCoverEverySource() {
        XCTAssertEqual(LearnLibrary.guideEntries.count, 6)   // #589 — hand-written, like safety
        XCTAssertEqual(LearnLibrary.bodyEntries.count, BioMetric.allCases.count)
        XCTAssertEqual(LearnLibrary.bodyScienceEntries.count, BioScienceTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.musicEntries.count, MusicTheoryTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.lightEntries.count, LightScienceTopic.allCases.count)
        XCTAssertEqual(LearnLibrary.safetyEntries.count, 2)
    }

    func testAllIsSectionOrderedAndComplete() {
        let all = LearnLibrary.all
        XCTAssertEqual(all.count,
                       6 + BioMetric.allCases.count + BioScienceTopic.allCases.count
                       + MusicTheoryTopic.allCases.count
                       + LightScienceTopic.allCases.count + 2)
        // #589: the Guide opens the library — the way IN before the reference material
        // (founder: "leichtes Eintauchen … hörbar, sichtbar und spürbar"). Safety stays last.
        let sections = all.map { $0.section }
        XCTAssertEqual(sections.first, .guide)
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
        // Looked up by ID, not by index: the contraindications entry now sits first,
        // and an index-based assertion would silently test the wrong entry.
        let d = LearnLibrary.safetyEntries
            .first { $0.id == "safety.scope" }?.detail.lowercased()
        XCTAssertNotNil(d)
        XCTAssertTrue(d?.contains("diagnos") ?? false)
        XCTAssertTrue(d?.contains("not") ?? false)
    }

    /// CLAUDE.md mandates five in-app safety warnings. Four of them were reachable
    /// ONLY through one-time onboarding (no reset path), so a returning user or an App
    /// Review pass on a second launch could not see them at all. They now have a
    /// permanent home in the Learn library — this test is what keeps them there.
    func testContraindicationsEntryCarriesEveryMandatedWarning() {
        let e = LearnLibrary.safetyEntries.first { $0.id == "safety.contraindications" }
        XCTAssertNotNil(e, "the persistent safety entry must exist")
        let text = ((e?.title ?? "") + " " + (e?.summary ?? "") + " " + (e?.detail ?? ""))
            .lowercased()
        for required in ["driving", "machinery", "alcohol", "drugs",
                         "provider", "reduce motion"] {
            XCTAssertTrue(text.contains(required),
                          "mandated safety warning missing the word '\(required)'")
        }
        // The 3 Hz cap must be stated as a number, not paraphrased away.
        XCTAssertTrue(text.contains("3 flashes per second") || text.contains("3 hz"),
                      "the WCAG flash cap must be stated explicitly")
        // It is a LIMIT, never a treatment claim.
        XCTAssertTrue(text.contains("not part of a treatment"))
    }

    /// The warnings must be reachable without onboarding — i.e. they must be part of
    /// the `.safety` section the Learn surface renders, not a detached constant.
    func testContraindicationsAreInTheRenderedSafetySection() {
        let ids = LearnLibrary.entries(for: .safety).map(\.id)
        XCTAssertTrue(ids.contains("safety.contraindications"))
        XCTAssertTrue(LearnLibrary.all.map(\.id).contains("safety.contraindications"))
    }

    func testNoEsotericClaimsAnywhere() {
        let banned = ["healing", "chakra", "solfeggio", "quantum", "akasha", "planetary", "aura"]
        for e in LearnLibrary.all {
            let text = (e.title + " " + e.summary + " " + e.detail).lowercased()
            for term in banned { XCTAssertFalse(text.contains(term), "\(e.id) contains '\(term)'") }
        }
    }
}
