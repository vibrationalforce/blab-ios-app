// TheTempoBoxShowsTheClockTests.swift
// Echoel — two boxes side by side may not render the same number under two names.
//
// WHAT THIS GUARDS (#491, founder 2026-08-07, screenshot of v10.79.374 (2491) with the
// transport row circled: *"Transport, bpm , Schloss und Biofeedback bar zu einer schöneren
// Ebene ohne doppelt bpm zusammen fassen."*).
//
// ⭐ THE DUPLICATION WAS REAL AND MEASURABLE, not a matter of arrangement. `BodyTempoField`
// unlocked rendered `cameraRPPG.displayBPM`, and `PulseMonitorMiniLive` — the pill sitting
// in the SAME row — renders `cameraRPPG.displayBPM`. Same property, same instant, two boxes:
// whenever the camera was live the founder saw one number twice, one of them in a box
// labelled "Tempo".
//
// ⭐ AND IT WAS A LYING CONTROL ON TOP OF THAT, which is the half that decided the fix. The
// clock does NOT run at the pulse. `EchoelStudioView` drives it through the generative
// mapping (`StudioCalculator.tilted(genreTempo(...))`), so a 144 bpm pulse can sit above a
// 72 bpm clock — and `toggleLock` adopted the SHOWN value, i.e. locking moved the music by
// an octave of tempo in one tap while presenting itself as "freeze what you have".
//
// ⛔ THE OBVIOUS FIX IS THE FORBIDDEN ONE. Deleting either readout would remove the
// duplication in one line, and the founder's own 2026-07-04 ask — quoted at the top of
// `BodyTempoField.swift` — ends in *"beide behalten"*: keep BOTH controls. So the fix is not
// to remove a box, it is to make each box show the fact it is NAMED for. The pill is the
// heart rate. The tempo field is the clock. Four of the six assertions below exist to keep a
// later "simplification" from taking the cheap route.
//
// ⚠️ HONEST GRADING, measured against `HEAD` before this commit rather than asserted.
// TWO assertions are regressions:
//   · `testTheUnlockedReadoutIsTheClock` — the parent declares
//     `followingValue { liveBodyBPM > 0 ? liveBodyBPM : transport.tempo }`, so the
//     no-`liveBodyBPM` half is FALSE there and TRUE here.
//   · `testNoLabelClaimsTheBoxFollowsYourPulse` — the parent carries three such labels in
//     CODE, this tree carries none.
// The other FOUR are green on both sides. They are counterweights, and saying so is the
// #433 rule: mis-grading your own guards in the flattering direction is the same defect as
// in the harsh one.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, and that is MEASURED, not assumed (#484
// had to retract exactly this claim). The retraction comments this slice writes quote the
// removed strings verbatim: `"your pulse"` appears **3×** in the raw text of
// `BodyTempoField.swift` on BOTH trees, and **3× in code on the parent / 0× in code here**.
// A raw-text scan would therefore be RED on correct code. Same collision as #486: this repo
// writes down what it removed, so a negative scan always meets its own obituary.
//
// ⚠️ Source-text scan, no simulator; `Tests/CISmoke` is the blocking bundle. Nothing here
// proves the row RENDERS, that the two numbers now look different on a device, or that the
// arrangement is "schöner" — those are device checks and they are open. SKIPS rather than
// passing if the tree is not at this file's compile-time path.

import Foundation
import XCTest

final class TheTempoBoxShowsTheClockTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/BodyTempoField.swift"
    private static let monitors = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"

    private func codeLines(_ rel: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(rel) not present under \(root.path) — this test inspects source text, so it \
                SKIPS rather than reporting a green it did not earn
                """)
        }
        let raw = try String(contentsOf: path, encoding: .utf8)
        return SourceText.codeOnly(raw)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: - Regressions

    /// REGRESSION. The unlocked number is the clock, and nothing else.
    func testTheUnlockedReadoutIsTheClock() throws {
        let code = try codeLines(Self.field)
        let decl = code.filter { $0.contains("private var followingValue") }
        XCTAssertEqual(decl.count, 1, """
            Expected exactly one declaration of `followingValue` in \(Self.field), found \
            \(decl.count). This is the single answer to "what does the tempo box show while \
            the body is driving it"; two answers is the #416 shape that produced the defect \
            in the first place.
            """)
        guard let line = decl.first else { return }
        XCTAssertTrue(line.contains("transport.tempo"), """
            `followingValue` no longer reads `transport.tempo`. The unlocked tempo box must \
            show THE CLOCK — the thing the music actually runs at — because that is what \
            makes the lock ("freeze where you are") continuous and what stops this box \
            duplicating the pulse pill beside it. Found: \(line.trimmingCharacters(in: .whitespaces))
            """)
        XCTAssertFalse(line.contains("liveBodyBPM"), """
            `followingValue` reads `liveBodyBPM` again, i.e. the raw pulse: \
            \(line.trimmingCharacters(in: .whitespaces)). That is the #491 defect verbatim — \
            the box then renders `cameraRPPG.displayBPM`, which `PulseMonitorMiniLive` \
            already renders in the same row ("doppelt bpm"), inside a box labelled "Tempo" \
            that the clock does not run at. `liveBodyBPM` is a FLAG in this file (the accent \
            tint), not a value; it must not become a displayed number again.
            """)
    }

    /// REGRESSION. No accessibility label may promise that unlocking returns the box to the
    /// player's pulse — it returns it to the clock. An accessibility string is the one layer
    /// no screenshot can show (#480), which is how the wrong word survived here.
    func testNoLabelClaimsTheBoxFollowsYourPulse() throws {
        let code = try codeLines(Self.field)
        let offenders = code.filter {
            $0.contains(".accessibilityLabel(") && $0.contains("your pulse")
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) accessibility label(s) in \(Self.field) still say the tempo \
            box follows "your pulse": \
            \(offenders.map { $0.trimmingCharacters(in: .whitespaces) }). It follows the \
            CLOCK, which your body drives through the generative mapping. Naming the pulse \
            names the pill's number — the exact duplication #491 removed — and says it in \
            the layer only VoiceOver users hear.
            """)
    }

    // MARK: - Counterweights (green on both sides of #491, by design)

    /// The lock still captures the number on screen. This assertion did not move and must
    /// not: the invariant "lock captures what you see" was never broken by #491 — the NUMBER
    /// was wrong. Re-pointing the lock at anything else re-opens the jump.
    func testTheLockAdoptsTheShownNumber() throws {
        let code = try codeLines(Self.field)
        XCTAssertTrue(code.contains {
            $0.contains("followingValue.clamped(to: Transport.minTempo...Transport.maxTempo)")
        }, """
            `toggleLock` no longer adopts `followingValue`. Whatever it adopts instead is by \
            definition NOT the number the player was looking at when they tapped, which is \
            what a lock means. Before #491 this same line adopted the raw pulse and could \
            move the clock by an octave of tempo in one tap — the line did not change, the \
            value behind it did.
            """)
    }

    /// The accent tint must keep reading the live pulse. A cleanup that deletes the camera
    /// read entirely would pass the two regressions above while removing the only signal
    /// that the body is driving the clock at all.
    func testTheTintStillKnowsWhetherTheBodyIsDriving() throws {
        let code = try codeLines(Self.field)
        let tints = code.filter { $0.contains("liveBodyBPM > 0 ? EchoelTheme.accent") }
        XCTAssertEqual(tints.count, 2, """
            Expected 2 accent-tint reads of `liveBodyBPM` (compact + wide branch), found \
            \(tints.count). This is what tells the player the clock is being driven rather \
            than idling, and it is the ONLY remaining consumer of the camera rate in this \
            file. Losing it makes the unlocked box indistinguishable from a frozen one.
            """)
        let camera = code.filter { $0.contains("cameraRPPG.displayBPM") }
        XCTAssertEqual(camera.count, 1, """
            \(Self.field) reads `cameraRPPG.displayBPM` on \(camera.count) line(s); exactly \
            one is correct — the trust gate inside `liveBodyBPM`. More than one means the \
            pulse has found a second way into this control; zero means the tint above cannot \
            be true.
            """)
    }

    /// The pulse number keeps its own home. Removing the duplication by deleting the PILL
    /// would satisfy "ohne doppelt bpm" and violate the founder's older, still-standing
    /// *"beide behalten"* — and it would take the heart rate off the screen entirely.
    func testThePulsePillStillShowsThePulse() throws {
        let code = try codeLines(Self.monitors)
        XCTAssertTrue(code.contains { $0.contains("cameraRPPG.displayBPM") }, """
            `PulseMonitorMiniLive` no longer renders `cameraRPPG.displayBPM`. #491 removed a \
            DUPLICATE, not a capability: the heart rate belongs in the pulse pill, the clock \
            belongs in the tempo field, and deleting the pill's number would leave the app \
            with no live heart rate on the main surface at all.
            """)
    }

    /// The freeze law, pinned where a later reader will look for it. This view observes THREE
    /// sources (`transport.tempo` ~8 Hz at 120 BPM and up to ~20 Hz in a glide since #491, the
    /// ~10 Hz camera flag, and since #647 `bus.usableBio()` at ~1 Hz), so it may only ever be a
    /// leaf `View` struct — folding it inline into `startControlRow` is the 10.76.41/50 freeze
    /// with all of that churn.
    ///
    /// ⛔ THIS SAID "TWO" AND THE ASSERTION STAYED GREEN, which is why it needed pulling in the
    /// same commit rather than whenever somebody noticed (#456). The needle is
    /// `struct BodyTempoField: View`, untouched by #647 — so nothing here would EVER go red over
    /// a stale source count. A message that under-names the churn is only read on the day the
    /// guard fails, and that is exactly the day it must be right.
    func testTheControlIsStillItsOwnView() throws {
        let code = try codeLines(Self.field)
        XCTAssertTrue(code.contains { $0.contains("struct BodyTempoField: View") }, """
            `BodyTempoField` is no longer a `View` struct. All THREE of its live reads \
            (`transport.tempo`, `cameraRPPG.displayBPM`, `bus.usableBio()`) are legal ONLY \
            because this is an \
            observation boundary; `AnyView` is not one (10.76.50). Whatever body absorbed \
            them now rebuilds at up to 20 Hz and tears down every open `.menu` Picker \
            beneath it.
            """)
    }
}
