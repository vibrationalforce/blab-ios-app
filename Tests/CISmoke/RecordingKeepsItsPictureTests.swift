// RecordingKeepsItsPictureTests.swift
// Echoel — a running video take may not lose its only frame source. BLOCKING bundle. #319.
//
// THE DEFECT. `VisualRecorder` has exactly ONE frame source: `MetalBioView`'s draw loop calling
// `capture(from:in:device:)`. `FloatingVisualWindow.visualLayer` decides whether that renderer is
// mounted at all, and its `!isPresented` branch renders `Color.clear` — no renderer — because a
// hidden window rendering at 60 fps for a picture nobody can see is exactly the cost #311's
// always-mounted window was supposed to avoid.
//
// So: start a video take, tap the header's monitor button, and the take silently became nothing.
// `recorder.isRecording` stayed true. The REC badge kept counting — it counts wall-clock seconds
// from a `Date`, not seconds written — and was invisible anyway at `opacity(0)`. `stop()` returned
// `nil` because `AVAssetWriter` is built lazily from the FIRST ingested frame and none ever came.
// A recording that recorded nothing, reported by no control anywhere: the lying-control class
// (#164), on the one surface where the loss is unrecoverable.
//
// ⚠️ WHY NOT "STOP THE TAKE WHEN THE PICTURE HIDES". The window's own note had filed this as
// needing "a stop-or-pause decision". Neither: hiding a window is far too casual a gesture to end
// a performance capture, and pausing would need a writer-level concept that does not exist. The
// user asked to record the picture, so the picture keeps rendering — the GPU cost is the cost
// they asked for, and it is bounded by a state they entered deliberately.
//
// ⛔ THE HALF THIS DOES NOT FIX, and the reason the condition below has two terms instead of one:
// when an external stage is connected the phone yields its renderer BECAUSE the external screen
// has one ("ONE `MetalBioView` app-wide"). Forcing the local renderer back on top of that would
// run two — a worse defect than the one being fixed. So recording while a beamer holds the
// picture is still empty, and closing it means deciding WHICH renderer feeds the writer, plus
// what happens when a portrait phone take meets landscape beamer frames inside one file
// (`AVAssetWriter` is configured from the first frame's size). Its own slice, named here so a
// green on this file is not read as "#319 is closed".
//
// ⚠️ WHY A SOURCE SCAN. `visualLayer` is a `private` member of a SwiftUI `View`, the recorder is
// injected through `@Environment`, and there is no local toolchain to build a UI-test host with.
// House pattern — same as `DelayReachesEveryChainTests`, `SoundPanelReflowsTests`,
// `FXPanelReachesEveryChainTests`. It proves the branch is WRITTEN to keep the renderer; it
// cannot prove that an `opacity(0)` MTKView actually keeps drawing on a device.
//
// NEEDS-FOUNDER-VERIFY: start a video recording in the floating visual, tap the header monitor
// button to hide the picture, wait ~10 s, show it again, stop. Is the clip ~10 s longer than the
// visible-only part — i.e. did the hidden stretch record?

import Foundation
import XCTest

final class RecordingKeepsItsPictureTests: XCTestCase {

    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    /// ⭐ THE GUARD. The hidden branch must carry the recording exception. Without it the branch
    /// reads `if !isPresented` and every running take dies the moment the picture is hidden.
    func testTheHiddenBranchYieldsToARunningRecording() throws {
        let lines = try codeLines(Self.window)
        let hits = lines.filter { $0.contains("if !isPresented") }
        XCTAssertEqual(hits.count, 1, """
            expected exactly one `if !isPresented` branch in \(Self.window), found \(hits.count): \
            \(hits.map { $0.trimmingCharacters(in: .whitespaces) })

            That branch is the one that decides whether `MetalBioView` is mounted. If the file \
            grew a second one, this guard no longer knows which it is checking — point it at the \
            right one in the same commit rather than loosening the count.
            """)
        let branch = hits[0]
        // ⛔ THE NEEDLE CARRIES ITS `&&` AND ITS `!`, and that is not pedantry. A reviewer
        // found that asserting the bare NAME passes over `if !isPresented &&
        // mustKeepRenderingForRecording {` — one deleted character, which reintroduces BOTH
        // bugs at once: hidden+recording falls to `Color.clear` (this defect returns) and
        // hidden+idle mounts the renderer (#311's battery bug returns), with the whole
        // blocking bundle green. A guard that cannot tell a condition from its negation is
        // not guarding the condition.
        XCTAssertTrue(branch.contains("&& !mustKeepRenderingForRecording"), """
            the hidden branch is back to a bare `\(branch.trimmingCharacters(in: .whitespaces))`.

            A running video take has no other frame source (#319): hiding the picture drops the \
            renderer, no frame ever reaches `VideoRecorder.ingest`, the writer is never built, \
            and `stop()` returns nil — while the REC badge counts wall-clock seconds it never \
            wrote.
            """)
    }

