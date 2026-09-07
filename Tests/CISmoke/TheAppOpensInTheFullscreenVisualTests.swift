import XCTest
@testable import Echoelmusic

/// #1070 — THE APP OPENS IN THE FULLSCREEN VISUAL, AND TWO SEPARATE ARGUMENTS REST ON IT.
///
/// This guard exists because the premise was RETRACTED IN ERROR one commit earlier. #1069 read
/// the `@AppStorage` DEFAULT for `visual.floating.size` (`WindowSize.small`), concluded that a
/// fresh install opens a small card, and marked two long-standing source comments as wrong. The
/// default is real and irrelevant: `WorkspaceView`'s instrument-home seed writes
/// `floatingVisualVisible = true` and `floatingSizeRaw = .fullscreen` in `.onAppear`, once per
/// launch, behind `FeatureFlags.instrumentHome` — which `EchoelmusicApp.init()` REGISTERS as
/// `true`. The comments were right.
///
/// ⚠️ THE LESSON IS NOT "MEASURE MORE". A DEFAULT IS NOT A STATE. The cheap check that settles it
/// is a grep for WRITERS of the key, never a read of its declaration — a declaration cannot know
/// about a seed one file away. Nothing in the bundle held this, so a plausible-looking
/// measurement was enough to overturn two correct comments; that is what this file fixes.
///
/// WHAT DEPENDS ON IT, and why a wrong answer is expensive in both directions:
///   · `updateKeepAwake()` — the fullscreen keep-awake term must be CONJUNCTIVE. If fullscreen is
///     the launch state, a standalone term means "awake from the first frame, for everyone".
///   · `FloatingVisualLayout.chromeFit` — the Studio chip sheds LAST because it is the only
///     labelled way out of a surface the app opens into. Take the premise away and that ranking
///     loses its stated reason.
///
/// ⚠️ SOURCE-TEXT SCAN (§1). It proves the seed is written and reachable, never that a device
/// renders it — that stays the founder's look.
final class TheAppOpensInTheFullscreenVisualTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(path) could not be read — a missing anchor is a finding.")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    // 1 — the seed exists and writes BOTH keys. One without the other is not a launch state:
    // a fullscreen size on a hidden window shows nothing.
    func testTheSeedOpensTheVisualFullscreenAtLaunch() throws {
        let workspace = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(
            workspace.contains("floatingSizeRaw = FloatingVisualWindow.WindowSize.fullscreen.rawValue"),
            """
            `WorkspaceView` no longer seeds the fullscreen visual at launch. Two arguments rest on \
            it and BOTH become wrong silently: `updateKeepAwake()`'s conjunctive fullscreen term \
            (which exists because fullscreen is the launch state), and `chromeFit`'s "the Studio \
            chip sheds last, it is the only labelled way out of a surface the app opens into".

            If the front door genuinely changed, that is a founder decision — say so, and sweep \
            both of those comments in the same commit (#456).
            """)
        XCTAssertTrue(workspace.contains("floatingVisualVisible = true"), """
            The seed sets a fullscreen SIZE without making the window VISIBLE. Then the app opens \
            into nothing while the stored size claims otherwise — and `floatingVisualIsFullscreen` \
            in `EchoelStudioView` reads both keys precisely so that state cannot hold the screen \
            awake for a picture nobody is looking at.
            """)
    }

    // 2 — the seed is REACHABLE. A seed behind a flag that reads false is a seed that never runs,
    // and this exact thing already happened here: the flag read false for three weeks because it
    // was registered after the first view appeared (#580).
    func testTheSeedsFlagIsRegisteredTrueBeforeAnyViewReadsIt() throws {
        let app = try source("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertTrue(
            app.contains("register(defaults: [FeatureFlags.Key.instrumentHome.rawValue: true])"),
            """
            `instrumentHome` is no longer registered as `true`. `FeatureFlags.isOn` is a plain \
            `defaults.bool(forKey:)`, which answers false for an unregistered key — so the seed \
            in `WorkspaceView.onAppear` would silently never run and the app would open on the \
            chrome instead of the instrument. That is not a hypothetical: it is #580, where the \
            registration sat AFTER the first view appeared and the one flag that is read first \
            read false for three weeks with nothing saying so.
            """)
        let workspace = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(workspace.contains("if FeatureFlags.instrumentHome {"), """
            The seed no longer consults `instrumentHome`. The flag is the documented one-line \
            rollback lever for the front door (`FeatureFlags.set(.instrumentHome, false)`); a \
            seed that ignores it cannot be rolled back without a build.
            """)
    }

    // 3 — COUNTERWEIGHT (#343/#367): the two arguments that rest on the premise are still written
    // down. Without this, the file would stay green on a tree that kept the SEED and lost the
    // reasoning it justifies — which is how the retraction happened in the first place.
    func testBothDependentArgumentsStillNameTheLaunchState() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("(floatingVisualIsFullscreen && cameraRPPG.isRunning)"), """
            The fullscreen keep-awake term is not conjunctive any more. Standing alone it holds \
            the screen awake from the first frame of every launch, because the app OPENS in the \
            fullscreen visual (claim 1 pins that seed).
            """)
        let layout = try source("Sources/Echoelmusic/Studio/FloatingVisualLayout.swift")
        XCTAssertTrue(layout.contains("$0.studioChip = false"), """
            The Studio chip is no longer the last non-recorder item in the shed order. It sheds \
            last because it is the only LABELLED way out of a surface the app opens into — the \
            same premise claim 1 pins. If the ranking changed, the reason has to change with it.
            """)
    }
}
