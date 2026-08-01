// MixFaderRespondsBeforeThePersistTests.swift
// Echoel — #342. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE DEFECT THIS PINS. Founder, 2026-08-01: "Lautstärke fader vom Pad zum Beispiel
// reagiert versetzt." A Mix fader's whole effect was queued behind ONE debounce, and that
// debounce was sized by the expensive half of the work, not the audible half:
//   · AUDIBLE   — re-glue the raw bars at the new levels, stage them on the roll. A few
//                 hundred struct copies plus an array assignment.
//   · EXPENSIVE — `syncPrimaryRollClip` → `ClipStore.updateComposerMelody` → `persist()`
//                 → `AppGroupStore`: a pretty-printed JSON encode of the whole clip grid
//                 plus an atomic file-protected write, SYNCHRONOUSLY on the main actor
//                 that also hosts this view's `.menu` Pickers. At gesture rate that is
//                 the main-actor-starvation class that froze menus in 10.76.48.
// `scheduleRebalance`'s own comment already said the number came from the expensive half
// and already named this split as the next step. It was 350 ms of dead time in front of a
// control the founder holds while listening.
//
// ⚠️ WHAT THIS TEST DOES **NOT** CLAIM, written down because the honest bound is small and
// a later reader must not inflate it: the roll still swaps new levels in at the next BAR
// boundary (~2 s at 120 bpm), and that part is musically required — the alternative is a
// mid-bar note-array swap. So the Pad fader goes ~2.35 s → ~2.0 s, not to zero. Removing
// the remaining 2 s means taking the user level out of note VELOCITY entirely (#196), and
// that has to answer #205 first, because velocity doubles as "is this note audible" for
// the visual, the light output and the felt sub.
//
// WHAT THIS CAN AND CANNOT SHOW: `EchoelStudioView` is a SwiftUI view this bundle cannot
// build, and both methods are private, so this reads SOURCE TEXT — the same shape as
// `SoundPanelPresetBarTests` and `NoDoorlessStudioViewsTests`. Weaker than behavioural,
// stronger than nothing, and it pins the two things that actually decide the outcome: the
// ORDER (audible before the sleep) and the ABSENCE of the persist from the immediate half.
// An ordering assertion is used rather than a bare token because a bare token in this repo
// reappears as prose in a tombstone and the guard then goes permanently green.

import Foundation
import XCTest

final class MixFaderRespondsBeforeThePersistTests: XCTestCase {

    /// The order IS the fix. If the immediate call moves below the sleep — or disappears —
    /// the fader is back to waiting for a JSON write before it makes a sound.
    func testTheAudibleHalfRunsBeforeTheDebounce() throws {
        let body = try functionBody(named: "private func scheduleRebalance()")

        guard let audible = body.range(of: "rebalanceAudibleNow()") else {
            return XCTFail("""
                `scheduleRebalance()` no longer calls `rebalanceAudibleNow()`. Every Mix \
                fader is then queued behind the 350 ms settle again, and that settle is \
                sized by a pretty-printed JSON encode plus an atomic file write — not by \
                anything musical. This is the founder's "reagiert versetzt" (2026-08-01).
                """)
        }
        guard let sleep = body.range(of: "Task.sleep") else {
            return XCTFail("""
                `scheduleRebalance()` no longer sleeps. That is not automatically wrong, \
                but it means the EXPENSIVE half — `syncPrimaryRollClip` → `ClipStore` → \
                `AppGroupStore`, a synchronous JSON encode and atomic write on the actor \
                that hosts the `.menu` Pickers — now runs per drag event. That is the \
                10.76.48 main-actor-starvation class. Re-read this file before removing it.
                """)
        }
        XCTAssertTrue(audible.lowerBound < sleep.lowerBound, """
            `rebalanceAudibleNow()` now runs AFTER the debounce, which makes it pointless: \
            the whole point of the split is that the cheap, audible half does not wait for \
            the expensive, persistent one. Order, not presence, is what this fixes.
            """)
    }

    /// The other half of the contract. If the persist creeps back into the immediate path,
    /// the split silently becomes "do the expensive thing at gesture rate" — strictly worse
    /// than the bug it replaced, and it would present as a menu freeze, not as lateness.
    func testTheImmediateHalfCarriesNoPersist() throws {
        let body = try functionBody(named: "private func rebalanceAudibleNow()")

        for forbidden in ["syncPrimaryRollClip", "writeLaneTakes", "recomposeIfRunning"] {
            XCTAssertFalse(body.contains(forbidden), """
                `rebalanceAudibleNow()` now calls `\(forbidden)`, and it runs on EVERY \
                fader event. `syncPrimaryRollClip`/`writeLaneTakes` reach a synchronous \
                JSON encode + atomic file write on the main actor — the 10.76.48 \
                menu-freeze class. `recomposeIfRunning` would schedule a GENERATE per drag \
                event on every opened project, where `lastRawTake` is nil. All three \
                belong in the debounced half, which still calls the full `rebalanceTake()` \
                unchanged.
                """)
        }
    }

    /// The immediate half must be a strict subset, never a second opinion. Re-gluing with
    /// `style` instead of the take's own genre would make the two halves disagree for the
    /// length of a pending recompose — which sounds like the fader jumping, i.e. worse than
    /// being late. `rebalanceTake()` already carries this rule; both must follow it.
    func testBothHalvesReglueWithTheTakesOwnGenre() throws {
        for name in ["private func rebalanceAudibleNow()", "private func rebalanceTake()"] {
            let body = try functionBody(named: name)
            XCTAssertTrue(body.contains("genre: take.genre"), """
                `\(name)` no longer re-glues with `take.genre`. If one half uses the take's \
                composed genre and the other uses the currently selected `style`, a fader \
                moved while a genre recompose is still pending produces two different \
                balances a bar apart. A level control must never change the mix design.
                """)
        }
    }

    // MARK: - helpers

    /// Extract one function's body by brace matching from its signature. Deliberately not
    /// a regex: these methods contain nested closures and `Task { }` blocks, and a
    /// line-count or non-greedy match would silently read the wrong span — a guard that
    /// reads the wrong text is the false-GREEN this bundle exists to prevent.
    private func functionBody(named signature: String) throws -> String {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let start = code.range(of: signature) else {
            throw XCTSkip("""
                `\(signature)` not found — the method was renamed or removed. Skipping \
                rather than reporting a green this file did not earn; re-point the guard.
                """)
        }
        var depth = 0
        var seenOpen = false
        var body = ""
        for ch in code[start.upperBound...] {
            if ch == "{" { depth += 1; seenOpen = true }
            if seenOpen { body.append(ch) }
            if ch == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        return body
    }

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
