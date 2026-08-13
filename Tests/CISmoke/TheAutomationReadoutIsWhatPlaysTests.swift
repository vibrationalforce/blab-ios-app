// TheAutomationReadoutIsWhatPlaysTests.swift
// Echoel — #559, slice 2 of `scratchpads/PLAN_AUTOMATION_IN_DER_SPUR.md`.
//
// WHAT THIS IS ABOUT. Slice 2 puts the first automation surface in the app: a readout of which
// parameters move on their own. A readout can be wrong in two directions and both are worse
// than having none. It can UNDER-report — hide a lane that plays, so a player hunting a sound
// that changes by itself finds an empty list and concludes the feature is off. Or it can
// OVER-report — list the three structurally-empty enum lanes `AutomationPlayer.completed()`
// creates on every fresh install, so a device that has never seen automation shows three
// automated parameters. This file pins the reading against both.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–6 are END-TO-END BEHAVIOUR. `AutomationStatus`, `AutomationScale`,
//     `AutomationLane` and `AutomationTarget` are public, Foundation-only value types, so
//     these DRIVE the shipped decision instead of describing it.
//   · claims 7 and 8 are SOURCE-TEXT SCANS: `soundPanel` is `private` on a `View` no test
//     bundle can instantiate, and the freeze law is a statement about WHERE a read sits.
//   · DEVICE PROBE, open: whether the strip renders, whether it fits at accessibility text
//     sizes at the bottom of an already-long panel, and — the one that matters — whether an
//     open Picker in that panel survives while the camera runs with the strip mounted.
//     Nothing here can see a pixel.
//
// ⚠️ HONEST GRADING, and the honest answer is uncomfortable: **this file does not compile
// against the parent (`78af9c2`)** — claims 1–6 name `AutomationStatus`/`AutomationScale`/
// `AutomationStatusRow`, which this same commit creates. So NO assertion has a verdict there,
// and saying "zero regressions" would be the #488 ambiguity (a statement about the parent that
// is really a statement about this tree). Transcribed in Python instead, per §0 of
// `Tests/CISmoke/CLAUDE.md`:
//   · claims 1–6: the reading logic hand-ported and driven on constructed lanes. All six green
//     on this tree. On the parent they are FORWARD guards over a type that does not exist —
//     one absence, six assertions, ONE finding (#486). Booking six regressions would be the
//     flattering-direction defect (#433).
//   · claim 7 splits, and that is why it is one test with two assertions: the MOUNT
//     (`AutomationStatusStrip()` in `EchoelStudioView.swift`) is a REGRESSION — absent on the
//     parent, present here. The freeze half (`EchoelStudioView.swift` declares no
//     `@Environment(AutomationPlayer.self)`) is a COUNTERWEIGHT — green on both trees, and it
//     is the assertion that matters most: claims 1–6 all stay green on a tree that "simplified"
//     the strip away by reading the player in the panel instead, which is exactly the
//     10.76.41/50 menu freeze arriving by refactor.
//   · claim 8's two assertions are ONE finding, not two: the strip file does not exist on the
//     parent, so both needles miss for the same single reason (#486).
//   · STRIPPER: **PROPHYLAKTISCH, 0 of 6 verdicts flip** (4 needles; claim 8's two have no
//     verdict on the parent, where the file is absent). ⛔ THE FIRST VERSION OF THIS LINE SAID
//     "TRAGEND, 1 of 4" AND WAS A GUESS DRESSED AS A MEASUREMENT. The reasoning was that the
//     mount comment in `soundPanel` would name `@Environment(AutomationPlayer.self)` in prose
//     and trip claim 7's negative needle raw — the #486/#491 collision this session has hit
//     six times, so I expected a seventh and wrote it down before looking. The comment I
//     actually wrote says "reads `AutomationPlayer` in its OWN body" and contains no such
//     string; raw and stripped agree on all six verdicts. This is precisely what §2 of
//     `Tests/CISmoke/CLAUDE.md` records — three slices in a row claimed load-bearing without
//     measuring and had to retract — and the correction is kept rather than silently edited,
//     because the failure was not the number: it was writing a grading line from a PATTERN
//     that has been true six times instead of from the tree in front of me. The stripper stays
//     (#453, one definition of "code, not prose") and becomes load-bearing the day someone
//     writes a retraction here quoting the form the scan looks for.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutomationReadoutIsWhatPlaysTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let strip = "Sources/Echoelmusic/Studio/AutomationStatusStrip.swift"

    /// A linear 0…1 scale, the shape every registry descriptor has.
    private func plainScale(_ name: String) -> AutomationScale {
        AutomationScale(displayName: name, unit: "", decimals: 2, minValue: 0, maxValue: 1)
    }

    private func lane(_ parameter: String, _ values: [Double]) -> AutomationLane {
        var l = AutomationLane(parameter: parameter)
        for (i, v) in values.enumerated() { l.addPoint(tick: i * 480, value: v) }
        return l
    }

    // MARK: - claim 1 (END-TO-END) — an empty lane is not automation

    /// `AutomationPlayer.completed()` guarantees one lane per legacy enum target for the
    /// lifetime of the document, EMPTY on a fresh install. `applyStep` writes nothing for
    /// them (`value(atTick:)` returns nil), so a readout that listed them would report three
    /// automated parameters on a device where nothing has ever been drawn — and the player
    /// would go looking for a curve that does not exist.
    func testAnEmptyLaneProducesNoRow() {
        let rows = AutomationStatus.rows(
            global: [AutomationLane(parameter: "masterLevel"),
                     AutomationLane(parameter: "tempo"),
                     AutomationLane(parameter: "filterCutoff")],
            clip: [], arrangement: [], globalEnabled: true) { _ in self.plainScale("x") }
        XCTAssertTrue(rows.isEmpty, """
            \(rows.count) row(s) came back for lanes that hold no keyframes. \
            `AutomationPlayer.completed()` creates exactly these three on every fresh install, \
            and `applyStep` writes nothing for them — so this is the state of a device that has \
            never seen automation, reported as three automated parameters.
            """)
        let one = AutomationStatus.rows(
            global: [AutomationLane(parameter: "tempo"), lane("masterLevel", [0.2, 0.9])],
            clip: [], arrangement: [], globalEnabled: true) { _ in self.plainScale("Master") }
        XCTAssertEqual(one.map(\.parameter), ["masterLevel"], """
            A lane WITH keyframes must still be reported next to empty ones — got \
            \(one.map(\.parameter)). Without this, claim 1 would be green on a reader that \
            returns nothing at all.
            """)
    }

    // MARK: - claim 2 (END-TO-END) — a lane that reaches nothing is shown, not hidden

    /// Slice 1's finding made visible. `ParameterApplyRouter.applyNormalized` returns nil for
    /// an unbound keyPath — a deliberate, crash-free no-op — so a lane on one draws, saves,
    /// replays and moves nothing. Filtering those rows out would make the surface agree with
    /// the defect: no automation seen, no automation heard, no way to connect the two.
    func testAnUnboundParameterIsListedAndMarked() {
        let rows = AutomationStatus.rows(
            global: [lane("ddsp.osc.brightness", [0.25, 0.75])],
            clip: [], arrangement: [], globalEnabled: true) { _ in nil }
        XCTAssertEqual(rows.count, 1, """
            A lane whose parameter resolves to no scale was dropped from the readout. It still \
            REPLAYS every transport step; hiding it leaves the player with a curve that does \
            nothing and a screen that agrees nothing is there.
            """)
        XCTAssertEqual(rows.first?.isBound, false,
                       "an unresolvable parameter must be reported as reaching nothing")
        XCTAssertEqual(rows.first?.displayName, "ddsp.osc.brightness", """
            With no scale there is no display name, so the raw keyPath is the honest label — \
            it is also the string a later edit has to address. A blank or invented name would \
            leave the row unactionable.
            """)
        // `?? -1` and not `!`: a nil here means claim 2's first assertion already failed, and
        // a force-unwrap would turn that into a crashed test run instead of a named failure.
        XCTAssertEqual(rows.first?.lowest ?? -1, 0.25, accuracy: 1e-9, """
            With no scale the span stays NORMALIZED — there is no real range to map into. \
            Printing a denormalized-looking number for an unbound parameter would give the row \
            a unit it does not have.
            """)
        XCTAssertEqual(rows.first?.highest ?? -1, 0.75, accuracy: 1e-9)
    }

    // MARK: - claim 3 (END-TO-END) — only the global layer is gated by the switch

    /// The asymmetry is not a detail: in `applyStep` the enum loop and the extra-keyPath loop
    /// sit INSIDE `if enabled`, while the clip and timeline loops sit outside it, because clip
    /// automation is clip CONTENT and plays like the clip's notes. `enabled` is `false` with no
    /// in-app setter today, so a readout that greyed out every row would tell a player their
    /// clip automation is off while it is playing.
    func testOnlyTheGlobalLayerFollowsTheMasterSwitch() {
        for enabled in [true, false] {
            let rows = AutomationStatus.rows(
                global: [lane("masterLevel", [0.1, 0.2])],
                clip: [lane("ddsp.env.attack", [0.3, 0.4])],
                arrangement: [lane("ddsp.amp.level", [0.5, 0.6])],
                globalEnabled: enabled) { _ in self.plainScale("p") }
            let byLayer = Dictionary(uniqueKeysWithValues: rows.map { ($0.layer, $0.isActive) })
            XCTAssertEqual(byLayer[.global], enabled, """
                The global layer's rows must be active exactly when the master switch is up \
                (enabled = \(enabled)) — its lanes are the only ones `applyStep` writes inside \
                `if enabled`.
                """)
            XCTAssertEqual(byLayer[.clip], true, """
                A clip row went inactive at enabled = \(enabled). Clip lanes are applied \
                OUTSIDE the `enabled` gate — they are clip content, like the clip's notes — so \
                reporting them as off is telling the player something false about audio that is \
                being written right now.
                """)
            XCTAssertEqual(byLayer[.arrangement], true,
                           "arrangement lanes are also applied outside the `enabled` gate")
        }
    }

    // MARK: - claim 4 (END-TO-END) — precedence, under both identities

    /// `applyStep` writes global → clip → arrangement within one step, so the last write wins.
    /// The identities involved are NOT plain strings: a legacy rawValue ("masterLevel") and its
    /// registry keyPath alias ("master.amp.level") name the same lane, which is why this asks
    /// `TimelineAutomationRowMath.sameParameter` rather than comparing text (#416).
    func testALaterLayerOverridesAnEarlierOneUnderEitherIdentity() {
        let rows = AutomationStatus.rows(
            global: [lane("masterLevel", [0.1, 0.2])],
            clip: [lane("master.amp.level", [0.8, 0.9])],
            arrangement: [], globalEnabled: true) { _ in self.plainScale("Master") }
        XCTAssertEqual(rows.count, 2, "both lanes are reported; one of them is just losing")
        XCTAssertEqual(rows.first?.isOverridden, true, """
            The global lane is not marked overridden although the clip layer holds the SAME \
            parameter under its keyPath alias and is applied after it. Comparing the two \
            strings textually would miss this — the alias law is exactly what \
            `sameParameter` exists for, and a player watching an unmarked global curve do \
            nothing has no way to discover why.
            """)
        XCTAssertEqual(rows.last?.isOverridden, false,
                       "the LAST writer on a parameter is the one that wins")
        let independent = AutomationStatus.rows(
            global: [lane("ddsp.env.attack", [0.1])],
            clip: [lane("ddsp.env.release", [0.9])],
            arrangement: [], globalEnabled: true) { _ in self.plainScale("p") }
        XCTAssertEqual(independent.filter(\.isOverridden).count, 0, """
            Two DIFFERENT parameters on two layers were reported as overriding each other. \
            Without this the override rule would be green on a reader that marks every row in \
            every earlier layer.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the premise under `lowest`/`highest`

    /// `AutomationStatusRow` takes the lowest and highest NORMALIZED keyframes and maps each
    /// once. That equals the curve's real extremes only while every mapping is monotonically
    /// increasing. It is true today for all three enum targets and for every descriptor
    /// (`denormalized` is affine with `max > min`) — and it is exactly the kind of premise that
    /// stops holding silently, so it is driven rather than assumed.
    func testEveryScaleInUseIsMonotonicallyIncreasing() {
        let grid = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
        for target in AutomationTarget.allCases {
            let scale = AutomationScale(target: target)
            let mapped = grid.map { scale.real($0) }
            for i in 1..<mapped.count {
                XCTAssertGreaterThan(mapped[i], mapped[i - 1], """
                    `\(target.rawValue)` is not increasing between normalized \
                    \(grid[i - 1]) and \(grid[i]). `AutomationStatusRow.lowest`/`highest` map \
                    the lowest and highest KEYFRAMES; with a non-monotonic curve those two \
                    numbers stop being the span the parameter actually covers, and the readout \
                    would quietly print a narrower range than the ear hears.
                    """)
            }
        }
        let descriptor = ParameterDescriptor(keyPath: "x.y.z", displayName: "Z",
                                             min: 20, max: 20_000, defaultValue: 440, unit: "Hz")
        let scale = AutomationScale(descriptor: descriptor)
        XCTAssertLessThan(scale.real(0.1), scale.real(0.9),
                          "a registry descriptor's denormalization is affine and increasing")
        XCTAssertEqual(scale.decimals, 0, """
            A 20…20000 Hz span rendered with \(scale.decimals) decimals. The heuristic exists \
            so a wide range does not print two meaningless fraction digits; if it changes, the \
            reason at `AutomationScale(descriptor:)` moves with it.
            """)
    }

    // MARK: - claim 6 (END-TO-END) — the filter multiplier keeps its own curve

    /// The assertion that catches the shortcut I nearly took: modelling a scale as a
    /// min/max PAIR. `AutomationTarget.filterCutoff` maps `0.25 * pow(16, c)` so that 0,5 is
    /// ×1 — its neutral. A linear span would print ×2.125 at the middle of the curve, i.e. a
    /// filter the readout claims is doubling while the sound is untouched.
    func testTheFilterMultiplierIsNeutralAtTheMiddleOfItsCurve() {
        let scale = AutomationScale(target: .filterCutoff)
        XCTAssertEqual(scale.real(0.5), 1.0, accuracy: 1e-9, """
            The filter multiplier's midpoint is \(scale.real(0.5)) rather than ×1. \
            `AutomationScale` carries the target's own mapping closure precisely so this stays \
            true; a min/max pair would make the middle of the range read as a doubling of the \
            cutoff while nothing at all is happening to the sound.
            """)
        XCTAssertEqual(scale.unit, "×", "the multiplier is not measured in Hz")
        let linear = AutomationScale(target: .tempo)
        XCTAssertEqual(linear.real(0.5), 130, accuracy: 1e-9, """
            Tempo IS linear over 40…220, so its midpoint is 130. Without this, claim 6 would be \
            green on a scale that applies the log curve to everything.
            """)
    }

    // MARK: - claim 7 (REGRESSION + COUNTERWEIGHT) — mounted there, read here

    func testTheSoundPanelMountsTheStripAndObservesNothingItself() throws {
        let code = try codeText(Self.studio)
        XCTAssertTrue(code.contains("AutomationStatusStrip()"), """
            Nothing in `\(Self.studio)` mounts `AutomationStatusStrip()`. It is hosted in \
            `soundPanel` because ten of the thirteen parameters an automation lane can reach \
            today are the synth values on that panel's own rows — a player who sees one move \
            without touching it asks the question there. If the mount moved on purpose, this \
            anchor moves with it in the same commit (#456).
            """)
        XCTAssertFalse(code.contains("@Environment(AutomationPlayer.self)"), """
            `\(Self.studio)` declares an `@Environment(AutomationPlayer.self)`. \
            `EchoelStudioView.body` evaluates every panel builder PERMANENTLY and hosts every \
            `.menu` Picker of the instrument, so observing the player's lanes here rebuilds the \
            whole subtree whenever a clip or region installs its layer — the 10.76.41/50 menu \
            freeze, arriving by refactor. `AnyView(...)` is not an observation boundary. This \
            does NOT forbid the slice-4 master switch (#364): put it in its own `View` struct \
            in its own file, the way `AutomationStatusStrip`, `MasterVolumeField` and \
            `AlwaysOnBioPanelStrip` all are.
            """)
    }

    // MARK: - claim 8 (REGRESSION) — the read exists, and the orphan has a caller again

    func testTheStripReadsThePlayerItselfAndUsesTheHonestSet() throws {
        let code = try codeText(Self.strip)
        XCTAssertTrue(code.contains("@Environment(AutomationPlayer.self)"), """
            `\(Self.strip)` no longer reads `AutomationPlayer` in its own body. Either it \
            stopped showing anything, or — the dangerous case — the read moved UP into the \
            panel; see claim 7.
            """)
        XCTAssertTrue(code.contains("extraAutomatableDescriptors"), """
            The strip no longer asks `AutomationPlayer.extraAutomatableDescriptors`. That \
            property is the placebo law in executable form (registry ∩ bound, minus the legacy \
            enum targets) and it had ZERO callers from #473 until this slice — its declaration \
            carries a ⚠️ note saying so. If the strip stops using it, that note becomes wrong \
            in the same commit and has to be corrected there, not left to age (#472).
            """)
    }

    // MARK: - source access

    private struct StripAnchorMissing: Error { let reason: String }

    /// Reads a repo source file as CODE, never prose (#453).
    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StripAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
