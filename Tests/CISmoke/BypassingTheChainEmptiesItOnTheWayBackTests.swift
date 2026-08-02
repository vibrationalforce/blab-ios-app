// BypassingTheChainEmptiesItOnTheWayBackTests.swift
// Echoel — the whole-chain FX bypass drains on the rising edge. BLOCKING. #397.
//
// THE HOLE #389 LEFT, IN ITS OWN WORDS. That slice drained the chain when the voice falls
// ASLEEP, and its doc named what it did not cover: "`PolySynthVoice.setFXEnabled(false)`
// bypasses the WHOLE chain and freezes it in exactly the same way — the canonical
// switch-crackle case one level up, and the one whole-chain bypass switch still untreated."
// This is that case.
//
// ⛔ WHY IT IS THE SAME DEFECT AND NOT A SMALLER ONE. `EchoelFXChain`'s SWITCH-CRACKLE RULE
// (founder: "knistert beim Umschalten von Dingen") resets every STATEFUL stage on its enable
// flag's rising edge, because a bypassed stage is skipped entirely and freezes holding old
// audio. (Thirteen of the fourteen `*Enabled` flags — `saturationEnabled` has no `willSet`
// because a waveshaper has no state to freeze.)
// `fxEnabled` skips all thirteen at once and reset nothing: bypass mid-take, wait, re-enable,
// and the delay line and the reverb tank walk out audio from before the bypass. Unlike the
// idle sleep this one is a DELIBERATE user action with a visible control (Effects panel,
// applied to both `synth` and `touchSynth`), so the burst arrives at the exact moment the
// user is listening for a change.
//
// ⭐ THE TIMING IS THE INVARIANT, not the presence of a drain. It must fire on the RISING
// edge and BEFORE the flag is raised: while `fxEnabled` is still false the render block is
// skipping the chain, so the audio thread is not in the chain when the control-plane drain
// runs — the rule's own argument, reused unchanged. Draining on the falling edge would hit
// a chain the audio thread is inside, and would cut a tail the user can still hear.
//
// ⛔ AND THE SECOND HALF OF THAT INVARIANT WAS MISSING FROM THE FIRST VERSION OF THIS FILE,
// which is why `testTheTwoDrainsAreComplementaryAndNotConcurrent` exists. Adding the
// control-plane drain gave `noteRenderSleeping()` a SECOND caller — the audio thread's
// 2.5 s idle sleep (#389). Those two are not mutually exclusive by construction: the idle
// bookkeeping sits OUTSIDE the `if fxEnabled` branch (it measures the synth's output, which
// the bypass does not affect), so a bypassed voice can fall asleep and drain at the same
// instant the user's FX-on tap drains from the main thread. Both then zero-fill the same
// `EchoelReverb.combBufL` — the exact failure `noteRenderSleeping` was rewritten to prevent,
// re-entered from the other side. The audio-thread call is therefore gated on `fxEnabled`
// too, so the two are exactly complementary: audio thread owns the drain while the flag is
// TRUE, control plane while it is FALSE.
//
// ⚠️ WHY EVERYTHING HERE IS A SOURCE SCAN. Both assertions are about WHICH THREAD IS
// WHERE WHEN, and every test in this bundle drives its subject single-threaded — no amount
// of buffer-pushing can observe a two-thread ordering. That the drain actually EMPTIES the
// chain is a separate, genuinely behavioural fact, and it is already asserted with real
// float buffers in `SleepingChainDoesNotHoardAudioTests`; a second copy here was deleted
// rather than kept, because a duplicated assertion in the blocking bundle reads as extra
// coverage while proving nothing new. Stated plainly so the gap is on the record: if
// `noteRenderSleeping()` stopped draining, THIS file would still pass — that neighbour is
// what catches it.
//
// NEEDS-FOUNDER-VERIFY: play a take with reverb/delay audible, switch FX off, wait ~5 s,
// switch FX on. No echo or wash of the pre-bypass audio may appear — the effects come back
// on what is playing NOW.

import Foundation
import XCTest

final class BypassingTheChainEmptiesItOnTheWayBackTests: XCTestCase {

    // MARK: - Single ownership: the two drains must never both be live

