import XCTest
@testable import Echoelmusic

/// #1014 — when the camera stops feeding, the header pulse pill must say WHY, not hand out a
/// remedy no finger can act on.
///
/// WHY IT EXISTS. #992 fixed the louder half at the source: `isLocked` carries `framesFlowing`,
/// so an iOS interruption or a thermal trickle correctly drops the green lock. It did not fix
/// the sentence that takes the lock's place. `acquisitionCue` is derived from the analyzer's
/// LAST frame, and a frozen analyzer keeps answering with the last placement it saw — so the
/// pill went amber with "Cover the rear camera + flash" while iOS was holding the session. A
/// wrong remedy costs more than none: the performer stops playing and adjusts a finger for
/// something no finger can fix.
///
/// ⭐ THE LAW IS NOT NEW, THE SURFACE IS. `BioStripView` already states the precedence in its own
/// doc — the recovery hint wins over placement coaching whenever `recoveryState.userHint != nil`.
/// The strip sits behind the Bio panel; this pill is the only pulse surface visible WHILE
/// PERFORMING, and it was the one without the rule. Claim 5 pins that the strip keeps its half,
/// so the two surfaces cannot drift into two different answers about the same camera.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. It renders no SwiftUI and runs no camera. Whether "Camera
/// paused" in a `minWidth: 28` slot reads as honest rather than broken is a device question —
/// NEEDS-FOUNDER-VERIFY at the foot of this file.
///
/// GRADING (written AFTER transcription, and the transcription changed it). Claims 1–3 are RED
/// on `HEAD`, green on the worktree: each names a construct this commit introduces — 3 does not
/// even compile there, since `RPPGRecoveryState.shortLabel` does not exist yet. Claims 4, 5 and 6
/// are GREEN on BOTH: 4's needle is an ABSENCE, 5 and 6 point at code this commit does not touch.
/// That split is the only one available — a claim can be green on both trees only when its needle
/// is an absence or sits on unchanged code.
///
/// ⛔ AND CLAIM 4 WAS RED ON THE WORKTREE IN ITS FIRST DRAFT, on a correct tree. Its forbidden
/// phrase is spelled out verbatim in the comment that EXPLAINS the gate, three files' worth of
/// this repo's habit of quoting what it rejects (#491). `codeOnly` is the repair, and it is why
/// the grading line is written after transcribing rather than guessed before.
final class TheStalledPillSaysWhySilentTests: XCTestCase {

    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"

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

    // 1 — the pill asks whether frames are arriving before it trusts the cue.
    func testThePillGatesItsHintOnFramesActuallyArriving() throws {
        let text = try source(Self.header)
        XCTAssertTrue(text.contains("!cameraRPPG.framesFlowing"), """
            The header pill no longer asks whether camera frames are arriving before it decides \
            what to say. Without that term `acquisitionCue` — computed from the analyzer's last, \
            frozen frame — keeps offering a placement remedy while iOS holds the session.
            """)
    }

    // 2 — the recovery hint OUTRANKS the stale placement cue, because inside the pill
    //     `showCue` beats `showStatus` and would otherwise win the single line.
    func testTheStaleCueIsSuppressedWhileARecoveryHintExists() throws {
        let text = try source(Self.header)
        XCTAssertTrue(text.contains("cue: recoveryStatus != nil ? nil"), """
            The pill no longer suppresses the placement cue while a recovery hint exists. \
            `PulseMonitorMini.showCue` is `!locked && cue.isActionable` and `showStatus` is \
            `!locked && !showCue && status != nil`, so a cue left in place wins the one line and \
            the hint is never seen — the defect looks fixed and is not.
            """)
    }

