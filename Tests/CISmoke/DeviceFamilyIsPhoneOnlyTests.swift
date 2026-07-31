// DeviceFamilyIsPhoneOnlyTests.swift
// Echoel — #292. The app was shipping to iPad (`TARGETED_DEVICE_FAMILY: "1,2"` on ALL FOUR
// iOS targets — app, widget and both test bundles) while `CLAUDE.md` claimed "iPhone-only
// for v10 MVP". Nobody decided that; it was a default that nobody re-read. Founder delegated
// the call on 2026-07-31 ("Du entscheidest zukunftsweisend") and it is now iPhone only.
//
// ⛔ TWO COUNTS IN THIS HEADER WERE WRONG ON THE DAY IT WAS WRITTEN, in the file whose whole
// premise is that a number nobody re-reads goes stale. It said "the app AND the widget
// target" (it was four — the paragraph twelve lines below said so, in the same commit) and
// "in two places" of CLAUDE.md (`git show afcf3aa^:CLAUDE.md` has the phrase exactly once;
// the other line said "iPhone-first", a different claim). Neither changed what the guard
// does — which is the point: a wrong number in a header survives precisely because it is
// inert. Recount before quoting this paragraph.
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
//
// ⛔ AND THE COMMIT THAT INSTALLED THAT SENTENCE ALSO SHIPPED ITS OPPOSITE — four times.
// "Re-enabling is this one line" stood in `project.yml`, in CLAUDE.md, in the commit body and
// in `decisions.csv`, while the line right above says "change the settings AND this test".
// The honest count is FOUR settings (`project.yml`: app, widget, both test bundles) + this
// guard's equality at `:58` + the rationale block whose text goes false + the CLAUDE.md
// readiness row. That is still cheap and still makes the intended point — the door is
// DELIBERATE, not expensive — so the slogan was not even buying anything. Whoever re-opens
// iPad: plan from this paragraph, not from the slogan, and delete the slogan when you find it.

import Foundation
import XCTest

final class DeviceFamilyIsPhoneOnlyTests: XCTestCase {

    /// ⭐ EVERY iOS TARGET IN ONE TEST on purpose — a mismatch between them is its own
    /// defect, and no single assertion describes it.
    func testEveryIOSTargetIsIPhoneOnly() throws {
        let families = try deviceFamilyValues()
        let expected = try iOSTargetCount()
        let listing = families.joined(separator: "\n")

        // ⛔ THIS WAS A HARD-CODED `4`, AND THE HOLE IT LEFT IS THE ONE A NEW TARGET FALLS
        // INTO. A new iOS target that simply OMITS `TARGETED_DEVICE_FAMILY` inherits Xcode's
        // iOS default — `"1,2"` — and ships to iPad, while the declared entries stay at four
        // and every one of them is still `"1"`. Green, silently. The literal also argued for
        // itself ("do not loosen it to a range"), which was right about ranges and blind to
        // omission. Deriving the expectation from the number of `platform: iOS` targets is
        // not a loosening: it asserts that every iOS target DECLARES the key, which is the
        // half a value check can never see.
        XCTAssertGreaterThan(expected, 0, """
        found no `platform: iOS` target in project.yml — the parse failed, so a green result \
        here would be meaningless
        """)
        XCTAssertEqual(families.count, expected, """
        \(expected) iOS targets in project.yml but only \(families.count) declare \
        `TARGETED_DEVICE_FAMILY`:
        \(listing)

        A target that does not declare it inherits Xcode's iOS default `"1,2"` and ships to \
        iPad. Add the setting to the new target rather than relaxing this. (The Watch target \
        legitimately declares "4" and is excluded from both sides of this comparison.)
        """)
        for value in families {
            XCTAssertEqual(value, "1", """
            a shipping target no longer declares iPhone-only (`"1"`), it declares `"\(value)"`.

            If iPad is coming back, that is a real decision and it needs two things this \
            setting alone does not give it: a bio source that works there (no iPad has a \
            rear torch, and `CameraCapture` gates rPPG illumination on `device.hasTorch`), \
            and the adaptivity pass in #292 — nine of eleven panels have no reflow, so on a \
            wide screen their rows stretch across the FULL width (`menuPanelHost` sets \
            `maxWidth: .infinity`); only `mixerPanel` and `sessionPanel` go two-column. \
            Change the setting AND this test in the same commit, with the reason, rather \
            than deleting the guard.
            """)
        }
    }

    /// The `TARGETED_DEVICE_FAMILY` values of every non-Watch target, in file order.
    /// (This said "the two SHIPPING iOS targets" and returned four — both test bundles are
    /// in here too, and `testEveryIOSTargetIsIPhoneOnly` requires them to be.)
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
                // ⛔ THE `#`-STRIP IS NOT DECORATION. Without it a perfectly ordinary trailing
                // YAML comment — `TARGETED_DEVICE_FAMILY: "1"  # phone only` — parses to
                // `1"  # phone only` and reddens the BLOCKING bundle for a comment. Nobody
                // would read that failure as intended, and the next person deletes the guard
                // instead of the comment.
                var value = String(line[line.index(after: colon)...])
                if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
                let raw = value
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return raw == "4" ? nil : raw   // Watch — a different platform, not a widening
            }
    }

    /// How many targets declare `platform: iOS`. The Watch target declares `platform: watchOS`
    /// and is excluded by the exact match, which is why `deviceFamilyValues()` may drop its
    /// `"4"` without the two sides disagreeing.
    private func iOSTargetCount() throws -> Int {
        try codeLines("project.yml")
            .filter { $0.trimmingCharacters(in: .whitespaces) == "platform: iOS" }
            .count
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

    /// Every line of `path` that is not a whole-line comment.
    ///
    /// ⛔ ITS STATED REASON WAS FALSE AND I VERIFIED IT BY RUNNING THE PREDICATE BOTH WAYS.
    /// It claimed to be "load-bearing", because the `#` block above the app target's setting
    /// quotes the old `"1,2"` verbatim and "without the filter the guard would read its own
    /// epitaph". With the filter removed the result is byte-identical — five hits, four
    /// values — because that epitaph line does not contain the string
    /// `TARGETED_DEVICE_FAMILY:`, so the caller's own filter already excluded it. The filter
    /// is still worth keeping (it would catch a future commented-out `# TARGETED_DEVICE_FAMILY:
    /// "1,2"`), just for a reason that has not happened yet. Correct mechanism, wrong
    /// justification, sitting in the file whose stated purpose is to be where the reason
    /// lives — the exact pattern CLAUDE.md warns about, committed by the commit that quoted
    /// the warning.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }
}
