//
//  TheFXDoorNamesAControlThatExistsTests.swift
//  EchoelmusicTests (CISmoke — the BLOCKING bundle)
//
//  #480. The "All parameters" button in `effectsPanel` told VoiceOver it opens "the full effects
//  chain — every parameter as a slider". `Studio/EchoelFXView.swift` declares ZERO `Slider(`;
//  every numeric parameter there is an `EchoelValueField` and every named one is a `Picker`.
//
//  ⭐ WHAT MAKES THIS WORTH A GUARD IS WHERE THE REFUTATION SAT: in the comment block immediately
//  above the button, written for exactly this purpose — "NOT 'as sliders' — numeric parameters are
//  `EchoelValueField`s, and a parameter whose values have NAMES is a picker". Somebody corrected
//  the surrounding prose and left the string. A claim standing next to its own refutation, in the
//  one layer a sighted reviewer never opens: the accessibility hint is invisible unless VoiceOver
//  is on, so no screenshot, no design pass and no UI review would ever have surfaced it.
//  (⛔ The first version of this line said "four lines above". It was three — the block opened at
//  `4df0393:6185`, the "NOT" sentence began at 6187, the `Button` at 6190. A line DISTANCE inside a
//  file is the most perishable fact this repo writes down: the commit asserting it moves it in the
//  same breath. Described by position instead, which survives an insertion.)
//
//  ⚠️ HONEST SIZE, because "VoiceOver was lied to" reads bigger than it is. This is COPY, not a
//  broken affordance: `EchoelValueField` installs an `accessibilityAdjustableAction`, so swipe
//  up/down adjusts it exactly as it would a `Slider`. What the wrong word hid is the affordance a
//  slider does NOT have — double-tap to type an exact number. Each field says that in its own
//  hint, so the door deliberately does not repeat it (#416: one definition per fact).
//
//  ⚠️ AND THE CORRECTION THAT CAUGHT IT WAS ITSELF OVERSTATED. It said "the app has no raw
//  `Slider`", unqualified. There are TWO — the look scrub, in `EchoelStudioView.visualLookRow`
//  and again in `FloatingVisualWindow`. Both are deliberate and both are documented at the site;
//  the UI law's own word is "no raw `Slider`/`Stepper` FOR PARAMETERS", and a continuous morph
//  between NAMED looks is not a parameter row (`FloatingVisualWindow` says so in as many words:
//  "a live VJ control over the visual, not a Studio parameter row"). `testTheAppsOnlyRawSliders…`
//  pins the scoped claim so that neither half can drift: a third raw `Slider` anywhere, or either
//  of these two ceasing to be the look scrub, goes red.
//
//  ⭐ AND THE FIRST #480 PASS TRADED THE FALSE CLAIM FOR A DIFFERENT FALSE CLAIM — found by the
//  reviewer, measured before repairing. The replacement hint read "Open every effect stage —
//  filter, delay, modulation and dynamics, with every parameter exposed". `EchoelFXView` declares
//  FOURTEEN `effectSection(` calls AT THE TIME (fifteen since #692 added Granular — the
//  denominator is dated, not re-bumped, because it describes a hint that no longer exists);
//  those four categories covered eight. Saturation, Tape / VHS,
//  Bitcrush, Harmonizer, Reverb and Stereo Width fell outside all four, and Reverb is the one a
//  musician notices missing. Worse, the order was wrong as well: `EchoelFXChain.processStereo`
//  runs modulation BEFORE delay. A sighted user can glance at the sheet and see the rest; a
//  VoiceOver user has only that sentence. So `testTheDoorDoesNotEnumerateTheStages` derives the
//  stage names FROM `EchoelFXView` (#416 — one definition) and goes red if any of them appears in
//  the door's hint. The lesson is not "check the copy": it is that a list under the word "every"
//  is a completeness claim, and a completeness claim has to be re-counted every time the panel
//  grows, which is exactly the maintenance nobody performs.
//
//  ⚠️ HONEST GRADING — TWO of the five tests are regressions, each against a different baseline,
//  and saying "two" without saying against WHAT would be the #433 defect:
//    · `testTheFXDoorDoesNotNameASliderToVoiceOver` — red on `4df0393` (the pre-#480 tree).
//    · `testTheDoorDoesNotEnumerateTheStages` — red on `0ff8479` (#480's own first pass).
//  The other three are COUNTERWEIGHTS, green on both sides, and they are the half that earns the
//  file. The obvious next tidy-up after reading this commit is "sweep the word 'slider' out of the
//  app's copy" — which would take the visual-look customizer's heading, its per-chip VoiceOver
//  values and its hint, all of which name a control that genuinely exists and is a real `Slider`.
//
//  ⚠️ WHAT THIS CANNOT SHOW: that VoiceOver speaks the string, that the button is reachable on a
//  device, or that the new wording reads well aloud. Every assertion here is a SOURCE-TEXT scan.
//  Reachability was measured by hand instead: `effectsPanel` is returned from `dropdownContent`
//  for `.effects` (the Effects chip), and `showAllFX` has exactly one setter — this button.
//
//  ⚠️ The SF Symbol `slider.horizontal.3` on the button's own label is NOT a defect and is
//  explicitly allowed below. It is the conventional glyph for "parameters" (SF Symbols has no
//  value-field icon), and a symbol NAME is not a claim about a control type. Do not "fix" the icon
//  on the strength of this file. (⛔ The first version added "it is `accessibilityHidden` by virtue
//  of the label being replaced" — an invented mechanism. The button carries no `.accessibilityHidden`
//  and no `.accessibilityLabel`, so nothing is "replaced"; whether SwiftUI announces an
//  `Image(systemName:)` inside a `Button` label is a DEVICE question this file cannot answer. The
//  conclusion stands on the two real reasons; the mechanism is withdrawn.)
//

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFXDoorNamesAControlThatExistsTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    /// Comments blanked, one line per line (#453). Load-bearing here rather than prophylactic:
    /// the ⛔ block this slice added directly above the button QUOTES the forbidden phrase
    /// ("every parameter as a slider") twice, so a raw-text scan would be RED on correct code.
    private func codeLines(_ relative: String) throws -> [String] {
        SourceText.codeOnly(try source(relative)).components(separatedBy: "\n")
    }

    private let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private let floating = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    /// Lines taken from the `showAllFX = true` anchor forward. Measured offsets are in the doc
    /// comment of `testTheFXDoorDoesNotNameASliderToVoiceOver`; this number is chosen against
    /// them, not by feel.
    private static let windowLines = 32

    /// The FX door's own lines. Returns EMPTY when the anchor is not unique, so a caller that
    /// forgets to assert uniqueness fails loudly instead of measuring an arbitrary button.
    private func doorWindow(_ lines: [String]) throws -> [String] {
        let anchors = lines.indices.filter { lines[$0].contains("showAllFX = true") }
        guard anchors.count == 1, let anchor = anchors.first else { return [] }
        return Array(lines[anchor..<min(anchor + Self.windowLines, lines.count)])
    }

    /// Every stage title the FX panel actually declares, read out of `effectSection("…")`.
    /// One definition (#416): the ban list below cannot drift from the panel it describes.
    private func stageNames() throws -> [String] {
        var names: [String] = []
        for line in try codeLines(fxView) {
            guard let call = line.range(of: "effectSection(\"") else { continue }
            let rest = line[call.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { continue }
            names.append(String(rest[rest.startIndex..<close]))
        }
        return names
    }

    // MARK: - The regression

    /// The FX door's VoiceOver hint must not name a control the panel does not contain.
    ///
    /// WINDOWED from the `showAllFX = true` anchor rather than scanning the file, because
    /// "slider" is honest copy elsewhere in this same file (the visual-look customizer).
    /// Measured on the shipped tree with `codeOnly` applied: the hint sits at **+21**, the
    /// PREVIOUS `.accessibilityHint(` at −74 and the NEXT at +501. The window is `doorWindow`
    /// lines, comfortably inside that gap in both directions, so it can neither reach a
    /// neighbour nor be satisfied by somebody else's hint.
    ///
    /// The window must CONTAIN a hint — without that half, deleting the hint outright would
    /// leave this green on nothing (#343).
    func testTheFXDoorDoesNotNameASliderToVoiceOver() throws {
        let lines = try codeLines(studio)
        let anchors = lines.indices.filter { lines[$0].contains("showAllFX = true") }
        XCTAssertEqual(anchors.count, 1, """
            `showAllFX` must have exactly one setter — the "All parameters" button in \
            `effectsPanel`. A second setter means this window no longer identifies the door and \
            the scan below is measuring an arbitrary one of them.
            """)
        guard let anchor = anchors.first else { return }

        let window = try doorWindow(lines)
        XCTAssertTrue(window.contains { $0.contains(".accessibilityHint(") }, """
            The FX door lost its `.accessibilityHint(` (or it moved more than \(Self.windowLines) \
            lines from the `showAllFX = true` anchor at line \(anchor + 1)). Without a hint in the \
            window this test asserts nothing — restore the hint, or widen the window deliberately \
            and say why.
            """)

        for line in window {
            // The SF Symbol is the one allowed occurrence — see the ⚠️ note in the file header.
            let withoutSymbol = line.replacingOccurrences(of: "slider.horizontal.3", with: "")
            XCTAssertNil(withoutSymbol.range(of: "slider", options: .caseInsensitive), """
                A line in the FX door says "slider". If that is the hint, it names a control the \
                panel does not contain: `Studio/EchoelFXView.swift` declares zero `Slider(`, its \
                numeric parameters are `EchoelValueField`s and its named ones are `Picker`s. If it \
                is an identifier rather than user-visible copy, this message is pointing at the \
                wrong thing — narrow the scan, do not delete it. \
                Line: \(line.trimmingCharacters(in: .whitespaces))
                """)
        }
    }

    /// The SECOND false claim, and the one that #480's own first pass shipped: the door must not
    /// ENUMERATE what is behind it. A subset under the word "every" reads as exhaustive, and the
    /// four categories that pass named eight of the fourteen stages there were then.
    ///
    /// The needle list is DERIVED from `EchoelFXView`, never repeated here (#416) — so adding a
    /// stage automatically extends the ban instead of quietly falling outside a hand-written
    /// list, which is precisely how the first version rotted.
    ///
    /// ⭐ #693 — AND THAT PROMISE WAS KEPT, WHICH IS WHY IT IS WORTH RECORDING. This line said
    /// "adding a FIFTEENTH stage automatically extends the ban"; #692 added the fifteenth
    /// (Granular) and this test needed no edit — `stageNames()` picked it up and the hint was
    /// re-checked against it for free. Every hand-written count in the same file DID have to be
    /// walked. A derived list survives the change that dates a literal; that is the whole
    /// argument for #416 in one commit.
    ///
    /// RED against `0ff8479`, where the hint said "filter, delay, modulation and dynamics".
    func testTheDoorDoesNotEnumerateTheStages() throws {
        let stages = try stageNames()
        XCTAssertGreaterThan(stages.count, 10, """
            Only \(stages.count) `effectSection("…")` stages found in `EchoelFXView.swift` — the \
            scan below has lost its needles and would pass on anything. Fix the extraction, do \
            not relax the assertion. (The count is printed above and derived on every run; a \
            literal used to sit here and was one short from #692 until #693 removed it.)
            """)

        let hints = try doorWindow(codeLines(studio)).filter { $0.contains(".accessibilityHint(") }
        XCTAssertFalse(hints.isEmpty, "the FX door has no hint to check — see the test above")

        for hint in hints {
            for stage in stages {
                XCTAssertNil(hint.range(of: stage, options: .caseInsensitive), """
                    The FX door's hint names the stage "\(stage)". Naming SOME stages under the \
                    word "every" is a completeness claim, and it was false the last time it was \
                    written: four categories covered 8 of \(stages.count). A VoiceOver user cannot \
                    glance at the sheet to see what the sentence left out. Say "every effect \
                    stage" and let the panel be the inventory. Hint: \
                    \(hint.trimmingCharacters(in: .whitespaces))
                    """)
            }
        }
    }

    // MARK: - Counterweights (green on both sides, and that is the point)

    /// The premise. If `EchoelFXView` ever gains a real `Slider`, the hint COULD honestly say so
    /// again — but that is a divergence from the app-wide `EchoelValueField` law and goes to The
    /// Council, not into a string. This assertion makes the premise moving visible instead of
    /// leaving the copy quietly wrong in the other direction.
    ///
    /// ⛔ The first version was a BARE negative — `sites.isEmpty` and nothing else — which is
    /// green on an emptied, renamed or split-up file. The test directly above it adds a "the
    /// window must CONTAIN a hint" half for exactly that reason and cites #343 while doing it;
    /// the very next test then omitted the equivalent. The stage count is the positive anchor.
    func testTheDoorsOwnPanelDeclaresNoSlider() throws {
        let lines = try codeLines(fxView)
        // Bound OUTSIDE the assertion: the message parameter is a non-throwing `@autoclosure`,
        // so a `try` inside it does not compile — and there is no compiler in this session.
        let stageCount = try stageNames().count
        XCTAssertGreaterThan(stageCount, 10, """
            `EchoelFXView.swift` no longer declares the stages this test is about (found \
            \(stageCount), and the floor is 10). The negative assertion below would pass on \
            an empty or renamed file — re-point it, do not delete it. No literal count here: \
            the one that used to be went stale at #692 inside a message nothing re-derives.
            """)
        let sites = lines.filter { $0.contains("Slider(") }
        XCTAssertTrue(sites.isEmpty, """
            `EchoelFXView.swift` now declares a raw `Slider(` — \(sites.count) of them. The UI \
            law is "no raw `Slider`/`Stepper` for parameters" (CLAUDE.md); if this is a \
            deliberate exception it needs The Council and the FX door's hint needs revisiting.
            """)
    }

    /// The UI law made falsifiable. Exactly TWO raw `Slider(` in `Sources/`, both the look scrub,
    /// and ZERO `Stepper(` anywhere.
    ///
    /// ⚠️ LINE-BASED, not paren-matched: both of today's sites fit on one line. A future
    /// multi-line `Slider(` would still be COUNTED (the `Slider(` token is on its own line) but
    /// its `lookScrub` binding might not be, so the second half would go red for a shape reason
    /// rather than a truth reason. Said here rather than pretended away.
    ///
    /// ⚠️ And `contains("Slider(")` is a SUFFIX match: `EchoelSlider(`, `LabeledSlider(` and
    /// `SwiftUI.Slider(` all count, while `Slider (value:` with a space does not. Deliberately
    /// left loose — over-counting fails CLOSED (someone reads the message and looks), whereas
    /// tightening it to a word boundary would let a wrapper type through unremarked.
    func testTheAppsOnlyRawSlidersAreTheLookScrub() throws {
        var sliderSites: [(file: String, text: String)] = []
        var stepperSites: [String] = []
        let root = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            XCTFail("could not walk Sources/ — the scan checked nothing")
            return
        }
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            for line in SourceText.codeOnly(text).components(separatedBy: "\n") {
                if line.contains("Slider(") {
                    // Labels written OUT at the append. `[(String, String)]` and
                    // `[(file: String, text: String)]` are different types once they are an
                    // Array's element, and there is no compiler in this session to catch a
                    // mismatch — this repo has already paid for that once.
                    sliderSites.append((file: rel,
                                        text: line.trimmingCharacters(in: .whitespaces)))
                }
                if line.contains("Stepper(") {
                    stepperSites.append("\(rel): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(stepperSites.isEmpty, """
            A raw `Stepper(` appeared in Sources/. The UI law bans it for parameters and the app \
            has shipped without one: \(stepperSites.joined(separator: " · "))
            """)

        XCTAssertEqual(sliderSites.count, 2, """
            Sources/ declares \(sliderSites.count) raw `Slider(`, not 2. The two known ones are \
            the visual look scrub (EchoelStudioView + FloatingVisualWindow), which are morphs \
            between NAMED looks and not parameter rows. A third is a divergence from \
            `EchoelValueField` and goes to The Council. Sites: \
            \(sliderSites.map { $0.file }.joined(separator: " · "))
            """)

        for site in sliderSites {
            XCTAssertTrue(site.text.contains("lookScrub"), """
                A raw `Slider(` in \(site.file) does not bind `lookScrub`, so it is not the \
                documented look-scrub exception: \(site.text)
                """)
        }
    }

    /// The tidy-up counterweight. The visual-look customizer calls its control a slider because
    /// it IS one — deleting that copy in the name of #480 would take honest wording with it, and
    /// would leave the one real `Slider` in the instrument unnamed for VoiceOver.
    func testTheHonestSliderCopyIsNotSweptUp() throws {
        let studioCode = try codeLines(studio).joined(separator: "\n")
        XCTAssertTrue(studioCode.contains("Slider looks"), """
            The visual-look customizer's heading is gone. That copy names a control that really \
            is a `Slider` — #480 removed the word only where no slider exists.
            """)
        XCTAssertTrue(studioCode.contains("Visual look"), """
            The look scrub lost its `accessibilityLabel`. It is the app's only raw `Slider` on \
            this surface and VoiceOver has nothing else to announce it by.
            """)
        let floatingCode = try codeLines(floating).joined(separator: "\n")
        XCTAssertTrue(floatingCode.contains("Visual look"), """
            The fullscreen window's look scrub lost its `accessibilityLabel` — same control, \
            same reason.
            """)
    }
}
