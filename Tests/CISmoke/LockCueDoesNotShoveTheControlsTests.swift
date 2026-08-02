// LockCueDoesNotShoveTheControlsTests.swift
// Echoel — a six-second congratulation must not move the buttons under the finger. #382.
//
// WHAT THIS GUARDS. `BioStripView.statusBanner` is one `@ViewBuilder` if/else-if chain that
// renders AT MOST one line above the strip. Two of its three cases are persistent states
// (camera recovering, camera access denied). The third is a TIMER: when the pulse settles,
// `lockedCueVisible` flips true, and six seconds later it flips back — both inside
// `withAnimation`. While it was an ordinary `else if`, those two flips INSERTED and REMOVED a
// view from the layout, so everything below moved twice.
//
// "Everything below" is not the strip alone. In `EchoelStudioView.bioPanel` this view is the
// FIRST child of a `VStack`, followed by the explanatory sentence, the "Open Routing" button
// and `HealthWriteOptInRow()`. So the shove lands on two controls, and it lands six seconds
// apart — long enough that the user has stopped expecting it and is plausibly reaching for the
// button when the second one fires.
//
// ⭐ WHY THIS BECAME WORTH A SLICE NOW, stated plainly because the honest version is less
// flattering than "we found a bug": the behaviour is OLD, and #353d made it BIGGER. Before
// that slice the banner was pinned at 11 pt and the shove was one line, roughly 26 pt. Now the
// banner scales with Dynamic Type and wraps, so at AX3+ the same sentence is three or four
// lines and the shove is on the order of 80–110 pt — a third of a phone's usable panel height,
// twice, unannounced. Fixing the font exposed the layout, which is the normal shape of this
// kind of debt and not a reason to regret the font fix.
//
// THE FIX AND WHY THIS ONE. Three answers were on the table and only one needs no device to
// justify:
//   (a) reserve the slot — calm, but a naive fixed height cannot be right at every Dynamic
//       Type size, and a wrong reservation clips or wastes space;
//   (b) drop only the HIDE animation — halves nothing. It is still two layout changes; it just
//       makes the second one instant, i.e. gives the user LESS warning, not more;
//   (c) float the cue over the strip — no shove, but it covers the numbers at the exact moment
//       the numbers are the payoff.
// What ships is (a) done without a magic number: the slot holds the REAL cue view, made
// invisible with `.opacity`, so its reserved height is by construction the height that view
// will occupy at whatever text size the reader has chosen. There is no constant to get wrong.
//
// AND THE RESERVATION IS GATED ON `cameraRPPG.isRunning`, which is the part that keeps it
// honest. A status line that exists only while a measurement is running is a design statement;
// a permanently blank 26 pt above the strip for someone who never starts the camera is a tax.
// The `else` branch is therefore conditional, and this file asserts that it stays conditional —
// an unconditional `else` would "fix" the shove by charging every user for it.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the cue is expressed as an
// opacity change inside a conditionally-reserved slot; it cannot prove the panel actually
// holds still, and it cannot prove the reserved height is comfortable at AX5.
// NEEDS-FOUNDER-VERIFY: Larger Text at AX3+, open Bio, let the pulse lock, and reach for
// "Open Routing" while the green line appears and disappears. Does anything move?
//
// BOTH tests go red on the pre-fix source (`6e58d8e`), verified by re-deriving every assertion
// against `git show 6e58d8e:…` before this file was committed. The shape test fails three of
// its four ways — `else if lockedCueVisible` present, `.opacity(` absent, the `isRunning` gate
// absent; only "no unconditional `else`" was already true, and it is a pin against a future
// over-correction rather than a description of the bug. The VoiceOver test fails because
// `accessibilityHidden` appears nowhere in the file. Written out per assertion instead of as a
// tally, because a tally in exactly this position has been wrong twice in this bundle.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class LockCueDoesNotShoveTheControlsTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"
    private static let bannerDeclaration = "private var statusBanner: some View"

    /// The transient cue changes its OPACITY inside a reserved slot — it is not inserted.
    func testTheLockCueIsAReservedSlotNotAnInsertion() throws {
        let source = try codeLines(Self.strip)
        let slot = try window(source, from: Self.bannerDeclaration)

        XCTAssertFalse(slot.contains { $0.contains("else if lockedCueVisible") }, """
            `statusBanner` is branching on `lockedCueVisible` again, which puts the six-second \
            "Pulse detected" cue back INTO and OUT OF the layout. In `bioPanel` this view is \
            the first child of a `VStack`, so both flips move the sentence below it, the \
            "Open Routing" button and the Health opt-in row — twice, six seconds apart, at a \
            moment when the user has every reason to be reaching for one of them. Since the \
            banner scales with Dynamic Type (#353d) that shove is 80–110 pt at AX3+, not the \
            26 pt it used to be. Express the cue as an opacity change inside a slot that is \
            already reserved, so the panel holds still.
            """)

        XCTAssertTrue(slot.contains { $0.contains("opacity(lockedCueVisible ? 1 : 0)") }, """
            The lock cue lost `.opacity(lockedCueVisible ? 1 : 0)`. That expression is the \
            whole fix: the slot always builds the REAL cue view while a measurement runs, so \
            the height it reserves is by construction the height the cue will need at the \
            reader's own text size — no constant to get wrong, at any Dynamic Type setting. \
            Replacing it with a conditional, or with a hard-coded `minHeight`, brings back \
            either the shove or a number that is right at exactly one text size.
            """)

        XCTAssertTrue(slot.contains { $0.contains("else if cameraRPPG.isRunning {") }, """
            The reserved slot is no longer gated on `cameraRPPG.isRunning`. That gate is what \
            keeps the reservation from becoming a tax: while a measurement runs, a status line \
            exists and the panel is stable; when nothing is measuring there is no line and no \
            blank space. An ungated slot would hold empty height above the strip for every \
            user who never starts the camera — solving the shove by charging everyone for it.
            """)

        XCTAssertFalse(slot.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("} else {") }, """
            `statusBanner` grew an unconditional `else`. Every branch here must be gated on a \
            state that means "there is something to say", otherwise the slot is reserved even \
            when the camera is off — see the message above. If a genuinely unconditional \
            status line is wanted, that is a design change and this guard should be rewritten \
            with it, deliberately, rather than deleted to let it through.
            """)
    }

    /// An invisible cue must be invisible to VoiceOver too.
    ///
    /// ⚠️ `.opacity(0)` does NOT remove a view from the accessibility tree. `banner(_:_:_:)`
    /// ends in `.accessibilityLabel(text)`, which makes it an element; without an explicit
    /// hide, a VoiceOver user would swipe into "Pulse detected — you can let go & play" for
    /// the entire measurement, including before any pulse has been detected. That is worse
    /// than the layout bug this slice set out to fix: the shove was an annoyance for sighted
    /// users, this would be a false statement to the one reader who cannot check it.
    func testTheInvisibleCueIsSilentForVoiceOver() throws {
        let source = try codeLines(Self.strip)
        let slot = try window(source, from: Self.bannerDeclaration)

        XCTAssertTrue(slot.contains { $0.contains("accessibilityHidden(!lockedCueVisible)") }, """
            The reserved lock-cue slot lost `.accessibilityHidden(!lockedCueVisible)`. \
            Opacity is a visual property only — the view stays in the accessibility tree, so \
            VoiceOver would announce "Pulse detected — you can let go & play" for the whole \
            measurement, including the many seconds before anything has been detected. The \
            two modifiers are a pair: whatever hides this cue from the eye must hide it from \
            the ear in the same commit.
            """)
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural, not a naming convention and not a line count — the two shapes that have
    /// already failed in this bundle. A count rots the moment a rationale block above the
    /// member grows; a `private var ` / `private func ` terminator is a guess about how the
    /// author of the NEXT declaration writes, and when it misses, the window runs on and the
    /// failure text accuses this member of a neighbour's line. `CoachingTextScalesTests`
    /// carries the same helper and the same reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. `statusBanner` holds no
    /// string literal spanning lines; if it grows one, this needs a real brace scanner.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from BioStripView — if the status line was \
                restructured this test should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` in BioStripView has no closing brace at its own indentation \
                — the file was reformatted or the member restructured, and reading on would \
                inspect the wrong lines. Rewrite this guard with the new shape rather than \
                letting it report on a window it cannot delimit
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments. Required here: the rationale block
    /// above `statusBanner` names the old `else if lockedCueVisible` shape in order to explain
    /// why it went, and a naive match would find the refuted spelling in the prose refuting it.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code. Same
    /// accepted limit as the sibling guards in this bundle.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent(Self.strip)
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
