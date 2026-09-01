// TheInputTapAsksTheNodeForItsFormatTests.swift
// Echoel — #956. Blocking bundle. **SOURCE-TEXT SCAN** (`Tests/CISmoke/CLAUDE.md` §1): every
// claim reads `Sources/Echoelmusic/Audio/AudioEngine.swift` through `SourceText.codeOnly`.
// Nothing here starts an engine — an `AVAudioEngine` graph cannot be built in this bundle, and
// the defect is an ABORT inside Apple's code, which a test could not survive observing anyway.
//
// ⭐ THE DEFECT, and it is the SECOND abort on the toggle the founder reported. `installTap`
// validates its `format:` against the NODE's own bus format. Since #954 the variable that was
// being handed to it — `inFmt` — may be a SESSION substitute, deliberately different from what
// the node reported (that substitution is #954's fix for the CONNECT edge and stays). Handing a
// deliberately-different format to `installTap` is the same `required condition is false`
// family as `isInputConnToConverter`, one rung later, and equally uncatchable from Swift.
//
// ⚠️ AND IT WAS NOT ONLY AN ABORT RISK. Two fields recorded beside the tap feed arithmetic:
//   · `monitorTapSampleRate` → `PitchTracker.detect(_:sampleRate:)`. A 44.1↔48 substitution
//     shifts every detected pitch by ~147 cents, so "Tune to key" snaps the voice to WRONG
//     notes — silently, with no abort at all;
//   · `monitorTapSampleRate`/`monitorTapChannelCount` → the #612/#826 configuration-change
//     gate, which compares a LIVE node format against them. Recording a format the node never
//     had makes that comparison mismatch on every change, i.e. a re-arm loop.
// ⛔ AND THE SENTENCE THAT STOOD HERE — "the wrong-format path had three outcomes and only
// one of them was loud" — IS RETRACTED (#956b, reviewer). Both mechanisms above are real and
// were verified at their call sites; their JOINT reachability was not. `inFmt` differs from the
// node's format only on the substitution branch, where either the node still disagrees (abort,
// so nothing silent is ever observed) or it has caught up after the restart (the formats agree,
// so there is no wrong rate to record). Under this fix's own abort premise the silent pair is
// UNREACHABLE, not quiet. The fix stands as DEFENCE IN DEPTH: if `installTap` tolerates some
// mismatch shapes, the tolerated ones land exactly there. A weaker reason, and the true one.
//
// ⚠️ EPOCH 2 — #956b, the mandatory reviewer on #956. IT FOUND THREE RED ASSERTIONS IN TWO
// EXISTING BLOCKING GUARDS that #956 had caused, and the four standing instruments were
// STRUCTURALLY BLIND to all three — two of them say so in their own `--all` output ("interpolated
// needle", "`code` not bound to a path"). `dead-needles` only finds needles matching NOTHING; a
// needle whose COUNT changed still matches. So "Instrumente grün" was true as printed and
// worthless as coverage — the #937 lesson, one tool layer up. What was red, and the repair:
//   · `TheInputEdgeFollowsTheHardwareFormatTests` pinned `input.inputFormat(forBus: 0)` at ONE
//     and #956 made it two. That is not a spelling drift: the claim's own failure text states
//     the law "the decision must happen ONCE and be carried in `inFmt`". Repaired by reading the
//     OUTPUT scope at the tap — which is what `installTap` validates against and what every
//     other tap in this repo already reads — so the law stays literally true, plus a sibling
//     pin there on that one read;
//   · `TheEngineLifecycleSpeaksInTheDiagLogTests` pinned `on 5/5` at exactly 2 and its SKIPPED
//     at exactly 1. #956 added a second legitimate skip reason. An EQUALITY there forbids the
//     next honest reason (#364); the property is "at least one taken AND at least one skipped".
//   · Two prose twins about "a death INSIDE installTap" were left stale in a third file (#456:
//     a repair goes into every home), and my own claim 5 pinned the message STRING while a
//     `return false` on the next line would have kept it green.
//
// ⚠️ HONEST GRADING (§3), EPOCH 1 as amended. **13 assertion SITES** (Python, lines whose first token is
// `XCTAssert`; ⛔ my first draft of this header said 8 — a loop hides its own arithmetic and
// that has now cost a grading in this bundle four times). Two of those sites live inside loops,
// so the number of assertions EXECUTED is higher and is not a countable property of the file.
// This file names no symbol the commit creates, so it COMPILES against the parent and every
// claim has a verdict there. Transcribed against `c6a6787` (predicates reimplemented in Python,
// driven over both trees): **7 RED on the parent, 0 on the worktree** — and #956b additionally
// drove the TWO NEIGHBOUR guards' pins over both trees, because this slice reddened three of
// them; all are green here now. Red were claim 1, both
// halves of claim 2, claim 4, claim 5 and claim 6's rung count. GREEN on BOTH trees — the
// COUNTERWEIGHTS in the strict #343 sense — are claim 3 (#954's connect format survives), claim
// 6's no-triple-quote half and claim 7 (the installed flag stays a single site).
//
// ⛔ AND CLAIM 1 CAUGHT ME MID-SLICE, which is the reason the grading is worth its cost. Its
// first draft asked for `occurrences(of: "format: inFmt") == 0` across the file — and `inFmt`
// is the CORRECT argument for the three `connect(…, format: inFmt)` calls, i.e. #954's fix. The
// broad form stayed red on a correct worktree and would have forbidden correct work (#364). The
// transcription showed it in one run; a hand-read would not have.
//
// ⚠️ WHAT THIS DOES NOT PROVE. Nothing here runs on a device, so it does not show that the
// abort was ever reached in the wild — the founder's v10.79.433 log died at the CONNECT, not
// here, and v10.79.434 repaired that edge. This is a structurally reachable second path on the
// same toggle, closed before it is observed. Saying it fixed his crash would be a claim no
// artifact in this repo supports.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheInputTapAsksTheNodeForItsFormatTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    private func source() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.engine), encoding: .utf8))
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// claim 1 (THE FIX) — no `installTap` in this file is handed the connect-time format.
    ///
    /// ⛔ THE FIRST DRAFT ASKED FOR `occurrences(of: "format: inFmt") == 0` AND THAT WAS A #364
    /// VIOLATION I CAUGHT BY GRADING IT: `inFmt` is the RIGHT argument for the three
    /// `connect(…, format: inFmt)` calls — that IS #954's fix — so the broad form forbade
    /// correct work and stayed red on a correct tree. The scan now looks only at what follows
    /// an `installTap(`.
    func testNoInstallTapIsHandedTheConnectTimeFormat() throws {
        let code = try source()
        let afterEachTap = code.components(separatedBy: "installTap(").dropFirst()
        XCTAssertFalse(afterEachTap.isEmpty, """
            No `installTap(` at all in \(Self.engine). This claim has stopped selecting the \
            thing it names and would report GREEN on nothing (#454) — re-anchor it.
            """)
        for tap in afterEachTap {
            // ⚠️ 400, not 200, AND the window must actually CONTAIN `format:`. `codeOnly`
            // blanks comment TEXT but keeps the lines, so two or three indented comment lines
            // between `installTap(` and its `format:` walk the argument out of a tight window
            // and this claim goes VACUOUSLY green (#926). The presence check is what turns
            // that into a red instead of a pass; `window-margins.py` does not measure a
            // `.prefix` on a `components(separatedBy:)` slice, so nothing else would notice.
            let args = String(tap.prefix(400))
            XCTAssertTrue(args.contains("format:"), """
                An `installTap(` in \(Self.engine) has no `format:` within 400 characters. \
                Either the call lost its format argument or the window no longer reaches it — \
                in which case the assertion below stops selecting anything and passes on \
                nothing. Widen the window or anchor on the call's closing paren.
                """)
            XCTAssertFalse(args.contains("format: inFmt"), """
                An `installTap` is handed `format: inFmt` in \(Self.engine). Since #954 `inFmt` \
                may be a SESSION substitute the node never reported, while `installTap` \
                validates against the NODE's own bus format — an uncatchable ObjC abort on the \
                monitor toggle, the same family as `isInputConnToConverter`, one rung later. \
                Read the node at the tap. ⚠️ Do NOT "fix" this by changing a \
                `connect(…, format: inFmt)`: those three are correct and claim 3 pins them.
                """)
        }
    }

    /// claim 2 (THE FIX) — the node is asked again, at the tap, for the format the tap uses.
    func testTheTapReadsTheNodeFormatItself() throws {
        let code = try source()
        XCTAssertTrue(code.contains("let tapFmt = input.outputFormat(forBus: 0)"), """
            Nothing re-reads the node's OUTPUT format at the tap site. The format captured at \
            the top of the ON path has since survived a connect, an engine restart and a \
            possible session substitution; the node is the only authority for its own bus. \
            ⚠️ `outputFormat`, not `inputFormat`: a tap installs on an OUTPUT bus and \
            `installTap` validates against that scope — which is also what every other tap in \
            this repo reads, and what keeps `TheInputEdgeFollowsTheHardwareFormatTests`' \
            "the raw decision is read once" law literally true.
            """)
        XCTAssertTrue(code.contains("format: tapFmt"), """
            The tap does not install with `tapFmt`. Reading the node and then passing something \
            else is the same defect with an extra step.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — #954's CONNECT format is untouched. This slice repairs the tap
    /// only; taking the session substitution out of the connect would reopen the crash the
    /// founder actually hit.
    func testTheConnectStillUsesTheHardwareAgreeingFormat() throws {
        let code = try source()
        XCTAssertTrue(code.contains("let nodeDisagreesWithHardware"), """
            #954's hardware-agreement check is gone from \(Self.engine). That check is what makes \
            the CONNECT edge survive a node/route disagreement — the v10.79.433 crash. A tap fix \
            must not take it with it.
            """)
        XCTAssertTrue(code.contains("inFmt = fallback"), """
            The session substitution no longer reaches `inFmt`. #954 exists because the node's \
            own format can be stale at connect time; only the TAP argument was wrong.
            """)
    }

    /// claim 4 (THE FIX) — the two recorded fields describe the format the tap actually uses.
    /// This is the half that was silent: YIN and the #612/#826 gate both divide by this rate.
    func testTheRecordedFieldsComeFromTheInstalledFormat() throws {
        let code = try source()
        XCTAssertTrue(code.contains("monitorTapSampleRate = tapFmt.sampleRate")
                      && code.contains("monitorTapChannelCount = tapFmt.channelCount"), """
            The recorded tap format does not come from `tapFmt`. Then `PitchTracker.detect` is \
            handed a rate the tap never ran at (a 44.1↔48 substitution moves every detected \
            pitch ~147 cents, so "Tune to key" targets the wrong notes) and the #612/#826 \
            configuration gate compares the live node against a format it never had, re-arming \
            on every change. Neither failure is loud.
            """)
    }

    /// claim 5 (COUNTERWEIGHT) — an unusable node format must SKIP the tap, not tear the
    /// monitor down. By this point the chain is connected and the engine is running; a
    /// `return false` here would take a working monitor away over an analysis feature.
    func testAnUnusableTapFormatSkipsInsteadOfFailing() throws {
        let code = try source()
        XCTAssertTrue(code.contains("on 5/5 SKIPPED: node reports no usable tap format"), """
            There is no SKIPPED outcome for an unusable node format at the tap. Either the code \
            aborts (guard-less `installTap`) or it tears down a monitor that is already working. \
            The ladder's own law is that a step which does not run must SAY it did not (#882).
            """)
        // ⛔ THE MESSAGE ALONE WAS NOT THE PROPERTY. A `return false` on the next line would
        // keep the assertion above green while destroying exactly what this claim is named for:
        // monitoring SURVIVES a missing tap. Pin the branch, not the string — the (c3) scan in
        // `TheEngineLifecycleSpeaksInTheDiagLogTests` is the pattern reused here.
        if let skip = code.range(of: "on 5/5 SKIPPED: node reports no usable tap format") {
            let branch = String(code[skip.lowerBound...].prefix(400))
            XCTAssertFalse(branch.contains("return false"), """
                The unusable-format skip is followed by `return false` — it tears the monitor \
                down after all. By this rung the chain is connected and the engine is running; \
                losing the notch defence and pitch tracking is a degradation, losing the \
                monitor is a regression.
                """)
        }
    }

    /// claim 6 (COUNTERWEIGHT, and the one that keeps the LADDER honest) — every `on 5/5` rung
    /// literal stays on ONE source line. `scripts/diag-ladder.py --source` finds emitters by
    /// scanning source text; a multi-line `"""` rung made it report the step as MISSING, i.e. a
    /// healthy run would read as a death. That happened during #954 and was caught by the tool.
    func testEveryFifthRungLiteralIsOnOneSourceLine() throws {
        let code = try source()
        let rungLines = code.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("on 5/5") }
        XCTAssertGreaterThanOrEqual(rungLines.count, 3, """
            Fewer than three `on 5/5` lines in \(Self.engine): the install, the \
            already-installed skip and the unusable-format skip. If a rung was removed, the \
            ladder promises a step that cannot speak.
            """)
        for line in rungLines {
            XCTAssertFalse(line.contains("\"\"\""), """
                An `on 5/5` rung is written as a multi-line string literal: \(line.trimmingCharacters(in: .whitespaces))
                `diag-ladder.py --source` then cannot see the emitter and reports step 5 as \
                MISSING — a healthy run reads as a death at step 4. Keep the marker text on one \
                source line; the DETAIL may be concatenated after it.
                """)
        }
    }

    /// claim 7 (COUNTERWEIGHT) — the tap is still installed exactly once per ON, behind
    /// `monitorTapInstalled`. Moving the flag inside a new branch is the obvious way to break
    /// this: set it unconditionally and a skipped tap reads as installed forever.
    func testTheInstalledFlagIsSetOnlyWhereATapWasInstalled() throws {
        let code = try source()
        XCTAssertEqual(occurrences(of: "monitorTapInstalled = true", in: code), 1, """
            `monitorTapInstalled = true` no longer appears exactly once. A second site — or the \
            same site moved out of the branch that actually installs — makes a SKIPPED tap read \
            as installed, and the OFF path would then `removeTap` a bus that has none.
            """)
    }
}
