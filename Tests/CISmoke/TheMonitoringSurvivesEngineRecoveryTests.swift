// TheMonitoringSurvivesEngineRecoveryTests.swift
// Echoel — #612. Live monitoring is re-armed after engine recovery and rate switches.
//
// KIND (§1): SOURCE-TEXT SCAN throughout (AudioEngine needs a device session no bundle
// here can drive). Whether the recycle is glitch-free on device is a DEVICE PROBE.
//
// WHY. Second CRITICAL of the #610 ultracode sweep (mic-monitoring-sweep, 2026-08-15),
// one mechanism with two symptoms: (a) a media-services reset orphans the monitor tap
// and chain, but `isInputMonitoring` survives as true — both door toggles rendered ON
// over a dead mic, the feedback guard read a frozen window, and a naive re-engage was a
// no-op behind the `guard !isInputMonitoring` early return; only a manual OFF→ON
// (⛔ #913 reshaped that guard into a block so the no-op could announce itself in the
// diag log; this header used to quote the whole one-liner and was falsified by the same
// commit that re-anchored the pin below — the #655/#656 pattern this file lectures about
// four lines down. The PREMISE is unchanged: a re-engage while monitoring is a no-op.)
// healed it. (b) `monitorTapSampleRate` is captured ONCE at tap install; after a
// 44.1↔48 kHz route switch the notch maths sat up to ~9 % off and YIN (#599) divided by
// the stale rate — Tune-to-key then snapped to WRONG notes. ⛔ #625b: this cited the
// tap-install comment in `setInputMonitoring` as NAMING "a route-change re-arm of
// monitoring" as the honest fix. #624 removed that naming — the phrase survives there only
// inside its own retraction, because the fix has since been BUILT. A pointer is only as
// durable as what it points at; the durable reference is `rearmInputMonitoring` itself and
// the two callers pinned below.
//
// THE FIX pinned here: ONE recycle helper `rearmInputMonitoring(reason:)` — full OFF→ON,
// restoring the tune choice BETWEEN off and on (the OFF path deliberately disarms it,
// #599 M1) — called from exactly TWO places: the end of `start()` (covers reset →
// recoverEngine → start and every manual retry) and the configuration-change running
// branch, gated on a real (> 0) and CHANGED input rate. The `start()` call sits AFTER
// the clean-state block on purpose: earlier, `degraded = false` would mask a failed
// recycle's own `restartOrDegrade` verdict (#611) with a healthy claim.
//
// HONEST GRADING (§3), against parent 55b4458:
// · Claims 1–3 are FORWARD — the helper and both call sites are born with this commit.
//   Red on the parent by ANCHOR ABSENCE: ONE finding (#486).
// · Claim 4 is a COUNTERWEIGHT pair (#343), green on both trees: the no-op guard and the
//   OFF-path tune disarm are the two premises that make the recycle (and its tune
//   save/restore) load-bearing rather than decorative.
// · Stripper (§2): 9 needles counted raw vs. stripped on both trees — the #612 comments
//   avoid quoting the helper token, 0 file-level differences, 0 verdict flips,
//   PROPHYLAKTISCH.

import Foundation
import XCTest

