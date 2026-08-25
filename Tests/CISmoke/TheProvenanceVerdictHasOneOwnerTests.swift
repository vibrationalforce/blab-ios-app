// TheProvenanceVerdictHasOneOwnerTests.swift
// Echoel — #811: one fact lived in four places and moved in one of them.
//
// WHAT WAS WRONG. "Which egress protocols still carry no provenance?" was answered in FOUR
// files. #785 closed the discrete-event path and #789 closed sACN (E1.31 carries a 64-byte
// source name, which a demo session fills with "Echoelmusic (DEMO)"). Both slices updated
// `CLAUDE.md` and shipped their own guards — and left three copies asserting the old answer:
//
//   · `Sources/Echoelmusic/EchoelmusicApp.swift`  — the #462 status note beside `demoSource`
//   · `Sources/Echoelmusic/Bio/BioSimulator.swift` — which ALREADY pointed at the owner and
//     restated the list anyway, the worst of the three: a pointer plus a stale copy reads as
//     a confirmed copy
//   · `Tests/CISmoke/TheDemoSourceIsMarkedWhereItRendersTests.swift` — whose own header calls
//     it "THE ONE place a session looks to ask 'which surfaces are marked?'"
//
// ⭐ THE SHAPE, and it is why this guard exists rather than three fixed comments. #456 says
// prose moves in EVERY home in the same commit. What this cycle adds is the reason a home
// gets missed: **a register that restates a neighbour's fact does not look like a copy** — it
// looks like coverage. The file that most loudly claims to be the single place was one of the
// three that aged, and the file that pointed at the right owner still kept its own list beside
// the pointer. Nobody was careless; the copies were invisible AS copies.
//
// THE OWNER is `TheWireSaysWhoseBodyTests`. It carries the per-protocol verdict, the precise
// reason Art-Net differs from sACN (ArtDMX 0x5000 has no name field at all — identity lives in
// `ArtPollReply` 0x2100, a discovery packet Echoel does not implement, so Art-Net needs a BUILD
// and not a decision), and why ADM-OSC is a decision rather than a build (a foreign standard's
// address space, spec behind the AES paywall).
//
// ⛔ WHAT THIS GUARD DELIBERATELY DOES NOT DO: scan the three files for the retracted sentence.
// All three now QUOTE it in order to withdraw it, so a negative needle would match its own
// retraction — #491, which the #809 guard walked into one cycle earlier and its control run
// caught. Every claim below is POSITIVE.
//
// KIND (§1): **MIXED, source-text scans — and the split below is DRIVEN, not predicted.** ⛔ The
// first version of this block said "claim 1 is a REGRESSION … the owner's own verdict was one of
// the copies that had not been reconciled". The drive says otherwise: on the parent, claim 1 is
// GREEN. The owner had every protocol and both closing slices all along — which is precisely WHY
// it is the owner, and predicting a regression there was me assuming the defect was everywhere
// because it was in three places. Measured against `HEAD`, exactly two assertions fail:
//   · **2 TRUE REGRESSIONS** — the `EchoelmusicApp` pointer (claim 2) and the surface-register
//     pointer (claim 3a). Those are the two homes that answered the question themselves.
//   · **1 PREVENTIVE, partly** — claim 2's other two paths (`BioSimulator` and the surface
//     register) already named the owner on the parent; they pin a pointer that existed.
//   · **3 COUNTERWEIGHTS, green on both trees** — claim 1 (owner names every protocol and both
//     dates), claim 3b (the measuring command), claim 4 (`ArtPollReply`). Each stays green
//     across the change, which is what makes the two reds above mean something.
// This correction is kept rather than quietly rewritten: #808 was a needle graded FORWARD while
// it was red on its own commit's tree, and the lesson there was that transcribing a claim is not
// driving it. Grading it is not driving it either.
//
// ⚠️ #364 — NOTHING HERE FORBIDS FUTURE WORK. When Art-Net or ADM-OSC gain provenance, claim 1
// keeps passing (it asks that the owner NAMES each protocol, not what verdict it gives), and
// the owner is the one file to edit. That is the whole point of collapsing four homes to one.

