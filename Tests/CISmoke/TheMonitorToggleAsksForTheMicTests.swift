// TheMonitorToggleAsksForTheMicTests.swift
// Echoel — #601. Founder: "Audio in funktioniert bisher nicht das sollte vermieden werden."
//
// WHAT THIS GUARDS. Before #601, BOTH doors to live input monitoring — the Mix board's
// "Monitor" toggle (`micMixStrip`) and the Audio-input sheet's "Live monitoring" toggle
// (`AudioInputPickerView`) — called `AudioEngine.setInputMonitoring(true)` directly. That
// method reads `inputNode.inputFormat(forBus: 0)`, and with mic permission UNDETERMINED
// iOS reports a 0 Hz format, so the call bailed with only a log ("mic permission?") and
// returned false. **No code path on either toggle ever requested the permission**, so on a
// fresh install the system dialog never appeared: the switch flipped back silently, forever.
// The one path that DOES ask (`MicrophoneManager.startRecording` → `requestPermission`) is
// the voice-capture path — a different door the founder wasn't at.
//
// THE FIX SHAPE. One permission-aware front door, `AudioEngine.engageInputMonitoring()`
// (async): `.granted` falls through, `.undetermined` awaits the system dialog and engages
// only on grant, `.denied` returns false without touching the record route — the refusal
// copy ("check microphone access in Settings") is then literally the right advice. Both
// toggles' ON paths go through it; their OFF paths keep calling `setInputMonitoring(false)`
// synchronously (no dialog is ever needed to STOP listening).
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN, every assertion. Nothing here can present a permission
// dialog, run an AVAudioSession, or verify that iOS actually shows the alert; that is a
// device probe and stays with the founder (the whole point of the slice is that it now CAN
// happen on device). What the scans carry: the asker exists, both doors route through it,
// and the dialog-free paths this repo already guards did not silently change meaning.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (a9c0cb5) and this tree
// (#433/#464; there is no local compiler, transcription is the grade). 19 assertions in 5
// tests, hand-counted: claims 1 (5) + 2 (3) + 3 (4) + 4 (5) + 5 (2). On THIS tree all 19
// pass in transcription. Claim 3's last two are the #601b review addendum (the picker's
// own refusal surface — `monitorRefused` verdict write + engine-gated copy) and are
// forward against BOTH a9c0cb5 and the first #601 commit (c4c15ee): the symbol is born
// with the addendum. Against the PARENT, TWO findings (#486), both FORWARD:
// (a) `engageInputMonitoring` does not exist there, so all 10 assertions naming it are
// absent together — one absence, reported 10 times (claim 1's 5, claim 2's first two,
// claim 3's first, claim 5's two);
// (b) the literal `setInputMonitoring(false)` also does not exist there — the parent's
// toggles passed `on`/`$0` straight through, the literal is born with this commit's
// if/else split — so claim 4's two OFF-path assertions and claim 2's `micMonitorRefused =
// !engaged` are red there too, a second one-commit absence. ZERO regressions claimed,
// because zero exist; the remaining 3 of claim 4 plus claim 3's refresh needle are
// COUNTERWEIGHTS, green on both trees (#343): the sync method's signature, its
// route-release on the bail path, the refusal copy, the input-list refresh.
// `SourceText.codeOnly` is LOAD-BEARING, MEASURED (#453) as {`engageInputMonitoring`
// raw-vs-stripped × 3 files × this tree}: **2 of 3 counts flip** — AudioEngine raw 2 vs
// stripped 1 (the ⚠️ note above `setInputMonitoring` names the front door in prose) and
// EchoelStudioView raw 2 vs stripped 1 (the #485/#601 doc on `micMonitorRefused`); raw
// counting would break claims 2 and 5's exact-counts. The picker does not flip (its
// comment describes the mechanism without naming the symbol).

import Foundation
import XCTest

final class TheMonitorToggleAsksForTheMicTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - claim 1 — the front door exists and actually asks

    func testTheFrontDoorExistsAndAsks() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("func engageInputMonitoring() async -> Bool"), """
            `AudioEngine.engageInputMonitoring()` is gone or re-signatured. It is the ONE \
            permission-aware path to live input monitoring (#601): without it, both monitor \
            toggles regress to the fresh-install dead end where the mic dialog never appears. \
            If it moved, re-anchor this scan and the two caller scans below in the SAME commit.
            """)
        let body = slice(code, from: "func engageInputMonitoring() async -> Bool", to: "\n    }")
        XCTAssertTrue(body.contains("requestRecordPermission"), """
            The front door no longer requests the record permission. That request IS the fix — \
            `setInputMonitoring(true)` cannot show the dialog (0 Hz input format → bail), so if \
            nothing here asks, "Audio in" is dead again on every fresh install.
            """)
        XCTAssertTrue(body.contains("case .undetermined"), """
            The `.undetermined` arm is gone from `engageInputMonitoring`. That is the arm the \
            founder's report lives in: a fresh install is undetermined, and only this arm turns \
            it into a dialog.
            """)
        XCTAssertTrue(body.contains("case .denied"), """
            The `.denied` arm is gone from `engageInputMonitoring`. A previously-denied mic \
            must return false WITHOUT claiming the record route, so the refusal copy's advice \
            ("check microphone access in Settings") stays true.
            """)
        XCTAssertTrue(body.contains("return setInputMonitoring(true)"), """
            The front door no longer hands over to `setInputMonitoring(true)` after the \
            permission gate. Asking without engaging is the mirror bug: the dialog appears, \
            the user grants, and nothing starts.
            """)
    }

    // MARK: - claim 2 — the Mix-board toggle goes through it

    func testTheMicStripToggleGoesThroughTheFrontDoor() throws {
        let code = try source(Self.studio)
        XCTAssertEqual(occurrences(of: "engageInputMonitoring()", in: code), 1, """
            `EchoelStudioView` no longer calls `engageInputMonitoring()` exactly once (the \
            Monitor toggle's ON path). Zero means the Mix-board door regressed to the silent \
            dead end; two means a second caller appeared — decide whether it belongs and \
            update this count with its reason in the same commit (#408).
            """)
        XCTAssertTrue(code.contains("await audioEngine.engageInputMonitoring()"), """
            The Mix-board call is no longer awaited on the engine. The refusal flag must be \
            written from the REAL answer (after the dialog), not from a guess before it.
            """)
        XCTAssertTrue(code.contains("micMonitorRefused = !engaged"), """
            The Monitor toggle no longer records the front door's verdict in \
            `micMonitorRefused`. Without that write the toggle can lie (#485): \
            `isInputMonitoring` is `private(set)` and stays false on refusal, so nothing else \
            invalidates the body and the switch keeps showing ON.
            """)
    }

    // MARK: - claim 3 — the Audio-input sheet's toggle goes through it

    func testThePickerToggleGoesThroughTheFrontDoor() throws {
        let code = try source(Self.picker)
        XCTAssertEqual(occurrences(of: "engageInputMonitoring()", in: code), 1, """
            `AudioInputPickerView` no longer calls `engageInputMonitoring()` exactly once \
            (the Live-monitoring toggle's ON path). Both doors onto one engine must ask the \
            same way — this is the door the founder opens from the master panel.
            """)
        XCTAssertTrue(code.contains("inputs.refresh()"), """
            The picker no longer refreshes its input list around the monitoring switch. The \
            refresh is not decoration: turning monitoring on upgrades the session to \
            `.playAndRecord`, which is the moment `availableInputs` returns anything at all.
            """)
        XCTAssertTrue(code.contains("monitorRefused = !engaged"), """
            The picker no longer records the front door's verdict (#601b). Without it a \
            denied mic snaps the toggle back with ZERO explanation on this surface — the \
            founder's "Audio in" silence, surviving on one of the two doors.
            """)
        XCTAssertTrue(code.contains("monitorRefused && !audioEngine.isInputMonitoring"), """
            The picker's refusal line lost its engine gate (#601b). The gate is the #485 \
            pattern: the engine stays the single source of truth for "is it listening", so a \
            grant through the OTHER door self-corrects a stale refusal here instead of \
            rendering "could not start" next to a running monitor.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHTS, #343) — the dialog-free paths kept their meaning

    func testTheDialogFreePathsStay() throws {
        let engine = try source(Self.engine)
        XCTAssertTrue(engine.contains("func setInputMonitoring(_ on: Bool) -> Bool"), """
            `setInputMonitoring` lost its answer-returning signature. Every caller branches on \
            that Bool (`TheVoiceIsOnTheBoardTests` pins the same premise); the front door \
            returns it as its own verdict.
            """)
        let body = slice(engine, from: "func setInputMonitoring(_ on: Bool) -> Bool", to: "\n    }")
        XCTAssertTrue(body.contains("releaseRecordRoute(.inputMonitoring)"), """
            The 0-Hz bail path no longer releases the record route. #299: a denied mic must \
            not leave the whole system on `.playAndRecord` — that was the bug that made a \
            refcount unsafe. The front door deliberately does NOT touch the route on denial \
            because THIS line hands it back.
            """)
        let studio = try source(Self.studio)
        XCTAssertTrue(studio.contains("setInputMonitoring(false)"), """
            The Mix-board toggle's OFF path no longer calls `setInputMonitoring(false)` \
            directly. Stopping needs no dialog and no suspension point — routing OFF through \
            an async permission check would be shape for shape's sake.
            """)
        XCTAssertTrue(studio.contains("Monitoring could not start"), """
            The refusal copy is gone from the mic strip. With the front door able to return \
            false at the dialog, this line is the only honest surface telling the user WHY \
            nothing is listening and where the fix lives (Settings).
            """)
        let picker = try source(Self.picker)
        XCTAssertTrue(picker.contains("setInputMonitoring(false)"), """
            The picker toggle's OFF path no longer calls `setInputMonitoring(false)` \
            directly — same reasoning as the Mix-board OFF path.
            """)
    }

    // MARK: - claim 5 — exactly one declaration, exactly two callers

    /// #416 in caller form: the day a THIRD surface wants monitoring, it must come through
    /// the same front door — a new direct `setInputMonitoring(true)` caller would re-create
    /// the dialog-less dead end one door over.
    func testTheFrontDoorHasExactlyTwoCallers() throws {
        var declarations = 0
        var calls = 0
        for rel in try swiftFiles() {
            let code = try source(rel)
            declarations += occurrences(of: "func engageInputMonitoring", in: code)
            calls += occurrences(of: "audioEngine.engageInputMonitoring()", in: code)
        }
        XCTAssertEqual(declarations, 1, """
            `engageInputMonitoring` is declared \(declarations) times under Sources/. One \
            definition of "ask for the mic" (#416) — a second copy will drift from the first \
            on exactly the arm that matters.
            """)
        XCTAssertEqual(calls, 2, """
            `audioEngine.engageInputMonitoring()` has \(calls) call sites under Sources/ — \
            expected exactly 2 (the Mix-board Monitor toggle and the Audio-input sheet's \
            Live-monitoring toggle). Fewer: a door regressed to the silent dead end. More: a \
            new door exists — good, count it here WITH its reason in the same commit.
            """)
    }

    // MARK: - source access

    private struct AnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw AnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw AnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so an exact-count result here would be vacuous.
                """)
        }
        return out.sorted()
    }

    /// Brace-free window extraction: from the first occurrence of `from` to the FIRST
    /// occurrence of `to` after it. Both methods here end with a `return` at one indent
    /// above `\n    }`, and neither contains a nested type — the window is the member body
    /// plus nothing (same shape `RecordRouteOwnershipTests` uses on the same file).
    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
