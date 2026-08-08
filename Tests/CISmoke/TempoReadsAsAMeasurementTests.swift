// TempoReadsAsAMeasurementTests.swift
// Echoel — a number may not claim more precision than the thing it measures has.
//
// WHAT THIS GUARDS (#368). `BodyTempoField` has two states behind one lock. UNLOCKED it
// shows the CLOCK the body is driving (`transport.tempo`). LOCKED it shows a value the
// player set, rounded and persisted to 1e-4 and edited through the number pad at that
// resolution.
//
// ⛔ THE UNLOCKED HALF USED TO READ `cameraRPPG.displayBPM` — the raw pulse — and this
// header said so until #491 (founder 2026-08-07, "ohne doppelt bpm"). That was the same
// number the pulse pill beside it renders, in a box labelled "Tempo", while the clock ran
// somewhere else entirely (the genre-tilted mapping of it). EVERY ASSERTION BELOW SURVIVES
// UNCHANGED, and that is the point worth writing down rather than the edit: the precision
// argument was never about the camera specifically. `transport.tempo` in the unlocked state
// is that same estimate carried through a genre map — the map adds no resolution — so one
// decimal is still all the digits the number has. If anything the case got stronger: the
// unlocked readout is now a DERIVED value, one step further from a measurement, not closer.
//
// ⚠️ ONE VISIBLE CONSEQUENCE, stated because a reader will meet it before this file: after
// unlocking, `transport.tempo` still carries the 4-decimal value the lock glided it to, so
// the number visually drops digits (71,2345 → 71,2) on unlock. That is a formatting change,
// not a clock change, and it replaces the far worse #491 behaviour where unlocking made the
// box JUMP to the raw pulse.
//
// Both printed four decimals. The founder circled the result — `71,0000` in the transport
// bar — in THREE separate device screenshots before it was read. Three of those digits were
// never information: nothing in a camera-derived pulse estimate resolves to a ten-thousandth
// of a beat per minute, and in the shipped build they read as literal zeros.
//
// ⭐ WHAT MADE IT DECIDABLE rather than a matter of taste: the app already disagreed with
// itself. `followingSpoken` has always used ONE decimal. A sighted player read "71,0000"
// while VoiceOver said "71,0 beats per minute" — same value, same instant, two precisions.
// One of the two had to move, and only one of them was defensible.
//
// ⚠️ THIS FILE DELIBERATELY DOES NOT TOUCH THE APP-WIDE DEFAULT. `EchoelValueField.decimals`
// defaults to 4 and every set parameter in the app uses it (Brightness 0,2590 · Energy
// 0,9561 · the "exact to 0.0001" subtitle in the Sound panel). That is a deliberate
// science-first position, not a bug, and sweeping it out with this finding would be the #364
// mistake again — grepping a token instead of its meaning. The rule proven here is narrower
// and stronger: a MEASUREMENT is not a SETTING.
//
// ⚠️ Source-text scan, no simulator; `Tests/CISmoke` is the blocking bundle. SKIPS rather
// than passes if the tree is not at this file's compile-time path.

import Foundation
import XCTest

final class TempoReadsAsAMeasurementTests: XCTestCase {

    private func codeLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/BodyTempoField.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// The two readouts of the SAME unlocked value — printed and spoken — must agree on how
    /// many decimals that value actually has.
    func testTheFollowingTempoIsPrintedAndSpokenAtTheSamePrecision() throws {
        let code = try codeLines()
        let printed = code.filter { $0.contains("EchoelDecimalText.string(followingValue") }
        XCTAssertEqual(printed.count, 2, """
            Expected exactly two formattings of `followingValue` (the printed one and the \
            spoken one), found \(printed.count): \
            \(printed.map { $0.trimmingCharacters(in: .whitespaces) }). A third copy is a \
            third place for the precision to drift; fewer means one of the two readouts is \
            gone and this guard no longer describes the control.
            """)
        let decimals = printed.compactMap { line -> String? in
            guard let r = line.range(of: "decimals: ") else { return nil }
            return String(line[r.upperBound...].prefix { $0.isNumber })
        }
        XCTAssertEqual(Set(decimals).count, 1, """
            The printed and spoken forms of the following tempo use different precisions \
            (\(decimals)). That is the exact defect #368 closed: the screen said "71,0000" \
            while VoiceOver said "71,0 beats per minute" for the same number at the same \
            moment. Change both or neither.
            """)
        XCTAssertEqual(decimals.first, "1", """
            The following tempo is formatted to \(decimals.first ?? "?") decimals. It is the \
            clock as the body is driving it — a camera-derived estimate over a ~10 s window \
            carried through the genre map, which adds no resolution — so it does not resolve \
            to a ten-thousandth of a BPM, and the founder circled the four-decimal version \
            in three separate screenshots. If the pulse estimator ever gains real \
            resolution, raise this WITH the estimator, not ahead of it.
            """)
    }

    /// The locked half is a set value and keeps the precision it was asked for. Pinned so a
    /// later reader "harmonising" the two states cannot quietly take the editable resolution
    /// away — that direction would cost a real capability, not a false claim.
    func testLockingStillStoresTheValueAtEditingResolution() throws {
        let code = try codeLines()
        XCTAssertTrue(code.contains { $0.contains("(v * 10_000).rounded() / 10_000") }, """
            The lock no longer rounds to 1e-4 before persisting. The locked field is the \
            editable one — the founder's 2026-07-04 ask (four decimals, lockable) lives \
            THERE, and #368 only narrowed the unlocked reading beside it.
            """)
        XCTAssertFalse(code.contains { $0.contains("decimals: 1") && $0.contains("lockedBinding") }, """
            The locked field was narrowed to one decimal along with the following readout. \
            That is the opposite of #368: the measurement lost digits it never had, the \
            setting must keep the ones it does.
            """)
    }
}