import XCTest

final class TheProvenanceVerdictHasOneOwnerTests: XCTestCase {

    private static let owner = "Tests/CISmoke/TheWireSaysWhoseBodyTests.swift"
    private static let pointers = [
        "Sources/Echoelmusic/EchoelmusicApp.swift",
        "Sources/Echoelmusic/Bio/BioSimulator.swift",
        "Tests/CISmoke/TheDemoSourceIsMarkedWhereItRendersTests.swift",
    ]

    private func root() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(relative) not in this tree — nothing to grade (#454: missing TREE skips).")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1 · the owner answers for every protocol, and records the two that closed

    /// REGRESSION. On the parent tree the owner had the per-protocol split but the three copies
    /// did not; this claim is what makes "there is one owner" checkable rather than asserted.
    func testTheOwnerCarriesTheVerdictForEveryProtocol() throws {
        let owner = try text(Self.owner)
        for proto in ["ADM-OSC", "Art-Net", "sACN"] {
            XCTAssertTrue(owner.contains(proto), """
                The provenance owner stopped naming \(proto). Four files used to answer "which
                egress carries provenance"; three now point here instead of keeping a list, so
                a protocol missing from THIS file is a protocol nobody answers for.
                """)
        }
        for closed in ["#785", "#789"] {
            XCTAssertTrue(owner.contains(closed), """
                The owner lost the record of \(closed), one of the two slices that closed a
                protocol while three copies still called it open. The dates are what let a
                reader tell "still open" from "nobody updated this".
                """)
        }
    }

    // MARK: - 2 · the three former copies point instead of restating

    func testTheFormerCopiesNameTheOwner() throws {
        for path in Self.pointers {
            let src = try text(path)
            XCTAssertTrue(src.contains("TheWireSaysWhoseBodyTests"), """
                `\(path)` stopped naming the provenance owner. It used to answer the question
                itself and was stale for two slices. If the pointer goes, the next session
                writes a fresh list here — a fourth home, which is exactly what #811 removed.
                """)
        }
    }

    // MARK: - 3 · the surface register keeps its pointer too

    /// The SECOND list in `EchoelmusicApp`'s note — "the label is on six surfaces" — was stale
    /// in the same comment, for the same reason, and omitted `EchoelFXView`. It was replaced by
    /// the same move: name the register, keep the measuring command.
    func testTheSurfaceListWasReplacedByItsRegisterAndACommand() throws {
        let app = try text("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertTrue(app.contains("TheDemoSourceIsMarkedWhereItRendersTests"), """
            `EchoelmusicApp`'s demo-source note stopped naming the per-surface register. It
            carried its own list of surfaces through "five" and "six", the second omitting
            `EchoelFXView` — while the very next sentence said "measure, do not carry the
            number forward".
            """)
        XCTAssertTrue(app.contains(#"git grep -n 'Text("Demo")' -- Sources"#), """
            The measuring command is gone from the demo-source note. A pointer plus a command
            is what replaced the list; without the command the pointer is an invitation to
            count by hand, and counting by hand is what produced both stale numbers.
            """)
    }

    // MARK: - 4 · Art-Net's reason is a BUILD, not a decision

    /// Kept because it is the one open item whose reason is routinely mis-stated as "no room
    /// in DMX". A universe has 512 slots and `ArtNetSender` uses four; the real obstacle is
    /// that ArtDMX carries no name field, and identity lives in a discovery packet this app
    /// does not implement.
    func testTheOwnerSaysWhyArtNetDiffersFromSACN() throws {
        let owner = try text(Self.owner)
        XCTAssertTrue(owner.contains("ArtPollReply"), """
            The owner stopped naming `ArtPollReply`. Without it the Art-Net entry reads as a
            missing decision, and the next session re-opens the settled "just use a spare DMX
            slot" idea — which invents a convention inside somebody else's standard, the exact
            move rejected for ADM-OSC.
            """)
    }
}
