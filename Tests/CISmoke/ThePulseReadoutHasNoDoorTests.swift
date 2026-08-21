// ThePulseReadoutHasNoDoorTests.swift
// Echoel — a surface that says it is on screen, and is not. #525.
//
// WHAT WAS WRONG, and it was one sentence in the first paragraph of a file. The header of
// `PulseMeasurementView.swift` said the readout is "shown above the controls while a take is
// playing". Measured (`git grep -n 'PulseMeasurementView(' -- Sources`): ONE construction
// site, `BioSourceView.swift`. `git grep -n 'BioSourceView(' -- Sources`: ZERO. The chain
// terminates one hop up — nothing in the app mounts it, during a take or otherwise.
//
// ⭐ WHY IT IS WORTH A GUARD RATHER THAN A QUIET EDIT. This is the OTHER END of #523. That
// slice found the rPPG stall remedy reaching a sighted user nowhere; the reason is that
// `CameraRPPGBioPublisher.coachingHint` has exactly ONE reader in `Sources/`, and that reader
// is this view. A file whose opening line says it is on screen is precisely what stops the
// next person noticing. Six places now assert this view's doorlessness in prose — this file,
// the view's own header, `BioStripView`, `PulseCue`, and two blocks in
// `TheStallRemedyReachesTheScreenTests` — and prose cannot notice when it stops being true.
//
// ⚠️ THIS GUARD DOES NOT FORBID RE-DOORING IT (#364). Mounting the readout is welcome work;
// what the guard forbids is doing it while six files keep saying it is unreachable. When it
// goes red for that reason, the fix is to update those six IN THE SAME COMMIT, not to delete
// the assertion — the failure messages below name them.
//
// ⚠️ AND IT MUST NOT BECOME AN ARGUMENT FOR DELETING THE FILE. `PulseMeasurementView`'s header
// carries the canonical statement of the 10.76.41/50 freeze law for this shape, and CLAUDE.md
// cites the view BY NAME as the worked example. That is the #472 trap — a doorless VIEW
// sharing a file with something load-bearing — so `testTheFreezeLawStillHasItsWorkedExample`
// is a counterweight, not decoration.
//
// ⚠️ HONEST GRADING (#433/#464). This file COMPILES against the parent tree — it names no
// symbol this commit adds — so every assertion really has a verdict there, unlike #523's.
// Transcribed by hand (a Python rebuild of `SourceText.codeOnly`, run against
// `git show HEAD:` and the worktree):
//   · **ONE needle is red on the parent**, and it is the entire defect: the header's claim,
//     which on `HEAD` sits on a line with no `SAID` on it. That is the regression.
//   · **FOUR are counterweights**, green on both trees, and they are the value. The two
//     construction-site scans return the same answer on both trees — `['Studio/BioSourceView.swift']`
//     and `[]` — because #525 changed prose, not wiring. They exist so that the day someone
//     re-doors this view, the six prose sites go stale LOUDLY instead of silently.
//   · No assertion here proves the app is correct; every one proves that a sentence and a
//     measurement still agree.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING for the construction-site scans, and that is
// MEASURED rather than assumed (#484 and #485 each had to withdraw the stronger claim once,
// #486 twice). The corrected header this slice writes quotes `git grep -n 'BioSourceView('`
// verbatim to show its working — so on the worktree the RAW text of `PulseMeasurementView.swift`
// carries that needle while its CODE does not, and a raw scan would report the readout's own
// file as a construction site of its parent: **RED ON CORRECT CODE**. Measured: raw `True`,
// stripped `False`. The #486/#491 collision again — this repo writes down what it measured.
//
// ⛔ AND THE STRIPPER IS THE WRONG TOOL FOR THE HEADER NEEDLE, which is the sharper half of the
// same lesson. That claim lives in a COMMENT on both trees, so `codeOnly` blanks it either way
// and the assertion becomes unwritable rather than merely raw-fragile. Neither raw nor stripped
// works; the shape that does is SCOPED — see `testTheHeaderStatesTheClaimOnlyToWithdrawIt`.
// One file, two needles, two different right answers about the same helper.
//
// ⚠️ AND THE LIMIT FIRST. Every assertion here is a SOURCE SCAN. It proves where text is, not
// what the app draws. It cannot prove the readout is invisible on a device — only that no line
// in `Sources/` constructs it. `Tests/CISmoke` is the blocking bundle; a missing tree SKIPS.

