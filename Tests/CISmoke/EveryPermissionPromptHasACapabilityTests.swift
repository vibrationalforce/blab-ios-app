// EveryPermissionPromptHasACapabilityTests.swift
// Echoel — #771. The system permission dialog is user-facing copy, and nothing checked it.
//
// WHAT THIS GUARDS. `Resources/iOS/Info.plist` carries nine `NS…UsageDescription` strings.
// Each one is shown to the user by iOS, verbatim, at the moment they are asked to grant
// something — the highest-stakes sentence the app ever prints, and the one App Store review
// reads first for a 5.1.1 rejection. They are ALSO a capability claim: "Finished visual
// recordings are saved to your photo library" promises a behaviour the app must actually have.
//
// ⭐ WHY IT IS A NEW GUARD AND NOT A ROW IN AN OLD ONE. #765 checked the paywall, #766 the
// routing port, #767 the safety warnings, #768/#769 the store metadata, #770 the engine's own
// log line and doc comments. Every one of those is Swift, Markdown or a `.txt` leaf. The plist
// is a fourth medium and was in nobody's enumeration — the #768 detection sign again: when all
// the checked surfaces share one GATTUNG, the ENUMERATION is what was incomplete.
//
// ⚠️ MEASURED BEFORE IT WAS WRITTEN, and the result was that the copy is HONEST. All nine keys
// have live production code behind them today: `PHPhotoLibrary` in `VisualRecorder`,
// `CBCentralManager` in `PolarH10BioPublisher`, `CLLocationManager` in `LocationNamer`,
// `MCNearbyServiceAdvertiser` in `MultipeerSession` (and `LiveColaboView`, its door, IS mounted
// in `EchoelStudioView` — checked, because a doorless collaboration surface would have made
// "nearby collaboration" a promise in a system dialog that nobody can reach). So this file is
// **PREVENTIVE, not a repair**, and it says so rather than dressing a clean measurement up as a
// catch (#464). The incident it is paid for is not hypothetical: #167 deleted the drums, #121
// deleted the video editor, and each of those removals orphaned a door somewhere else. The day
// a slice deletes `VisualRecorder`, the photo-library sentence becomes a promise with no code
// AND an unused permission string in the binary — and no gate would have said a word.
//
// ⚠️ THE REPAIR IS FOUNDER-GATED AND THE FAILURE MESSAGES SAY SO. `Resources/iOS/Info.plist` is
// report-do-not-edit. A red here is therefore an instruction to REPORT, or to restore the
// capability — never to quietly delete the user-facing sentence.
//
// ⚠️ ONE DIRECTION ONLY (#364). A key with no capability is checked; a capability with no key is
// NOT. The second would forbid correct work — Apple renames and adds these keys, a new one is a
// legitimate edit, and the crash it causes is immediate and loud on device. Guarding the
// direction that fails SILENTLY is the whole point.
//
// ⚠️ THE ROSTER IS READ FROM THE PLIST, NOT TYPED HERE (#768/#769). Claim 1 fails when the plist
// carries a key this file has no row for — the exact trap #769 closed one level out, where a
// guard read a hand-typed list of locales while the directory had grown. The needle SET per key
// is unavoidably hand-written (no tool derives "what code proves a microphone is used"), so the
// plist is the source of truth for WHICH keys exist and this table only says what each means.
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN. A needle proves the symbol is written in a shipped file, not
// that any user path reaches it — `MIDIInput`'s reachability lesson applies. What it does prove
// is the thing that actually goes wrong: the capability was DELETED and the sentence stayed.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here, and it is measured in the test itself rather
// than asserted in this comment (#453): `testTheStripperIsNotDecoration` counts each needle raw
// and stripped, and fails if a needle's ONLY occurrence is prose. This repo writes long ⛔ blocks
// naming exactly these symbols, so a raw scan could pass on a tree where the capability is gone
// and only its obituary remains — the #762 comment-as-code trap, one medium further out.
//
// ⚠️ HONEST GRADING FOR #771 (parent `66b68f7`): **ZERO REGRESSIONS, and that is the correct
// result.** Every assertion is green on both trees because the slice changes no `Sources/` and
// no plist. It is bought for the FUTURE red, the same way #548 was — and #766 and #770 were the
// instalments that proved that purchase pays. Booking it as a catch would be the
// flattering-direction defect (#433).
//
// ⚠️ #367 DRIVEN, not assumed — each claim was transcribed in Python and run against a
// deliberately mutated tree:
//   · a tenth `NS…UsageDescription` key added to the plist with no row  → claim 1 RED, others green
//   · `PHPhotoLibrary` removed from `VisualRecorder`                    → claim 2 RED
//   · the same removal PLUS a comment that still names it (#762 shape)  → claims 2 AND 3 RED
//   · an ordinary unrelated comment added to the same file             → all three GREEN
//
// ⛔ AND THAT THIRD ROW IS ONE FINDING REPORTED TWICE (#486), which is worth writing down rather
// than letting the count flatter the file. Claim 3 cannot go red while claim 2 is green: if the
// only occurrence is prose, the stripped scan finds nothing either. Its value is the DIAGNOSIS —
// "look in the comment, the symbol was eulogised, not renamed" — not an independent catch. Two
// red assertions there are one defect, and a status delta that reports two is wrong.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryPermissionPromptHasACapabilityTests: XCTestCase {

    private static let plist = "Resources/iOS/Info.plist"

    /// key → the tokens that must appear in comment-stripped `Sources/`, ANY of which proves the
    /// capability is still written. Measured 2026-08-23; the file each was found in is named so a
    /// red can be diagnosed without a second search.
    private static let table: [String: (needles: [String], seenIn: String)] = [
        "NSMicrophoneUsageDescription":
            (["AVAudioSession.sharedInstance()"], "Audio/AudioConfiguration.swift + 7 more"),
        "NSHealthShareUsageDescription":
            (["HKHealthStore"], "Bio/EchoelBioEngine.swift, Bio/HealthKitWriter.swift"),
        "NSHealthUpdateUsageDescription":
            (["HKQuantitySample"], "Bio/HealthKitWriter.swift"),
        "NSCameraUsageDescription":
            (["AVCaptureSession", "AVCaptureDevice"], "Video/CameraCapture.swift"),
        "NSPhotoLibraryAddUsageDescription":
            (["PHPhotoLibrary"], "Video/VisualRecorder.swift"),
        "NSBluetoothAlwaysUsageDescription":
            (["CBCentralManager"], "Bio/PolarH10BioPublisher.swift"),
        "NSBluetoothPeripheralUsageDescription":
            (["CBCentralManager"], "Bio/PolarH10BioPublisher.swift"),
        "NSLocationWhenInUseUsageDescription":
            (["CLLocationManager"], "Core/LocationNamer.swift"),
        "NSLocalNetworkUsageDescription":
            (["NWConnection", "MCNearbyServiceAdvertiser"],
             "Sync/OSCSender.swift, Sync/MultipeerSession.swift")
    ]

    // MARK: - claim 1 — the roster comes from the plist, not from this file

    func testEveryUsageKeyInThePlistHasARow() throws {
        let keys = try usageKeys()
        XCTAssertFalse(keys.isEmpty, """
            No `NS…UsageDescription` key found in \(Self.plist). This scan found NOTHING rather \
            than nothing wrong (#454). If the permission strings moved to another plist or to \
            `project.yml`, re-anchor this file in the same commit — do not let it skip.
            """)
        let unknown = keys.filter { Self.table[$0] == nil }.sorted()
        XCTAssertTrue(unknown.isEmpty, """
            \(Self.plist) asks the user for something this guard cannot check: \
            \(unknown.joined(separator: ", ")).

            A permission string is user-facing copy AND a capability claim. Add a row to \
            `table` naming the code that proves the capability is real, in the SAME commit that \
            adds the key. #769 is why the roster is read from the plist instead of typed here: \
            a hand-written list silently stops covering what the directory grew.
            """)
    }

    // MARK: - claim 2 — every promise still has code behind it

    func testEveryPromisedCapabilityIsStillInTheSources() throws {
        let sources = try swiftSources()
        for key in try usageKeys().sorted() {
            guard let row = Self.table[key] else { continue }   // claim 1 owns that failure
            let found = row.needles.contains { needle in
                sources.values.contains { $0.contains(needle) }
            }
            XCTAssertTrue(found, """
                \(Self.plist) still shows the user the "\(key)" prompt, but none of \
                \(row.needles.joined(separator: " / ")) occurs in `Sources/` any more \
                (last seen in \(row.seenIn)).

                Either the capability was deleted and the promise stayed — an unused permission \
                string in the binary and a sentence iOS will still print — or the API was \
                replaced and this row needs its new needle. `Resources/iOS/Info.plist` is \
                FOUNDER-GATED: report the finding, do not delete the string yourself.
                """)
        }
    }

    // MARK: - claim 3 — the stripper is doing work, not decorating

    /// #453 asks every guard to MEASURE whether `SourceText.codeOnly` is load-bearing instead of
    /// claiming it. Here the measurement is itself an assertion, because the failure it prevents
    /// is precisely this repo's habit: when a capability is removed, a long ⛔ block naming the
    /// deleted symbol is written in its place. A raw scan would then read the obituary as proof
    /// of life (#762). Any needle whose only occurrence is prose is that failure, already begun.
    func testTheStripperIsNotDecoration() throws {
        let stripped = try swiftSources()
        let raw = try swiftSources(strip: false)
        for key in try usageKeys().sorted() {
            guard let row = Self.table[key] else { continue }
            for needle in row.needles {
                let inCode = stripped.values.contains { $0.contains(needle) }
                let inText = raw.values.contains { $0.contains(needle) }
                if inText && !inCode {
                    XCTFail("""
                        "\(needle)" (\(key)) occurs in `Sources/` ONLY inside a comment. A \
                        capability that survives merely as prose is a deleted capability with a \
                        live permission prompt still pointing at it — see claim 2's message.
                        """)
                }
            }
        }
    }

    // MARK: - source access

    private struct PermissionAnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Every `NS…UsageDescription` key declared in the shipped plist, read from the file so the
    /// roster can never drift from what iOS actually shows.
    private func usageKeys() throws -> Set<String> {
        let path = try repoRoot().appendingPathComponent(Self.plist)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw PermissionAnchorMissing(reason: """
                \(Self.plist) is missing while the tree is present — moved or renamed. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        let text = try String(contentsOf: path, encoding: .utf8)
        // Split rather than range-walk: a `<key>` never spans a line in this file, and a
        // line-local parse cannot lose its place the way an index walk over a Substring can.
        var keys = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let open = line.range(of: "<key>"),
                  let close = line.range(of: "</key>"),
                  open.upperBound <= close.lowerBound else { continue }
            let name = String(line[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasPrefix("NS"), name.hasSuffix("UsageDescription") { keys.insert(name) }
        }
        return keys
    }

    /// Every shipped Swift file, comment-stripped by default (#453 — one stripper for the
    /// bundle). `strip: false` is used ONLY by claim 3, which needs both readings to measure.
    private func swiftSources(strip: Bool = true) throws -> [String: String] {
        let root = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw PermissionAnchorMissing(reason: "cannot enumerate \(root.path)")
        }
        var out: [String: String] = [:]
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            out[rel] = strip ? SourceText.codeOnly(text) : text
        }
        guard !out.isEmpty else {
            throw PermissionAnchorMissing(reason: "no Swift file under \(root.path)")
        }
        return out
    }
}
