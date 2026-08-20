// OneSpellingOfTheDemoSubjectTests.swift
// Echoel — #649: the mid-sentence demo subject had ten spellings and one of them was
// invisible to the tool this family uses to check itself.
//
// WHAT THIS GUARDS. Every surface that renders a reading from `BioSimulator` names it with the
// same phrase — "the simulated demo source, not your body". Before this slice that phrase was
// written out at TEN code sites. Nine were findable with `git grep`; the tenth, in
// `autoModeHint`, split the phrase MID-PHRASE across two literals to fit the line limit
// (`"… of the simulated demo " + "source, not your body"`), so no search for the contiguous
// phrase ever returned it and no source scan in this bundle could have policed it.
//
// ⭐ THAT IS A DIFFERENT ARGUMENT FROM ORDINARY #416, and it is why this slice happened at all.
// "Two spellings drift" is a prediction. "One of ten was already unreachable by the checking
// tool" is a measurement — and it means the previous state was not merely duplicated, it was
// duplicated in a way that hid one copy from review. `BioProvenanceCopy.demoSubject` is now the
// one definition; `demoSubjectSentenceInitial` is DERIVED from it, never re-spelled.
//
// ⛔ AND THE FIRST DRAFT OF THIS SLICE'S OWN DOC SAID "three of nine were split" — written from
// the shape of the diff, not from a count. Two of the three break at a LINE boundary with the
// phrase intact inside one literal, so grep found them. Corrected before the commit. The
// lesson this file adds to the pile is narrow: **a claim about what a grep can see must be
// made by running the grep, not by looking at where the line breaks fall.**
//
// KIND (§1): **MIXED.** Claims 1–3 DRIVE the shipped pure types (`BioProvenanceCopy`,
// `BioPanelRowCopy`, `TempoFollowLabel`, `BioVariationMaze`, `AlwaysOnBioChannel`,
// `BioShapedParameter`) — END-TO-END, the strong kind. Claims 4–5 are SOURCE-TEXT SCANS over
// `Sources/`, which is the only way to state "there is no SECOND definition". **DEVICE PROBE,
// open:** that VoiceOver speaks the phrase intelligibly is not checkable here.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (7e906cd), both trees, raw and
// stripped by the same comment rule `SourceText.codeOnly` applies:
//   · **1 REGRESSION — claim 4.** The contiguous phrase occurs **9** times in parent `Sources/`
//     code and **1** in this tree. `== 1` is red there for exactly the reason its name gives.
//   · **1 REGRESSION — claim 5** (the split-detector). `autoModeHint`'s parent form ends a
//     literal with `simulated demo ` and opens the next with `source, not your body`; both
//     halves of the scan hit there and neither hits here.
//   · **2 FORWARD — claims 1 and 2.** They drive `BioProvenanceCopy`, which is born with this
//     commit; they could never have been red on the parent (one absence, #486). Claim 2 is the
//     one that matters: it drives the DERIVATION, so a future hand-written capitalised literal
//     is the failure it catches.
//   · **1 COUNTERWEIGHT — claim 3**, green on both trees, and it is the point of the file. It
//     re-renders every sentence the migration touched and asserts each still marks its demo
//     branch and each body branch still says nothing about a demo. A migration that changed a
//     rendered byte would be a copy regression wearing a refactor's clothes; this is what says
//     it did not. ⚠️ `soundPanelSentence` is asserted SEPARATELY and more weakly, because its
//     clause-carrying branch is conditional on a non-empty row list — folding it into the loop
//     would have made a claim about the hoist depend on a fact about the channel audit.
//   · **1 COUNTERWEIGHT — claim 6**, green on both trees: the OTHER two documented forms still
//     exist at their own sites. Folding them into this one is #634b, and the cheapest wrong
//     next step after a successful hoist is exactly that.
//   · **Stripper: TRAGEND, MEASURED — 2 of the 4 scan verdicts flip raw-vs-stripped on THIS
//     tree.** The definition's own doc block quotes the phrase and quotes the split halves, so
//     an unstripped claim 4 counts 4 instead of 1 and an unstripped claim 5 fires on the very
//     comment that explains it. First genuinely load-bearing stripper in this family after
//     three prophylactic ones — and the reason is structural, not luck: a guard whose subject
//     is A SPELLING will always be quoted by the prose that justifies it.
//
// ⚠️ #364: rewording the marker is NOT forbidden — change the one `static let` and every one of
// the ten sites moves with it, which is the whole benefit. What claims 4–5 forbid is a SECOND
// place that spells it. A genuinely new demo sentence that cannot use the constant (there are
// four such today, each named at the definition with its grammatical reason) is legitimate; it
// simply must not re-spell this phrase.

