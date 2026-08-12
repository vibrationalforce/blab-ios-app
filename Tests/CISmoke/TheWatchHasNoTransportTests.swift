// TheWatchHasNoTransportTests.swift
// Echoel — #549. The wearable roadmap named a route that cannot carry a byte.
//
// WHAT THIS GUARDS. Three prose sites described the watch producer half as
// "on-wrist HealthKit HR → App Group → phone": `EchoelWatchApp.swift`'s header, `CLAUDE.md`'s
// platform ladder, and `project.yml`'s watch block ("C7 adds HealthKit on-wrist HR → App
// Group"). **An App Group container is PER DEVICE.** The watch and the iPhone do not share a
// `UserDefaults(suiteName:)`; an App Group is shared between processes on ONE device — which
// is precisely why the identical `BioFeedbackManager` path IS correct for the Widget and can
// carry nothing between wrist and phone in either direction. There is no transport in the repo
// at all: `WatchConnectivity`/`WCSession` appear nowhere under `Sources/`.
//
// ⭐ WHY THIS IS WORTH A GUARD RATHER THAN A NOTE. C7 as specified is a HealthKit task; C7 as
// it actually stands is a TRANSPORT DECISION, and `WCSession` is a new framework — which under
// `CLAUDE.md` needs the Council/founder step BEFORE any code. Someone implementing the written
// version would produce correct HealthKit code against a channel that does not exist.
//
// ⚠️ AND THEY COULD NOT TELL, WHICH IS THE ACTUAL HAZARD. `refreshFromSharedStore()` returns
// nil for an empty container and the watch renders its ordinary idle state ("Start a session
// on iPhone."). A wired route that transports nothing renders BYTE-IDENTICALLY to an unwired
// one. Silent-by-construction failures are the ones that need an executable witness.
//
// ⚠️ HONEST SEVERITY: planning cost, not user impact. The watch target is NOT embedded —
// `project.yml` keeps `- target: EchoelmusicWatch` commented out under the app's dependencies
// (the signing-safe C5 pattern) — so no build ships it and no user has seen the misleading
// empty state. Claim 3 pins that premise, so the day the embed is enabled this file goes red
// and says the severity has risen.
//
// ⚠️ THE LIMIT. Claims 1–3 are SOURCE-TEXT SCANS. That an App Group is per-device is a
// PLATFORM fact, not something this bundle can demonstrate: no test here can run on a watch,
// and there is no simulator. What the scans can carry is that no transport exists and that the
// premises the prose now rests on still hold. The platform fact itself is cited, not proved.
//
// ⚠️ HONEST GRADING — TRANSCRIBED against the parent and this tree. **ZERO REGRESSIONS, and
// that is correct rather than a gap** (#433): this slice changes PROSE in two files, and every
// claim below describes code and configuration neither tree touches, so all six verdicts are
// green on both. What the file buys is the FUTURE red — claim 1 fires on the commit that adds
// a transport, which is exactly the commit that must rewrite all three prose sites, and claim 3
// fires on the commit that embeds the target. It fires on the right events instead of
// forbidding correct work (#364).
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING for claim 1, MEASURED (#453) over {3 claims × 2
// trees}: **1 of 6** verdicts flips — claim 1 on THIS tree, PASS stripped and FAIL raw, because
// the ⛔ block this slice writes into `EchoelWatchApp.swift` names `WCSession` verbatim while
// explaining that there is none. The #486/#491 collision in its purest form: the negative scan
// meets the very sentence that records the absence.

import Foundation
import XCTest

final class TheWatchHasNoTransportTests: XCTestCase {

    private static let watchApp = "Sources/EchoelmusicWatch/EchoelWatchApp.swift"

    /// The three places whose text rests on "there is no transport". Named in the failure
    /// message so the commit that adds one moves all of them together, rather than leaving two
    /// describing a world that ended (#472).
    private static let prose = """
        (1) the ⛔ block in \(watchApp)'s header, (2) the Watch row of `CLAUDE.md`'s platform \
        ladder, and (3) `project.yml`'s watch block ("C7 adds HealthKit on-wrist HR → App \
        Group") — that third one is founder-gated: REPORT it, do not edit it.
        """

    // MARK: - claim 1 — no transport exists

    func testNoWatchTransportIsWiredAnywhere() throws {
        var hits: [String] = []
        for rel in try swiftFiles() {
            let code = try source(rel)
            for needle in ["WatchConnectivity", "WCSession"] where code.contains(needle) {
                hits.append("\(rel): \(needle)")
            }
        }
        XCTAssertTrue(hits.isEmpty, """
            A watch transport now exists (\(hits.joined(separator: ", "))). That is GOOD NEWS \
            and this assertion is how it gets announced — but the wrist↔phone route is no \
            longer "App Group", so three prose sites are now wrong and must move in the SAME \
            commit: \(Self.prose)
            Then delete this assertion; it has done its job.
            """)
    }

    // MARK: - claim 2 (COUNTERWEIGHT) — the consumer half still exists to be described

    /// #343. A file asserting only "no transport" stays green on a tree that deleted the watch
    /// app entirely, leaving prose that carefully explains a target nobody has. So pin that the
    /// consumer half is still there and still reads the App Group — the thing the corrected
    /// prose says is Widget-shaped.
    func testTheWatchStillReadsItsOwnAppGroup() throws {
        let code = try source(Self.watchApp)
        XCTAssertTrue(code.contains("BioFeedbackManager()"), """
            The watch app no longer constructs `BioFeedbackManager`. The corrected prose \
            describes a consumer that reads THIS device's App Group container and therefore \
            cannot see the phone; if that consumer is gone, the description is about nothing — \
            rewrite \(Self.prose)
            """)
        XCTAssertTrue(code.contains("refreshFromSharedStore()"), """
            The watch app no longer calls `refreshFromSharedStore()`. That call is the exact \
            mechanism the correction names: it returns nil on an empty container, so a route \
            that transports nothing renders identically to no route at all. Without it the \
            "silent by construction" reasoning needs re-deriving.
            """)
    }

    // MARK: - claim 3 (THE SEVERITY PREMISE) — nobody can see it yet

    /// The honest-severity half, and it is the one that must be able to go red: "planning cost,
    /// not user impact" is true only while the target is unembedded. `project.yml` is read as
    /// raw text — it is YAML, and `SourceText.codeOnly` would blank nothing useful and
    /// misparse `#` comments (it strips `//`, not `#`).
    func testTheWatchTargetIsStillNotEmbedded() throws {
        let yml = try text("project.yml")
        let embedded = yml
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { $0 == "- target: EchoelmusicWatch" }
        XCTAssertFalse(embedded, """
            `EchoelmusicWatch` is now embedded as a dependency of the app, so a real user can \
            reach the watch face. The severity note in \(Self.watchApp) and in `CLAUDE.md` \
            says "planning cost, not user impact — and it rises the day the embed is turned \
            on". That day is today: the wrist now shows "Start a session on iPhone." forever, \
            because nothing on the watch writes that container and nothing transports the \
            phone's. Re-rank it and say so in \(Self.prose)
            """)
        // The COMMENTED form must still be there: an entry that vanished entirely would pass
        // the assertion above while meaning something completely different (the plan dropped,
        // not deferred) — green for a reason that no longer exists (#456).
        XCTAssertTrue(yml.contains("# - target: EchoelmusicWatch"), """
            The commented-out watch dependency is gone from `project.yml` altogether. The \
            assertion above then passes for the wrong reason. If the watch plan was dropped, \
            this whole file goes with it; if it was merely reworded, re-anchor here.
            """)
    }

    // MARK: - source access

    private struct WatchAnchorMissing: Error { let reason: String }

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

    /// Raw text — for `project.yml`, whose comment marker is `#` and which the Swift stripper
    /// would leave untouched anyway. Using the wrong tool quietly would be worse than not
    /// using one.
    private func text(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WatchAnchorMissing(reason: "\(relativePath) is missing while the tree is present")
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WatchAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Every `.swift` path under `Sources/`, including the watch and widget targets — the scan
    /// must cover the whole tree, since a transport could legitimately be introduced on either
    /// side of the pair.
    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw WatchAnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw WatchAnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so a "no transport" result here would be vacuous.
                """)
        }
        return out.sorted()
    }
}
