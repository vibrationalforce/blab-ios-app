//
//  TheFXDoorNamesAControlThatExistsTests.swift
//  EchoelmusicTests (CISmoke — the BLOCKING bundle)
//
//  #480. The "All parameters" button in `effectsPanel` told VoiceOver it opens "the full effects
//  chain — every parameter as a slider". `Studio/EchoelFXView.swift` declares ZERO `Slider(`;
//  every numeric parameter there is an `EchoelValueField` and every named one is a `Picker`.
//
//  ⭐ WHAT MAKES THIS WORTH A GUARD IS WHERE THE REFUTATION SAT: four lines above the button, in
//  a comment written for exactly this purpose — "NOT 'as sliders' — numeric parameters are
//  `EchoelValueField`s, and a parameter whose values have NAMES is a picker". Somebody corrected
//  the surrounding prose and left the string. A claim standing next to its own refutation, in the
//  one layer a sighted reviewer never opens: the accessibility hint is invisible unless VoiceOver
//  is on, so no screenshot, no design pass and no UI review would ever have surfaced it.
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
//  ⚠️ HONEST GRADING — exactly ONE of the four assertions is a regression against the pre-#480
//  tree (`testTheFXDoorDoesNotNameASliderToVoiceOver`). The other three are COUNTERWEIGHTS and
//  are green on both sides, and they are the half that earns the file. The obvious next tidy-up
//  after reading this commit is "sweep the word 'slider' out of the app's copy" — which would
//  take the visual-look customizer's heading, its per-chip VoiceOver values and its hint, all of
//  which name a control that genuinely exists and is genuinely a `Slider`.
//
//  ⚠️ WHAT THIS CANNOT SHOW: that VoiceOver speaks the string, that the button is reachable on a
//  device, or that the new wording reads well aloud. Every assertion here is a SOURCE-TEXT scan.
//  Reachability was measured by hand instead: `effectsPanel` is returned from `dropdownContent`
//  for `.effects` (the Effects chip), and `showAllFX` has exactly one setter — this button.
//
//  ⚠️ The SF Symbol `slider.horizontal.3` on the button's own label is NOT a defect and is
//  explicitly allowed below. It is the conventional glyph for "parameters" (SF Symbols has no
//  value-field icon), it is `accessibilityHidden` by virtue of the label being replaced, and a
//  symbol name is not a claim about a control type. Do not "fix" the icon on the strength of
//  this file.
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

    // MARK: - The regression

    /// The FX door's VoiceOver hint must not name a control the panel does not contain.
    ///
    /// WINDOWED from the `showAllFX = true` anchor rather than scanning the file, because
    /// "slider" is honest copy elsewhere in this same file (the visual-look customizer). The
    /// window is 24 lines; measured on the shipped tree the hint sits at +14, the PREVIOUS
    /// `.accessibilityHint(` at −65 and the NEXT at +494, so it cannot reach a neighbour in
    /// either direction and cannot be satisfied by somebody else's hint.
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

        let window = Array(lines[anchor..<min(anchor + 24, lines.count)])
        XCTAssertTrue(window.contains { $0.contains(".accessibilityHint(") }, """
            The FX door lost its `.accessibilityHint(` (or it moved more than 24 lines from the \
            `showAllFX = true` anchor). Without a hint in the window this test asserts nothing — \
            restore the hint, or widen the window deliberately and say why.
            """)

        for line in window {
            // The SF Symbol is the one allowed occurrence — see the ⚠️ note in the file header.
            let withoutSymbol = line.replacingOccurrences(of: "slider.horizontal.3", with: "")
            XCTAssertNil(withoutSymbol.range(of: "slider", options: .caseInsensitive), """
                The FX door names a "slider" to the user. `Studio/EchoelFXView.swift` declares \
                zero `Slider(` — its numeric parameters are `EchoelValueField`s and its named \
                ones are `Picker`s. Offending line: \(line.trimmingCharacters(in: .whitespaces))
                """)
        }
    }

    // MARK: - Counterweights (green on both sides, and that is the point)

    /// The premise. If `EchoelFXView` ever gains a real `Slider`, the hint COULD honestly say so
    /// again — but that is a divergence from the app-wide `EchoelValueField` law and goes to The
    /// Council, not into a string. This assertion makes the premise moving visible instead of
    /// leaving the copy quietly wrong in the other direction.
    func testTheDoorsOwnPanelDeclaresNoSlider() throws {
        let lines = try codeLines(fxView)
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