import Foundation
import XCTest
@testable import Echoelmusic

final class OneSpellingOfTheDemoSubjectTests: XCTestCase {

    private static let phrase = "simulated demo source, not your body"

    /// 1 — FORWARD. The one definition still says both halves a marker has to say.
    ///
    /// ⚠️ NOT pinned character-for-character on purpose (#364): the founder may reword it, and
    /// the point of the hoist is that a reword is one edit. What may not vanish is either half
    /// — name the source, and deny the body.
    func testTheOneDefinitionNamesTheSourceAndDeniesTheBody() {
        XCTAssertTrue(BioProvenanceCopy.demoSubject.contains("simulated demo"), """
            The one definition stopped naming the demo generator. Every marked surface in this \
            family renders this string; if it stops saying where the reading came from, ten \
            surfaces stop saying it at once — which is the same leverage that makes the hoist \
            worth having, pointed the wrong way.
            """)
        XCTAssertTrue(BioProvenanceCopy.demoSubject.contains("not your body"), """
            The one definition stopped denying the body. Naming the source without denying the \
            body leaves the reader to infer the point; #627's whole family exists because that \
            inference is not made.
            """)
    }

    /// 2 — FORWARD, and the assertion this file exists to make twice. The sentence-initial form
    /// is DERIVED, so it cannot drift from the mid-sentence one.
    func testTheSentenceInitialFormIsDerivedAndNotRespelled() {
        let mid = BioProvenanceCopy.demoSubject
        let head = BioProvenanceCopy.demoSubjectSentenceInitial
        XCTAssertEqual(head, mid.prefix(1).uppercased() + mid.dropFirst(), """
            The sentence-initial form is no longer a capitalisation of the mid-sentence form. \
            The only difference between the two is the first letter; the moment the second one \
            is hand-written, a reword of the first silently leaves the Sound panel behind — \
            which is precisely the ten-spelling state this slice removed.
            """)
        XCTAssertEqual(head.dropFirst(), mid.dropFirst(), """
            The two forms differ beyond their first character. Then they are two strings, not \
            one string in two positions.
            """)
    }

