import XCTest
@testable import Echoelmusic

/// #1065 — the spectrum-donut look can be entered from a surface that is not the cover.
///
/// WHY IT EXISTS, and it is a prerequisite rather than a tidy-up. Before this slice,
/// `git grep -n "spectralDonuts.toggle()\|spectralDonuts =" -- Sources` returned exactly ONE
/// writer capable of producing `true`: the glyph button in the fullscreen COVER's top bar.
/// `lookScrub`'s setter writes only `false` (scrubbing the look always lands on a metal field)
/// and `FloatingVisualWindow` only READS the flag. S3 of PLAN_ONE_VISUAL_SURFACE_2026-09-07
/// deletes that cover — which would have left the donut look a state nothing can enter, the
/// #227 defect described in four places in `EchoelStudioView`, with the renderer #1043 had just
/// ported into the floating window unreachable again.
///
/// ⚠️ WHAT THIS FILE PINS is the CAPABILITY, not today's arrangement (#364). A future slice may
/// move the switch, restyle it, or fold it into a look picker; all of those keep this green.
/// Only losing the last non-cover way in fails it — including by deleting the cover without
/// having replaced its glyph, which is precisely the mistake this exists to stop.
final class TheDonutLookSurvivesTheCoverTests: XCTestCase {

    private func studioSource() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: EchoelStudioView.swift could not be read — a missing "
                    + "anchor is a finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — a switch exists, and it can turn the look ON. A binding is the whole point: a Button
    // that only ever wrote `false` is what `lookScrub` already had, and it is why the flag was
    // one-way.
    func testAWordedSwitchCanEnterTheDonutLook() throws {
        let studio = try studioSource()
        XCTAssertTrue(studio.contains("Toggle(isOn: $spectralDonuts)"), """
            No two-way switch for the donut look outside the cover's glyph. Measured before \
            #1065: the cover's top bar was the ONLY writer that could produce `true`. If the \
            switch moved, re-anchor this needle; if it was deleted, the look is unreachable \
            again and the deleted `normaliseUnreachableDonutMode()` becomes necessary once more.
            """)
        XCTAssertTrue(studio.contains("Spectrum donuts instead of the field"), """
            The switch lost its words. The control it replaces was a glyph whose meaning \
            existed only in VoiceOver — replacing one wordless control with another would \
            miss the point of moving it.
            """)
    }

    // 2 — the switch is in the PANEL, not inside the fullscreen cover. This is the claim that
    // actually survives S3: an ordering check, because the panel is declared far below the
    // cover's block and stays there when the cover goes.
    func testTheSwitchIsBelowThePanelDeclarationAndNotInTheCover() throws {
        let studio = try studioSource()
        guard let panel = studio.range(of: "private var visualPanel: some View"),
              let toggle = studio.range(of: "Toggle(isOn: $spectralDonuts)") else {
            XCTFail("""
                Could not locate `visualPanel`'s declaration or the donut switch. Re-anchor \
                this case in the same commit rather than deleting it — its subject is that the \
                switch lives in the panel and not in a modal that is scheduled for deletion.
                """)
            return
        }
        XCTAssertTrue(panel.lowerBound < toggle.lowerBound, """
            The donut switch sits ABOVE `visualPanel`'s declaration, i.e. in the body chain \
            where the fullscreen cover lives. Deleting the cover would take the switch with \
            it and leave the look unreachable — the exact sequence this file exists to make \
            impossible.
            """)

        // COUNTERWEIGHT (#367): the flag is genuinely one-way without this switch. If a second
        // ON-writer ever appears elsewhere, this claim goes red and should be widened — that is
        // good news being reported, not a failure.
        //
        // ⛔ COUNTED THROUGH `SourceText.codeOnly`, AND THE FIRST VERSION WAS NOT — it counted 2
        // where the code has 1, because the header of this very file QUOTES the grep recipe
        // that contains the needle. That is #1050 exactly: a raw-text count pin counting its
        // own documentation. Left as a note rather than by deleting the recipe, because the
        // recipe is how the next reader re-derives the finding.
        let code = SourceText.codeOnly(studio)
        let onWriters = code.components(separatedBy: "spectralDonuts.toggle()").count - 1
        XCTAssertLessThanOrEqual(onWriters, 1, """
            More than one `spectralDonuts.toggle()` call site (\(onWriters)). Two toggles for \
            one flag is not automatically wrong — the record button has had two doors since \
            #747 — but it must be deliberate, so say which surfaces own it and widen this \
            counterweight rather than letting the count drift.
            """)
    }
}
