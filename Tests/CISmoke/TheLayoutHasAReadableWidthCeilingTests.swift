import XCTest

/// #1025 — THE CONTROL COLUMN MAY NOT GROW WIDER THAN IT CAN BE READ.
///
/// WHY. Founder clip, 2026-09-06, build v10.79.448 (2567): *"Die adaptive View muss her. Es
/// muss vermieden werden, dass wir plötzlich verzerrte und zu große Fenster haben."* The
/// frames show it precisely — the Mix panel's closing paragraph stops wrapping and runs off
/// the right edge, and the Routing sheet (`PatchbayView`) is cut on BOTH sides at once.
///
/// ⛔ THE CAUSE NAMED HERE WAS WRONG AND IS WITHDRAWN (#1026). This file said the defect was
/// the rotation — that `Info.plist` declares landscape for iPhone, that removing those two
/// entries was "the real fix", and that this ceiling was a stand-in for it. The founder
/// measured it on the device: *"Queer war doch alles gut. Nur hochkant war nicht passend."*
/// Landscape was fine; PORTRAIT was broken, by three rows in `PatchbayView` that put two
/// width-pinned `EchoelValueField`s on one line. `TwoControlsShareALineOnlyWhileTheyFitTests`
/// owns that repair. The ceiling below stands on its own merit — a control column has a
/// readable maximum on any wide canvas — and NOT as a compensation for an orientation.
///
/// ⚠️ WHAT THIS DOES AND DOES NOT PROVE. It is a source scan: it proves the ceiling is
/// declared once and applied at both sites, never that a rotated phone now looks right. That
/// is a device probe and it is open (NEEDS-FOUNDER-VERIFY: rotate to landscape and say
/// whether "centred with margins" is acceptable, or whether the orientation should simply be
/// locked to portrait).
///
/// ⛔ THE FIRST CUT OF THIS SLICE CLAIMED "every sheet inherits the ceiling from one
/// modifier, which is why the fix is two sites and not twenty" — MEASURED AND FALSE, in the
/// commit message, the source comment AND the founder-facing deploy note at once. Counted:
/// `.echoelSheetPanel()` is worn by FOUR sheets (FX · Input · Routing · LiveColabo), while
/// Open, Diagnostics and Learn are presented without it — and Learn must NEVER wear it,
/// because it manages its own `presentationDetents` and the panel modifier sets them too.
/// The rule I broke is this repo's own: an aggregate claim ("every", "all") is a COUNT, and
/// a count is measured, not reasoned from where the code was put. Claim 2 below now counts
/// the sites rather than asserting the shape, so the same sentence cannot go stale silently.
///
/// ⚠️ AND IT IS DELIBERATELY NOT AN ORIENTATION LOCK (#364). If the founder later drops
/// landscape from the plist, nothing here goes red — the ceiling stays useful, because the
/// stated platform goal is the whole Apple ecosystem and iPad, Mac and Vision all arrive
/// with canvases far wider than a column of controls should ever be.
final class TheLayoutHasAReadableWidthCeilingTests: XCTestCase {

    private static let theme = "Sources/Echoelmusic/Studio/EchoelTheme.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let sheet = "Sources/Echoelmusic/Studio/EchoelSheetPanel.swift"
    private static let visual = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    private static let capLine = ".frame(maxWidth: EchoelTheme.readableContentWidth)"
    private static let centreLine = ".frame(maxWidth: .infinity)"

    // MARK: - 1. the ceiling is declared exactly once, and it is a real number

    func testTheCeilingIsDeclaredOnceAndIsWiderThanAnyPhone() throws {
        let theme = try code(Self.theme)
        let declaration = "static let readableContentWidth: CGFloat ="
        XCTAssertEqual(occurrences(of: declaration, in: theme), 1, """
            `EchoelTheme.readableContentWidth` is not declared exactly once. Zero means the \
            ceiling moved or was deleted — re-anchor this guard AND both call sites in the \
            same commit (#456). Two means a second definition appeared, and the two sites \
            below could then silently disagree about how wide "readable" is.
            """)
        let value = try XCTUnwrap(numberAfter(declaration, in: theme), """
            `readableContentWidth` no longer ends in a plain numeric literal. If it became a \
            computed value, this claim cannot check it and must be replaced by one that can — \
            do not delete it and leave the range unguarded.
            """)
        XCTAssertGreaterThanOrEqual(value, 480, """
            The readable ceiling is \(value) pt, which is inside the range a real iPhone \
            uses in PORTRAIT (440 pt on the widest device today). A ceiling that binds in \
            portrait does not fix the founder's complaint, it becomes it: the instrument \
            would visibly shrink on the device he actually holds. The number exists to catch \
            canvases the layout was never drawn for — landscape, iPad, Mac, Vision — and \
            must stay clear of the ones it was.
            """)
        XCTAssertLessThanOrEqual(value, 900, """
            The readable ceiling is \(value) pt, which is wider than the landscape canvas it \
            exists to tame (~852 pt on a large iPhone). At that size it never engages and the \
            guard passes while guarding nothing — the #808 shape.
            """)
    }