    /// 3 — COUNTERWEIGHT, green on both trees, and the reason a refactor may be trusted: every
    /// rendered sentence the migration touched still marks its demo branch, and no body branch
    /// gained a demo word.
    func testEveryMigratedSentenceStillMarksOnlyItsDemoBranch() {
        // ⚠️ `soundPanelSentence` is DELIBERATELY NOT in this list, and the reason is a premise
        // this file must not silently assume: its subject branch only renders when
        // `shapedByTheBody.flatMap(\.soundPanelRows)` is non-empty. With no rows it returns
        // "The simulated demo source is not shaping any control on this panel right now." —
        // honest, marked, and WITHOUT the clause, because "…, not your body, is not shaping…"
        // is not a sentence. Asserting the full phrase over it would make this claim depend on
        // the row list rather than on the hoist. It gets its own assertion below.
        let demo: [String] = [
            AlwaysOnBioChannel.alwaysOnSentence(synthetic: true),
            AlwaysOnBioChannel.bioPanelSentence(synthetic: true),
            BioPanelRowCopy.subject(synthetic: true),
            BioPanelRowCopy.breathVoiceHint(for: Self.frame(.fallback)),
            BioPanelRowCopy.breathVoiceCaption(for: Self.frame(.fallback)),
            BioPanelRowCopy.autoModeHint(for: Self.frame(.fallback)),
            BioPanelRowCopy.autoModeCaption(for: Self.frame(.fallback)),
            TempoFollowLabel.spoken(for: Self.frame(.fallback)),
            BioVariationMaze.boardSentence(driver: .simulatedDemo, density: "a calm groove"),
        ]
        for text in demo {
            XCTAssertTrue(text.lowercased().contains(Self.phrase), """
                A demo sentence stopped carrying the marker: "\(text)". The hoist is only safe \
                while every call site still renders the constant; a site that drops it renders \
                a body claim over the simulator, which is the defect, not the refactor.
                """)
        }
        // Both of `soundPanelSentence`'s demo branches name the source; only one carries the
        // clause. This is the assertion that holds under EITHER row list.
        XCTAssertTrue(BioShapedParameter.soundPanelSentence(synthetic: true)
                        .contains("simulated demo source"), """
            The Sound panel's line stopped naming the demo generator in its demo branch. Both \
            of its branches must — the one that lists rows renders the sentence-initial form of \
            the constant, the one that reports "not shaping anything" says it in its own words.
            """)
        let body: [String] = [
            AlwaysOnBioChannel.alwaysOnSentence(synthetic: false),
            AlwaysOnBioChannel.bioPanelSentence(synthetic: false),
            BioShapedParameter.soundPanelSentence(synthetic: false),
            BioPanelRowCopy.subject(synthetic: false),
            BioPanelRowCopy.breathVoiceHint(for: Self.frame(.cameraPPG)),
            BioPanelRowCopy.breathVoiceCaption(for: Self.frame(.cameraPPG)),
            BioPanelRowCopy.autoModeHint(for: Self.frame(.cameraPPG)),
            BioPanelRowCopy.autoModeCaption(for: Self.frame(.cameraPPG)),
            TempoFollowLabel.spoken(for: Self.frame(.cameraPPG)),
            BioVariationMaze.boardSentence(driver: .body, density: "a calm groove"),
        ]
        for text in body {
            XCTAssertFalse(text.lowercased().contains("simulated demo"), """
                A REAL-BODY sentence names the demo generator: "\(text)". The hoist must not \
                leak the marker into the ordinary path — that path's wording is the founder's \
                and stays byte-identical.
                """)
        }
    }

    /// 4 — REGRESSION. Exactly ONE code-level spelling of the phrase in `Sources/`.
    func testThePhraseIsSpelledOnceInTheWholeSource() throws {
        let hits = try Self.phraseHits()
        XCTAssertEqual(hits.count, 1, """
            The phrase is spelled at \(hits.count) code sites, not one: \
            \(hits.map(\.description).joined(separator: ", ")). It was TEN before #649 and one \
            of the ten was invisible to grep. Render \
            `BioProvenanceCopy.demoSubject` instead of writing it out; if a new sentence \
            genuinely cannot use it, it must not re-spell it either — see the four grammatical \
            exceptions named at the definition.
            """)
        // ⛔ THIS COMPARED THE PATH TO "Studio/AlwaysOnBioChannel.swift" AND WAS RED ON ITS OWN
        // CORRECT TREE — the walk is rooted at `Sources/`, so every path it yields begins
        // `Echoelmusic/`. Caught by driving the scan in Python before first run, which is the
        // only reason it is not another entry in this bundle's red-on-correct-work list. A
        // suffix, so the guard survives a directory move without inviting the next one.
        XCTAssertEqual(hits.first?.file.hasSuffix("Studio/AlwaysOnBioChannel.swift"), true, """
            The single spelling moved out of the file that declares `BioProvenanceCopy`. That \
            is not forbidden, but the constant and its one literal must travel together — \
            otherwise the definition reads as a reference to something written elsewhere.
            """)
    }

