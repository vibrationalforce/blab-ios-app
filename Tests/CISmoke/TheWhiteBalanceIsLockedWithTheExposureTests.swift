import XCTest
@testable import Echoelmusic

/// #1075 — the camera's white balance is locked in the same breath as its exposure.
///
/// WHY IT MATTERS, in one line: rPPG reads the RED/GREEN ratio, and a drifting auto white
/// balance rescales exactly those two channels against each other — it writes a slow trend
/// straight into the signal the pulse estimator is trying to read. Exposure has been locked
/// since 2026-06-23 (a device-log root cause); white balance never was.
/// `git grep -c whiteBalance -- Sources` returned **0** the day this landed, which is how a
/// deep-research sweep found it: not a new idea, a missing half of one already shipped.
///
/// ⚠️ SOURCE-TEXT SCAN (§1). It cannot see a camera. Whether the pulse locks faster or more
/// reliably is a DEVICE PROBE and stays open — the arithmetic here is only that the two
/// photometric settings are handled as ONE pair.
final class TheWhiteBalanceIsLockedWithTheExposureTests: XCTestCase {

    private func capture() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent("Sources/Echoelmusic/Video/CameraCapture.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: CameraCapture.swift could not be read — a missing anchor "
                    + "is a finding, not a pass.")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    // 1 — the lock happens INSIDE `lockExposure()`, not in a method of its own.
    func testTheWhiteBalanceIsLockedInsideTheExposureLock() throws {
        let code = try capture()
        guard let start = code.range(of: "func lockExposure()") else {
            XCTFail("`lockExposure()` is gone or renamed — re-anchor this whole file with it.")
            return
        }
        // 21 CODE lines, measured rather than generous, and the assertion below is what
        // measured it. `codeWindow` skips blank lines, so a doc block costs it nothing — but
        // `lockExposure()` is exactly 21 code lines, and the first draft's budget of 40 ran
        // nineteen lines into `unlockExposure()`. That is #899's false-GREEN headroom hazard:
        // no needle here can match in the neighbour TODAY, and nothing said so out loud.
        // (22 was the second draft and still reached it — line 22 IS the neighbour's `func`.)
        let body = SourceText.codeWindow(code, from: start.lowerBound, lines: 21)
        XCTAssertFalse(body.contains("func unlockExposure()"), """
            The window from `lockExposure()` now reaches `unlockExposure()`, so claims 1a/1b             could be satisfied by the WRONG method. `lockExposure()` shrank; shrink this             budget with it. (It cannot fail the other way: if the method grows, the window             simply covers less of it.)
            """)
        XCTAssertTrue(body.contains("whiteBalanceMode = .locked"), """
            `lockExposure()` no longer locks the white balance. rPPG reads the red/green \
            ratio, so a drifting AWB rescales the two channels the pulse estimator compares \
            — a slow trend written directly into the signal. If this was moved somewhere \
            else, read claim 3 first: the placement is the whole design.
            """)
        XCTAssertTrue(body.contains("isWhiteBalanceModeSupported(.locked)"), """
            The white-balance lock is no longer guarded by its support check. Not every \
            device/format supports locking it, and setting an unsupported mode is not a \
            no-op worth gambling on in the one path a performance depends on.
            """)
    }

    // 2 — BOTH are restored, and NEITHER restore hangs off the other's support check. That
    // was a real trap: `unlockExposure()`'s `guard` used to carry
    // `isExposureModeSupported(.continuousAutoExposure)`, so on a device without it the
    // method returned having restored nothing. Harmless while exposure was alone; the moment
    // white balance joined, one unsupported mode would leave the OTHER locked — a stuck
    // photometric setting no control can clear (#939's defect class).
    func testBothSettingsAreRestoredIndependently() throws {
        let code = try capture()
        guard let start = code.range(of: "func unlockExposure()") else {
            XCTFail("`unlockExposure()` is gone or renamed — re-anchor with claim 1.")
            return
        }
        let body = SourceText.codeWindow(code, from: start.lowerBound, lines: 24)
        XCTAssertTrue(body.contains("exposureMode = .continuousAutoExposure"),
                      "`unlockExposure()` no longer restores auto exposure.")
        XCTAssertTrue(body.contains("whiteBalanceMode = .continuousAutoWhiteBalance"), """
            `unlockExposure()` restores exposure but not white balance. Then every recovery \
            path — a saturated lock, a re-grip, teardown — leaves the device with frozen \
            colour gains, and the next session (or the next app) inherits them.
            """)
        guard let guardStart = body.range(of: "guard let self") else {
            XCTFail("`unlockExposure()`'s guard is gone — re-read claim 2's reasoning before "
                    + "re-anchoring; the SHAPE of that guard is what this claim is about.")
            return
        }
        let guardClause = SourceText.codeWindow(body, from: guardStart.lowerBound, lines: 4)
        XCTAssertFalse(guardClause.contains("isExposureModeSupported"), """
            A mode-support check is back on `unlockExposure()`'s `guard`, so one unsupported \
            mode makes the method return without restoring the OTHER one. Each restore must \
            stand on its own `if`. This is not hypothetical — it is the exact line this slice \
            had to move.
            """)
    }

    // 3 — COUNTERWEIGHT (#367), and it names the premise rather than freezing the design.
    // Locking white balance is safe here ONLY because this capture session feeds rPPG alone.
    // If it ever also fed a recorded video, frozen colour gains would tint the film.
    func testThisCaptureSessionStillFeedsOnlyTheRPPGPath() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let sources = dir.appendingPathComponent("Sources/Echoelmusic")
        var sites: [String] = []
        if let walker = FileManager.default.enumerator(atPath: sources.path) {
            for case let rel as String in walker where rel.hasSuffix(".swift") {
                let url = sources.appendingPathComponent(rel)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if SourceText.codeOnly(text).contains("CameraCapture()") { sites.append(rel) }
            }
        }
        XCTAssertEqual(sites.sorted(), ["Bio/CameraRPPGBioPublisher.swift"], """
            `CameraCapture()` is constructed in \(sites.sorted()) — not only by the rPPG \
            publisher any more.

            ⭐ THIS IS NOT A PROHIBITION (#364). It is the premise #1075 rests on: freezing \
            the colour gains is free when the frames are only ever measured, and NOT free \
            when they are also recorded or shown, because a locked white balance tints the \
            picture. If a second consumer is correct, decide there whether the lock should \
            be conditional on it — then re-anchor this list in the same commit.
            """)
    }

    // 4 — NO SEPARATE PAIR. This is the design decision most likely to be "tidied" back, and
    // the reason is countable: `lockExposure()` has one caller, `unlockExposure()` has five
    // (saturated lock, re-grip, two teardowns, leave-it-in-auto). A parallel
    // `lockWhiteBalance()`/`unlockWhiteBalance()` would need all six to remember its partner.
    func testWhiteBalanceHasNoMethodPairOfItsOwn() throws {
        let code = try capture()
        for name in ["func lockWhiteBalance", "func unlockWhiteBalance"] {
            XCTAssertFalse(code.contains(name), """
                `\(name)` exists. The two photometric settings were deliberately folded into \
                ONE pair so their symmetry cannot rot: five separate recovery paths call \
                `unlockExposure()`, and each would have to remember to call a partner. If a \
                separate pair is genuinely needed, every one of those paths has to be updated \
                in the same commit — and this claim rewritten to say why.
                """)
        }
    }
}
