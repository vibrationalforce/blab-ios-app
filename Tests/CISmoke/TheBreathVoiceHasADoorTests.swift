// TheBreathVoiceHasADoorTests.swift
// Echoel — #277. The guard over a voice that was BUILT, TESTED and TUNED and that no surface
// could switch on.
//
// ⚠️ THE LIMIT FIRST. Every claim here is a SOURCE-TEXT SCAN. `BreathVoiceRow` is a `private`
// `View` behind `#if canImport(SwiftUI)` that resolves two `@Environment` values, and
// `bioPanel` is a `private var` on a view this bundle cannot construct — nothing here renders,
// sounds, or arms anything. **That the toggle actually produces a held tone, and that the tone
// reads as musical rather than as a stuck note, are device trials and both are OPEN.**
//
// ⭐ WHAT WAS WRONG. `BioReactiveSynthVoice.arm()` had **zero production callers**.
// `isArmed` is `public private(set)` and is written only by `arm()`/`disarm()`, so it could
// never become `true`; `consumeBioEventsIfFresh` opens with `guard isArmed, …`, so every breath
// onset the bio graph produced was discarded. CLAUDE.md's own pipeline line calls this voice
// *"silent until user-armed"* — accurate, and nobody noticed that "user-armed" named an act the
// app had no control for. The producer half was never the gap: `BioEventGraph` emits
// `.breathInhaleOnset`/`.breathExhaleOnset`, `BioEventPublisher` publishes them, and
// `EngineBus.latestBioEvent` carries them. They arrived at a closed gate.
//
// ⭐ WHY THE COPY NAMES THE HELD TONE FIRST, and why claim 4 defends that ordering. The
// obvious label — "Breath plays the synth" — would be a LYING CONTROL on most takes. `arm()` is
// `isArmed = true; playNote()`: it sounds a held tone immediately, and only a
// `.breathExhaleOnset` closes it. Measured at #497: `PolarH10BioPublisher` and
// `FaceExpressionBioPublisher` write the literal `breathRate: 0` ALWAYS (neither derives
// respiration), and `CameraRPPGBioPublisher` withholds breath below its confidence floor. So on
// the shipped strap, and on the camera before it trusts itself, there are no onsets at all and
// the "breath" control is a permanent drone. Same class as #435's caption that promised
// silence, #480's hint that promised sliders, #491's box that promised a pulse. The shipped
// sentence describes the held tone (always true), then the breath gating (conditional), and it
// BRANCHES on `hasMeasuredBreath` so the conditional half is only claimed when it is real.
//
// ⚠️ HONEST GRADING (#433/#464), TRANSCRIBED against the parent tree rather than asserted (a
// Python rebuild of `SourceText.codeOnly` plus the brace matcher, run over `git show HEAD:` and
// the worktree, every needle driven separately). **Thirteen needles: six red, one red, six
// green — and the two reds are TWO findings, not seven.** Six of them (the struct scan and
// every needle inside claims 1 and 4) fail because `BreathVoiceRow` does not exist there, so
// their anchor is missing: that is ONE absence reported six times (#486), and counting it as
// six would be the flattering direction of the defect this file is named after. The seventh —
// the mount in claim 2 — is a genuine second finding in the #485 shape: `bioPanel` EXISTS on
// the parent, the block extracts non-empty, and it goes red on CONTENT. The remaining six are
// **green on both trees** — claims 5 and 6 are COUNTERWEIGHTS (#343), and they are the half
// that earns the file: a guard that only asserted the new row would stay green on a tree that
// kept the row and lost the way to silence it.
//
// ⚠️ `SourceText.codeOnly` is **PROPHYLACTIC here, and that is MEASURED rather than assumed**
// (#484/#485 each had to retract the stronger claim once, #486 twice). Raw versus stripped,
// **0 of 13 needle verdicts differ, on BOTH trees**: this slice's ⛔/⚠️ prose in
// `EchoelStudioView.swift` names `arm()` and `bioPanel` but writes neither `voice.arm()` nor
// `BreathVoiceRow()` nor `private struct BreathVoiceRow: View`, so no needle forms in prose. It
// stays because #453 made one definition for the whole blocking bundle — and it stops being
// prophylactic the moment someone writes a retraction here quoting a needle verbatim, which is
// exactly how #486 and #491 became load-bearing.

import Foundation
import XCTest

final class TheBreathVoiceHasADoorTests: XCTestCase {

    private let viewPath = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private let voicePath = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"

    // 1 — the whole point: `arm()` finally has a production caller, and the same control can
    // take it back. A one-way arm would be worse than no arm: the drone above has no other off.
    func testTheRowArmsAndDisarmsTheVoice() throws {
        let row = try block(startingAt: "private struct BreathVoiceRow: View {", in: viewPath)
        XCTAssertFalse(row.isEmpty, """
        anchor missing — `BreathVoiceRow` is not declared in \(viewPath). Every other claim in \
        this file reads that block, so a green here would mean nothing (#367)
        """)
        XCTAssertTrue(row.contains("voice.arm()"), """
        `BreathVoiceRow` no longer calls `arm()`. That call is the entire slice: without it \
        `BioReactiveSynthVoice.isArmed` has no writer that a user can reach, and every breath \
        onset the bio graph publishes is discarded at `guard isArmed`
        """)
        XCTAssertTrue(row.contains("voice.disarm()"), """
        `BreathVoiceRow` no longer calls `disarm()`. `arm()` sounds a HELD tone; this toggle is \
        its only off switch on the surface. Arming without disarming ships a drone with no door
        """)
    }

