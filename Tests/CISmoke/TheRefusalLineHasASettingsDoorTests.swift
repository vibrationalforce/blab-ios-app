// TheRefusalLineHasASettingsDoorTests.swift
// Echoel — #610. The mic-refusal lines carry a working door to Settings.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — every member here is `private` on a `View`
// no test bundle can instantiate. This proves where text sits, never that a tap opens
// anything. Whether the button reads well and the Settings jump lands is a DEVICE PROBE,
// registered as open in the deploy note, not covered here.
//
// WHY. The founder's screenshot of 2518 showed the #601b refusal line — "Monitoring could
// not start — check microphone access in Settings." — while asking "Wir wollen schon Device
// microphon Audio Input Live Monitoring haben". The line names Settings and opened no door:
// iOS asks for the mic ONCE, so after an OS-level denial the Settings app is the only fix
// (`AudioEngine.engageInputMonitoring`'s `.denied` branch logs exactly that and returns
// false). #610 puts a one-tap door — the app's ONE settings-opening function (#416), the
// same one BioStripView's camera door calls — inside BOTH refusal blocks.
//
// HONEST GRADING (§3), against parent 8d52f42:
// · Claims 1–3 are FORWARD — their needles (the Button line, the button copy) are born with
//   this commit. On the parent they are red together by ANCHOR ABSENCE: ONE finding (#486),
//   reported once, however many assertions name it.
// · Claims 4–6 are COUNTERWEIGHTS (#343) — green on both trees, deliberately: they pin the
//   premises that make the door the right advice (the engine really refuses on denial
//   instead of claiming the route; the one definition really exists; its other consumer
//   really survives).
// · Stripper measurement (§2): every needle counted raw vs. `SourceText.codeOnly`-stripped
//   on both trees — 0 of 12 verdicts flip, PROPHYLAKTISCH. (The studio comment block above
//   the button deliberately avoids quoting the `openAppSettings()` token, so no needle is
//   shadowed by prose.) Claim 7's needles (#613/#613b) were measured separately on their
//   own trees: the source comments quote neither the denial-gate token nor the copy
//   strings, so raw == stripped there too — still 0 flips.
//
// ORDERING SOUNDNESS (#408): the two "inside the refusal block" claims use ordering between
// anchors that each occur EXACTLY ONCE in their file — asserted here, not assumed (⛔ the
// first version SAID this while asserting only the door's uniqueness; the review caught the
// gap and claims 1–2 now carry `occurrences == 1` for the gates and next-branches). Studio:
// refusal gate < button < the `else if …degraded` silence branch. Picker: refusal gate <
// button < the silence gate `if !audioEngine.isRunning && !audioEngine.degraded {`. The
// gates themselves are pinned with full messages by TheMonitorSaysWhyItIsSilentTests; this
// file leans on them as ordering anchors only (#416 — no second copy of their reasoning).

import Foundation
import XCTest

final class TheRefusalLineHasASettingsDoorTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"
    private static let micman = "Sources/Echoelmusic/MicrophoneManager.swift"
    private static let bioStrip = "Sources/Echoelmusic/Studio/BioStripView.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    /// The door, one spelling in both files. If the label form changes, change it in BOTH
    /// doors and here, in the same commit — one state, one wording, two doors.
    private static let doorNeedle = "Button { openAppSettings() } label: {"
    private static let copyNeedle = "Text(\"Allow microphone\")"

    // MARK: - claim 1 — the mix-board refusal block carries the door

    func testTheMixBoardRefusalBlockCarriesTheDoor() throws {
        let code = try source(Self.studio)
        XCTAssertEqual(occurrences(of: Self.doorNeedle, in: code), 1, """
            The mix board's Settings door (#610) vanished or was duplicated. The refusal \
            line names Settings; without the button the user is told where the fix lives \
            and left to find it — the exact dead end the founder screenshotted on 2518. \
            If the door moved into a shared component, re-anchor this scan on the new call \
            site in the same commit.
            """)
        let gateNeedle = "if micMonitorRefused && !audioEngine.isInputMonitoring {"
        let nextNeedle = "else if audioEngine.isInputMonitoring && !audioEngine.isRunning && !audioEngine.degraded {"
        // #610b (review WARN): the ordering below is sound only while ALL THREE anchors are
        // unique — `range(of:)` keys on the FIRST occurrence, so a later second copy of a
        // gate string could keep this green over a relocated door. Asserted, not assumed.
        XCTAssertEqual(occurrences(of: gateNeedle, in: code), 1,
                       "the mix-board refusal gate is no longer unique — the ordering below keys on the first copy; re-anchor")
        XCTAssertEqual(occurrences(of: nextNeedle, in: code), 1,
                       "the mix-board silence branch is no longer unique — the ordering below keys on the first copy; re-anchor")
        let gate = code.range(of: gateNeedle)
        let door = code.range(of: Self.doorNeedle)
        let next = code.range(of: nextNeedle)
        let g = try XCTUnwrap(gate); let d = try XCTUnwrap(door); let n = try XCTUnwrap(next)
        XCTAssertTrue(g.lowerBound < d.lowerBound && d.lowerBound < n.lowerBound, """
            The mix board's Settings door is no longer INSIDE the refusal block (between \
            the #601b gate and the #605 silence branch). Outside that block it would show \
            while monitoring works, or vanish exactly when it is needed. All three anchors \
            occur once in this file — if this went red on a reorder, put the button back \
            between refusal text and silence branch.
            """)
    }

    // MARK: - claim 2 — the input sheet's refusal block carries the door

    func testTheInputSheetRefusalBlockCarriesTheDoor() throws {
        let code = try source(Self.picker)
        XCTAssertEqual(occurrences(of: Self.doorNeedle, in: code), 1, """
            The input sheet's Settings door (#610) vanished or was duplicated — same \
            consequence as the mix board's (claim 1): a refusal line that names Settings \
            with no way to get there.
            """)
        let gateNeedle = "if monitorRefused && !audioEngine.isInputMonitoring {"
        let nextNeedle = "if !audioEngine.isRunning && !audioEngine.degraded {"
        // #610b: same anchor-uniqueness law as claim 1 — asserted, not assumed.
        XCTAssertEqual(occurrences(of: gateNeedle, in: code), 1,
                       "the input sheet's refusal gate is no longer unique — the ordering below keys on the first copy; re-anchor")
        XCTAssertEqual(occurrences(of: nextNeedle, in: code), 1,
                       "the input sheet's silence gate is no longer unique — the ordering below keys on the first copy; re-anchor")
        let gate = code.range(of: gateNeedle)
        let door = code.range(of: Self.doorNeedle)
        let next = code.range(of: nextNeedle)
        let g = try XCTUnwrap(gate); let d = try XCTUnwrap(door); let n = try XCTUnwrap(next)
        XCTAssertTrue(g.lowerBound < d.lowerBound && d.lowerBound < n.lowerBound, """
            The input sheet's Settings door is no longer INSIDE its refusal block — see \
            claim 1's message. All three anchors occur once in this file.
            """)
    }

    // MARK: - claim 3 — one wording, two doors

    func testTheDoorCopyIsIdenticalInBothDoors() throws {
        let studio = try source(Self.studio)
        let picker = try source(Self.picker)
        XCTAssertEqual(occurrences(of: Self.copyNeedle, in: studio), 1, """
            The mix board's door label changed or vanished. It is deliberately identical \
            in both doors — if this is a rewording, update the picker door and this \
            guard's `copyNeedle` in the same commit.
            """)
        XCTAssertEqual(occurrences(of: Self.copyNeedle, in: picker), 1, """
            The input sheet's door label changed or vanished — see the studio message: \
            one wording, two doors, same commit.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the one definition still opens Settings

    func testTheSettingsFunctionStillOpensSettings() throws {
        let code = try source(Self.micman)
        XCTAssertTrue(code.contains("func openAppSettings()"), """
            The app's one settings-opening function is gone from MicrophoneManager. Three \
            consumers lean on it (BioStripView camera door, both #610 mic doors) — if it \
            moved files, re-anchor this scan; if it was renamed, rename the call sites in \
            the same commit.
            """)
        XCTAssertTrue(code.contains("UIApplication.openSettingsURLString"), """
            `openAppSettings()` no longer builds the system settings URL — the #610 \
            buttons would tap into a no-op. Whatever replaced it must still land the user \
            on Echoel's Settings page.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the engine still refuses on denial

    func testTheEngineStillRefusesOnDenial() throws {
        let code = try source(Self.engine)
        XCTAssertTrue(code.contains("Settings is the only door"), """
            `engageInputMonitoring`'s `.denied` branch changed. The #610 buttons are the \
            UI half of exactly this branch: the engine refuses WITHOUT claiming the record \
            route, so "go to Settings" is literally the right advice. If the denial \
            handling was redesigned, re-judge whether the refusal blocks' advice (and \
            these doors) still match it — do not let the two halves drift apart silently.
            """)
    }

    // MARK: - claim 7 (#613) — the Settings costume is gated on real denial

    /// Sweep WARN 3: `engageInputMonitoring` returns false for permission denial AND for
    /// non-permission failures (busy session, 0 Hz format, restart throw). Ungated, the
    /// Settings line + this file's door showed for ALL of them — asserting "Microphone
    /// access is off" over a granted mic and sending the user to a toggle that is
    /// already on. Both doors now branch on the engine's ONE denial definition (#416).
    /// FORWARD grading: the gate needles are born with #613, whose TRUE parent is
    /// eb69265 (⛔ the first wording said "parent (0360c90)" — that is the last
    /// SOURCE-touching ancestor, three commits back; the two between are deploy/docs
    /// only, so the grading was materially right and the word "parent" wrong — the
    /// review caught the mislabel). One absence, several assertions (#486). Ordering:
    /// gate < door < NEUTRAL COPY (#613b — the first cut asserted only gate < door,
    /// which stays green if the door slides past the `else` into the non-denied
    /// branch; the neutral copy is the first token after that branch opens, so it
    /// closes exactly that gap). Claims 1–2 above are unchanged by the branch.
    /// The studio's neutral branch carries `!audioEngine.degraded` (#605b law:
    /// AudioDegradedRow renders beside it and owns cause + Retry); the picker's
    /// DELIBERATELY does not — the row is invisible under the sheet, and an empty
    /// refusal block is the defect class this chain fights. Asserted asymmetrically.
    func testTheSettingsCostumeIsGatedOnRealDenial() throws {
        let studio = try source(Self.studio)
        let picker = try source(Self.picker)
        let engine = try source(Self.engine)
        let deniedGate = "if audioEngine.micPermissionDenied {"
        for (code, name, neutral) in [
            (studio, "mix-board strip", "Monitoring could not start — try again, or pick another input."),
            (picker, "input sheet", "Monitoring could not start — try again."),
        ] {
            XCTAssertEqual(occurrences(of: deniedGate, in: code), 1, """
                The \(name)'s denial gate (#613) vanished or was duplicated. Without it \
                every engage failure wears the permission costume again — Settings advice \
                and an "access is off" door shown to a user whose access is granted.
                """)
            let g = try XCTUnwrap(code.range(of: deniedGate))
            let d = try XCTUnwrap(code.range(of: Self.doorNeedle))
            let nt = try XCTUnwrap(code.range(of: neutral), """
                The \(name)'s non-denial refusal line changed or vanished. It is the \
                honest half of #613: a granted mic whose engage failed transiently gets \
                "try again", not a Settings hunt. If this is a rewording, update this \
                guard in the same commit.
                """)
            XCTAssertTrue(g.lowerBound < d.lowerBound && d.lowerBound < nt.lowerBound, """
                The \(name)'s Settings door moved OUTSIDE the denial branch — it must \
                only render when Settings is actually the fix. `gate < door < neutral` \
                pins it INSIDE: the neutral copy opens the non-denied branch, so a door \
                that slid past the `else` would sort after it (#613b closed exactly \
                this gap in the first cut's `gate < door` check).
                """)
        }
        XCTAssertEqual(occurrences(of: "} else if !audioEngine.degraded {", in: studio), 1, """
            The studio's neutral refusal branch lost its `!degraded` gate (#613b/#605b): \
            on the restart-throw path the engage failure and restartOrDegrade's verdict \
            land together, and without the gate this line and AudioDegradedRow say the \
            same thing twice, side by side. The PICKER's neutral branch deliberately has \
            no such gate (the row is invisible under the sheet — an empty refusal block \
            would be worse); if you are unifying them, re-judge that asymmetry, do not \
            just copy the gate over.
            """)
        XCTAssertTrue(picker.contains("if monitorRefused && audioEngine.micPermissionDenied {"), """
            The input sheet's empty-state lost its #613 gate — with a granted mic it \
            would again claim "The microphone is not available to Echoel" and point at \
            Settings, instead of falling through to the correct "turn on monitoring \
            above" instruction.
            """)
        XCTAssertTrue(engine.contains("var micPermissionDenied: Bool"), """
            The engine's one denial definition is gone. Both doors and the empty state \
            branch on it — if it was renamed or moved, re-point the three consumers and \
            this guard in the same commit (#416: never re-derive it per door).
            """)
    }

    // MARK: - claim 6 (COUNTERWEIGHT) — the sibling consumer survives

    func testTheCameraDoorStillUsesTheSameFunction() throws {
        let code = try source(Self.bioStrip)
        XCTAssertTrue(code.contains("openAppSettings()"), """
            BioStripView's camera door no longer calls `openAppSettings()`. That is \
            allowed — but the studio door's comment names it as the sibling consumer, and \
            claim 4's message counts three consumers. Update both in the same commit so \
            the "one definition" story stays true.
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
