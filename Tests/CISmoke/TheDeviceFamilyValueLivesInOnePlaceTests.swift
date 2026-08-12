// TheDeviceFamilyValueLivesInOnePlaceTests.swift
// Echoel — #551. Two doc blocks on the launch path quoted a build setting that had changed
// under them, and both used it as the PREMISE of an argument.
//
// WHAT THIS GUARDS. `TARGETED_DEVICE_FAMILY` is decided in exactly one place, `project.yml`,
// and pinned there by `DeviceFamilyIsPhoneOnlyTests` (#292). Two `Sources/` comments restated
// its VALUE — `EchoelmusicApp.swift` ("we ship `TARGETED_DEVICE_FAMILY: "1,2"`") and
// `ExternalDisplayScene.swift` ("`project.yml` ships …") — and #292 changed the setting to
// phone-only without moving either. That is #416 in prose: one decision, three places, and the
// two copies nothing checks are the two that went stale.
//
// ⭐ WHY IT IS WORSE THAN A STALE NUMBER, which is the transferable part: neither comment
// merely mentioned the value, both REASONED from it. The first justified a one-shot latch on
// the launch path ("iPadOS can open a SECOND window"); the second explained a deliberate side
// effect. A session reading either would conclude the app ships to iPad — and a session
// deciding whether the latch may be deleted would weigh a scenario that cannot happen today.
// A false premise under a correct conclusion is the shape `CLAUDE.md` names repeatedly: the
// next reader cannot refute it, because the conclusion still looks right.
//
// ⛔ AND THIS GUARD DELIBERATELY DOES **NOT** USE `SourceText.codeOnly` — the one file in this
// bundle where stripping comments would remove the entire subject. Every other scan here asks
// "does the CODE do X"; this one asks "does the PROSE assert a value it does not own". Running
// the house stripper out of habit would have produced a permanently green scan over an empty
// string, which is the silent-pass failure this bundle exists to prevent (#453 says one
// stripper for the whole bundle; it does not say every scan is about code).
//
// ⚠️ IT FORBIDS A VALUE ASSERTION, NOT THE TOKEN (#364/#491). `TARGETED_DEVICE_FAMILY:` followed
// by a quoted value is what goes stale; naming the setting to say where it lives is exactly
// what the corrected comments now do, and a guard that banned the word would red on its own
// repair — the collision three slices in this session already had to unpick.
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN. It cannot see what the app actually ships; that is
// `project.yml`'s value and `DeviceFamilyIsPhoneOnlyTests`' job. This file only enforces that
// nothing else claims to know it.
//
// ⚠️ HONEST GRADING — TRANSCRIBED in Python against the parent (`887ec12`) and this tree; both
// walks reached 350 files under `Sources/`, so neither verdict is an empty-set artefact:
//   · ONE REGRESSION: claim 1, red on the parent, listing BOTH offending comments
//     (`EchoelmusicApp.swift:206` and `ExternalDisplayScene.swift:41`). Two offenders, ONE
//     finding — #486: a single scan reporting N sites is not N regressions.
//   · NO stripper measurement, because this file does not use one (see the ⛔ note above); the
//     `TRAGEND/PROPHYLAKTISCH` count that §2 requires applies to `SourceText.codeOnly` users.
//   · TWO COUNTERWEIGHTS green on both trees, and they are why the correction is honest rather
//     than convenient: the `startupDone` latch is still there AND still consulted (claim 2),
//     and the external scene still mounts `ExternalStageView` rather than `WorkspaceView`
//     (claim 3) — the two facts that make "the named scenario is unreachable today" true. If
//     either moved, the corrected prose would be wrong in the other direction and the latch's
//     status would need re-deciding rather than re-describing.

import Foundation
import XCTest

final class TheDeviceFamilyValueLivesInOnePlaceTests: XCTestCase {

    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let scene = "Sources/Echoelmusic/Studio/ExternalDisplayScene.swift"
    private static let setting = "TARGETED_DEVICE_FAMILY"

    // MARK: - claim 1 (the regression) — nobody under Sources/ states the value

    func testNoSourceFileAssertsADeviceFamilyValue() throws {
        var offenders: [String] = []
        for rel in try swiftFiles() {
            let text = try rawText(rel)   // RAW on purpose — see the ⛔ note in the header
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                let s = String(line)
                guard let r = s.range(of: "\(Self.setting):") else { continue }
                // A VALUE assertion is the setting name followed by a quoted literal. Naming
                // the setting to point at its owner is legitimate and must stay legal.
                guard s[r.upperBound...].contains("\"") else { continue }
                offenders.append("\(rel):\(i + 1): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) comment(s) under `Sources/` quote a `\(Self.setting)` value: \
            \(offenders.joined(separator: " | ")). That value is decided in `project.yml` and \
            pinned by `DeviceFamilyIsPhoneOnlyTests` — a copy here is a second definition of \
            one decision (#416) and nothing checks it, which is exactly how #292 changed the \
            setting while two doc blocks on the launch path went on reasoning from the old one. \
            Name the setting and say where it lives; do not restate what it is.
            """)
    }

    // MARK: - claim 2 (COUNTERWEIGHT) — the latch the old prose justified is still there

    /// #343. A file asserting only "the stale quote is gone" stays green on a tree that ALSO
    /// deleted the latch — which is the tempting move once its scenario reads as unreachable,
    /// and the wrong one: it still executes, it costs one boolean, and iPad is explicitly not
    /// ruled out forever.
    func testTheStartupLatchStillExistsAndIsStillConsulted() throws {
        let code = try rawText(Self.app)
        XCTAssertTrue(code.contains("@State private var startupDone = false"), """
            The `startupDone` latch is gone from `\(Self.app)`. #551 corrected the PREMISE of \
            its doc block (phone-only ships, so the second-window scenario is unreachable \
            today) and deliberately kept the mechanism. Removing it is a separate decision \
            with its own reasoning — and if it was made, the ⭐ paragraph in that doc block and \
            the sentence in `ExternalStageBridge` that reasons from the latch both move in the \
            same commit.
            """)
        XCTAssertTrue(code.contains("guard !startupDone"), """
            `startupDone` is declared but no longer consulted. A latch nothing reads is worse \
            than no latch: it reads as protection while providing none.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the premise that makes "unreachable today" true

    func testTheExternalSceneMountsItsOwnRootNotTheWorkspace() throws {
        let code = try rawText(Self.scene)
        XCTAssertTrue(code.contains("rootView: ExternalStageView()"), """
            The external-display scene no longer mounts `ExternalStageView`. Both corrected \
            comments rest on this: the ONE extra scene the app enables hosts its own root, so \
            the startup `.task` on `WorkspaceView` cannot run a second time. If this scene ever \
            hosts `WorkspaceView`, the latch stops being belt-and-braces and becomes the only \
            thing standing between a second scene and a hot attach to a running engine — say \
            so in `\(Self.app)` in the same commit.
            """)
        XCTAssertFalse(code.contains("rootView: WorkspaceView()"), """
            The external-display scene now mounts `WorkspaceView`. See above — this is the \
            case the latch was written for, arriving by a different door than the one its \
            original prose predicted.
            """)
    }

    // MARK: - source access

    private struct FamilyAnchorMissing: Error { let reason: String }

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

    /// RAW file text. This file's subject IS the comments (see the header) — using
    /// `SourceText.codeOnly` here would delete everything the scan is looking for and report a
    /// confident green over nothing.
    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw FamilyAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw FamilyAnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw FamilyAnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so a "nobody states it" result here would be vacuous.
                """)
        }
        return out.sorted()
    }
}
