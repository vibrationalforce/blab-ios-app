import XCTest
@testable import Echoelmusic

/// #992 — the pulse lock cannot be green while the camera sends nothing.
///
/// WHY IT EXISTS. `isLocked` asked three questions about the READING (bpm, confidence,
/// autocorrelation strength) and none about whether a reading was still arriving. When iOS
/// interrupts the capture session, or a thermal throttle cuts the feed to a trickle, the
/// analyzer's last values simply FREEZE — byte-identical every tick — so all three stayed true
/// while the publish loop bailed one line in on its own rate guard
/// (`inboundRateEMA >= minMeasurableInboundHz`) and nothing reached the bus. The header pill
/// showed a green lock and a confident bpm, `PulseCue` said "Locked", and the instrument was
/// being fed nothing. The file's own doc block two paragraphs above `isLocked` describes exactly
/// this failure in its FIRST hiding place (the newly-rejected confidence band) and closed it
/// there; this is the same lie in its second.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. It runs no camera and renders no SwiftUI. Whether the pill
/// going dark within about a second of a real interruption reads as honest rather than broken is
/// the NEEDS-FOUNDER-VERIFY at the foot of this file. What it pins is that the lock carries a
/// frame-flow term, that the term is the publish path's own two facts and not the thermal
/// banner, and that a fresh take never opens on a stale stall.
final class TheLockNeedsFramesTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// The lines of a `{ … }` member starting at the line that opens it, brace-counted.
    private func memberBody(from marker: String, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else { return nil }
        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            out.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth <= 0 && out.count > 1 { break }
        }
        return out.joined(separator: "\n")
    }

    // 1 — the lock carries a frame-flow term at all. This is the whole finding: without it,
    // "locked" means "the last reading was good", not "the instrument is being fed".
    func testTheLockAsksWhetherFramesAreStillArriving() throws {
        let text = try source(Self.publisher)
        guard let body = memberBody(from: "public var isLocked: Bool {", in: text) else {
            return XCTFail("ANCHOR MISSING: `public var isLocked: Bool {` — re-derive this guard.")
        }
        XCTAssertTrue(body.contains("framesFlowing"), """
            `isLocked` no longer asks whether camera frames are arriving. Its three remaining \
            terms all judge the last READING, and a frozen analyzer keeps every one of them \
            true — so the header pill shows a green lock and a confident bpm while the publish \
            loop bails on `inboundRateEMA >= minMeasurableInboundHz` and the bus gets nothing. \
            Restore the `framesFlowing` term, or move the frame-flow fact into whatever \
            replaces it and re-point this guard.
            """)
    }

    // 2 — the term is the PUBLISH PATH's own two facts. If the lock and the bus gate disagree
    // about what "frames are arriving" means, one of the two surfaces is lying again.
    func testFrameFlowIsTheSameTwoFactsThePublishGateUses() throws {
        let text = try source(Self.publisher)
        guard let range = text.range(of: "let flowing = ") else {
            return XCTFail("ANCHOR MISSING: the `let flowing = ` assignment — re-derive this guard.")
        }
        let assignment = String(text[range.lowerBound...].prefix(400))
        XCTAssertTrue(assignment.contains("capture.isInterrupted"), """
            The frame-flow term no longer consults `capture.isInterrupted`. That is the ONE \
            state where zero frames is certain immediately; without it the lock stays green \
            for about a second of EMA decay every time iOS takes the camera.
            """)
        XCTAssertTrue(assignment.contains("inboundRateEMA")
                      && assignment.contains("minMeasurableInboundHz"), """
            The frame-flow term no longer uses the measured inbound rate against \
            `minMeasurableInboundHz`. That threshold IS the publish gate's condition; using \
            anything else lets the lock and the bus disagree about the same camera.
            """)
    }

    // 3 — COUNTERWEIGHT, and the trap this slice was written to avoid. `recoveryState` looks
    // like the obvious source of truth and is NOT: `.cooling` also fires on
    // `ProcessInfo.thermalState` alone, while frames keep flowing perfectly well. Gating the
    // lock on the banner would blank a working readout on a warm phone — a new lie replacing
    // the old one. This guard does not forbid a better term (#364); it forbids THAT one.
    func testTheLockIsNotGatedOnTheThermalBanner() throws {
        let text = try source(Self.publisher)
        guard let body = memberBody(from: "public var isLocked: Bool {", in: text),
              let range = text.range(of: "let flowing = ") else {
            return XCTFail("ANCHOR MISSING: `isLocked` or `let flowing = ` — re-derive this guard.")
        }
        let assignment = String(text[range.lowerBound...].prefix(400))
        for (name, code) in [("isLocked", body), ("the frame-flow assignment", assignment)] {
            XCTAssertFalse(code.contains("recoveryState"), """
                \(name) now reads `recoveryState`. `.cooling` fires on thermal state alone \
                while frames still arrive, so this turns a warm phone into a dead readout — \
                the same class of dishonest control, pointing the other way. Ask the frame \
                rate, not the banner.
                """)
        }
    }

    // 4 — the observable stays LOW-FREQUENCY. It is written inside a ~10 Hz tick, so an
    // unconditional assignment would notify every observer ten times a second and drag the
    // 10.76.50 freeze law onto whichever leaf reads the lock.
    func testTheFlagIsAssignedOnlyOnChange() throws {
        let text = try source(Self.publisher)
        XCTAssertTrue(text.contains("if flowing != self.framesFlowing { self.framesFlowing = flowing }"), """
            The frame-flow flag is no longer assigned only on CHANGE. It lives in the ~10 Hz \
            publish tick; an unconditional write notifies every observer of this @Observable \
            ten times a second, which is exactly the churn the header pill was split into a \
            leaf to avoid.
            """)
        XCTAssertFalse(text.contains("@ObservationIgnored public private(set) var framesFlowing"), """
            The frame-flow flag was made `@ObservationIgnored`. It would then notify nobody — \
            and when frames stop, `detectedBPM` and `confidence` stop changing too, so a header \
            leaf would keep rendering its last frame forever and never learn the camera went \
            quiet. Being observable is the entire point of storing it.
            """)
    }

    // 5 — a fresh take never opens on a stale stall. Both non-tick reset blocks (the start
    // path and `stop()`) already re-seed `inboundRateEMA` and `recoveryState`; the flag must
    // travel with them or the first tick of the next session shows a lock that cannot lock.
    func testEveryResetClearsTheStall() throws {
        let text = try source(Self.publisher)
        // Newline + the method-body indent, so the DECLARATION's own `= true` default
        // (four spaces, after `var `) is not counted as a third reset site.
        let resets = text.components(separatedBy: "\n        framesFlowing = true").count - 1
        XCTAssertEqual(resets, 2, """
            Expected exactly two `framesFlowing = true` reset sites (the start path and \
            `stop()`), found \(resets). Both re-seed `inboundRateEMA` and `recoveryState` for \
            the same reason: a new placement must not inherit the previous take's stall.
            """)
        for anchor in ["recoveringTicks = 0\n        recoveryState = .healthy\n        framesFlowing = true"] {
            XCTAssertTrue(text.contains(anchor), """
                A reset site sets `recoveryState` back to `.healthy` without clearing \
                `framesFlowing`. The two describe the same camera; resetting one and not the \
                other leaves the next session's first tick disagreeing with itself.
                """)
        }
    }

    // NEEDS-FOUNDER-VERIFY: run a take, then background the app (or let the phone get hot
    // enough to throttle the feed) and look at the header pill. The lock light should go dark
    // within about a second and the bpm should stop reading as confirmed. Say whether that
    // reads as HONEST or as BROKEN — if it reads as broken, the missing half is a sentence in
    // the pill's status slot ("Camera paused"), which is its own slice, not a wider gate here.
}