final class TheMonitoringSurvivesEngineRecoveryTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    // MARK: - claim 1 — the recycle helper is a full OFF→tune→ON, in that order

    func testTheRearmHelperRecyclesInOrder() throws {
        let code = try source(Self.engine)
        let body = try braceMatchedBlock(after: "private func rearmInputMonitoring(reason: String)", in: code)
        XCTAssertTrue(body.contains("guard isInputMonitoring else { return }"), """
            `rearmInputMonitoring` lost its already-off guard. Without it, every engine \
            start would force-toggle monitoring ON for users who never asked for it — \
            the opposite defect of the one it fixes.
            """)
        let off = body.range(of: "setInputMonitoring(false)")
        let tune = body.range(of: "setVoiceTune(true)")
        let on = body.range(of: "setInputMonitoring(true)")
        let o = try XCTUnwrap(off, "the recycle lost its OFF half")
        let t = try XCTUnwrap(tune, """
            the recycle lost the tune restore. The OFF path deliberately disarms the \
            tune (#599 M1), so a recycle without the restore silently strips Tune-to-key \
            from a performer's monitor chain on every engine recovery.
            """)
        let n = try XCTUnwrap(on, "the recycle lost its ON half")
        XCTAssertTrue(o.lowerBound < t.lowerBound && t.lowerBound < n.lowerBound, """
            The recycle order changed — it must be OFF, then restore the tune choice, \
            then ON. The restore only STORES the choice while monitoring is off; moved \
            after the ON it would bypass-flip a live chain instead (#858 — harmless \
            but the wrong mechanism), and before the OFF it \
            would be disarmed again by the OFF path itself.
            """)
    }

    // MARK: - claim 2 — start() re-arms, after the clean-state block

    func testStartRearmsAfterTheCleanStateBlock() throws {
        let code = try source(Self.engine)
        // Anchor deliberately WITHOUT the brace: braceMatchedBlock scans for the first
        // `{` AFTER the anchor, so an anchor that includes it would match the wrong
        // (nested) block. `func start(` occurs once in this file, measured at write time.
        let body = try braceMatchedBlock(after: "func start()", in: code)
        let clean = body.range(of: "degraded = false")
        let rearm = body.range(of: "rearmInputMonitoring(reason: \"engine start\")")
        let c = try XCTUnwrap(clean, "start() lost its clean-state block — re-judge this ordering scan")
        let r = try XCTUnwrap(rearm, """
            start() no longer re-arms monitoring. That was the sweep's reset symptom: \
            after a media-services reset, recoverEngine → start() rebuilt every tap \
            EXCEPT the monitor chain, leaving both toggles ON over a dead microphone \
            with no path to heal but a manual OFF→ON.
            """)
        XCTAssertTrue(c.lowerBound < r.lowerBound, """
            The re-arm moved BEFORE start()'s clean-state block. There `degraded = \
            false` masks a failed recycle's own restartOrDegrade verdict (#611) with a \
            healthy claim — the re-arm must stay the last act of start().
            """)
    }

    // MARK: - claim 3 — the format-change branch re-arms, gated on a REAL change
    // (#826 widened the gate from rate-only to rate OR channel count — the #625b
    // registered gap: mono BT mic → stereo USB at the same 48 kHz re-armed nothing)

    func testTheConfigChangeBranchRearmsOnRateChange() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("\"route sample-rate change\"")
                      && code.contains("\"route channel-count change\""), """
            The configuration-change running branch no longer names BOTH re-arm \
            reasons. Rate-only was #612 (stale `monitorTapSampleRate`: notch maths up \
            to ~9 % off, YIN snapping Tune-to-key to wrong notes); channel-count was \
            #826 (#625b's registered gap — a route switch that changes channels but \
            not rate left the monitor chain connected at the old count). Two named \
            reasons, so the founder's diag log says WHICH half fired.
            """)
        XCTAssertTrue(code.contains("newRate != self.monitorTapSampleRate"), """
            The rate gate is gone. Without comparing against the captured tap rate the \
            branch would recycle monitoring on EVERY configuration change (audible \
            interruption for no reason); without the `> 0` companion a transient \
            input-less moment mid-switch would tear monitoring down entirely.
            """)
        XCTAssertTrue(code.contains("newFormat.channelCount != self.monitorTapChannelCount"), """
            The channel-count half of the #826 gate is gone — the #625b gap reopens: \
            a BT-mic → USB-interface switch at the same sample rate re-arms nothing \
            and the monitor chain stays connected at the old channel count.
            """)
        XCTAssertTrue(code.contains("monitorTapChannelCount = inFmt.channelCount"), """
            The channel count is no longer captured at tap install — the #826 gate \
            then compares against a permanent 0 and re-arms on EVERY configuration \
            change (the exact needless-recycle failure the rate gate exists to avoid).
            """)
        XCTAssertEqual(occurrences(of: "rearmInputMonitoring(reason:", in: code), 3, """
            The re-arm call-site count changed (expected 3: the declaration, start(), \
            the rate branch). A NEW caller should be deliberate — the recycle pauses \
            the engine (#595 pattern) and is not free; update this count in the same \
            commit and say why the new site needs it.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHTS) — the two premises

    func testTheTwoPremisesSurvive() throws {
        let code = try source(Self.engine)
        // ⛔ #913 — THIS NEEDLE USED TO PIN THE WHOLE ONE-LINER, body included
        // (`guard !isInputMonitoring else { return true }`), and #913 reddened it by adding
        // a breadcrumb INSIDE the block. The premise did not change; only its shape did.
        // `scripts/count-pins.py` caught it before the push, which is the whole reason that
        // tool exists (#903/#904: CI cannot show a stale count pin, because the pipeline
        // reports `failure` on every push under #396).
        // The needle now pins the CONDITION plus, separately, that the block still returns
        // early. That is the actual premise — "a re-engage while already monitoring is a
        // no-op" — and it survives adding a line to the block without weakening.
        XCTAssertEqual(occurrences(of: "guard !isInputMonitoring else {", in: code), 1, """
            The already-monitoring no-op guard in setInputMonitoring(true) changed. It \
            is WHY a full recycle exists at all — if a plain re-engage now heals an \
            orphaned chain, re-judge whether rearmInputMonitoring should simplify, and \
            update this guard in the same commit.
            """)
        if let g = code.range(of: "guard !isInputMonitoring else {") {
            let after = code[g.upperBound...].prefix(400)
            XCTAssertTrue(after.contains("return true"), """
                The already-monitoring guard no longer RETURNS — pinning its condition \
                alone would then pass while the no-op became a fall-through, which is the \
                opposite of the premise this claim carries.
                """)
        }
        XCTAssertEqual(occurrences(of: "setVoiceTune(false)", in: code), 1, """
            The OFF path's tune disarm (#599 M1) changed. It is why the recycle saves \
            and restores the tune choice — if the disarm is gone, the restore in \
            rearmInputMonitoring becomes dead ballast; re-judge both in the same commit.
            """)
    }

    // MARK: - helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: needle, range: search) {
            count += 1
            search = r.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Brace-matched body after `anchor`'s first `{` — no fixed line window (#408).
    private func braceMatchedBlock(after anchor: String, in code: String) throws -> String {
        struct AnchorMissing: Error { let reason: String }
        guard let a = code.range(of: anchor) else {
            throw AnchorMissing(reason: "anchor `\(anchor)` not found — re-anchor this scan")
        }
        var depth = 0
        var begun = false
        var out = String.UnicodeScalarView()
        for ch in code[a.upperBound...].unicodeScalars {
            if ch == "{" { depth += 1; begun = true }
            if begun { out.append(ch) }
            if ch == "}" {
                depth -= 1
                if begun && depth == 0 { break }
            }
        }
        guard begun else {
            throw AnchorMissing(reason: "no block opened after `\(anchor)`")
        }
        return String(out)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
