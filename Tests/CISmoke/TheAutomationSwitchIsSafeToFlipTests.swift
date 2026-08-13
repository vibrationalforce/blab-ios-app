// TheAutomationSwitchIsSafeToFlipTests.swift
// Echoel — #561. `AutomationPlayer.enabled` gets a door, one slice earlier than the plan
// scheduled it, and this file is why that is safe rather than reckless.
//
// TWO THINGS CHANGED THE SCHEDULE. `scratchpads/PLAN_AUTOMATION_IN_DER_SPUR.md` put the switch
// last and gave a reason — "ein Schalter, der etwas Unsichtbares einschaltet, ist kein Feature".
// #559 put the state on screen, so that reason expired: the strip can now print `off` beside a
// curve, and a player who reads that has no way to act on it. The second reason is a defect
// rather than a feature request — `AutomationState`'s decode defaults `enabled` to `false` on any
// unreadable document, deliberately, and until this slice nothing in `Sources/` could set it
// back. Its own doc block called that a ONE-WAY DOOR. A conservative default with no manual
// switch is not conservatism; it is a trapdoor.
//
// ⚠️ THE SAFETY ARGUMENT, AND IT IS THE WHOLE FILE. Turning automation on hands recorded curves
// authority over values the performer set by hand — master level, tempo, the filter multiplier.
// Shipping that switch before any writer exists is only safe because with nothing recorded the
// two states are the SAME SOUND, and that is three separate facts, each pinned below:
//   1. master and tempo apply only `if let r = real`, and `real` is nil for an empty lane;
//   2. the filter multiplier applies `real ?? target.neutralValue`, and that neutral is ×1;
//   3. the DISABLED branch writes exactly ×1 too, via `setCutoffScale(1)`.
// Break any one and flipping the switch on a fresh install changes the sound — which is the
// thing a player would least expect from a control the app describes as doing nothing yet.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claim 1 is END-TO-END BEHAVIOUR (`AutomationTarget` is a public Foundation-only enum).
//   · claims 2–4 are SOURCE-TEXT SCANS. `applyStep` is public but driving it means constructing
//     an `AutomationPlayer`, whose `init` reads — and whose `enabled` setter WRITES — the real
//     App-Group container; the type takes no injectable store, and its own source says so. A
//     scan of the dispatch is the honest instrument here, and it is labelled as one.
//   · DEVICE PROBE, open: whether the switch reads as "play what I recorded" rather than as a
//     global bio switch, and whether flipping it mid-take is audible. Nothing here plays a note.
//
// ⚠️ HONEST GRADING, transcribed in Python against the parent (`59d4500`) and this tree — this
// file compiles against both, because everything it names already existed:
//   · claim 2 is the REGRESSION: red on the parent, where no production file writes
//     `player.enabled`. One writer, one finding.
//   · claims 1, 3 and 4 are COUNTERWEIGHTS, green on both, and they are the point of the file
//     (#343): the switch may only ship while the empty-lane path stays inaudible and the
//     decode default stays conservative. Claims 1–3 all stay green on a tree that "simplified"
//     the disabled branch away, which is why claim 4 pins that branch separately.
//   · STRIPPER — measured BEFORE this line was written, which is the point: two consecutive
//     slices (#559, #560) wrote it from a pattern and had to retract. **PROPHYLAKTISCH, 0 of 12
//     verdicts flip** (6 needles × 2 trees). The number is the transcription's, not an estimate;
//     the draft of this very sentence said "0 of 8" from counting needles in my head, and the
//     run said 12. Even in the harmless direction, a count written before the command is a
//     guess wearing a measurement's clothes.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutomationSwitchIsSafeToFlipTests: XCTestCase {

    private static let player = "Sources/Echoelmusic/Core/AutomationPlayer.swift"
    private static let strip = "Sources/Echoelmusic/Studio/AutomationStatusStrip.swift"

    // MARK: - claim 1 (END-TO-END) — the filter multiplier's neutral really is ×1

    /// The number the whole safety argument turns on. `applyStep` writes
    /// `target.neutralValue` for an EMPTY filter lane whenever automation is enabled, so if
    /// that value drifts off 1, switching automation on with nothing recorded audibly filters
    /// the instrument — on a control whose own caption says it changes nothing yet.
    func testTheFilterMultipliersNeutralIsUnity() {
        XCTAssertEqual(AutomationTarget.filterCutoff.neutralValue, 1.0, accuracy: 1e-12, """
            `filterCutoff.neutralValue` is \(AutomationTarget.filterCutoff.neutralValue), not \
            ×1. It is what `applyStep` writes for an empty lane while automation is ON, and \
            `setCutoffScale(1)` is what it writes while automation is OFF — the two branches \
            have to agree, or flipping the switch on a fresh install changes the sound.
            """)
        XCTAssertEqual(AutomationTarget.filterCutoff.value(forNormalized: 0.5), 1.0,
                       accuracy: 1e-9, """
            The multiplier's curve no longer passes through ×1 at its midpoint. The neutral and \
            the mid-curve value are the same claim from two directions — a range whose middle \
            is not neutral makes "no automation" and "a flat curve" different sounds.
            """)
    }

    // MARK: - claim 2 (REGRESSION) — the one-way door has a way back

    func testTheSwitchExistsAndLivesInTheLeaf() throws {
        let code = try codeText(Self.strip)
        XCTAssertTrue(code.contains("player.enabled = "), """
            Nothing in `\(Self.strip)` writes `AutomationPlayer.enabled`. That flag decodes to \
            `false` on ANY unreadable document — deliberately, because automation overwrites \
            what the performer set live — so without a setter a user whose earlier build \
            persisted `true` loses it to one truncated write and can never get it back from \
            inside the app. `AutomationState`'s doc block calls that a one-way door. If the \
            switch moved to another file, re-anchor here in the SAME commit (#456); if it was \
            removed, the door is open again and that doc block has to say so.
            """)
        XCTAssertTrue(code.contains("@Environment(AutomationPlayer.self)"), """
            The strip no longer reads the player in its own body. A `Toggle` bound to a value \
            the HOST panel observes would make `EchoelStudioView.body` an observer of the \
            automation document — the panel builder is evaluated permanently and hosts every \
            `.menu` Picker of the instrument (10.76.41/50).
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — an empty lane applies nothing on the ON path

    /// SOURCE SCAN of the dispatch, because driving it means writing into the real App-Group
    /// container (see the header). What it pins is the SHAPE that makes an empty lane silent:
    /// the two absolute targets are guarded by an optional bind, and only the multiplier — the
    /// one with a defined neutral — falls back.
    func testMasterAndTempoOnlyApplyWhenALaneReallyProducesAValue() throws {
        let body = try memberBody("public func applyStep(_ step: Int)", in: Self.player)
        for target in ["case .masterLevel:", "case .tempo:"] {
            guard let line = body.split(separator: "\n").first(where: { $0.contains(target) })
            else {
                return XCTFail("""
                    `applyStep` no longer has a `\(target)` arm. Re-anchor this scan rather \
                    than letting it pass over nothing (#454).
                    """)
            }
            XCTAssertTrue(line.contains("if let r = real"), """
                `\(target)` in `applyStep` no longer applies only when the lane produced a \
                value: "\(line.trimmingCharacters(in: .whitespaces))". Master level and tempo \
                have no neutral to fall back to — they are absolute values the performer set — \
                so a fallback here would make switching automation ON jump the master or the \
                tempo of an install that has recorded nothing.
                """)
        }
        XCTAssertTrue(body.contains("real ?? target.neutralValue"), """
            The filter arm of `applyStep` no longer falls back to the target's neutral. That \
            fallback is deliberate and asymmetric to the two above: the multiplier is a HIDDEN \
            ×-factor, so an unused lane must actively reset it to ×1 rather than leave the \
            sound filtered by whatever came before.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — and the OFF path writes the same ×1

    /// The half that makes claim 3 mean something. If the disabled branch stopped releasing the
    /// multiplier, "automation off" and "automation on with no lanes" would be two different
    /// sounds — and the switch this slice adds would be the control that revealed it.
    func testTheDisabledBranchReleasesTheMultiplier() throws {
        let body = try memberBody("public func applyStep(_ step: Int)", in: Self.player)
        XCTAssertTrue(body.contains("setCutoffScale(1)"), """
            `applyStep`'s disabled branch no longer calls `setCutoffScale(1)`. With automation \
            off the hidden filter multiplier would keep whatever a lane last wrote, so turning \
            automation OFF mid-take would leave the instrument filtered with no control \
            anywhere that could release it — and turning it back ON would sound different \
            again. The two branches must agree on ×1.
            """)
        let decode = try codeText(Self.player)
        XCTAssertTrue(decode.contains("?? false"), """
            `AutomationState`'s decode no longer defaults `enabled` to `false`. The direction \
            is the law, not a preference: automation overwrites values the performer set live, \
            so an unreadable flag must never be able to turn it ON. #561 added a manual switch \
            precisely so the conservative default stops being a trapdoor — it did not license \
            changing the default.
            """)
    }

    // MARK: - source access

    private struct SwitchAnchorMissing: Error { let reason: String }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwitchAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Brace-matched body of a member (#408) — a fixed line window is unsound in this repo,
    /// where a member routinely carries a forty-line comment block and `SourceText.codeOnly`
    /// preserves the line count.
    private func memberBody(_ anchor: String, in relative: String) throws -> String {
        let code = try codeText(relative)
        guard let a = code.range(of: anchor),
              let open = code.range(of: "{", range: a.upperBound..<code.endIndex) else {
            throw SwitchAnchorMissing(reason: """
                `\(anchor)` was not found in \(relative). It is the one place automation \
                reaches live values; re-anchor rather than letting these scans pass on \
                nothing (#454).
                """)
        }
        var depth = 0
        var i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.lowerBound...i]) }
            }
            i = code.index(after: i)
        }
        throw SwitchAnchorMissing(reason: "`\(anchor)`'s braces do not close")
    }
}