    /// ⛔ THE SHIP BLOCKER THE FIRST VERSION OF #397 CARRIED. Giving `noteRenderSleeping()` a
    /// control-plane caller made it a method reachable from TWO threads on the same chain
    /// instance. The rising-edge argument covers only the control-plane side; the audio-thread
    /// side (`#389`'s 2.5 s idle sleep) is decided by the idle counter, which lives OUTSIDE the
    /// `if fxEnabled` branch and therefore keeps running while the chain is bypassed. Gating it
    /// on the same flag is what makes the two complementary rather than concurrent.
    func testTheTwoDrainsAreComplementaryAndNotConcurrent() throws {
        let voice = try codeLines("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        guard let idx = voice.firstIndex(where: {
            $0.contains("idleQuietFrames >= Self.idleFrameThreshold")
        }) else {
            return XCTFail("""
                the idle-sleep transition is gone from `PolySynthVoice`. If the skip was \
                removed, remove this guard with it; if it moved, move this guard too.
                """)
        }
        guard let drain = voice[idx...].first(where: { $0.contains("noteRenderSleeping()") }) else {
            return XCTFail("""
                the idle sleep no longer drains the chain at all — that is #389, and \
                `SleepingChainDoesNotHoardAudioTests` owns it. Fix that one first.
                """)
        }
        XCTAssertTrue(drain.contains("if fxEnabled"), """
            the audio thread's sleep drain is no longer gated on `fxEnabled` (#397).

            It is not an optimisation. The idle counter sits outside the `if fxEnabled` \
            branch — it measures the SYNTH's output, which the bypass does not change — so \
            without this gate a bypassed voice can fall asleep and drain at the same instant \
            the user's FX-on tap drains from the main thread. Both zero-fill the same \
            `EchoelReverb.combBufL`: an exclusivity trap, and an index cleared against a \
            half-cleared buffer. Nothing is lost by gating it — a chain bypassed at sleep is \
            drained by `setFXEnabled`'s rising edge, the only moment it could be heard again.
                \(drain.trimmingCharacters(in: .whitespaces))
            """)
    }

    // MARK: - The gate, and the ORDER it does things in

    /// ⛔ POSITIONAL, because the position IS the safety argument. A drain placed AFTER
    /// `fxEnabled = on` runs while the audio thread has already resumed processing the chain
    /// — two threads in the same delay-line zero-fill, which is the race the SWITCH-CRACKLE
    /// RULE's "in `willSet`, while the flag is still false" phrasing exists to avoid.
    func testBothVoicesDrainBeforeRaisingTheFlagAndOnlyOnTheRisingEdge() throws {
        for path in ["Sources/Echoelmusic/Tools/PolySynthVoice.swift",
                     "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"] {
            let body = try memberBody(startingWith: "public func setFXEnabled(_ on: Bool)", in: path)
            guard !body.isEmpty else { continue }

            guard let drain = body.firstIndex(where: { $0.contains("noteRenderSleeping()") }) else {
                XCTFail("""
                    \(path) no longer drains the chain when FX are re-enabled (#397).

                    Bypassing skips all thirteen stages at once, so the delay line and the \
                    reverb tank keep the take's last seconds for the whole bypass and release \
                    them on the way back — the switch-crackle the founder reported, arriving \
                    through the master gate instead of a per-stage toggle.
                    setFXEnabled: \(body.map { $0.trimmingCharacters(in: .whitespaces) })
                    """)
                continue
            }
            guard let raise = body.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "fxEnabled = on"
            }) else {
                XCTFail("""
                    \(path) no longer raises `fxEnabled` with a bare `fxEnabled = on`, so this \
                    guard cannot say where "before the flag" is. Re-point it at whatever took \
                    that line's place — do not drop the ordering check for a `contains`.
                    """)
                continue
            }
            XCTAssertLessThan(drain, raise, """
                \(path) drains the chain AFTER raising `fxEnabled` (#397).

                By then the audio thread has resumed `processBuffer`, so the control-plane \
                reset and the render loop are in the same pre-allocated buffers at once. The \
                drain is only race-free while the flag is still false — that is the entire \
                argument the SWITCH-CRACKLE RULE rests on, and the order is what carries it.
                setFXEnabled: \(body.map { $0.trimmingCharacters(in: .whitespaces) })
                """)
            XCTAssertTrue(body[drain].contains("on && !fxEnabled"), """
                \(path) no longer drains on the RISING EDGE only (#397).

                An unconditional drain fires on the falling edge too — into a chain the audio \
                thread is actively processing, and cutting a tail the user can still hear. \
                A repeated `setFXEnabled(true)` would also clear the chain mid-take.
                    \(body[drain].trimmingCharacters(in: .whitespaces))
                """)
        }
    }

    // MARK: - Helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
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
        return Array(lines[(start + 1)..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here: both gates carry long
    /// blocks that quote `fxEnabled`, `noteRenderSleeping()` and the ordering rule verbatim
    /// while explaining them, so a scan that read prose would find every needle in the
    /// explanation of the code rather than in the code.
    private func codeLines(_ path: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — the ordering assertions inspect \
                source text, so they SKIP rather than reporting a green they did not earn
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