    // MARK: - 2. the ceiling is ONE definition, applied at every site that needs it

    /// The idiom (cap, then reclaim the width so the capped column is CENTRED) exists exactly
    /// once, in `View.readableWidth()`. Repeating the two `frame`s inline is how the order
    /// gets dropped at one site and nobody notices — with the cap alone the content hugs the
    /// leading edge and all the empty space piles up on one side.
    func testTheIdiomIsWrittenExactlyOnce() throws {
        let panel = try code(Self.sheet)
        XCTAssertEqual(occurrences(of: "func readableWidth() -> some View", in: panel), 1, """
            `readableWidth()` is not declared exactly once in \(Self.sheet). Zero means it \
            moved — re-anchor this guard and every call site in the same commit (#456).
            """)
        XCTAssertTrue(panel.contains(Self.capLine) && panel.contains(Self.centreLine), """
            `readableWidth()` no longer caps AND re-centres. Both halves are required and the \
            ORDER carries the fix: `\(Self.capLine)` first, then `\(Self.centreLine)`.
            """)
        let cap = try XCTUnwrap(panel.range(of: Self.capLine))
        let next = panel[cap.upperBound...].drop(while: { $0 == "\n" || $0 == " " })
        XCTAssertTrue(next.hasPrefix(Self.centreLine), """
            The two halves of `readableWidth()` are no longer adjacent and in that order. Cap \
            first, then reclaim the full width — reversed or separated, the column stops being \
            centred and the margin reads as a bug.
            """)
        for path in [Self.workspace, Self.studio] {
            let body = try code(path)
            XCTAssertEqual(occurrences(of: Self.capLine, in: body), 0, """
                \(path) writes the cap inline instead of calling `readableWidth()`. One \
                definition, or the order gets dropped at one site and nothing notices.
                """)
        }
    }

    /// COUNT, do not reason (#766/#768). The first cut of this slice asserted that one
    /// modifier covered "every sheet"; it covers four of seven. This claim names each
    /// presented surface and where its ceiling comes from, so adding a sheet without one is
    /// a red rather than a silently stretched panel on a wide canvas.
    func testEveryPresentedSurfaceHasACeilingOrAStatedReasonNotTo() throws {
        let studio = try code(Self.studio)
        let workspace = try code(Self.workspace)

        XCTAssertEqual(occurrences(of: ".readableWidth()", in: workspace), 1, """
            The chrome + instrument column no longer calls `readableWidth()` exactly once. \
            This is the surface the founder filmed: rotate the phone and its paragraphs stop \
            wrapping.
            """)

        // The four that inherit it through the shared panel, and the three that carry it
        // directly. Every entry is a sheet a user can open.
        for wearer in ["AudioInputPickerView().echoelSheetPanel()",
                       "PatchbayView().echoelSheetPanel()"] {
            XCTAssertTrue(studio.contains(wearer), """
                `\(wearer)` is gone. It is one of the sheets that inherits the readable \
                ceiling from `.echoelSheetPanel()`; if the sheet moved or was renamed, keep \
                its ceiling and re-anchor this list in the same commit.
                """)
        }
        XCTAssertGreaterThanOrEqual(occurrences(of: ".echoelSheetPanel()", in: studio), 4, """
            Fewer than four sheets wear `.echoelSheetPanel()`. That modifier is where FX, \
            Input, Routing and LiveColabo get both their detents and their width ceiling — a \
            sheet dropped from it loses the ceiling silently, which is exactly the defect \
            this file exists for.
            """)
        for direct in ["AnyView(openSheet.readableWidth())",
                       "AnyView(diagnosticsSheet(report.text).readableWidth())",
                       "AnyView(LearnView().readableWidth())"] {
            XCTAssertTrue(studio.contains(direct), """
                `\(direct)` is gone. These three sheets do NOT wear `.echoelSheetPanel()` — \
                Learn cannot, because it sets its own `presentationDetents` and the panel \
                sets them too — so they carry the ceiling directly. Dropping the call leaves \
                them stretching on a wide canvas while every neighbour behaves.
                """)
        }
    }