    /// 5 — REGRESSION, and the one an ordinary count could never make: the phrase must not be
    /// re-broken across two literals, which is how the tenth site hid.
    ///
    /// ⚠️ Narrow ON PURPOSE. It looks only for a literal ENDING in "simulated demo " or
    /// BEGINNING with "source, not your body" — the exact seam `autoModeHint` had. No honest
    /// sentence ends a literal on "simulated demo " with more to come; the shipped prefix form
    /// ends on "Simulated demo, " (a comma), which this does not match.
    func testThePhraseIsNotReBrokenAcrossTwoLiterals() throws {
        for (file, line, text) in try Self.codeLines() {
            XCTAssertFalse(text.contains("simulated demo \""), """
                \(file):\(line) ends a string literal on "simulated demo " with the sentence \
                continuing in the next literal. That is exactly how the tenth spelling stayed \
                invisible to every grep for four cycles. Concatenate \
                `BioProvenanceCopy.demoSubject` instead of splitting the words.
                """)
            XCTAssertFalse(text.contains("\"source, not your body"), """
                \(file):\(line) opens a string literal on the tail of the marker phrase. Same \
                seam as above, seen from the other side.
                """)
        }
    }

    /// 6 — COUNTERWEIGHT, green on both trees. The other two documented forms are still their
    /// own strings. A successful hoist makes "fold the rest in too" look tidy; it is #634b.
    func testTheOtherFormsAreNotFoldedIntoThisOne() throws {
        let all = try Self.codeLines().map(\.2).joined(separator: "\n")
        XCTAssertTrue(all.contains("Bio source: simulated demo, not your body"), """
            The element-LABEL form is gone from `Sources/`. It labels a whole control (strip · \
            widget · watch) and ends a sentence; this phrase continues into a clause. They are \
            two jobs. Note the label also lives in the watch and widget TARGETS, which \
            `project.yml` does not give `Studio/AlwaysOnBioChannel.swift` — it cannot be \
            hoisted here even if someone wanted to.
            """)
        XCTAssertTrue(all.contains("\"Simulated demo, \""), """
            The spoken-PREFIX form is gone from `Sources/`. It starts a spoken sentence; this \
            phrase sits inside one. Collapsing them makes one of the two read wrong.
            """)
    }

    // MARK: - helpers

    private struct Hit: CustomStringConvertible {
        let file: String
        let line: Int
        var description: String { "\(file):\(line)" }
    }

    private static func frame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 12, breathPhase: 0.25,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    private static func sourcesRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "Sources/ not present in this checkout")
        return sources
    }

    /// Every code line under `Sources/`, comments blanked by the one stripper (#453).
    private static func codeLines() throws -> [(String, Int, String)] {
        let sources = try sourcesRoot()
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            XCTFail("cannot enumerate Sources/ — re-anchor this scan (#454)")
            return []
        }
        var out: [(String, Int, String)] = []
        var files = 0
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(rel)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files += 1
            for (i, line) in SourceText.codeOnly(raw).split(separator: "\n",
                                                           omittingEmptySubsequences: false).enumerated() {
                out.append((rel, i + 1, String(line)))
            }
        }
        // #454: an extraction that returns nothing makes every negative claim above vacuous.
        XCTAssertGreaterThan(files, 200, """
            The walk found \(files) Swift files under Sources/ — far fewer than this repo has. \
            Claims 5 and 6 are negatives over this list, so a short walk turns them green \
            without looking at anything.
            """)
        return out
    }

    private static func phraseHits() throws -> [Hit] {
        try codeLines().filter { $0.2.lowercased().contains(phrase) }
            .map { Hit(file: $0.0, line: $0.1) }
    }
}