import Foundation
import XCTest

final class ThePulseReadoutHasNoDoorTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let readout = "Sources/Echoelmusic/Studio/PulseMeasurementView.swift"

    // MARK: - The chain terminates

    /// The readout is constructed exactly once, and only by `BioSourceView`.
    func testTheReadoutHasExactlyOneConstructionSite() throws {
        let sites = try constructionSites(of: "PulseMeasurementView")
        XCTAssertEqual(sites, ["Studio/BioSourceView.swift"], """
            `PulseMeasurementView` is constructed at \(sites.isEmpty ? "no site" : sites.joined(separator: ", ")) \
            rather than only `Studio/BioSourceView.swift`. If you MOUNTED it, that is welcome \
            work — but six places currently state in prose that it is unreachable, and they go \
            stale in this same commit or not at all: this file, the view's own header, \
            `BioStripView`'s ⭐ block about `fullHint`, `PulseCue.warrantsFullHintOnScreen`'s ⛔ \
            block, and two blocks in `TheStallRemedyReachesTheScreenTests`. If instead it is \
            constructed NOWHERE, say so there too — "one mount, behind a doorless parent" and \
            "no mount at all" are different facts.
            """)
    }

    /// …and that one parent is itself constructed nowhere, which is what makes it doorless.
    ///
    /// This is the half a reachability check usually gets wrong (CLAUDE.md's own lesson: a
    /// construction site is NOT proof of reachability, because the caller can be dead too).
    func testTheOnlyParentIsItselfUnmounted() throws {
        let sites = try constructionSites(of: "BioSourceView")
        XCTAssertTrue(sites.isEmpty, """
            `BioSourceView` is now constructed at \(sites.joined(separator: ", ")) — so the pulse \
            readout has a door for the first time since the tools-grid removal. Nothing about \
            that is wrong; what IS wrong is leaving the six prose sites listed in the sibling \
            assertion saying the opposite. Update them here, in this commit.
            """)
    }

    // MARK: - Counterweights

    /// COUNTERWEIGHT — the header must keep saying what it now says.
    ///
    /// A guard that only pins the construction count stays green on a tree that restores the
    /// old "shown above the controls while a take is playing" sentence — the #343 shape, where
    /// the FACT survives and the DESCRIPTION goes back to lying.
    /// ⛔ AND THE FIRST VERSION OF THIS ASSERTION WOULD HAVE BEEN RED ON CORRECT CODE — caught
    /// by measuring before the commit, in the very file whose header warns about it. It was a
    /// bare `XCTAssertFalse(raw.contains(<the sentence>))`, and the retraction this slice writes
    /// QUOTES the sentence verbatim in order to withdraw it. `SourceText.codeOnly` cannot save
    /// a needle like this either: the claim lives in a comment on BOTH trees, so a stripped scan
    /// sees nothing at all and the assertion becomes unwritable rather than merely wrong. The
    /// shape that works is neither raw nor stripped but SCOPED — every line carrying the
    /// sentence must also carry `SAID`, i.e. must be a retraction. Restore the claim as a claim
    /// and it lands on a line without that word.
    func testTheHeaderStatesTheClaimOnlyToWithdrawIt() throws {
        let raw = try rawText(Self.readout)
        let sentence = "shown above the controls while a take is playing"
        let offenders = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(sentence) && !$0.contains("SAID") }
        XCTAssertTrue(offenders.isEmpty, """
            The readout's header asserts again that it is "\(sentence)", outside a retraction:
            \(offenders.joined(separator: "\n"))
            It is not: its only parent, `BioSourceView`, has zero construction sites. That \
            sentence is what made the #523 defect hard to see — `coachingHint`'s ONLY reader is \
            this view, so a header saying it is on screen implies the rPPG remedy reaches \
            somebody. If it has genuinely been re-doored, this guard's two construction-site \
            assertions go red in the same run and the six prose sites they name are the work.
            """)
    }

    /// COUNTERWEIGHT — doorless must not read as deletable.
    ///
    /// `PulseMeasurementView`'s header is where the 10.76.41/50 freeze law is written out for
    /// this shape, and CLAUDE.md cites the view by name as the worked example. Deleting the
    /// "unreachable" file would take the law's home with it — the #472 trap, where a doorless
    /// VIEW and a load-bearing neighbour share one file.
    func testTheFreezeLawStillHasItsWorkedExample() throws {
        let raw = try rawText(Self.readout)
        XCTAssertTrue(raw.contains("WHY ITS OWN VIEW"), """
            The freeze-law rationale is gone from `PulseMeasurementView.swift`. That block is \
            the canonical statement of the 10.76.41/50 rule for this shape — a ~10 Hz \
            `@Observable` read belongs in its own leaf `View` struct, because `AnyView` is not \
            an observation boundary — and CLAUDE.md points at this view as the example. If the \
            file is being removed, the law moves FIRST and the citations move with it.
            """)
        XCTAssertTrue(raw.contains("struct PulseMeasurementView: View"), """
            `PulseMeasurementView` is no longer declared in its own file. Folding it back into \
            a computed `var` on `EchoelStudioView` is the exact regression the 10.76.41 freeze \
            fix undid: those ~10 Hz `cameraRPPG` reads would register the root body as an \
            observer again and tear down any open `.menu` Picker while playing.
            """)
    }

    /// COUNTERWEIGHT — the one consumer that makes the doorlessness matter.
    ///
    /// `coachingHint` exists to be read. If its last reader disappears, the property becomes a
    /// producer with no consumer and this whole file is describing nothing.
    /// ⛔ THIS MESSAGE ONCE SAID a second reader "changes #523's premise — the rPPG remedy
    /// would reach a surface other than this doorless one", and that premise was ALREADY false
    /// when it was written (#703). The remedy reaches a sighted user through
    /// `acquisitionCue.fullHint`, not through this property: `BioStripView` banners it in
    /// `bioPanel` behind the Bio chip, gated by `cueWarrantsFullHintOnScreen`, and
    /// `TheStallRemedyReachesTheScreenTests.testTheStripRendersTheStallRemedy` — in this same
    /// bundle — pins exactly that. Two guards one directory apart resting on premises that
    /// contradict each other, and CLAUDE.md inherited the wrong one and stated a shipped
    /// capability as missing. The ASSERTION below was and is correct; only its explanation was
    /// wrong. **What is dead is the PROPERTY, not the capability** — which is why this claim is
    /// worth keeping and why its message must not imply otherwise.
    func testTheReadoutIsStillTheOnlyReaderOfTheCoachingHint() throws {
        let readers = try filesUnderSources(containing: "coachingHint")
            .filter { $0 != "Bio/CameraRPPGBioPublisher.swift" }
        XCTAssertEqual(readers, ["Studio/PulseMeasurementView.swift"], """
            `coachingHint` is read by \(readers.isEmpty ? "nothing" : readers.joined(separator: ", ")) \
            rather than only the pulse readout. A SECOND reader means the ⛔ blocks in \
            `PulseCue` and `BioStripView` need rewriting with it. NO reader at all means the \
            publisher is computing a sentence for nobody.
            """)
    }

    // MARK: - Reading the source

    /// Files under `Sources/Echoelmusic` whose CODE constructs `type` — the declaring file and
    /// any file that merely mentions it in prose are excluded.
    ///
    /// ⛔ Matches `Type(` rather than the bare name, because a name-shaped grep answers a
    /// question about NAMES: the #475 lesson, where `audition` scored 37 hits that were all
    /// commentary about an unrelated type. And it reads CODE ONLY, because this repo documents
    /// what it measured — the corrected header this slice writes quotes both needles verbatim.
    private func constructionSites(of type: String) throws -> [String] {
        try filesUnderSources(containing: "\(type)(")
            .filter { !$0.hasSuffix("/\(type).swift") }
            .sorted()
    }

    private func filesUnderSources(containing needle: String) throws -> [String] {
        let root = try repoRoot()
        let base = root.appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let url = base.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if SourceText.codeOnly(text).contains(needle) { hits.append(relative) }
        }
        return hits.sorted()
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
