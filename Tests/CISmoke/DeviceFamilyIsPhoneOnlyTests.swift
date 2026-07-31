// DeviceFamilyIsPhoneOnlyTests.swift
// Echoel — #292. The app was shipping to iPad (`TARGETED_DEVICE_FAMILY: "1,2"` on the app
// AND the widget target) while `CLAUDE.md` claimed "iPhone-only for v10 MVP" in two places.
// Nobody decided that; it was a default that nobody re-read. Founder delegated the call on
// 2026-07-31 ("Du entscheidest zukunftsweisend") and it is now iPhone only.
//
// ⭐ WHY THIS IS WORTH A GUARD RATHER THAN A COMMENT. The deciding reason is the SENSOR, and
// it is invisible from the build setting: `CameraCapture` gates the rPPG illumination on
// `device.hasTorch`, and no iPad ships a rear LED. On iPad the finger-on-lens pulse runs
// without the torch — the exact condition the 2026-06-18 fix identified as why it fails to
// lock. So an iPad build ships the app's own premise ("your body plays it") onto a device
// where the primary bio source is degraded. A future reader who sees only `"1"` has no way
// to know that; they see a restriction and "helpfully" widen it. This test is where the
// reason lives, next to the assertion that enforces it.
//
// ⚠️ THE SET IS THE POINT, not any single target. A widget extension declaring a device
// family its container app does not support is an App Store validation finding, so those two
// move together or not at all. And writing this guard is what surfaced that the TWO TEST
// bundles were still on `"1,2"` after both shipping targets had been changed — an
// inconsistency I would have missed and reported as done. That is the whole argument for
// asserting over the set instead of over the one line you happen to be editing.
//
// ⭐ THIS IS A SEQUENCING GUARD, NOT AN EXCLUSION — read this before you read the assertion.
// The founder's stated platform target (2026-07-31, verbatim) is *"Das gesamte Apple Ökosystem
// soll langfristig unterstützt werden auch VR/XR und Waerables."* iPhone-first is the ORDER,
// not the scope. This file exists so the door opens on purpose and with the prerequisite in
// hand, not because a default flipped it — which is exactly how iPad got shipped unnoticed.
// If you are here to widen it, that is a legitimate errand; see the readiness ladder in
// CLAUDE.md for what each platform still needs.
//
// ⛔ HONEST LIMIT: this reads `project.yml`. It proves what XcodeGen will be TOLD, not what
// the resulting .xcodeproj contains, and it says nothing about whether the app behaves well
// on any device. Re-enabling iPad needs a bio source that works there (the BLE strap is built
// and wired) plus the adaptivity pass (#292). Do it deliberately: change the settings AND
// this test in the same commit.

import Foundation
import XCTest

final class DeviceFamilyIsPhoneOnlyTests: XCTestCase {

    /// ⭐ EVERY iOS TARGET IN ONE TEST on purpose — a mismatch between them is its own
    /// defect, and no single assertion describes it.
    func testEveryIOSTargetIsIPhoneOnly() throws {
        let families = try deviceFamilyValues()
        let listing = families.joined(separator: "\n")
        XCTAssertEqual(families.count, 4, """
        expected exactly four non-Watch `TARGETED_DEVICE_FAMILY` entries (Echoelmusic, \
        EchoelmusicWidgets, EchoelmusicTests, EchoelmusicFullTests) but found \(families.count):
        \(listing)

        The Watch target legitimately declares "4" and is excluded here. If an iOS target \
        was added or removed, update this count deliberately — do not loosen it to a range, \
        because "at least N are iPhone-only" is exactly the assertion that lets a new \
        iPad-enabled target through.
        """)
        for value in families {
            XCTAssertEqual(value, "1", """
            a shipping target no longer declares iPhone-only (`"1"`), it declares `"\(value)"`.

            If iPad is coming back, that is a real decision and it needs two things this \
            setting alone does not give it: a bio source that works there (no iPad has a \
            rear torch, and `CameraCapture` gates rPPG illumination on `device.hasTorch`), \
            and the adaptivity pass in #292 — nine of eleven panels still render as one \
            fixed column. Change the setting AND this test in the same commit, with the \
            reason, rather than deleting the guard.
            """)
        }
    }

    /// The `TARGETED_DEVICE_FAMILY` values of the two SHIPPING iOS targets, in file order.
    ///
    /// ⚠️ The Watch target's `"4"` is deliberately filtered out rather than counted — it is
    /// a different platform and a legitimate value. Filtering on the value (not on a target
    /// name) keeps this from breaking when the target list is reordered, which is the kind
    /// of edit that has no business reddening the blocking bundle.
    private func deviceFamilyValues() throws -> [String] {
        try codeLines("project.yml")
            .filter { $0.contains("TARGETED_DEVICE_FAMILY:") }
            .compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let raw = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return raw == "4" ? nil : raw   // Watch — a different platform, not a widening
            }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let spec = root.appendingPathComponent("project.yml")
        guard FileManager.default.fileExists(atPath: spec.path) else {
            throw XCTSkip("project.yml not present at \(spec.path) — this test inspects the "
                          + "project spec as text, so it SKIPS rather than reporting a green "
                          + "it did not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Load-bearing here: the long
    /// `#` block above the app target's setting quotes the old `"1,2"` verbatim so the
    /// history stays legible, and without the filter the guard would read its own epitaph.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }
}
