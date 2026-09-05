// TheFaceSourceHasNoDoorTests.swift
// Echoel — #1002. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// where construction sites sit, never that anything renders.
//
// ⭐ WHY THIS FILE EXISTS, AND IT IS NOT "FaceExpressionBioPublisher IS UNREACHABLE".
// Unreachable is not a defect in this repo — `ImmersiveStageView` and `BroadcastView` are parked
// on purpose. The defect is **unreachable AND missing from the register**, and this one is the
// eighth such entry and the first that is neither a view nor a pure core: it is a whole INPUT
// MODALITY. A finished ARKit front-camera publisher — blendShapes → smile/brow/jaw as [0..1] on
// the bus, source `.faceCam`, ~10 Hz, draining under a lock rather than hopping to the main
// actor per frame — with zero construction sites anywhere in `Sources/`.
//
// ⭐ THE OMISSION WAS EXPENSIVE IN BOTH DIRECTIONS, which is why a register line is the fix
// rather than a deletion or a wiring. Without it a session either rebuilds face tracking that
// already exists, or wires a TrueDepth path without the two things that must travel with it:
// the founder-gated front-camera purpose string, and the EU AI Act framing the file's own header
// states — these channels are EXPRESSION used as a CONTROL signal, never an inferred emotion. A
// smile MOVES a parameter; it is not read as a feeling.
//
// ⚠️ #364 — THIS GUARD DOES NOT FORBID WIRING IT. Every claim's message says what else must move
// in the same commit the day someone does. That day is a product decision (which pulse source, if
// any, coexists with an expression source) plus a founder decision (the purpose string), and
// neither belongs to a test.
//
// ⚠️ HONEST GRADING. Four claims. 3 is the LOAD-BEARING one — the register line is what this
// slice adds, and it is red on `HEAD`. 1, 2 and 4 are COUNTERWEIGHTS, green on both trees: they
// do not prove a repair, they make the register line rot loudly instead of silently.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFaceSourceHasNoDoorTests: XCTestCase {

    private static let publisherFile = "Sources/Echoelmusic/Bio/FaceExpressionBioPublisher.swift"
    private static let optionFile = "Sources/Echoelmusic/Studio/BioSourceOption.swift"

    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped text of every `.swift` file under `Sources/`, one string. This repo
    /// writes long ⛔ blocks that NAME the types they discuss, and a raw scan would read this
    /// very register's prose as a construction site (#453/#762).
    private func sourcesCode() throws -> String {
        let root = try repoRoot()
        let dir = root.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: dir.path) else {
            XCTFail("Sources/ is present but not enumerable — re-anchor rather than skip (#454).")
            return ""
        }
        var out = ""
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
            out += SourceText.codeOnly(text) + "\n"
        }
        guard !out.isEmpty else {
            XCTFail("walked Sources/ and read nothing — the scan found nothing, not nothing wrong.")
            return ""
        }
        return out
    }

    private func file(_ relative: String) throws -> String {
        let root = try repoRoot()
        guard let text = try? String(
            contentsOf: root.appendingPathComponent(relative), encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) — a missing anchor is a finding, not a pass.")
            return ""
        }
        return text
    }

    /// claim 1 — COUNTERWEIGHT: nothing builds it, which is what the register line asserts.
    func testNothingConstructsTheFaceSource() throws {
        let calls = try sourcesCode().components(separatedBy: "FaceExpressionBioPublisher(").count - 1
        XCTAssertEqual(calls, 0, """
            `FaceExpressionBioPublisher` now has \(calls) construction site(s). That is allowed \
            and may well be right (#364) — but the register entry in `CLAUDE.md` says zero, and \
            it must be corrected in the SAME commit. Two other things travel with that wiring \
            and neither is optional: the front-camera purpose string in Info.plist (founder-gated \
            — report, do not edit), and the framing that these are expression channels used as \
            control, never an inferred emotion.
            """)
    }

    /// claim 2 — COUNTERWEIGHT: and the picker cannot reach it either, one level up.
    func testTheSourcePickerOffersNoFace() throws {
        let options = SourceText.codeOnly(try file(Self.optionFile))
        XCTAssertTrue(options.contains("case camera, ble, sim"), """
            `BioSourceOption`'s case list changed. The register line rests on the picker offering \
            exactly camera / ble / sim — if a face option appeared, the modality has a door and \
            the entry in `CLAUDE.md` is now false; if the list merely moved, re-anchor this claim.
            """)
    }

    /// claim 3 — LOAD-BEARING: the register actually carries the entry.
    func testTheRegisterNamesTheFaceSource() throws {
        let law = try file("CLAUDE.md")
        XCTAssertTrue(law.contains("FaceExpressionBioPublisher"), """
            `CLAUDE.md` does not name `FaceExpressionBioPublisher` at all. That register is the \
            list a session reads to decide what may still be opened and what already exists; a \
            whole input modality missing from it is the expensive kind of gap, because it never \
            comes up as a question. This is the line #1002 added — restore it rather than \
            deleting this claim.
            """)
    }

    /// claim 4 — COUNTERWEIGHT: the file's own header keeps the two facts that must travel.
    func testTheFileStillCarriesItsOwnFraming() throws {
        let text = try file(Self.publisherFile)
        XCTAssertTrue(text.contains("NOTHING instantiates it"), """
            The publisher's header no longer states that nothing instantiates it. If that is \
            because it IS wired now, claim 1 has already said what else must move; if the \
            sentence was merely tidied away, the file has lost the one honest note a reader \
            checks before assuming the modality ships.
            """)
        XCTAssertTrue(text.contains("EU AI Act"), """
            The EU AI Act framing is gone from \(Self.publisherFile). It is not decoration: it \
            is the reason this type publishes movement rather than an inferred affective state, \
            and it is the sentence a future wiring slice has to honour. Do not remove it without \
            a founder decision.
            """)
    }
}
