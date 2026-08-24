// TheADMObjectCarriesNoOriginTests.swift
// Echoel — #786: the ADM-OSC half of the provenance family, and the workaround that does not work.
//
// WHAT THIS GUARDS. #639 put `/echoelmusic/bio/synthetic` on the bio BATCH and #785 put it on the
// discrete EVENTS. Two halves stay open by design, and this file pins the premises of the ADM-OSC
// one so the register entry in `TheWireSaysWhoseBodyTests` cannot go quietly false. It does NOT
// argue for a particular fix — see #364 at the bottom.
//
// THE THREE MEASURED FACTS behind the register entry (2026-08-24):
//   1. `/adm/obj/{n}/*` is a PUBLISHED address space owned by someone else. Inventing
//      `/adm/obj/n/synthetic` inside it is the opposite of the open-standards posture the
//      positioning rests on.
//   2. ⭐ WHETHER THE STANDARD RESERVES A VENDOR NAMESPACE IS **UNMEASURED, AND NOT MEASURABLE
//      FROM PUBLIC SOURCES**. The public README of `immersive-audio-live/ADM-OSC` defines only
//      `/adm/obj/{n}/…` and says a fuller dictionary "is being discussed"; the thing that would
//      answer the question — "Specification v1.0 and implementation guide" — is an AES e-library
//      paper (aes2.org id=22722), i.e. paywalled. So a session cannot check today whether an
//      extension address would even be LEGAL, let alone welcome. Stated as UNMEASURED rather
//      than guessed, per `.claude/rules/context.md` §2.
//   3. ⛔ AND THE OBVIOUS WORKAROUND IS FALSE BY DEFAULT — this is the fact worth a guard.
//      "An ADM integrator can just also subscribe to our own `/echoelmusic/bio/synthetic`"
//      sounds right and does not hold: `OSCSender` and `ADMOSCSender` are INDEPENDENT senders
//      with SEPARATELY PERSISTED targets (`net.osc.host`/`net.osc.port` vs
//      `net.adm.host`/`net.adm.port`) and different default ports. A renderer listening on the
//      ADM port receives no `/echoelmusic/*` at all. It works only if an operator deliberately
//      aligns both senders on one host that listens on both ports — a configuration
//      coincidence, not a contract, and not something a spec sheet may claim.
//
// KIND (§1): claim 1 is END-TO-END BEHAVIOUR (it drives the shipped `admMessages`); claim 2 is a
// SOURCE SCAN of two production files for two literal key strings, which is the only way to read
// them — both are `private static let`, so no behavioural path exposes them.
//
// GRADING (#433 / §3): **2 PREVENTIVE**. Neither reddens on any parent — nothing is being fixed
// here. They exist so that the day someone adds provenance to the ADM arm, or unifies the two
// targets into one config, the register entry that reasons from their absence goes red in the
// same run instead of ageing silently. That is the honest grade; calling them regressions would
// be §3's flattering direction.
//
// MUTATIONS DRIVEN (§3): appending `("\(prefix)/synthetic", 1)` to `admMessages` reddens claim 1;
// renaming `ADMOSCSender`'s `hostKey` to `"net.osc.host"` reddens claim 2. The unmutated tree is
// green on both.
//
// ⚠️ #364 — THIS FILE FORBIDS NOTHING. Adding provenance to the ADM arm is a legitimate future
// decision, and so is unifying the two network targets. Either turns a claim here red, and that
// red is the SIGNAL, not the verdict: the failure message names the prose to pull in the same
// commit (#456). What is forbidden silently is the register entry in `TheWireSaysWhoseBodyTests`
// drifting out of step with the code it reasons about.

#if canImport(Network)
import Foundation
import XCTest
@testable import Echoelmusic

final class TheADMObjectCarriesNoOriginTests: XCTestCase {

    /// 1 — PREVENTIVE. The bio→object arm asserts position and gain and nothing else. A frame
    /// with every channel measured is used on purpose: it opens every arm, so the absence of a
    /// provenance address cannot be an artefact of a closed gate.
    func testTheBioObjectArmEmitsNoProvenanceAddress() {
        let demo = BioSampleFrame(timestamp: 1000, heartRateBPM: 64, hrvNormalized: 0.45,
                                  breathRate: 12, breathPhase: 0.3, coherence: 0.62,
                                  motionEnergy: 0, source: .fallback)
        let msgs = ADMOSCSender.admMessages(for: demo, object: 1)
        XCTAssertFalse(msgs.isEmpty, """
            The fixture opened no arm at all — re-anchor this case (#454). With nothing emitted \
            the provenance assertion below would pass for the wrong reason.
            """)
        let offenders = msgs.map(\.0).filter {
            $0.lowercased().contains("synthetic") || $0.lowercased().contains("origin")
        }
        XCTAssertTrue(offenders.isEmpty, """
            The ADM arm emitted \(offenders). That may well be the right product decision — see \
            #364 in this file's header — but it makes the ADM-OSC bullet in \
            TheWireSaysWhoseBodyTests ("still carry no provenance") FALSE. Pull that prose in \
            this commit, and note fact 2: whether the standard reserves a vendor namespace is \
            still unmeasured, so an address invented here is invented inside someone else's space.
            """)
    }

    /// 2 — PREVENTIVE, and the one that pins the workaround. Two senders, two persisted targets:
    /// so Echoel's own provenance address does NOT reach an ADM renderer unless an operator
    /// aligns the two by hand.
    func testTheTwoSendersKeepSeparateTargets() throws {
        let osc = try source("Sources/Echoelmusic/Sync/OSCSender.swift")
        let adm = try source("Sources/Echoelmusic/Sync/ADMOSCSender.swift")
        for (file, key) in [("OSCSender", "\"net.osc.host\""), ("OSCSender", "\"net.osc.port\""),
                            ("ADMOSCSender", "\"net.adm.host\""), ("ADMOSCSender", "\"net.adm.port\"")] {
            let text = file == "OSCSender" ? osc : adm
            XCTAssertTrue(text.contains(key), """
                \(file) no longer persists its target under \(key). If the two senders now share \
                ONE config, fact 3 in this file's header is false and the ADM-OSC bullet in \
                TheWireSaysWhoseBodyTests must say so: our own /echoelmusic/bio/synthetic would \
                then reach the ADM receiver, and the open half would be smaller than it claims.
                """)
        }
        XCTAssertFalse(adm.contains("\"net.osc."), """
            ADMOSCSender reads an OSC-namespaced key. Same consequence as above — the two \
            targets are no longer independent, so the header's fact 3 needs rewriting here.
            """)
    }

    /// The repo-root helper every source-scanning sibling in this bundle uses — copied rather
    /// than re-invented, and it SKIPS when the tree is absent for the reason those siblings give:
    /// a source scan with no source must not report a green it did not earn.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — claim 2 inspects source text, so it \
                SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// ⚠️ RAW text, NOT `SourceText.codeOnly`. The needles here are string LITERALS in production
    /// code (`"net.osc.host"`), and a comment stripper is line-based: #781 showed it swallowing a
    /// real declaration because a `/*` sat inside a message. Stripping would also not help — a
    /// key name cannot hide in a comment and still be the key.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(path), encoding: .utf8)
    }
}
#endif
