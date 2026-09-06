import XCTest

/// #1025 — THE CONTROL COLUMN MAY NOT GROW WIDER THAN IT CAN BE READ.
///
/// WHY. Founder clip, 2026-09-06, build v10.79.448 (2567): *"Die adaptive View muss her. Es
/// muss vermieden werden, dass wir plötzlich verzerrte und zu große Fenster haben."* The
/// frames show it precisely — the Mix panel's closing paragraph stops wrapping and runs off
/// the right edge, and the Routing sheet (`PatchbayView`) is cut on BOTH sides at once.
///
/// THE CAUSE IS ONE LINE AND IT IS NOT IN THIS REPO'S REACH. `Resources/iOS/Info.plist`
/// declares `UIInterfaceOrientationLandscapeLeft` and `…Right` for iPhone, so the device
/// rotates and hands the instrument a ~852 pt canvas that nothing was drawn for. Removing
/// those two entries is the real fix and it is FOUNDER-GATED (`.claude/rules/context.md` §3:
/// report, do not edit). This guard covers the half a session may ship.
///
/// ⚠️ WHAT THIS DOES AND DOES NOT PROVE. It is a source scan: it proves the ceiling is
/// declared once and applied at both sites, never that a rotated phone now looks right. That
/// is a device probe and it is open (NEEDS-FOUNDER-VERIFY: rotate to landscape and say
/// whether "centred with margins" is acceptable, or whether the orientation should simply be
/// locked to portrait).
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

    // MARK: - 2. both sites apply it, and both CENTRE what they capped

    func testBothSitesCapAndThenRecentre() throws {
        for (path, name) in [(Self.workspace, "the chrome + instrument column"),
                             (Self.sheet, "every sheet wearing echoelSheetPanel()")] {
            let body = try code(path)
            XCTAssertEqual(occurrences(of: Self.capLine, in: body), 1, """
                \(name) no longer applies `\(Self.capLine)` exactly once. Without it a rotated \
                phone hands this content ~852 pt and the layout does what the founder filmed: \
                paragraphs stop wrapping, a centred sheet loses both edges.
                """)
            let cap = try XCTUnwrap(body.range(of: Self.capLine))
            let after = body[cap.upperBound...]
            let next = after.drop(while: { $0 == "\n" || $0 == " " })
            XCTAssertTrue(next.hasPrefix(Self.centreLine), """
                \(name) caps its width but the very next modifier is no longer \
                `\(Self.centreLine)`. The pair is the whole trick and the ORDER carries it: \
                cap the content, then reclaim the full width so the capped column is CENTRED. \
                With the cap alone the column hugs the leading edge and all the empty space \
                piles up on one side — which looks like a bug rather than a margin.
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
        XCTAssertEqual(occurrences(of: "readableContentWidth", in: workspace), 1, """
            `WorkspaceView` names the readable ceiling more than once. There is exactly ONE \
            place it belongs: on the chrome + instrument VStack, INSIDE the ZStack. A second \
            mention is most likely the cap hoisted onto the ZStack or applied to the visual \
            as well — see this method's doc comment for why that is worse than no cap.
            """)
        XCTAssertTrue(workspace.contains("FloatingVisualWindow"), """
            `FloatingVisualWindow` is no longer mounted in `WorkspaceView`. That makes the \
            claim above vacuous (#808): it would pass on a tree with no visual at all. If the \
            window genuinely moved, re-anchor this counterweight on its new host in the same \
            commit.
            """)
    }

    // MARK: - 4. COUNTERWEIGHT — the founder-gated half is named, not silently skipped

    /// A session that reads only the code would conclude the ceiling IS the fix. It is not:
    /// it makes landscape readable, it does not stop the rotation. The one-key repair lives
    /// in a file this repo may not edit, so the only place it can be recorded is prose — and
    /// prose with no guard is how a founder-gated item is quietly forgotten.
    func testThePlistStillDeclaresTheLandscapeThisCeilingCompensatesFor() throws {
        let plist = try text("Resources/iOS/Info.plist")
        let landscape = occurrences(of: "UIInterfaceOrientationLandscape", in: plist)
        XCTAssertGreaterThan(landscape, 0, """
            `Info.plist` no longer declares any landscape orientation. THAT IS GOOD NEWS, not \
            a defect — it means the founder took the one-key fix this ceiling was standing in \
            for. Retire this claim and say so in `EchoelTheme.readableContentWidth`'s comment \
            and in `.deploy/release`, in the same commit (#456). Keep the ceiling itself: \
            iPad, Mac and Vision still arrive with canvases wider than a control column.
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
