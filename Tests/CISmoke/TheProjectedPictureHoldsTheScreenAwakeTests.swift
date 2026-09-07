import XCTest

/// SOURCE-TEXT SCAN (§1). `updateKeepAwake()` is `private` on a `View` no test bundle can
/// instantiate, and `UIApplication.shared.isIdleTimerDisabled` is a device fact besides. What
/// this file proves is that the TERM is in the expression and that the value it reads can
/// still change the view — never that a phone stayed lit. That half is a DEVICE PROBE and is
/// registered as open, not implied.
///
/// ⭐ #1044 — THE "PROJECTING" HALF OF A PROMISE THAT WAS ONLY EVER HALF KEPT.
/// `updateKeepAwake()`'s own doc comment says *"Hold the screen on while the instrument is
/// performing or projecting"*, and `EchoelStudioView.swift:5` says it again beside the UIKit
/// import — *"keep screen awake while projecting"*. Measured before the slice, the condition
/// was `running || showVisual || showMeditation || breathPacer.isRunning`: four terms, all of
/// them about the PHONE being looked at. The one route where the phone is NOT being looked at
/// — the picture on a beamer or a TV, `ExternalStageBridge.isConnected` — appeared in none of
/// them, and `git grep ExternalStageBridge Sources/` returned nine sites, not one of them in
/// this method.
///
/// WHY IT MATTERS MORE THAN A DIM SCREEN: iOS locking the phone tears down the foreground
/// scene, and the single `MetalBioView` that feeds the external display lives there
/// (`ExternalStageBridge`'s own header: "GPU rule = ONE MetalBioView app-wide"). So the
/// projection stops, in the middle of the performance the founder asked this route for.
///
/// ⛔ THIS FORBIDS NOTHING (#364). A different way to hold the session up — a background
/// mode, a `UIApplication` assertion of another kind — makes these needles red on purpose;
/// the messages name what moves with them (#456).
///
/// GRADING against the parent (transcribed in Python, no local toolchain — §0):
///   claim 1  REGRESSION — the term is absent there.
///   claim 2  REGRESSION — the helper does not exist there.
///   claim 3  COUNTERWEIGHT — green on both trees (the four older terms survive).
///   claim 4  COUNTERWEIGHT — green on both trees (`disableKeepAwake` still exists).
final class TheProjectedPictureHoldsTheScreenAwakeTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The term itself.
    func testKeepAwakeCountsAnExternalScreen() throws {
        let studio = try code(of: Self.studio)
        XCTAssertTrue(studio.contains("|| isProjectingExternally"), """
        `updateKeepAwake()` no longer counts a picture on an external screen. Every other \
        term in that OR describes the PHONE being looked at, and while projecting the phone \
        is face-down: iOS locks it, the foreground scene goes away, and the one MetalBioView \
        that feeds the beamer goes with it. The projection dies mid-performance.

        If keep-awake moved to another mechanism, delete this claim and correct the two \
        prose homes that promise it (#456): `updateKeepAwake()`'s doc comment and the \
        `import UIKit` comment at the top of the same file, both of which say "projecting".
        """)
    }

    /// The read has to be able to WAKE the view, or the term above is correct and never
    /// re-evaluated. This is the half a term-only scan would miss.
    func testTheProjectionFlagIsReadableFromTheBody() throws {
        let studio = try code(of: Self.studio)
        XCTAssertTrue(studio.contains("private var isProjectingExternally: Bool"), """
        the `isProjectingExternally` helper is gone. It is not decoration: this file compiles \
        wherever SwiftUI does, `ExternalStageBridge` exists only under UIKit, and the trigger \
        expression in `body` must be able to name the value on every platform.
        """)
        XCTAssertTrue(studio.contains("ExternalStageBridge.shared.isConnected"), """
        the helper no longer reads the bridge, so nothing observes the connect. \
        `ExternalDisplayScene` calls `setConnected(true)` from UIKit, nowhere near a SwiftUI \
        update — the `@Observable` read in `body` is the entire mechanism by which the phone \
        learns a screen was plugged in.
        """)
    }

    /// COUNTERWEIGHT (#343): the new term must be an ADDITION. A slice that swapped it in for
    /// one of the four would leave this file green while taking a capability away.
    func testTheFourOlderKeepAwakeTermsSurvive() throws {
        let studio = try code(of: Self.studio)
        for term in ["running || showVisual", "|| showMeditation", "|| breathPacer.isRunning"] {
            XCTAssertTrue(studio.contains(term), """
            `updateKeepAwake()` lost the term `\(term)`. #1044 ADDED the projecting case; it \
            did not replace anything. `showMeditation` in particular is deliberately kept \
            while its surface is doorless, so the decision is ready for a re-door.
            """)
        }
    }

    /// COUNTERWEIGHT: holding the screen awake is only safe while something still releases it.
    func testSomethingStillLetsTheScreenSleep() throws {
        let studio = try code(of: Self.studio)
        XCTAssertTrue(studio.contains("private func disableKeepAwake()"), """
        nothing releases the idle timer any more. Every term added to `updateKeepAwake()` \
        raises the cost of a missing release — a phone that never sleeps is a battery bug \
        the user cannot see and cannot fix from inside the app.
        """)
        XCTAssertTrue(studio.contains(".onDisappear { stopEverything(reason: \"unmount\"); disableKeepAwake() }"), """
        the release is no longer wired to unmount. iOS resets `isIdleTimerDisabled` on \
        background, so this is not the only safety net — but it is the one that covers the \
        app staying foreground with the instrument gone.
        """)
    }

    // MARK: - Source helper

    private func code(of path: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(path)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Repo root from this file's compile-time path. Gates on the DIRECTORY, not on each
    /// file, so a missing source tree SKIPS instead of turning the catastrophe green (#472).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
