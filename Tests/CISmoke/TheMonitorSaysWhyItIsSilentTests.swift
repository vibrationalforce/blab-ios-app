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

// ⛔ #1024 (2026-09-06) — ONE OF THE TWO DOORS IS GONE BY FOUNDER ORDER. "das mit dem
// Audio Input Monitoren klappt immer noch nicht also fliegt das raus", said twice, the
// second time over a screenshot of build 448/2567 circling the mix-board card. The three
// microphone doors were removed, so `EchoelStudioView` carries no monitor strip, no
// engine-stopped branch and no silence line. Claim 1 is INVERTED below and quotes its two
// original needles; claim 3 lost its studio half for the same reason. Claim 2 and the rest
// of claim 3 are untouched and still guard the SURVIVING door, `AudioInputPickerView` —
// which is also where `!degraded` mattered MORE all along, because AudioDegradedRow is
// invisible under that sheet. Everything this file says about WHY the sentence exists is
// unchanged; only the mix-board site is gone.

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

    // MARK: - claim 1 — the mix-board door is GONE (#1024, inverted)

    /// ⛔ INVERTED BY #1024. This asserted that `EchoelStudioView` contained
    /// `else if audioEngine.isInputMonitoring && !audioEngine.isRunning && !audioEngine.degraded {`
    /// and, inside it, `Self.silenceLine`. Both needles are quoted here so a re-door restores
    /// this method verbatim instead of re-deriving the #605/#605b reasoning. Left as it stood
    /// it would be RED on a CORRECT tree — the tangle the founder's second sentence named
    /// ("erst wird munter drauf los programmiert und dann verhäddert es sich").
    ///
    /// ⭐ THE LAW IS NOT RETRACTED, only its second site. Claim 2 still proves that a door
    /// showing a live monitor must explain the paused-engine state, and still proves the
    /// `!degraded` gate — which was always the more important of the two, because
    /// `AudioDegradedRow` is invisible under the sheet.
    func testTheMixBoardNoLongerHasAMonitorToExplain() throws {
        let code = try source(Self.studio)
        for needle in [
            "else if audioEngine.isInputMonitoring && !audioEngine.isRunning && !audioEngine.degraded {",
            Self.silenceLine,
        ] {
            XCTAssertFalse(code.contains(needle), """
                The mix board carries `\(needle)` again. THIS IS NOT AUTOMATICALLY A BUG — \
                the founder may have asked for the microphone doors back (#1024). But it is \
                HIS decision, and re-dooring means restoring this method and claim 3's studio \
                half to their pre-#1024 form (both needles are quoted in the comment above) \
                and pulling the prose homes listed in `TheMicrophoneHasNoDoorTests` along in \
                the SAME commit.
                """)
        }
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
        // ⛔ #1024 removed this claim's studio half. It asserted
        // `studio.contains("if micMonitorRefused && !audioEngine.isInputMonitoring {")` —
        // the mix board's #601b refusal gate, which the silence line was written BEHIND so a
        // denied microphone could not fall through to "wait for the call to end". The gate
        // went with the mic doors; the LAW (refusal branch first, silence branch second) is
        // unchanged and still proven on the picker in the assertion below. `studio` is kept
        // and re-pointed at the inverse, so this counterweight still says something.
        XCTAssertFalse(studio.contains("if micMonitorRefused && !audioEngine.isInputMonitoring {"), """
            The mix board's #601b refusal gate is back (#1024). Restore this assertion to its
            pre-#1024 `XCTAssertTrue` form in the same commit — the ordering law it pins
            (refusal branch, THEN silence branch) applies again the moment the strip returns.
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