    // 3 — BEHAVIOURAL. The short form exists for exactly the states that have a long form, so a
    //     caller may require both and can never be handed half an answer.
    func testEveryStateWithASentenceAlsoHasAShortLabel() {
        for state: RPPGRecoveryState in [.healthy, .recovering, .cooling, .interrupted] {
            XCTAssertEqual(state.userHint == nil, state.shortLabel == nil, """
                `RPPGRecoveryState.\(state)` has one of the two strings and not the other. The \
                header requires BOTH (short for the 28 pt slot, full for VoiceOver), so a state \
                with only one silently falls through to the stale cue this guard exists to stop.
                """)
        }
        XCTAssertNil(RPPGRecoveryState.healthy.shortLabel,
                     "a healthy camera must produce no header text at all")
        XCTAssertEqual(RPPGRecoveryState.interrupted.shortLabel, "Camera paused")
    }

    /// Non-empty lines with `//` comments removed. DEFENSIVE AND LOAD-BEARING, not tidiness:
    /// claim 4 forbids a phrase that the paragraph EXPLAINING claim 4 spells out verbatim, in
    /// this same repo's own habit of quoting what it rejects. The first draft of this guard was
    /// red on a correct tree for exactly that reason (#491), caught by transcribing it before
    /// committing. A negative scan must read CODE, never the prose that justifies it.
    private func codeOnly(_ text: String) -> String {
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let r = line.range(of: "//") {
                let before = line[line.startIndex..<r.lowerBound]
                if before.filter({ $0 == "\"" }).count % 2 == 0 { line = String(before) }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out.joined(separator: "\n")
    }

    // 4 — COUNTERWEIGHT, and the needle is an ABSENCE. The gate must not become the banner:
    //     `.cooling` fires on thermal state alone while frames arrive fine, so gating on
    //     `recoveryState` would replace a live, actionable placement cue on a merely warm phone.
    func testTheGateIsFrameFlowAndNotTheThermalBanner() throws {
        let text = codeOnly(try source(Self.header))
        for wrong in ["recoveryState == .healthy", "recoveryState != .healthy"] {
            XCTAssertFalse(text.contains(wrong), """
                The pill gates on `\(wrong)`. That is the thermal BANNER, not frame flow: \
                `.cooling` also fires on `ProcessInfo.thermalState` while frames keep arriving, \
                so this blanks a working readout on a warm phone. The two facts are measured in \
                the same tick — use `framesFlowing`.
                """)
        }
    }

    // 5 — COUNTERWEIGHT. The strip keeps the long-form banner it already owned. Two surfaces,
    //     one source of truth; if this disappears, the wide banner and the pill can disagree.
    func testTheBioStripStillOwnsTheLongFormBanner() throws {
        let text = try source(Self.strip)
        XCTAssertTrue(text.contains("cameraRPPG.recoveryState.userHint"), """
            `BioStripView` no longer renders the recovery sentence. The pill's short label is an \
            abbreviation OF that sentence — if the strip stops showing it, the only full \
            explanation of a paused camera has left the app.
            """)
    }

    // 6 — the publisher still measures both facts in one tick, which is what lets claim 4 be
    //     cheap. If they were measured apart, gating on frame flow could disagree with the state.
    func testBothFactsAreStillMeasuredInTheSameTick() throws {
        let text = try source(Self.publisher)
        XCTAssertTrue(text.contains("if newRecovery != self.recoveryState { self.recoveryState = newRecovery }"), """
            ANCHOR MOVED: the recovery-state assignment. This guard's reasoning — that \
            `framesFlowing == false` implies `.interrupted`/`.recovering`/`.cooling` outside the \
            warm-up window — rests on the two being computed from the same `capture.isInterrupted` \
            and `inboundRateEMA` in one pass. Re-derive it before trusting claim 4.
            """)
        XCTAssertTrue(text.contains("if flowing != self.framesFlowing { self.framesFlowing = flowing }"), """
            ANCHOR MOVED: the `framesFlowing` assignment (also pinned by \
            `TheLockNeedsFramesTests`). See above.
            """)
    }

    // NEEDS-FOUNDER-VERIFY: cover the lens, then background the app (or let the phone get hot)
    // while a take runs. The pill must drop its green lock AND read "Camera paused" / "Cooling"
    // rather than an amber placement cue. Judgement asked: does the short label read as honest,
    // or does it read as the app being broken?
}
