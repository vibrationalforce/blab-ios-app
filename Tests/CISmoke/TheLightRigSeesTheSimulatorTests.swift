// TheLightRigSeesTheSimulatorTests.swift
// Echoel — #789: the DMX half of the provenance family turned out to be BUILDABLE, not a decision.
//
// WHAT THIS GUARDS. #639 labelled the bio batch on OSC, #785 the discrete events, #786 measured the
// ADM-OSC half and left it open with evidence. The register in `TheWireSaysWhoseBodyTests` said of
// the light half: "What is missing is a CONVENTION — a slot a desk would have to be patched to
// read." **That is wrong for sACN, and the counter-evidence was already in our own packet
// builder**: E1.31 puts a 64-byte **Source Name** in the framing layer of every data packet, and
// `SACNSender` has been filling it with a hardcoded "Echoelmusic" since the file was written. A
// console shows that string in its source list. Nothing to invent, no namespace to pollute, no
// slot to patch — the standard's own field, already on the wire.
//
// ⭐ WHY THIS IS THE ONE THAT MOVED, and it is a lesson about registers rather than about DMX. The
// register's sentence was about **DMX**, and DMX genuinely has no metadata layer — 512 slots of
// raw levels. But sACN is not DMX: it is DMX *carried over* E1.31, and the CARRIER has a header
// the payload does not. Writing "Art-Net and sACN carry DMX" collapsed two protocols into their
// shared payload and lost the difference that decides the question. **A register entry that names
// what two things have in common can hide the thing that separates them.**
//
// STILL OPEN, and now for a PRECISE reason rather than a shared one: **Art-Net**. Its data packet
// (`ArtDMX`, OpCode 0x5000 — the only opcode `ArtNetSender` implements) carries no name. Art-Net's
// identity lives in `ArtPollReply` (0x2100), a discovery packet sent in answer to an `ArtPoll`
// broadcast, with `ShortName`/`LongName` fields. So Art-Net's convention EXISTS too; what is
// missing is that Echoel implements no discovery half at all. That is a build, not a decision —
// registered as such, deliberately not attempted in this slice.
//
// KIND (§1): **END-TO-END BEHAVIOUR**. `e131Packet` is `nonisolated static` and returns `Data`, so
// these claims read the real bytes a console would receive, at the real offset the standard puts
// the name at. No source-text scanning.
//
// THE OFFSET, stated because a magic number in a test is worthless: the E1.31 framing layer's
// Source Name starts at **byte 44** — 16 (preamble/postamble/ACN ID) + 22 (root layer: flags+len
// 2, vector 4, CID 16) = 38, then the framing flags+length (2) and vector (4) = 44. Claim 1
// derives it rather than trusting it, by locating the base name in the packet.
//
// GRADING (#433 / §3), driven against e2b829c and this tree:
//   · **2 REGRESSIONS** — claims 1 and 2. The parent's name is the bare constant whatever the
//     source, so a demo session is indistinguishable from a body in a console's source list.
//     ONE finding (#486): the parameter did not exist there at all.
//   · **1 SPLIT** — claim 3, and driving it is what showed the split. ⛔ IT WAS BOOKED AS A CLEAN
//     COUNTERWEIGHT AND IS NOT ONE. Its CHANNEL half is a genuine counterweight (green on the
//     parent; red the moment provenance touches a level). Its LENGTH half is **PREVENTIVE, and
//     unreachable today**: the 64-byte truncation can only matter for a name LONGER than 64 bytes,
//     and `sourceName(synthetic:)` returns one of two fixed strings, the longer being 18 bytes. So
//     no input this API can produce will ever exercise it. Kept anyway — it goes red the day
//     somebody makes the name dynamic (a device identifier, a session label) and drops the cap,
//     which is exactly when a patched rig would start reading garbage where its levels were.
//     ⭐ THIS IS #785's CLAIM-14 SPLIT HAPPENING AGAIN, four cycles later and found the same way:
//     by driving a mutation rather than re-reading the prose. The first mutation attempt was a
//     NO-OP — it removed the cap while the name still fitted, so nothing moved and nothing
//     reddened. **A mutation is not evidence until you confirm it landed** (#782).
//
// MUTATIONS DRIVEN: dropping the suffix reddens claim 1; suffixing the REAL case too reddens claim
// 2; making the name exceed 64 bytes AND removing the `prefix` reddens claim 3's length half
// (removing the cap alone does not — that was the no-op above); writing a different level for a
// demo packet reddens claim 3's channel half. The unmutated tree is green on all three.
//
// ⚠️ #364: a different provenance shape is not forbidden. A per-source name, an `ArtPollReply`
// implementation, or a decision to drop the suffix would each turn a claim red — that red is the
// signal, and the message names the prose to pull with it (#456).
//
// ⚠️ NEEDS-FOUNDER-VERIFY: whether a real console REDRAWS the source name when it changes
// mid-session. E1.31 permits it; desks may cache per CID. Not measurable in this repo.

