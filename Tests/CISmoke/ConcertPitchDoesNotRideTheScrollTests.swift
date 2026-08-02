// ConcertPitchDoesNotRideTheScrollTests.swift
// Echoel — scrolling the header strip must not retune the instrument. BLOCKING. #391.
//
// THE DEFECT, and it is on video. `EchoelValueField`'s drag adjusts on BOTH axes (founder
// 2026-07-12: "up = increase, right = increase"), which is right for a field in a vertical
// panel. The Concert-pitch A4 field is not in one: it sits inside `WorkspaceView`'s
// `ScrollView(.horizontal)` header chip strip. So the gesture that scrolls the strip sideways
// fed its own travel into the field. On the founder's 2026-08-02 screen recording of
// v10.79.366 the value walks 440 → 483,4352 → 500,0000 Hz — the range ceiling — while the
// header labels march Genre → Key → Scale → Tone system → Note names → A4, i.e. while the strip
// is being scrolled, and with the keypad never opening.
//
// ⛔ WHY THIS IS NOT A COSMETIC MISS-SCRUB. A4 is the global tuning reference. `onCommit` posts
// "a4", which `EchoelStudioView.handleCompositionEdit` turns into `applyConcertPitch(...)` +
// `recomposeIfRunning()` — every voice retuned and the running take recomposed. And
// `session.a4Hz` is PERSISTED, so the accident survives relaunch: the instrument stays a
// semitone and a half sharp until someone notices a four-decimal number in a 104 pt box.
//
// This is also the strongest candidate yet for the founder's "es klingt sehr unharmonisch"
// (same build), because it composes with the re-seed overlap: `loadArrangement` deliberately
// does not `allNotesOff` while playing, so notes still sounding at the OLD reference ring
// under new ones at the new reference. #390's breadcrumb now prints `a4=`, which is what will
// confirm or kill that in the next device log — this guard does not claim it, it enables it.
//
// ⚠️ WHY A SOURCE SCAN. The defect is a gesture inside a `ScrollView` on a `@MainActor` view
// with the whole session graph behind it; there is no local toolchain and no simulator. House
// pattern. It proves the axis is OFF at the call site; it cannot prove the drag feels right.
//
// NEEDS-FOUNDER-VERIFY: scroll the header strip left and right with a finger deliberately
// dragged across the A4 box. The number must not move. Tapping it must still open the keypad,
// and a deliberate UP/DOWN drag on it must still adjust.

import Foundation
import XCTest

final class ConcertPitchDoesNotRideTheScrollTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/EchoelValueField.swift"
    private static let header = "Sources/Echoelmusic/Studio/WorkspaceView.swift"

    /// ⭐ THE CALL SITE. This is the assertion that actually protects the tuning: the capability
    /// can exist and default to `true`, and then nothing has changed.
    func testTheA4FieldOptsOutOfTheSidewaysAxis() throws {
        let code = try codeLines(Self.header)
        guard let a4 = code.firstIndex(where: { $0.contains("value: $session.a4Hz") }) else {
            return XCTFail("""
                the Concert-pitch A4 field is gone from \(Self.header). If it moved, move this \
                guard with it — do not leave a check for a control that no longer exists.
                """)
        }
        // The construction spans several lines, so the window is the call itself and not the
        // file: a `horizontalScrub: false` on some OTHER field a few hundred lines away would
        // otherwise pass while the A4 field kept riding the scroll. A fixed 12-line window is
        // deliberately blunt — the call is 9 lines today, and a window that tracked brackets
        // would be more code than the thing it guards.
        let construction = code[a4..<min(a4 + 12, code.endIndex)]
        XCTAssertTrue(construction.contains(where: { $0.contains("horizontalScrub: false") }), """
            the A4 field no longer passes `horizontalScrub: false` (#391).

            It lives in a `ScrollView(.horizontal)`, so with the sideways axis live the gesture \
            that scrolls the header strip also raises the global tuning reference — measured on \
            device as 440 → 483,4352 → 500,0000 Hz without the keypad opening. `onCommit` then \
            retunes every voice and recomposes, and the value is persisted.
            construction: \(Array(construction).map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    /// The knob has to be WIRED, not merely declared. A property nothing reads is the same
    /// defect with a reassuring name on it.
    func testTheSidewaysAxisIsActuallyGated() throws {
        let code = try codeLines(Self.field)
        XCTAssertTrue(code.contains(where: { $0.contains("var horizontalScrub: Bool = true") }), """
            `EchoelValueField.horizontalScrub` is gone. If the axis was removed outright the \
            call site above is now passing a parameter that does not exist; if it was renamed, \
            move both this needle and the call site in the same commit.
            """)
        let gated = code.filter { $0.contains("let dxStep") }
        XCTAssertEqual(gated.count, 1, """
            expected exactly one `dxStep` binding in \(Self.field), found \(gated.count):
            \(gated.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        XCTAssertTrue(gated[0].contains("horizontalScrub ?"), """
            the sideways delta is no longer gated on `horizontalScrub`:
            \(gated[0].trimmingCharacters(in: .whitespaces))

            Ungated, the flag is decoration and the header scroll retunes the instrument again.
            """)
    }

    /// ⛔ THE REASON, PINNED. The opt-out is only correct because the strip really is a
    /// horizontal scroll. If that container ever becomes a vertical stack, `horizontalScrub:
    /// false` stops being a fix and becomes an unexplained restriction on a founder-asked
    /// gesture — so the premise is asserted next to the conclusion rather than left in prose.
    func testTheHeaderStripIsStillAHorizontalScroll() throws {
        let code = try codeLines(Self.header)
        XCTAssertTrue(code.contains(where: { $0.contains("ScrollView(.horizontal") }), """
            \(Self.header) no longer contains a horizontal ScrollView — the premise of #391 is \
            gone. Re-decide whether the A4 field should get its sideways axis back instead of \
            leaving an opt-out whose reason no longer holds.
            """)
    }

    // MARK: - Source helpers

    /// Every line that is not a whole-line comment. Load-bearing: the ⛔ block above the call
    /// site quotes `horizontalScrub` and the measured Hz values verbatim while explaining them.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