    // 2 — a row nobody mounts is the same defect with more steps. It belongs under the measured
    // half (`BioStripView`) and the practised half (`BreathCoachStrip`) — measure, practise, play.
    func testTheRowIsMountedInTheBioPanel() throws {
        let panel = try block(startingAt: "private var bioPanel: some View {", in: viewPath)
        XCTAssertFalse(panel.isEmpty, "anchor missing — `bioPanel` is not declared in \(viewPath)")
        XCTAssertTrue(panel.contains("BreathVoiceRow()"), """
        `BreathVoiceRow` is no longer mounted in `bioPanel`. The voice would be built, correct \
        and unreachable again — the state this slice exists to end
        """)
    }

    // 3 — the freeze law (10.76.41/50), in the form #486 had to correct. `bioPanel` has NO
    // `panel(...)` host at its top level; it is reached through `dropdownContent`, which is
    // evaluated in the ROOT body PERMANENTLY. So inlining this fragment puts its `usableBio()`
    // read directly on `EchoelStudioView.body` — the body hosting every `.menu` Picker of the
    // instrument. `AnyView(bioPanel)` is not a boundary. A separate `View` struct is.
    func testTheRowIsItsOwnViewStruct() throws {
        let src = try code(of: viewPath)
        XCTAssertTrue(src.contains("private struct BreathVoiceRow: View {"), """
        `BreathVoiceRow` is no longer a `View` struct. Folding it into `bioPanel` as a \
        `@ViewBuilder` fragment is the obvious later simplification and it is the 10.76.41/50 \
        freeze: the row reads `bus.usableBio()`, and inlined that read registers the ROOT body \
        as an observer of the bio snapshot
        """)
    }

    // 4 — the copy may not promise breath control it cannot deliver. Two publishers write
    // `breathRate: 0` unconditionally and the camera withholds it below its confidence floor
    // (#497), so on those takes there are no onsets and the tone simply holds. The obvious later
    // cleanup — "merge the two sentences into one" — re-creates the lying control.
    func testTheCopyBranchesOnWhetherBreathIsMeasured() throws {
        let row = try block(startingAt: "private struct BreathVoiceRow: View {", in: viewPath)
        XCTAssertFalse(row.isEmpty, "anchor missing — `BreathVoiceRow` is not declared")
        XCTAssertTrue(row.contains("hasMeasuredBreath"), """
        `BreathVoiceRow` no longer asks whether breath is measured. Its sentence then claims \
        "your inhale opens it, your exhale closes it" on a strap that never publishes \
        respiration — a control that describes a behaviour the take cannot produce
        """)
        XCTAssertTrue(row.contains("bus.usableBio()"), """
        the row no longer asks the per-source freshness question (#499/#507). Reading raw \
        `bus.latestBio` would keep claiming breath from a frozen frame long after the finger \
        left the lens — `latestBio` is never cleared
        """)
    }

    // 5 — COUNTERWEIGHT, green on both trees. This row is the first control in the app that can
    // hold a tone indefinitely, so `panicAllNotesOff`'s inclusion of `bioVoice` stops being
    // defensive tidiness and becomes the second way out of the drone. Removing it as "dead"
    // would be a reading of the tree as it was BEFORE this slice.
    func testThePanicFanOutStillReachesTheBioVoice() throws {
        let panic = try block(startingAt: "private func panicAllNotesOff() {", in: viewPath)
        XCTAssertFalse(panic.isEmpty, "anchor missing — `panicAllNotesOff` is not declared")
        XCTAssertTrue(panic.contains("bioVoice"), """
        `panicAllNotesOff` no longer fans out to `bioVoice`. Since #277 that entry is \
        load-bearing: the "Body voice" toggle can hold a tone with no natural end, and panic is \
        the escape that does not require finding the panel again
        """)
    }

    // 6 — COUNTERWEIGHT, green on both trees. Arming is a performance act, not a setting. A
    // persisted arm means the app sounds a held tone on the NEXT launch before the user has
    // touched anything — a worse first run than the silence #159 fixed.
    func testArmingIsNotPersisted() throws {
        let voice = try code(of: voicePath)
        XCTAssertFalse(voice.contains("UserDefaults"), """
        `BioReactiveSynthVoice` now touches `UserDefaults`. If that is `isArmed`, the app sounds \
        a held tone at launch before any input
        """)
        XCTAssertFalse(voice.contains("AppStorage"), "`BioReactiveSynthVoice` now uses @AppStorage")
        let row = try block(startingAt: "private struct BreathVoiceRow: View {", in: viewPath)
        XCTAssertFalse(row.isEmpty, "anchor missing — `BreathVoiceRow` is not declared")
        XCTAssertFalse(row.contains("AppStorage"), """
        `BreathVoiceRow` now persists its own arm state. Same outcome by a different route: a \
        tone at launch that the user did not ask for
        """)
    }

    // MARK: - helpers (the `TheBreathingPracticeIsInTheMainViewTests` shapes)

    /// ⚠️ The matcher counts braces inside string literals too. It is sound for these four
    /// anchors because their blocks are brace-balanced in prose as well; a future block holding
    /// an unbalanced `{` in a literal would need a real lexer, not a wider net.
    private func block(startingAt anchor: String, in path: String) throws -> String {
        let src = try code(of: path)
        guard let start = src.range(of: anchor) else { return "" }
        var depth = 0
        var index = src.index(before: start.upperBound)   // the anchor's own `{`
        while index < src.endIndex {
            let ch = src[index]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return String(src[start.lowerBound...index]) }
            }
            index = src.index(after: index)
        }
        return ""
    }

    private func code(of path: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(path)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

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
