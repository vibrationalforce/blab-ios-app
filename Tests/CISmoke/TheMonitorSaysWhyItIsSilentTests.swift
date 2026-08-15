// TheMonitorSaysWhyItIsSilentTests.swift
// Echoel — #605 (GUI-Board Scheibe 2, from the #603 UX audit's finding #9).
//
// WHAT THIS GUARDS. `AudioEngine.setInputMonitoring(true)` wires the monitor graph but
// starts the engine ONLY if it was already running (`wasRunning` — read the function).
// So `isInputMonitoring == true` with `isRunning == false` is a real, reachable state:
// the toggle shows ON, the mic path is wired, and NOTHING sounds — most commonly the
// window while a call/Siri/alarm interruption holds the session paused. #601b gave both
// monitoring doors a REFUSAL line (permission denied); this slice gives both doors the
// SILENCE line for the stopped-engine case, gated on the same #485 principle: the ENGINE
// is the single source of truth, so the line clears itself the moment audio resumes.
//
// ⚠️ WHAT IT DELIBERATELY DOES NOT DO: no retry button. The interruption case heals
// itself on the `.active` return (the resume gate), and the gave-up case sets `degraded`,
// which `AudioDegradedRow` already explains WITH the retry (`audioEngine.start()`).
// Duplicating that button here would put two competing "fix audio" affordances on screen.
// Claim 3 pins that division of labour.
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN (§1). Nothing here renders the line or drives the engine
// state; whether the sentence is legible and correctly timed is a device probe. The
// freeze-law argument (both reads are event-rate: `isRunning` changes a handful of times
// per session, `isInputMonitoring` on user toggles) lives in prose at the read sites.
//
// ⚠️ HONEST GRADING (#433/#464) — transcribed in Python against the parent (ba6b72e) and
// this tree. 7 assertions in 3 tests, hand-counted: claims 1 (2) + 2 (2) + 3 (3).
// Against the PARENT: FOUR are red as ONE finding (#486) — the two gate needles and the
// two copy needles name lines born with this commit, FORWARD. Claim 3's three are
// COUNTERWEIGHTS, green on both trees (the #601b refusal lines and the degraded row's
// retry predate this slice). ZERO regressions claimed, because zero exist.
// `SourceText.codeOnly` is PROPHYLAKTISCH here, MEASURED (#453): 0 of 7 verdicts flip
// raw-vs-stripped on either tree — no needle below is quoted whole in a comment (the
// #605b comments quote "comes back by itself", a SUBSTRING of the copy needle; a
// substring cannot green a `contains` of the full sentence).
//
// ⛔ #605b (same review cycle): both gate needles gained `&& !audioEngine.degraded`.
// The review found the sentence's promise FALSE exactly in the degraded state — and in
// the sheet the false promise would have stood ALONE (AudioDegradedRow is invisible
// under it). Against fe1390c (the #605 first cut) the two gate needles are red by that
// widening — deliberate, one finding; the copy needles and counterweights are unchanged.

import Foundation
import XCTest

final class TheMonitorSaysWhyItIsSilentTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"
    private static let degradedRow = "Sources/Echoelmusic/Studio/AudioDegradedRow.swift"

    /// The one sentence, shared by both doors — one state, one wording. If it changes,
    /// change it in BOTH doors and here, in the same commit.
    private static let silenceLine =
        "Monitoring is on, but audio is paused — it comes back by itself when the call, alarm or Siri ends."

    // MARK: - claim 1 — the mix-board door says why it is silent

    func testTheMixBoardDoorCarriesTheSilenceLine() throws {
        let code = try source(Self.studio)
        XCTAssertTrue(code.contains("else if audioEngine.isInputMonitoring && !audioEngine.isRunning && !audioEngine.degraded {"), """
            The mix board's monitor strip lost its engine-stopped branch (or its gate \
            changed). Without it the Monitor toggle can show ON while the engine is paused \
            (a call, Siri, an alarm) and the card explains nothing — UX audit #9, the state \
            #601b's refusal line cannot see because permission was granted. The `!degraded` \
            half is #605b: the sentence promises audio "comes back by itself", which is \
            FALSE exactly when self-heal gave up — that state belongs to AudioDegradedRow \
            (cause + Retry), and without the gate the two sat on screen contradicting each \
            other. The branch must stay BETWEEN the refusal line and the headphone hint.
            """)
        XCTAssertTrue(code.contains(Self.silenceLine), """
            The mix-board silence sentence changed or vanished. It is deliberately \
            identical in both doors (one state, one wording) — if this is a rewording, \
            update the picker door and this guard's `silenceLine` in the same commit.
            """)
    }

    // MARK: - claim 2 — the input sheet says it too

    func testTheInputSheetCarriesTheSilenceLine() throws {
        let code = try source(Self.picker)
        XCTAssertTrue(code.contains("if !audioEngine.isRunning && !audioEngine.degraded {"), """
            The input sheet's monitoring section lost its engine-stopped branch (or its \
            gate changed). It sits INSIDE `if audioEngine.isInputMonitoring` (that block \
            only renders while the toggle is on), so the check there IS the same compound \
            gate the mix board spells out. `!degraded` matters MORE here than in the strip \
            (#605b): AudioDegradedRow is invisible under this sheet, so without the gate \
            the degraded case would show the false "comes back by itself" promise as the \
            ONLY sentence on screen, with the real recovery a dismiss away and unnamed.
            """)
        XCTAssertTrue(code.contains(Self.silenceLine), """
            The input-sheet silence sentence changed or vanished — see claim 1's message: \
            one state, one wording, two doors, same commit.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHTS, #343) — the neighbours this line leans on

    func testTheNeighbouringExplanationsSurvive() throws {
        let studio = try source(Self.studio)
        let picker = try source(Self.picker)
        let degraded = try source(Self.degradedRow)
        XCTAssertTrue(studio.contains("if micMonitorRefused && !audioEngine.isInputMonitoring {"), """
            The mix board's #601b refusal gate is gone. The silence line is written as the \
            `else if` BEHIND it — without the refusal branch, a denied microphone would fall \
            through to the silence line and tell the user to wait for a call to end instead \
            of pointing at Settings.
            """)
        XCTAssertTrue(picker.contains("if monitorRefused && !audioEngine.isInputMonitoring {"), """
            The input sheet's #601b refusal gate is gone — same consequence as the mix \
            board's: the wrong explanation for a denied mic.
            """)
        XCTAssertTrue(degraded.contains("audioEngine.start()"), """
            `AudioDegradedRow` lost its retry call. The silence line deliberately carries \
            NO button because that row owns the recovery affordance for the gave-up case — \
            if the retry moved or died, the silence line's "no button" decision needs \
            re-judging, not silent inheritance.
            """)
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
