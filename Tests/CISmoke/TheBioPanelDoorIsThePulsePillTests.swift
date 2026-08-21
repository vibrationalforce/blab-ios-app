// TheBioPanelDoorIsThePulsePillTests.swift
// Echoel — #705. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `bioPanel` is reachable, and the control that reaches it is a TAP on the
// pulse pill (`PulseMonitorMiniLive` → `.echoelChromeDoor` "bio" → `activeMenu = .bio`), with
// the pill's long-press context menu carrying a duplicate "Bio details…" entry. It is NOT a
// chip: `.bio` is absent from `EchoelStudioView.studioChips`, and #290 REJECTED adding one as
// a "zweite Tür". The doc beside that array has said so, correctly, since #290.
//
// ⭐ WHY IT NEEDED A GUARD RATHER THAN SEVEN QUIET EDITS. "Bio chip" had become a house idiom:
// seven live prose sites in `Sources/` and `Tests/CISmoke` named a control that does not exist,
// and #704 corrected three of them without noticing the other four, because a reviewer found
// the phrase in the file being edited rather than in a scan. The failure mode is not cosmetic:
// a reader verifying a reachability claim hunts for a Bio chip, does not find one, and can
// conclude the reachability claim itself was wrong — re-reversing a correction back into the
// under-claim it fixed. That is what claim 5 exists to stop; #705 fixed all seven.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Adding a `.bio` chip is a founder-shaped UX decision
// that #290 declined once and could be revisited. On the day it lands, claim 2 goes red BY
// DESIGN and its message names the prose to pull along in the same commit (#456).
//
// ⚠️ WHY CLAIM 5 IS SCOPED AND NOT A BARE NEGATIVE. Every one of those seven sites now carries
// its own ⛔ retraction, and a retraction has to QUOTE the phrase it withdraws — so a bare
// "nowhere says `Bio chip`" would be red on the corrected tree, which is the #491/#655 shape
// this repo has paid for twice. The working form is the one `ThePulseReadoutHasNoDoorTests`
// proved: a line may carry the phrase only if it also carries **SAID**, i.e. only inside a
// withdrawal. Restore the phrase as a CLAIM and it lands on a line without that word.
//
// ⚠️ IT SCANS RAW, NOT `SourceText.codeOnly`. The whole subject lives in comments; a stripped
// scan would see nothing at all and the assertion would be unwritable rather than merely wrong
// — the same reasoning that file records for its own header scan.
//
// ⛔ AND THE FIRST VERSION OF CLAIM 5 WAS RED ON THE CORRECT TREE, FOUR TIMES — its own header
// and its own failure message. A guard whose subject is a FORBIDDEN PHRASE has to be able to
// NAME that phrase in order to explain itself, and no retraction wording fixes that: these are
// live statements of the rule, not withdrawals, so keying on SAID cannot exempt them. Caught by
// simulating the scan in Python before the commit, not by reasoning about it. The carve-out is
// THIS FILE ONLY, keyed off `#filePath` so a rename cannot silently widen it — the file that
// DEFINES the rule is the one place the phrase may appear as a claim.
//
// ⚠️ HONEST LIMITS. 5 tests, 8 assertion statements (2+1+3+1+1; counted in Python over lines
// whose first token is XCTAssert). It reads the SOURCE, so it proves which control posts the
// door notification, never that a finger can find it on glass. `CLAUDE.md` and the scratchpads
// are deliberately outside claim 5's scan: the law file quotes withdrawn claims on purpose
// (#491) and the ledgers are history that must not be rewritten.
//
// ⭐ GRADING (§3). Claims 1–4 are COUNTERWEIGHTS — green at the parent too; they record a
// standing state that #290 created and this commit does not touch. Claim 5 is FORWARD: it is
// red at the parent, by five separate offending lines, and this commit is what makes it green.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBioPanelDoorIsThePulsePillTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    /// The one file claim 5 skips — it must be able to state the rule it enforces. Derived
    /// from `#filePath` so a rename moves the carve-out with the file instead of widening it.
    private static let thisFileName = URL(fileURLWithPath: #filePath).lastPathComponent
    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"

    // MARK: - 1: the anchor — the chip strip exists and is the thing being measured

    /// Without this, claim 2's negative passes on a renamed or deleted array (#454).
    func testTheChipStripExists() throws {
        let src = try source(Self.studio)
        XCTAssertTrue(src.contains("private static let studioChips: [StudioMenu]"), """
            `studioChips` is gone or renamed. Claim 2 below is a NEGATIVE over that array, so \
            it goes quietly vacuous without this — re-anchor rather than letting it pass empty.
            """)
        XCTAssertTrue(src.contains(".sound") && src.contains(".export"), """
            The chip list no longer names the chips it did. Re-measure which menus the strip \
            carries before trusting claim 2.
            """)
    }

    // MARK: - 2: THE FINDING — there is no Bio chip

    /// ⭐ #290 rejected one as a "zweite Tür". Seven prose sites said otherwise anyway.
    func testTheStripDoesNotCarryABioChip() throws {
        let src = try source(Self.studio)
        let list = Self.chipList(in: src)
        XCTAssertFalse(list.contains(".bio"), """
            `.bio` is now a chip in `studioChips` (\(list)). If the founder reversed #290 that \
            is fine and this claim has done its job — delete it, and in the SAME commit (#456) \
            correct every prose site that now says the door is the pulse pill: this file's \
            header, `CLAUDE.md`'s `PulseMeasurementView` register entry and its B3 batch line, \
            `BioStripView`, `PulseMeasurementView`, and the four `Tests/CISmoke` headers that \
            claim 5 below scans.
            """)
    }

    // MARK: - 3: the door that DOES exist

    /// A negative alone would be satisfied by a panel nothing can open. This is the positive
    /// half: the pill posts the chrome door and the studio answers it.
    func testThePulsePillIsTheDoor() throws {
        let studio = try source(Self.studio)
        let header = try source(Self.header)
        XCTAssertTrue(header.contains(#"echoelChromeDoor, object: "bio""#), """
            Nothing in `HeaderMonitors` posts the "bio" chrome door any more. Then `bioPanel` \
            may have NO door at all, which is a bigger finding than this file's subject — \
            measure what opens it before editing any prose.
            """)
        XCTAssertTrue(studio.contains(#"case "bio""#), """
            The studio no longer maps the "bio" chrome door to a menu. The pill would post \
            into nothing; see the message above.
            """)
        XCTAssertTrue(studio.contains("PulseMonitorMiniLive("), """
            The pulse pill is no longer mounted in `EchoelStudioView`. It is the door this \
            whole file names; if it moved, every "pulse pill" prose site moves with it (#456).
            """)
    }

    // MARK: - 4: the counterweight — the long-press path is a deliberate duplicate

    /// ⚠️ Without this the file reads as "the tap replaced the long-press". It did not: the
    /// context-menu entry is kept ON PURPOSE, as the one place a VoiceOver user exploring the
    /// menu learns the panel exists. Deleting it as a duplicate would be a regression.
    func testTheLongPressStillOffersTheSameDoor() throws {
        let header = try source(Self.header)
        XCTAssertTrue(header.contains("Bio details"), """
            The context menu's "Bio details…" entry is gone. It duplicates the tap on purpose \
            — it is how a VoiceOver user discovers the panel. If it was removed as redundant, \
            that is the regression, not the cleanup, and the prose calling the long-press the \
            SECOND way in needs correcting too.
            """)
    }

    // MARK: - 5: the idiom cannot come back as a claim

    /// ⭐ THE ANTI-DRIFT CLAIM, and the reason this is a guard and not seven edits.
    func testNoLivingProseCallsItAChip() throws {
        var offenders: [String] = []
        for (path, text) in try scannedFiles() {
            if path.hasSuffix(Self.thisFileName) { continue }   // see the ⛔ in the header
            for (n, line) in text.components(separatedBy: .newlines).enumerated()
            where (line.contains("Bio chip") || line.contains("Bio-Chip")) && !line.contains("SAID") {
                offenders.append("\(path):\(n + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders) call `bioPanel`'s door a chip outside a retraction. There is no Bio \
            chip — `.bio` is absent from `studioChips` (claim 2) and #290 declined to add one. \
            The door is a TAP on the pulse pill, long-press second. If a line must quote the \
            old phrase, quote it inside a withdrawal that carries the word SAID, the way the \
            seven sites #705 corrected do.
            """)
    }

    // MARK: - reading the tree

    private struct DiagAnchorMissing: Error { let reason: String }

    /// The chip array's literal, or "" if the shape changed — claim 1 is what makes that
    /// distinguishable from an empty strip.
    private static func chipList(in source: String) -> String {
        guard let head = source.range(of: "private static let studioChips: [StudioMenu]"),
              let open = source.range(of: "[", range: head.upperBound..<source.endIndex),
              let close = source.range(of: "]", range: open.upperBound..<source.endIndex)
        else { return "" }
        return String(source[open.upperBound..<close.lowerBound])
    }

    /// Raw text of every `.swift` under `Sources/Echoelmusic` and `Tests/CISmoke`, keyed by a
    /// repo-relative path. RAW on purpose — see the ⚠️ note in the header.
    private func scannedFiles() throws -> [(String, String)] {
        var out: [(String, String)] = []
        for dir in ["Sources/Echoelmusic", "Tests/CISmoke"] {
            let base = try repoRoot().appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(atPath: base.path) else {
                throw DiagAnchorMissing(reason: "\(dir) cannot be walked — re-anchor (#454).")
            }
            for case let name as String in walker where name.hasSuffix(".swift") {
                let url = base.appendingPathComponent(name)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                out.append(("\(dir)/\(name)", text))
            }
        }
        guard !out.isEmpty else {
            throw DiagAnchorMissing(reason: """
                Neither scanned directory holds a Swift file — the extraction found nothing, \
                so claim 5's negative would pass empty (#454).
                """)
        }
        return out
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