#if canImport(Network)
import Foundation
import XCTest
@testable import Echoelmusic

final class TheLightRigSeesTheSimulatorTests: XCTestCase {

    private static let cid: [UInt8] = Array(repeating: 0xAB, count: 16)

    private func packet(_ synthetic: Bool?) -> [UInt8] {
        [UInt8](SACNSender.e131Packet(universe: 1, sequence: 0, cid: Self.cid,
                                      channels: [10, 20, 30], synthetic: synthetic))
    }

    /// The 64-byte Source Name as the console reads it: from the base name's offset, trimmed of
    /// the null padding the standard requires.
    private func sourceName(in bytes: [UInt8]) throws -> String {
        let base = Array(SACNSender.baseSourceName.utf8)
        guard let start = (0..<bytes.count).first(where: {
            $0 + base.count <= bytes.count && Array(bytes[$0..<($0 + base.count)]) == base
        }) else {
            throw XCTSkip("the base name is not in the packet at all — re-anchor this file (#454)")
        }
        let field = Array(bytes[start..<min(start + 64, bytes.count)])
        return String(decoding: field.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// 1 — REGRESSION. A demo session announces itself in the field a console actually displays.
    func testADemoSessionNamesItselfInTheConsolesSourceList() throws {
        let name = try sourceName(in: packet(true))
        XCTAssertTrue(name.contains("DEMO"), """
            The sACN Source Name for a synthetic source was "\(name)". A lighting operator reads \
            this string to tell one source from another; without a marker a simulator driving the \
            rig is indistinguishable from a body, which is the gap #639 opened this family to \
            close. This is the STANDARD's own field — nothing was invented to carry it.
            """)
    }

    /// 2 — REGRESSION, and the half that keeps the name usable: a real body, and an unknown
    /// provenance, both send the plain name. See the header for why two strings cover three
    /// states on purpose.
    func testARealBodyAndAnUnknownTickBothSendThePlainName() throws {
        for (label, value) in [("a real body", false), ("not yet known", nil)] as [(String, Bool?)] {
            let name = try sourceName(in: packet(value))
            XCTAssertEqual(name, SACNSender.baseSourceName, """
                With provenance "\(label)" the Source Name was "\(name)". Only the DEMO case \
                carries a marker; suffixing a real session would put noise in every console's \
                source list for the case that needs no warning.
                """)
        }
    }

    /// 3 — COUNTERWEIGHT, and the one that makes this safe for a rig that is already patched. The
    /// name field is FIXED at 64 bytes: a longer string must be truncated, never allowed to shift
    /// the DMP layer and the 512 slots behind it. Green on the parent by construction.
    func testTheSuffixCannotShiftASinglePacketByte() {
        let a = packet(nil), b = packet(true), c = packet(false)
        XCTAssertEqual(a.count, b.count, """
            A demo packet is \(b.count) bytes and a plain one \(a.count). The Source Name is a \
            fixed 64-byte field; if the suffix changed the length, every offset after it moved and \
            a patched rig would read garbage where its levels used to be.
            """)
        XCTAssertEqual(a.count, c.count, "a real-body packet must be the same length too")
        // The DMX payload itself is untouched by provenance — the last three slots we set.
        XCTAssertEqual(Array(a.suffix(512).prefix(3)), Array(b.suffix(512).prefix(3)), """
            The channel data differs between a plain and a demo packet. Provenance names the \
            SOURCE; it must never touch a level.
            """)
    }
}
#endif
