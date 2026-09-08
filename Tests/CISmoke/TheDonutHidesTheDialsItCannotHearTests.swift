// TheDonutHidesTheDialsItCannotHearTests.swift
// Echoel — #1057. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// which rows are CONDITIONAL, never what a screen looks like.
//
// ⭐ WHY THIS FILE EXISTS. `SpectralDonutView` declares exactly two inputs — `reduceMotion` and
// `bandCount`, and `bandCount` is `max(8, Int(visualDetail))`. So in donut mode Detail is live
// and Energy, Intensity, Motion, Spread, Hue, Saturation, Texture, Glitter and Structure are
// inert: NINE dials a player can drag while nothing on screen changes. That is the lying-control
// class #1003 fixed for one row, here nine rows wide, on the surface the founder asked to make
// "kompakter und übersichtlicher".
//
// ⭐ THE PREMISE IS MEASURED, NOT ASSUMED (claim 4, the shape #1056 introduced). If a future
// slice feeds the donut more parameters, claim 4 goes red and its message says what the repair
// is: UNHIDE the rows that now reach the picture. A guard that only pinned "these rows are
// hidden" would fight the improvement instead of following it (#364).
//
// ⛔ AND THE CONDITION IS NOT `spectralDonuts` (claim 2, the counterweight that matters most).
// With a projector attached, `FloatingVisualWindow` checks its external-stage branch BEFORE its
// donut branch — the window shows a placard while `ExternalDisplayScene` renders the METAL FIELD
// and reads `visual.hue`/`visual.saturation` from the very keys these rows write. In that state
// the dials DO reach a picture, the beamer's, and hiding them would swap a lying control for a
// missing one. `donutIsThePicture` is that two-term question, named once.
//
// ⛔ AND DETAIL MUST SURVIVE (claim 3). The obvious over-correction is to hide the whole fine-tune
// block in donut mode, which would remove the ONE control that works. The fix is a scalpel, not a
// switch.
//
// ⚠️ WHAT THIS SLICE DID NOT TOUCH, said plainly so a reader does not infer it did: the look
// slider and the preset row also do nothing to a donut. They are a DOOR question (the inline
// panel has no donut toggle at all — only the fullscreen overlay does), which belongs to the
// founder's "eine Steuer-Einheit" ask and not to a caption fix.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **Seven assertions across four claims**
// (3 · 2 · 1 · 1), driven against both trees. Against the pre-slice tree the three assertions of
// claim 1 and the first of claim 2 are RED (no `donutIsThePicture` anywhere, no conditional
// blocks); claim 3 and claim 4 and the second half of claim 2 are green. So **4 REGRESSION
// CATCHES, 3 COUNTERWEIGHTS**. Counted from the driven run, not from the outline (#1054).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDonutHidesTheDialsItCannotHearTests: XCTestCase {

    private static let studioFile = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let donutFile = "Sources/Echoelmusic/Studio/SpectralDonutView.swift"

    private func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass (#454).")
            return ""
        }
        // Comment-stripped (#1050): this file's subject is quoted at length in the ⛔ blocks it
        // guards, and a raw scan would count that prose as code.
        return SourceText.codeOnly(text)
    }

    /// claim 1 — the field's dials are CONDITIONAL on the donut not being the picture. Three
    /// separate blocks, because the rows sit in three places (the Energy pair, the second grid,
    /// and the Intensity row inside the first grid).
    func testTheFieldDialsAreHiddenWhenTheDonutIsThePicture() throws {
        let studio = try code(Self.studioFile)
        let guarded = studio.components(separatedBy: "if !donutIsThePicture").count - 1
        XCTAssertGreaterThanOrEqual(guarded, 3, """
            Only \(guarded) block(s) in `EchoelStudioView` are gated on `!donutIsThePicture`; \
            at least three are needed — the Intensity row inside the first grid, the \
            `detailReach` caption, and the whole second grid (Motion · Spread · Hue · \
            Saturation · Texture · Glitter · Structure). Anything ungated is a dial the player \
            can drag while the donut ignores it.
            """)
        XCTAssertTrue(studio.contains("if donutIsThePicture {"), """
            The donut branch of `visualAdjustFields` is gone. It carries the one sentence that \
            explains WHY nine rows are missing; without it the panel just looks broken.
            """)
        XCTAssertTrue(studio.contains("Switch back to the field to use them."), """
            The donut-mode explanation is gone. Hiding nine controls without saying so is the \
            other half of the lying-control defect: the player cannot tell "not applicable here" \
            from "this build lost its dials".
            """)
    }

    /// claim 2 — the counterweight (#367). The condition must include the external-stage term,
    /// and it must be named ONCE rather than spelled out at each of the four uses.
    func testTheConditionAsksAboutThePictureNotJustTheToggle() throws {
        let studio = try code(Self.studioFile)
        XCTAssertTrue(
            studio.contains("private var donutIsThePicture: Bool { spectralDonuts && !isProjectingExternally }"),
            """
            `donutIsThePicture` is gone or no longer excludes the external stage. With a \
            projector attached the window shows a placard and `ExternalDisplayScene` renders \
            the METAL FIELD from these same keys — so the dials DO reach a picture and hiding \
            them trades a lying control for a missing one. If the projector path changed, \
            re-derive this from `FloatingVisualWindow`'s branch ORDER, not from the toggle.
            """)
        XCTAssertTrue(studio.contains("private var isProjectingExternally: Bool"), """
            `isProjectingExternally` is gone. It is the one definition of "a projector is \
            attached" (#1044) and both the keep-awake law and this condition read it; a second \
            spelling would be #416 and the two would drift.
            """)
    }

    /// claim 3 — the scalpel, not the switch. Detail is the ONE row that reaches the donut and
    /// it must NOT be swept away with the other nine.
    func testDetailSurvivesDonutMode() throws {
        let studio = try code(Self.studioFile)
        let rows = studio.components(separatedBy: "label: \"Detail\"").count - 1
        XCTAssertEqual(rows, 1, """
            Expected exactly one `label: "Detail"` row in `EchoelStudioView`, found \(rows). \
            One means it is declared once and shown in BOTH modes — which is the point: it is \
            the only dial the donut reads (`bandCount: max(8, Int(visualDetail))`). Zero means \
            the fix over-corrected and hid the working control; two means a donut-mode copy was \
            added, which is #416 and breaks the two guards that count rows in that member.
            """)
    }

    /// claim 4 — the PREMISE, measured. This is what makes the slice self-correcting rather than
    /// a permanent verdict on the donut.
    func testTheDonutStillDeclaresOnlyTwoInputs() throws {
        let donut = try code(Self.donutFile)
        let hasOnlyTwo = donut.contains("var reduceMotion: Bool")
            && donut.contains("var bandCount: Int")
            && !donut.contains("var saturation")
            && !donut.contains("var hueShift")
        XCTAssertTrue(hasOnlyTwo, """
            `SpectralDonutView`'s inputs changed. The nine hidden rows are hidden because the \
            donut CANNOT read them — if it now can, the repair is to UNHIDE the rows you just \
            wired and shorten the donut-mode sentence in `visualAdjustFields`, in this commit. \
            This claim exists so the fix follows the improvement instead of outliving it (#364).
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Field-Panel öffnen, den Schalter „Spectrum donuts instead of the field"
// einschalten, dann im selben Panel auf „Fine tune" — es dürfen nur noch die Erklärzeile und
// „Detail" dastehen, und Detail muss die Ringzahl sichtbar ändern. Gegenprobe mit Beamer/AirPlay
// VERBUNDEN: dann müssen ALLE Regler wieder da sein, weil der externe Schirm das Metall-Feld
// zeigt und Hue/Saturation dort wirklich wirken.
//
// ⛔ DIESE BITTE NANNTE „Vollbild-Visual → Donut-Taste" UND SCHICKTE DAMIT AN EINE TÜR, DIE ES
// NICHT MEHR GIBT (#1145). Die Donut-Taste saß in der Vollbild-Chrome, die #1069 gelöscht hat;
// gemessen ist der EINE Schreiber von `spectralDonuts` heute der `Toggle(isOn: $spectralDonuts)`
// im Field-Panel (`EchoelStudioView.swift:5280`, Befehl: `git grep -n "spectralDonuts.toggle()\|
// spectralDonuts *=\|\$spectralDonuts" -- Sources`). Die FÄHIGKEIT war die ganze Zeit erreichbar
// — nur der WEG war weg. Das ist eine eigene Klasse: nicht BLOCKIERT (`founder-verify.py` sieht
// so etwas nicht), sondern FEHLGELEITET. Sie kostet den Founder eine Geräte-Sitzung, in der er
// eine Taste sucht statt eine Frage zu beantworten.
