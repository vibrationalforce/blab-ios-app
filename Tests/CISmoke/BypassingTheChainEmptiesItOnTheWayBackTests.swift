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
// (founder: "knistert beim Umschalten von Dingen") resets every stage on its enable flag's
// rising edge, because a bypassed stage is skipped entirely and freezes holding old audio.
// `fxEnabled` skips all thirteen at once and reset nothing: bypass mid-take, wait, re-enable,
// and the delay line and the reverb tank walk out audio from before the bypass. Unlike the
// idle sleep this one is a DELIBERATE user action with a visible control (Effects panel,
// applied to both `synth` and `touchSynth`), so the burst arrives at the exact moment the
// user is listening for a change.
//
// ⭐ THE TIMING IS THE INVARIANT, not the presence of a drain. It must fire on the RISING
// edge and BEFORE the flag is raised: while `fxEnabled` is still false the render block is
// skipping the chain, so the control-plane drain provably cannot race the audio thread —
// the rule's own argument, reused unchanged. Draining on the falling edge would hit a chain
// the audio thread is inside, and would cut a tail the user can still hear.
//
// ⚠️ WHY A SOURCE SCAN FOR THE ORDERING and a behavioural test for the drain: the ordering
// is a threading property (which thread is where when), and every behavioural test in this
// bundle drives the chain single-threaded. The drain ITSELF is observable, so that half is
// driven with real buffers.
//
// NEEDS-FOUNDER-VERIFY: play a take with reverb/delay audible, switch FX off, wait ~5 s,
// switch FX on. No echo or wash of the pre-bypass audio may appear — the effects come back
// on what is playing NOW.

import Foundation
import XCTest
@testable import Echoelmusic

final class BypassingTheChainEmptiesItOnTheWayBackTests: XCTestCase {

    private let sampleRate: Float = 48000
    private let block = 512

    // MARK: - The drain itself, with real buffers

    /// The chain-side half. `noteRenderSleeping()` is the drain both call sites use, so this
    /// asserts what the bypass gate is actually buying: a tank charged before the bypass
    /// cannot be heard after it, however the mix moves in between.
    func testADrainedChainCannotAnswerWithAudioItWasNotFed() {
        let chain = EchoelFXChain(sampleRate: sampleRate)
        chain.reverbEnabled = true
        chain.reverb.roomSize = 0.9
        chain.reverb.mix = 0.0008          // charge loud, output stays under any floor
        chain.limiterEnabled = false
        chain.compressorEnabled = false

        for _ in 0..<24 {
            var l = burst(), r = burst()
            chain.processBuffer(left: &l, right: &r, frameCount: block)
        }
        chain.noteRenderSleeping()          // what the rising edge of `fxEnabled` now calls
        chain.reverb.mix = 0.9

        var maxAfter: Float = 0
        for _ in 0..<24 {
            var l = [Float](repeating: 0, count: block)
            var r = [Float](repeating: 0, count: block)
            chain.processBuffer(left: &l, right: &r, frameCount: block)
            maxAfter = max(maxAfter, peak(l, r))
        }
        XCTAssertLessThan(maxAfter, 1e-6, """
            the drain the FX bypass relies on no longer empties the chain (\(maxAfter)) — so \
            re-enabling FX after a bypass will burst the pre-bypass take (#397).
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

    /// A full-scale-ish noise burst. Deterministic (a fixed recurrence, no `Random`) so a
    /// failure reproduces exactly — the house rule for anything that can end up in CI.
    private func burst() -> [Float] {
        var out = [Float](repeating: 0, count: block)
        var state: UInt32 = 0x9E37_79B9
        for i in 0..<block {
            state = state &* 1_664_525 &+ 1_013_904_223
            out[i] = Float(Int32(bitPattern: state)) / Float(Int32.max) * 0.5
        }
        return out
    }

    private func peak(_ l: [Float], _ r: [Float]) -> Float {
        var p: Float = 0
        for v in l where abs(v) > p { p = abs(v) }
        for v in r where abs(v) > p { p = abs(v) }
        return p
    }
}
