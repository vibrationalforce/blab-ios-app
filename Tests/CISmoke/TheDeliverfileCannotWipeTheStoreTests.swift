// TheDeliverfileCannotWipeTheStoreTests.swift
// Echoel — #633: the one irreversible action in the whole submission path, defaulted shut.
//
// WHAT THIS GUARDS. `fastlane/Deliverfile` shipped with `skip_screenshots false` and
// `overwrite_screenshots true`. Together those do not mean "replace the screenshots" — they
// mean **delete every live App Store screenshot, then upload whatever is in
// `fastlane/screenshots/`**, and that directory holds exactly one path: `.gitkeep`.
//
// ⛔ AND IT COULD NOT BE UNDONE FROM THIS REPO. All three capture lanes
// (`fastlane/Fastfile:221,236,249`) and `fastlane/Snapfile:36` target a scheme named
// `EchoelmusicScreenshots`; `project.yml`'s `schemes:` block declares only `Echoelmusic`,
// `EchoelmusicFullTests`, `EchoelmusicWidgets` and `EchoelmusicWatch`, and there is no
// UI-test target anywhere. So the loss would be permanent, and the app store listing would
// have to be re-shot by hand before any submission could proceed.
//
// ⚠️ THE LANE GUARD IS NOT A SUBSTITUTE, which is the whole reason this moved into the
// Deliverfile. `fastlane/Fastfile` disarms the `upload_screenshots` LANE with an
// unconditional `UI.user_error!` — but `fastlane deliver` typed at a terminal never enters
// a lane and reads these settings directly. A guard on the lane protects the path nobody
// takes. Claim 4 keeps the lane guard pinned anyway: belt AND braces, not belt OR braces.
//
// ⚠️ WHY THE RULE IS CONDITIONAL AND NOT A PIN (#364). "`overwrite_screenshots` must be
// false" would forbid the correct future — re-arming it the day real screenshots exist is
// exactly the intended work. The invariant is the LINK: **the destructive setting is legal
// only while there is something to upload.** That can fail in the dangerous direction, can
// never fail on legitimate work, and needs no edit when the screenshots land.
//
// KIND (§1): SOURCE-TEXT SCAN over two config files plus a directory listing. It proves what
// `deliver` would READ; that Apple then deletes the remote set is Apple's behaviour, not
// something this bundle can drive. Nothing here runs fastlane.
//
// GRADING (#433 / §3), measured against the parent (89e2dbc), both trees:
//   · claim 1 is a REGRESSION: on the parent `skip_screenshots false` and
//     `overwrite_screenshots true` are both present with an empty screenshots directory —
//     the exact combination it forbids. One assertion, red there for the reason its name gives.
//   · claims 2, 3 and 4 are COUNTERWEIGHTS, identical on both trees, and they are the point:
//     the screenshots directory really is empty (so claim 1 is not vacuous), `skip_metadata`
//     is deliberately still `false`, and the lane guard still stands.
//   · claim 3's `skip_metadata` counterweight is the one most likely to be "tidied": a later
//     session harmonising all four flags to the safe value would silently disable the
//     metadata upload this file exists to perform. It is pinned WITH its reason.

import Foundation
import XCTest

final class TheDeliverfileCannotWipeTheStoreTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Ruby settings lines with `#` comments removed. Not `SourceText.codeOnly` — that one is
    /// Swift-aware and would leave `# skip_screenshots false` in a comment standing as code.
    private func settingLines(_ relative: String) throws -> [String] {
        let url = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("""
                \(relative) is missing. This guard protects the live App Store listing; a \
                missing config is a RED, never a skip — a skip here would report safety for \
                a file nobody read.
                """)
            return []
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
    }

    /// Files in `fastlane/screenshots/` that are actual screenshots (`.gitkeep` is not one).
    private func screenshotCount() -> Int {
        let dir = repoRoot().appendingPathComponent("fastlane/screenshots")
        guard let all = try? FileManager.default
            .contentsOfDirectory(atPath: dir.path) else { return 0 }
        return all.filter { ["png", "jpg", "jpeg"].contains(($0 as NSString).pathExtension.lowercased()) }.count
    }

    /// 1. THE REGRESSION. Destroying the remote set is legal only with a local set to replace it.
    func testOverwriteIsOnlyLegalWithSomethingToUpload() throws {
        let lines = try settingLines("fastlane/Deliverfile")
        let overwrite = lines.contains { $0.hasPrefix("overwrite_screenshots") && $0.contains("true") }
        let uploads = lines.contains { $0.hasPrefix("skip_screenshots") && $0.contains("false") }
        guard overwrite || uploads else { return }   // safe state: nothing to check
        XCTAssertGreaterThan(screenshotCount(), 0, """
            fastlane/Deliverfile is armed to upload/overwrite App Store screenshots \
            (`overwrite_screenshots true` and/or `skip_screenshots false`) while \
            fastlane/screenshots/ holds no image. A bare `fastlane deliver` would then DELETE \
            the live screenshots and upload nothing, and this repo cannot regenerate them — \
            the capture lanes target a scheme `project.yml` does not declare. Re-arm these \
            two ONLY in the commit that adds the files.
            """)
    }

    /// 2. COUNTERWEIGHT, and the premise claim 1 rests on (#343). If screenshots ever land,
    ///    claim 1 stops being able to fail — this is the line that says so out loud rather
    ///    than letting the pair go quietly vacuous.
    func testTheScreenshotDirectoryIsStillEmpty() {
        XCTAssertEqual(screenshotCount(), 0, """
            fastlane/screenshots/ now holds images. That is GOOD and nothing here is broken — \
            but claim 1 above can no longer fail, so re-read it deliberately: with a real set \
            present, arming `overwrite_screenshots` is the correct move and this counterweight \
            is what should be deleted, in that same commit.
            """)
    }

    /// 3. COUNTERWEIGHT. `skip_metadata` is deliberately NOT defaulted shut — uploading the
    ///    reviewed copy in `fastlane/metadata/` is what this file is FOR (#184 curated it).
    ///    The tidy-up that harmonises all four flags would silently disable that.
    func testMetadataUploadIsDeliberatelyStillArmed() throws {
        let lines = try settingLines("fastlane/Deliverfile")
        XCTAssertTrue(lines.contains { $0.hasPrefix("skip_metadata") && $0.contains("false") }, """
            `skip_metadata` is no longer false. #633 defaulted the SCREENSHOT pair shut and \
            left this one armed on purpose: losing remote screenshots is irreversible, \
            overwriting listing copy is not, and the copy in fastlane/metadata/ is the \
            reviewed text. If this was changed to make all four flags look alike, that is the \
            defect — asymmetry here is the decision, not an oversight.
            """)
    }

    /// 4. COUNTERWEIGHT. The lane guard stays. It protects a different (narrower) path than
    ///    the Deliverfile defaults do, so neither replaces the other.
    func testTheUploadLaneIsStillDisarmed() throws {
        let lines = try settingLines("fastlane/Fastfile")
        XCTAssertTrue(lines.contains { $0.contains("UI.user_error!") }, """
            fastlane/Fastfile no longer refuses the screenshot-upload lane. That guard covers \
            `fastlane ios upload_screenshots`; the Deliverfile defaults cover a bare \
            `fastlane deliver`. Removing either leaves one door open.
            """)
    }
}