    /// ⛔ THE SECOND TERM, which is not decoration. `recorderIsRecording` ALONE would force the
    /// local renderer back while an external stage already has one — two `MetalBioView`s, the
    /// law this window's own docs spend paragraphs on. This is the assertion that stops a future
    /// "simplification" of the condition.
    func testTheExceptionStillYieldsToAnExternalScreen() throws {
        let body = try memberBody(startingWith: "private var mustKeepRenderingForRecording: Bool",
                                  in: Self.window)
        let code = body.joined(separator: "\n")
        // Both needles pin the SENSE, not just the token — `!recorderIsRecording && …` and
        // `recorderIsRecording && ExternalStageBridge…` are each a one-character inversion
        // that a name-only assertion waves through. Same reviewer finding as above.
        // ⛔ AND THE FIRST NEEDLE FOR THE FIRST TERM WAS ITSELF INVERTIBLE. It read
        // `code.contains("recorderIsRecording && !ExternalStageBridge")` — which is a
        // SUBSTRING of `!recorderIsRecording && !ExternalStageBridge…`, so the exact
        // inversion it was written to catch walked straight through it. A `contains` needle
        // can never pin a LEADING `!`; only an anchor can. Hence `hasPrefix` on the trimmed
        // line. Caught by running the inversion through the check before committing, which
        // is the only reason this file is not a third guard that guards nothing.
        let terms = body.map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(terms.contains(where: { $0.hasPrefix("recorderIsRecording &&") }), """
            `mustKeepRenderingForRecording` no longer asks whether a take is running, so it \
            either never fires or fires always:
            \(code)
            """)
        XCTAssertTrue(code.contains("&& !ExternalStageBridge.shared.isConnected"), """
            `mustKeepRenderingForRecording` no longer excludes the external-stage case:
            \(code)

            With an external screen connected, the phone yields its renderer BECAUSE the beamer \
            has one. Keeping the local one alive as well runs two `MetalBioView`s — a worse \
            defect than the empty recording this property exists to prevent. Recording through \
            an external stage is a separate decision (which renderer feeds the writer), not a \
            term to delete here.
            """)
    }

    /// Anti-vacuity for both assertions above: the branch they guard must still be the one that
    /// drops the renderer, and the live renderer must still be the `else`. If `visualLayer` is
    /// ever restructured so the hidden state renders something, the guard above would keep
    /// passing over a condition that no longer decides anything.
    func testTheHiddenBranchStillDropsTheRendererAndTheElseStillMountsIt() throws {
        let body = try memberBody(startingWith: "private func visualLayer(", in: Self.window)
        let code = body.joined(separator: "\n")
        XCTAssertTrue(code.contains("Color.clear"), """
            the hidden branch of `visualLayer` no longer renders `Color.clear`. It is what makes \
            hidden cost zero renderers — and therefore what makes the recording exception \
            necessary. If the hidden state now renders something else, re-read #319 before \
            trusting the guards above:
            \(code)
            """)
        XCTAssertTrue(code.contains("liveVisual(wv)"), """
            `visualLayer` no longer falls through to `liveVisual(wv)`, which is the only place \
            `MetalBioView(capturesVideo: true)` is built and therefore the only frame source the \
            video recorder has:
            \(code)
            """)
    }

    /// ⭐ #1043 (visual epic S4a) — A SECOND WAY TO STARVE THE WRITER, ported in with the
    /// donut look. The spectrum rings are a SwiftUI `Canvas`, not Metal, so while they are on
    /// screen there is no `MetalBioView` and therefore no frame source at all — the exact shape
    /// of the #319 defect this file was written for, arriving through a different door.
    ///
    /// The fullscreen COVER never had to decide this: it hid its record button under donuts and
    /// stopped there, which prevents STARTING a take but not switching looks during one. The
    /// window's branch therefore yields — `spectralDonuts, !mustKeepRenderingForRecording` —
    /// so a running take keeps the field until it ends.
    ///
    /// ⛔ THIS FORBIDS NOTHING (#364). Teaching `VisualRecorder` to capture a `Canvas`, or
    /// handing the writer a different source, makes the yield unnecessary and this claim red on
    /// purpose; its message says which prose moves with it. What it will not allow is the branch
    /// silently dropping the term while the writer still has one source.
    func testTheDonutBranchYieldsToARunningRecording() throws {
        let body = try memberBody(startingWith: "private func visualLayer(", in: Self.window)
        let code = body.joined(separator: "\n")

        guard code.contains("spectralDonuts") else {
            // The look is not mounted here (S4a reverted, or the window lost it again). Say so
            // out loud: a silent skip is how a lifted premise becomes an unnoticed hole (#454).
            print("#1043: `visualLayer` has no donut branch — claim not applicable.")
            return
        }
        XCTAssertTrue(code.contains("!mustKeepRenderingForRecording"), """
            `visualLayer` mounts the donut look WITHOUT yielding to a running take. The rings
            are a `Canvas`; while they are up there is no `MetalBioView`, so an `AVAssetWriter`
            already open receives no further frames and the REC pill counts wall-clock seconds
            over a file that stopped growing — #164's lying control, reached through a look
            change instead of the hide button this file's claim 1 guards.

            Either restore `spectralDonuts, !mustKeepRenderingForRecording`, or, if the recorder
            can now capture this look, delete this claim and correct the two comments that say
            it cannot: the donut branch's own block and `videoCaptureYielded`'s doc (#456).

            \(code)
            """)

        // COUNTERWEIGHT (#367): the yield is only half the rule. Starting a take under donuts
        // must be impossible, or the branch above is reached from a state it cannot repair.
        let yielded = try memberBody(startingWith: "private var videoCaptureYielded:",
                                     in: Self.window).joined(separator: "\n")
        XCTAssertTrue(yielded.contains("spectralDonuts"), """
            `videoCaptureYielded` no longer counts the donut look, so the record button is
            offered while there is nothing for the writer to read. That is the START half of
            the same defect; the yield in `visualLayer` only covers a take already running.

            Keep both reasons in this ONE property (#416) rather than hiding the button, which
            is how the cover expressed it — a control that vanishes says nothing to a screen
            reader, while a disabled one with a sentence says why.

            \(yielded)
            """)
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count: this file is edited often and a
    /// count-based window would silently start reporting on a neighbour.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here: the ⛔ blocks in this
    /// window quote `if !isPresented` and the old wording of the defect verbatim while
    /// explaining it, and a scan that read them would count the explanation as a branch.
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
