// TheLookReadoutKnowsWhichPictureItLabelsTests.swift
// Echoel — #1056. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1).
//
// ⭐ WHY THIS FILE EXISTS, AND IT GUARDS A LINK RATHER THAN A VALUE. `visualLookStrip` prints
// either "Donuts" or the Metal look's name, decided by `showsDonutState` — a parameter whose
// correct value is not a preference but a FACT about the picture the strip sits next to: can
// that picture render `SpectralDonutView` at all?
//
// #227 removed this readout's first lie (an unconditional ternary printing "Donuts" over a
// Metal look). #1043 then gave `FloatingVisualWindow` its own donut branch — and did not carry
// the claim that depended on the window NOT having one (#456). The Field panel kept passing
// `false`, so for two cycles it printed "Aurora" over a window that was rendering donuts: the
// same lie, arriving from the opposite direction, in the surface the founder actually uses.
//
// ⭐ SO THE CLAIM IS CONDITIONAL, NOT A PIN. Claim 2 asserts what claim 1 MEASURED implies. If
// a future slice removes the window's donut branch, claim 1 goes red first and its message says
// to re-derive the arguments rather than to "restore" a `true` that would then be the lie. A
// guard that simply pinned `true` twice would rot in exactly the way this defect rotted.
//
// ⛔ AND IT MUST NOT BE READ AS "the parameter is pointless now" (#367/#364). Claim 3 is the
// counterweight: the parameter must SURVIVE both callers agreeing. A third picture already
// exists — `ExternalDisplayScene` renders the Metal field and nothing else, and the window's
// external-stage branch is checked BEFORE its donut branch, so with a projector attached no
// donut is on any screen. A strip mounted next to that picture has to pass `false`, and
// deleting the parameter because today's two callers agree would remove the only place the
// question is asked.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **Five assertions across four claims**
// (1 · 2 · 1 · 1), driven against both trees. Against the pre-slice tree ONE is RED — the
// `showsDonutState: false` count, which was 1 and must be 0 — and four are green. So **1
// REGRESSION CATCH, 4 COUNTERWEIGHTS**, and that single catch is the whole defect: the other
// four exist to stop the repair being undone by a plausible cleanup. Counted from the driven
// run, not from the outline (#1054).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheLookReadoutKnowsWhichPictureItLabelsTests: XCTestCase {

    private static let studioFile = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let windowFile = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    private func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass (#454).")
            return ""
        }
        // Comment-stripped: this repo writes long ⛔ blocks that quote the very call sites
        // being counted, and #1050 retracted a pin whose number was code plus prose.
        return SourceText.codeOnly(text)
    }

    /// claim 1 — the PREMISE, measured rather than assumed: the floating window can render the
    /// donut. Everything below is only true because this is.
    func testTheFloatingWindowCanRenderTheDonut() throws {
        let window = try code(Self.windowFile)
        XCTAssertTrue(window.contains("spectralDonuts, !mustKeepRenderingForRecording"), """
            `FloatingVisualWindow` no longer branches its picture on `spectralDonuts`. That \
            branch is the PREMISE of claim 2 below — if it genuinely went away, the Field \
            panel's `visualLookStrip(showsDonutState:)` argument must go back to `false` in \
            the SAME commit, and this claim re-points at whatever replaced it. Do not fix \
            this by re-adding a branch you did not intend; re-derive the arguments.
            """)
        XCTAssertTrue(window.contains("SpectralDonutView("), """
            The window no longer constructs `SpectralDonutView`. Same reasoning as above: the \
            readout's argument follows the picture, not the other way round.
            """)
    }

    /// claim 2 — therefore no mount may claim it cannot show a donut. Written as a count of the
    /// wrong value, so a SECOND mount passing `false` is caught too, not just the one that exists
    /// (⛔ "the two that exist" until #1104 — #1069 deleted the cover and its VJ-overlay mount).
    func testNoMountClaimsItCannotShowADonutWhileItsPictureCan() throws {
        let studio = try code(Self.studioFile)
        let wrong = studio.components(separatedBy: "visualLookStrip(showsDonutState: false)").count - 1
        XCTAssertEqual(wrong, 0, """
            \(wrong) mount(s) still pass `showsDonutState: false`. Today's one picture — the \
            Field panel's `FloatingVisualWindow` (the `.fullScreenCover` VJ overlay went with \
            #1069) — renders `SpectralDonutView`, so `false` there prints a Metal look's name over a \
            donut field. That is the lie #227 removed, re-introduced by #1043 from the other \
            side. If a NEW mount was added next to a picture that genuinely cannot show the \
            donut (an external-stage strip, say), this claim is where to say so.
            """)
    }

    /// claim 3 — the counterweight (#367/#364). The one caller passing `true` must NOT become a
    /// reason to delete the parameter: a picture that cannot show the donut already exists.
    func testTheParameterSurvivesTheOneCallerPassingTrue() throws {
        let studio = try code(Self.studioFile)
        XCTAssertTrue(studio.contains("visualLookStrip(showsDonutState: Bool)"), """
            `visualLookStrip` lost its `showsDonutState` parameter. Today's one caller passes \
            `true`, which reads like a dead argument — it is not. `ExternalDisplayScene` \
            renders the Metal field and nothing else, and the window checks its external-stage \
            branch BEFORE its donut branch, so with a projector attached no donut is on any \
            screen. Removing the parameter removes the only place that question is asked, and \
            the next mount inherits the #227 bug with nothing to catch it.
            """)
    }

    /// claim 4 — and the readout still ASKS the parameter. Claim 3 keeps the signature; this
    /// keeps it load-bearing, so it cannot decay into an ignored argument.
    func testTheReadoutStillConsultsTheParameter() throws {
        let studio = try code(Self.studioFile)
        XCTAssertTrue(studio.contains("showsDonutState && spectralDonuts ? \"Donuts\""), """
            The look readout no longer consults `showsDonutState`. A parameter that is passed \
            and never read is worse than none: claim 3 would still pass, the signature would \
            still look like a guard, and every mount would print the same string regardless of \
            its picture — the unconditional ternary #227 deleted.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Field-Panel öffnen, das schwebende Visual auf Donuts stellen (Vollbild →
// Donut-Taste), zurück ins Field-Panel — steht in der Look-Zeile jetzt „Donuts" statt eines
// Metall-Look-Namens? Gegenprobe: zurück auf das Feld schalten, dort muss wieder der Look-Name
// stehen.