    // MARK: - 3. COUNTERWEIGHT — the immersive visual is NOT capped

    /// The cheapest wrong way to "finish" this slice is to hoist the cap one level, onto the
    /// `ZStack` or the whole scene. That would also cap `FloatingVisualWindow`, and "true
    /// Vollbild" — the visual covering the chrome too — is stated as a rule in `WorkspaceView`
    /// itself. Shrinking the one surface whose entire point is to fill everything would be a
    /// worse regression than the one being fixed.
    func testTheImmersiveVisualKeepsTheWholeScreen() throws {
        let visual = try code(Self.visual)
        XCTAssertEqual(occurrences(of: "readableContentWidth", in: visual), 0, """
            `FloatingVisualWindow` now reads the readable ceiling. The visual must keep the \
            FULL screen ("true Vollbild", stated in WorkspaceView) — capping it shrinks the \
            one surface that is supposed to cover everything.
            """)
        let workspace = try code(Self.workspace)
        XCTAssertEqual(occurrences(of: ".readableWidth()", in: workspace), 1, """
            `WorkspaceView` applies the ceiling more than once. There is exactly ONE place it \
            belongs: on the chrome + instrument VStack, INSIDE the ZStack. A second call is \
            most likely the cap hoisted onto the ZStack or put on the visual as well — see \
            this method's doc comment for why that is worse than no cap.
            """)
        XCTAssertEqual(occurrences(of: ".readableWidth()", in: try code(Self.visual)), 0, """
            `FloatingVisualWindow` now calls `readableWidth()`. Same finding as above, one \
            file over: the visual keeps the whole screen.
            """)
        XCTAssertTrue(workspace.contains("FloatingVisualWindow"), """
            `FloatingVisualWindow` is no longer mounted in `WorkspaceView`. That makes the \
            claim above vacuous (#808): it would pass on a tree with no visual at all. If the \
            window genuinely moved, re-anchor this counterweight on its new host in the same \
            commit.
            """)
    }

    // MARK: - 4. COUNTERWEIGHT — landscape is supported ON PURPOSE

    /// ⛔ THIS CLAIM IS INVERTED IN MEANING FROM ITS FIRST VERSION (#1026). It used to assert
    /// that landscape was still declared and called its removal "good news" — a stand-in for a
    /// founder-gated fix I had recommended. The founder tried it and said landscape was fine;
    /// portrait was the broken one. So the same assertion stays, for the OPPOSITE reason: the
    /// three orientations are a supported, working configuration, and dropping one silently
    /// would take away something a user has.
    func testTheThreeOrientationsStayDeclared() throws {
        let plist = try text("Resources/iOS/Info.plist")
        XCTAssertGreaterThan(occurrences(of: "UIInterfaceOrientationLandscape", in: plist), 0, """
            `Info.plist` no longer declares landscape for iPhone. It is FOUNDER-GATED (report, \
            do not edit), so this should only ever change on his word — and his word so far is \
            the opposite: he rotated build 452 and reported landscape looked right. If he has \
            since asked for portrait-only, retire this claim and correct \
            `EchoelTheme.readableContentWidth`'s comment and `TwoControlsShareALineOnlyWhileTheyFitTests` \
            in the same commit (#456).
            """)
    }

    // MARK: - helpers

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
            root.appendingPathComponent("Sources/Echoelmusic").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(relativePath),
                   encoding: .utf8)
    }

    /// Source with comments blanked by the ONE shared stripper (#453), so a needle quoted in
    /// a doc comment — and every needle here IS quoted in one — cannot green a claim.
    private func code(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try text(relativePath))
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// The first integer that follows `anchor`, or nil if the tail does not start with digits.
    private func numberAfter(_ anchor: String, in haystack: String) -> Int? {
        guard let r = haystack.range(of: anchor) else { return nil }
        let digits = haystack[r.upperBound...]
            .drop(while: { $0 == " " })
            .prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }
}
