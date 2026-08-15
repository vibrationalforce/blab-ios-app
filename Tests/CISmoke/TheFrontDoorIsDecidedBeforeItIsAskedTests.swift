// TheFrontDoorIsDecidedBeforeItIsAskedTests.swift
// Echoel — #580. A flag registered after the first view appears is a flag that is off.
//
// THE DEFECT, three weeks old and invisible on every build. `FeatureFlags.isOn` is plain
// `defaults.bool(forKey:)`, which returns **false** for a key that has not been registered
// yet. `register(defaults:)` writes a PROCESS-VOLATILE domain — never persisted, re-run every
// launch — and all three registrations lived in `EchoelmusicApp`'s startup `.task`, which runs
// after the first view appears. Exactly one flag has a reader that runs earlier, and it is a
// founder decision: `WorkspaceView`'s `.onAppear` seed is the ONLY reader of `instrumentHome`
// in `Sources/`. So the 2026-07-22 vision Step 1 — *"app open → it lives"* — was dead from the
// day it was written. Nothing ever set it false; it simply was not true YET when asked.
//
// ⭐ CONFIRMED ON THE FOUNDER'S OWN DEVICE, NOT ARGUED FROM SwiftUI ORDERING, and that
// distinction is why this slice went ahead instead of into a plan. Log 10.79.389/2506:
// seventeen minutes, clean launch, and **no `visual:` line at all**. Had the flag been true,
// the seed would have forced `floatingVisualVisible = true` + fullscreen — overriding any
// persisted "closed" — and `MetalBioView`'s draw loop prints that line every ~5 s. Zero lines
// means the branch was not taken, on a cold launch, with `didSeedInstrumentHome` fresh.
//
// ⭐ THE COST WAS NOT ONLY THE FRONT DOOR, and this is the half that answers a founder ask
// directly. `InstrumentHintOverlay` — whose own doc calls it "the FIRST thing a new user
// reads" — is gated on `windowSize.isFullscreen`, and this seed is what makes the window
// fullscreen at launch. The app's only first-run teaching text has therefore been unreachable
// unless a user found fullscreen by hand. *"Guide fehlt noch"* was measuring something real.
//
// ⚠️ WHAT ELSE THE MOVE CHANGES: NOTHING, measured rather than assumed — and this assertion
// set is what keeps that true. Every production reader of `multiRoll` (`EchoelmusicApp` rack
// attach + bio feed) and of `voiceKindRouting` (`LaneVoiceRack`, reachable only through that
// attach) already sat AFTER the old registration point in the same task. Registering earlier
// cannot change a read that does not exist earlier.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): claims 1–3 are SOURCE-TEXT SCANS with ORDERING — the
// registration must appear inside `init()` and before `var body: some Scene`. `EchoelmusicApp`
// is a `@main` `App` no bundle can instantiate, and `UserDefaults.register` is process-global
// state a parallel test bundle must not mutate. DEVICE PROBE, open and NOT covered: whether
// the app now actually opens into the fullscreen instrument, and whether the founder wants
// that as the front door. The `front door:` breadcrumb added by this slice is what makes the
// next pasted log answer it in one line; until then it is open.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`ecfebc1`) and this
// tree — no local toolchain (§0). **10 assertions** (three of them inside claim 1's loop, two
// inside claim 4's). The file names no symbol this commit creates, so it compiles against the
// parent and every assertion has a verdict there:
//   · **5 red on the parent, arising from TWO findings (#486)**, not five: the registration
//     block sat in the startup task (claim 1, three assertions — one misplacement, reported
//     once per flag), and the front door reported nothing (claim 2, two assertions — one
//     absence, reported once per branch).
//   · **5 COUNTERWEIGHTS**, green on both trees. They are the content (#343): the seed must
//     still be latched and still be the only reader, the rollback lever must stay documented
//     rather than called, and the hint overlay must still be gated on fullscreen — because if
//     THAT gate were simply removed, the teaching text would appear in a 180-pt card and every
//     positive assertion here would still pass while the front door stayed shut.
//   · STRIPPER: **TRAGEND (1 of 10 verdicts flips)** — claim 4, this repo's signature shape:
//     both files MENTION `FeatureFlags.set(.instrumentHome, false)` in prose because it is the
//     documented rollback lever, so the negative scan is false on raw text and true only
//     through `SourceText.codeOnly` (#364, "never ban a file from naming what it forbids").
//
// ⛔ MY PRE-MEASUREMENT GRADING SAID "7 assertions · 2 regressions · TRAGEND 2 of 7" AND ALL
// THREE NUMBERS WERE WRONG — the count because loop bodies were counted as one assertion each
// (the same slip as #579, so this is the second time; the rule is: count `XCTAssert` calls
// executed, not `func`s written), and the flip count because I predicted a flip in claim 1
// that the transcription refuted — the ⛔ block in `EchoelmusicApp` paraphrases the old call
// sites, it does not reproduce the exact needle. Recorded because a grading claim is a claim,
// and because guessing "TRAGEND" is not better than guessing "PROPHYLAKTISCH": both are
// guesses, and one of them merely happens to sound more careful.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFrontDoorIsDecidedBeforeItIsAskedTests: XCTestCase {

    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    // MARK: - claim 1 (REGRESSION) — registration happens in init(), before any view exists

    /// Ordering, not presence. Presence was always true and always useless: the whole defect
    /// is that the calls sat in the startup `.task`. The anchor is `var body: some Scene`,
    /// which is the exact boundary that matters — everything above it runs before SwiftUI can
    /// build, let alone appear, any view.
    func testTheThreeDefaultsAreRegisteredBeforeAnyViewCanRead() throws {
        let src = try source(Self.app)
        guard let bodyAt = src.range(of: "var body: some Scene")?.lowerBound else {
            XCTFail("`var body: some Scene` is gone — re-anchor this ordering scan (#454)")
            return
        }
        for flag in ["multiRoll", "voiceKindRouting", "instrumentHome"] {
            let needle = "UserDefaults.standard.register(defaults: [FeatureFlags.Key.\(flag).rawValue: true])"
            guard let at = src.range(of: needle)?.lowerBound else {
                XCTFail("""
                    `\(flag)`'s registration line is gone or reshaped. If it was reshaped, note \
                    that `EveryFlagSaysWhatItGatesTests` scans PER LINE and a multi-line \
                    dictionary literal reds it on a correct tree — see the note at both ends.
                    """)
                continue
            }
            XCTAssertTrue(at < bodyAt, """
                `\(flag)` is registered AFTER `var body: some Scene`, i.e. from somewhere the \
                scene can already have appeared. `FeatureFlags.isOn` is `defaults.bool(forKey:)`, \
                false for an unregistered key, so any view that reads this flag on appear gets \
                false — silently, on every launch, with nothing in the log to say so. That is \
                the three-week `instrumentHome` defect, re-committed.
                """)
        }
    }

    // MARK: - claim 2 (REGRESSION) — and the door that was decided says which way it went

    func testTheFrontDoorNamesItselfInTheLog() throws {
        let src = try source(Self.workspace)
        XCTAssertTrue(src.contains("front door: instrument"), """
            The instrument-home branch no longer reports itself. This branch decides which app \
            the user opens, and for three weeks a pasted device log could not tell which side \
            it took — the only evidence was the ABSENCE of `visual:` lines, which is the kind \
            of reasoning #445 forbids relying on.
            """)
        XCTAssertTrue(src.contains("front door: chrome first"), """
            The chrome-first branch is silent. Reporting only the new door is worse than \
            reporting neither: a log with no `front door:` line would then be ambiguous \
            between "took the old path" and "this build predates the line".
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the seed is still the only reader, and still a seed

    /// Green on both trees. The move is only safe BECAUSE `instrumentHome` has exactly one
    /// reader; a second reader somewhere earlier would make "registered in init()" necessary
    /// but no longer sufficient to reason about, and this assertion is what notices.
    func testTheSeedRunsOncePerLaunchAndIsTheOnlyReader() throws {
        let src = try source(Self.workspace)
        XCTAssertTrue(src.contains("guard !didSeedInstrumentHome else { return }"), """
            The once-per-launch latch is gone. Without it the seed re-forces fullscreen on \
            every appear, so contracting to the chrome mid-session would silently bounce back \
            — a control that undoes the user, which is worse than a door that never opens.
            """)
        let readers = try ["Sources/Echoelmusic/EchoelmusicApp.swift",
                           "Sources/Echoelmusic/Studio/EchoelStudioView.swift",
                           "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"]
            .filter { try source($0).contains("FeatureFlags.instrumentHome") }
        XCTAssertTrue(readers.isEmpty, """
            `FeatureFlags.instrumentHome` is now read in \(readers.joined(separator: ", ")) as \
            well as the seed. A second reader is not forbidden — but it must be checked against \
            the registration point by hand, because "registered in init()" only guarantees \
            correctness for readers that run after init(), and an `App` initialiser is not the \
            earliest thing in the process.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the rollback lever is still a lever, not a caller

    func testNothingInProductionFlipsTheFlag() throws {
        for path in [Self.app, Self.workspace] {
            let src = try source(path)
            XCTAssertFalse(src.contains("FeatureFlags.set(.instrumentHome"), """
                \(path) now CALLS the rollback lever instead of documenting it. Both files \
                mention `FeatureFlags.set(.instrumentHome, false)` in prose on purpose — that \
                is the documented one-line rollback — and this assertion is the difference \
                between naming it and pulling it. (It passes only through the shared comment \
                stripper; a raw scan finds the prose, which is exactly the "never ban a file \
                from naming what it forbids" case, #364.)
                """)
        }
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the teaching text still depends on the door

    /// The premise that makes the "Guide fehlt noch" half of this slice true. If someone
    /// "fixed" the unreachable hint by deleting its fullscreen gate, the overlay would appear
    /// in a 180-pt floating card — unreadable, and every other assertion here still green.
    func testTheFirstRunHintStillDependsOnFullscreen() throws {
        let src = try source(Self.window)
        // ⛔ #604b re-anchored this needle, and the OLD one was latently two-site (#408):
        // `if windowSize.isFullscreen {` also matched the layout helper's
        // `if windowSize.isFullscreen { return bounds }` — so when #604b widened the
        // overlay's gate, the old needle would have stayed green by matching a line that
        // has nothing to do with the hint. The `isPresented &&` half is load-bearing:
        // the window is hidden by `.opacity(0)`, never unmounted, so without it a hidden
        // fullscreen window banks invisible showings toward the cap (and a monitor
        // re-show is an opacity flip that never re-runs the `.task`).
        XCTAssertTrue(src.contains("if isPresented && windowSize.isFullscreen {"), """
            `InstrumentHintOverlay`'s visible-fullscreen gate is gone. The fullscreen half \
            is why the front-door fix also delivers the first-run teaching text (written \
            for the immersive surface, unreadable in a 180-pt floating card); the \
            `isPresented` half is why a HIDDEN window can neither show the hint nor COUNT \
            a showing toward the retire cap (#604b — the window is opacity-hidden, never \
            unmounted).
            """)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DoorAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DoorAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
