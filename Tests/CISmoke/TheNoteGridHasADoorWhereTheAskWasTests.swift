import XCTest
@testable import Echoelmusic

/// #1064 — the note grid has a switch in the panel the founder's ask was about.
///
/// WHY IT EXISTS. The ask names three things: *"Die physikalisch korrekte Darstellung der
/// Farbtöne, das Ton Gitter, das Menü kompakter."* The grid's only control was a glyph-only
/// button in the floating window's chrome bar, THIRD in that bar's shed order — so on a 375 pt
/// phone with a WAV take running it is not on screen at all (`ChromeBudgetFitsTests` drives
/// exactly that state), and the Field panel, which is where a player goes to decide how the
/// field is shown, had no switch for it whatever the width.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. It renders no SwiftUI, so whether the row reads well in the
/// panel is the founder's look. What it pins is that the door EXISTS, that it moves the ONE
/// stored flag the window already writes, and that the window's button was not quietly traded
/// away for it.
final class TheNoteGridHasADoorWhereTheAskWasTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — the door is in the Studio panel, it has WORDS, and it moves the flag.
    func testTheFieldPanelCarriesAWordedSwitchForTheGrid() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains("Toggle(isOn: $touchShowGrid)"), """
            `EchoelStudioView` no longer carries a switch for the note grid. Then the only \
            control is again the chrome-bar glyph, which the width budget drops third — the \
            defect this slice repaired, and the founder named the grid explicitly.
            """)
        XCTAssertTrue(studio.contains("Note grid on the field"), """
            The switch lost its words. A glyph-only control is what it was replacing: the \
            bar's own comments cite WCAG 2.2 against gating a capability behind something \
            with no words. If the wording changed, re-anchor this needle in the same commit.
            """)
    }

    // 2 — ONE stored flag, not two. A second key is the defect where a switch moves and
    // nothing on screen changes, and it would look completely correct in review.
    func testBothSurfacesMoveTheSameStoredFlag() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let window = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        for (name, text) in [("EchoelStudioView", studio), ("FloatingVisualWindow", window)] {
            XCTAssertTrue(text.contains("@AppStorage(StudioDefaultKeys.touchShowGrid.key)"), """
                \(name) does not bind the grid through `StudioDefaultKeys.touchShowGrid`. \
                Two surfaces reading two keys is a switch that appears to work and changes \
                nothing — the key is declared once so that cannot happen.
                """)
            XCTAssertFalse(text.contains("@AppStorage(\"touch.showGrid\")"), """
                \(name) spells the key as a literal. The literal and the constant agree \
                today; a rename would move one and leave the other, silently.
                """)
        }

        // COUNTERWEIGHT (#367/#364): the door was ADDED, not moved. Without this, claim 1
        // would pass over a tree where the panel gained a switch and the window lost its
        // button — which would take the control away from the surface the app cold-launches
        // into, in a commit whose message says a control was added.
        XCTAssertTrue(window.contains("Button { touchShowGrid.toggle() }"), """
            The floating window's own grid button is gone. Both places may press the one \
            flag; the window's is the one you can reach while looking at the picture. If it \
            was deliberately removed, say so in the commit and retire this counterweight — \
            do not leave the claim asserting a control that no longer exists.
            """)
    }
}
