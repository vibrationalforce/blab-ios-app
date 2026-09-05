import XCTest
@testable import Echoelmusic

/// #1022 — THE LAUNCH THAT CONFIGURED NOTHING, AND THE SWITCH IT BLOCKED NINE MINUTES LATER.
///
/// Measured on the founder's device, build v10.79.447 (2565). His `echoel_diag.log` opens:
///
///     session: configure 1/4 — setCategory(.playback)
///     session: configure FAILED — NSOSStatusErrorDomain Code=-50
///
/// and NO rung 2/4. The ladder law (#862b: a rung stands BEFORE its call) makes that
/// conclusive — the throw is inside `setCategory`, not in any later step. OSStatus -50 is
/// `paramErr`: an argument the session will not accept. `.playback` and `.default` are not in
/// question and `.mixWithOthers` is valid for playback-shaped categories, so by elimination
/// the refused argument is `.allowBluetoothA2DP`.
///
/// ⚠️ THE OPTION WAS NOT THE COST — THE ABANDONED FUNCTION WAS. One throw skipped rungs
/// 2/4…4/4 and left `isSessionConfigured` false for the entire run, so nine minutes later
/// `monitor: on 1/5` reached `on REFUSED — the session was never configured and reconfiguring
/// it failed`. The founder's live-monitoring switch — the one handgrip the whole vocal chain
/// waits on — could not be turned on, on a build whose music played fine the whole time.
///
/// ⚠️ WHAT THIS GUARD DOES **NOT** DO (#364). It does not require the option to be asked for,
/// and it does not require it to be dropped. Both are correct trees and the claim below is
/// shaped as an either/or so that neither is forbidden: ask for it and carry a fallback, or do
/// not ask for it at all. What is forbidden is the third shape — asking for it with no way back
/// — because that is exactly the shape that shipped.
///
/// ⚠️ AND IT IS NOT VACUOUS (#808). An either/or over two arms that between them cover every
/// tree in which the branch exists cannot pass by having no subject: claim 1 fails loudly if
/// the `.playback` `setCategory` itself is gone.
final class TheSessionSurvivesARefusedOptionTests: XCTestCase {

    // MARK: - 1. Either the option is not asked for, or its refusal has a way back

    func testTheDefaultCategoryCannotBeRefusedIntoAnUnconfiguredSession() throws {
        let body = try configureBody()

        guard let playback = body.range(of: "setCategory(.playback,") else {
            XCTFail("""
                `configureAudioSession` no longer sets `.playback` at all. That is the DEFAULT \
                category for this app — output only, no mic, no HFP downgrade for other apps \
                (#1022). If the branch moved, re-anchor this file (§4); do not delete the claim.
                """)
            return
        }

        let asksForA2DP = body[playback.lowerBound...].prefix(220).contains(".allowBluetoothA2DP")
        guard asksForA2DP else {
            // Arm B: a later session measured the pair as invalid everywhere and dropped the
            // option. Correct, and nothing here objects — but the promise the doc block makes
            // must survive it, so claim 2 below still runs.
            return
        }

        // Arm A: it is still asked for, so a refusal must not end the function.
        // The needle is the OPTION SET, not a whitespace-exact call — #408's other half: a
        // guard that pins indentation goes red on a reformat and teaches nothing.
        let fallback = body.range(of: "options: [.mixWithOthers])",
                                  range: playback.upperBound..<body.endIndex)
        XCTAssertNotNil(fallback, """
            The `.playback` category still asks for `.allowBluetoothA2DP` and there is no \
            fallback that omits it. On the founder's device that ask throws -50, and a throw \
            here abandons rungs 2/4, 3/4 and 4/4: the sample rate is never asked for, the \
            session is never activated, `isSessionConfigured` stays false, and every later \
            `monitor: on` refuses because of it (#1022).
            """)

        XCTAssertNotNil(body.range(of: "session: the .playback option set was refused ("), """
            The fallback is silent. `os_log` does not reach the exported `echoel_diag.log` \
            (#859), so a device that took the fallback would look identical to one that never \
            needed it — and the next such defect would again be invisible for two builds.
            """)
    }

    // MARK: - 2. No path may reach for the HFP option

    /// The unconditional half, and the one that protects a founder promise rather than a
    /// device: `.allowBluetooth` (HFP) pulls the SHARED Bluetooth route down to the 8/16 kHz
    /// mono call codec for every app on the phone. `.allowBluetoothA2DP` does not. A fallback
    /// written in a hurry is exactly where the wrong one of the two gets typed.
    func testNoOptionSetReachesForTheCallCodec() throws {
        let code = try source()
        var hits = 0
        var index = code.startIndex
        while let r = code.range(of: ".allowBluetooth", range: index..<code.endIndex) {
            if !code[r.upperBound...].hasPrefix("A2DP") { hits += 1 }
            index = r.upperBound
        }
        XCTAssertEqual(hits, 0, """
            `.allowBluetooth` (the HFP option) appears in `AudioConfiguration.swift`. It makes \
            iOS route every parallel app's Bluetooth headset through the mono call codec for as \
            long as Echoel holds the session — the exact degradation the file's own category \
            doc says it guarantees never to cause (founder, 2026-07-09).
            """)
    }

    // MARK: - helpers (the house shape: strip comments, bound by the next `static func`)

    private func source() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        let text = try String(contentsOf: path, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// #408: bounded by the next `static func`, never by a character count.
    private func configureBody() throws -> String {
        let code = try source()
        let fn = "static func configureAudioSession"
        let start = try XCTUnwrap(code.range(of: fn), "`\(fn)` is gone — re-anchor (§4).")
        let rest = code[start.upperBound...]
        let end = rest.range(of: "\n    static func")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }
}
