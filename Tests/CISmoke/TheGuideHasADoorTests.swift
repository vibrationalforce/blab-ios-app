// TheGuideHasADoorTests.swift
// Echoel — #603 B1+B2. Founder: "Gesamte GUI überarbeiten für User experience und
// accessibility mit an und auschaltbarem Guide der hilft die App zu bedienen und zu
// verstehen."
//
// WHAT THIS GUARDS. The guide is a NON-MODAL card overlay (`GuideOverlay`) mounted as
// the top layer of `WorkspaceView`'s ZStack, toggled by the shared
// `StudioDefaultKeys.guideVisible` key from a Toggle in the Save & Export panel, and
// rendering `LearnLibrary.guideEntries` — the guard-pinned "Start Here" content — as its
// ONE source (#416). Four laws hold this shape, and each has an assertion here:
//   · SHEET CEILING: the overlay must never become a sheet (10.76.34 black screen);
//   · FREEZE LAW: the overlay must never read a high-frequency observable (10.76.50);
//   · H15-KEYSTORE: the key is declared once, in Core, never re-typed as a literal;
//   · ONE CONTENT SOURCE: the guide renders LearnLibrary, it never authors copy —
//     `TheGuideNamesOnlyRealControlsTests` keeps THAT source true against renames, so
//     this file deliberately does not re-scan entry text (#416: one guard per decision).
//
// ⚠️ LIMIT — SOURCE-TEXT SCAN, every assertion. Nothing here renders the overlay,
// flips the toggle, or proves the card is legible/dismissable on device. That is the
// founder's probe. What the scans carry: the door exists, the mount exists, the wiring
// obeys the four laws above.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (2766428) and this tree
// (#433/#464). 10 assertions in 4 tests, hand-counted: claims 1 (3) + 2 (3) + 3 (2) +
// 4 (2). On THIS tree all 10 pass. Against the PARENT: ONE finding (#486) — neither
// `GuideOverlay.swift`, the keystore entry, nor the toggle exists there; claim 2's file
// read THROWS (anchor-missing, no verdicts) and claims 1/3/4's needles are absent
// together. All 10 are FORWARD, born with this commit; ZERO regressions claimed, because
// zero exist. `SourceText.codeOnly` is PROPHYLAKTISCH here, MEASURED (#453): 0 of the
// claim-2 needles flip raw-vs-stripped on this tree — GuideOverlay's comments say "no
// bio, no playhead, no transport" WITHOUT the dotted forms the needles scan for. The
// stripper stays because that is one comment edit away from the #491 collision (a
// future doc block quoting `transport.` literally would red the raw scan while the
// code stays clean), and prophylaxis against exactly that is what §2 asks be named.

import Foundation
import XCTest

final class TheGuideHasADoorTests: XCTestCase {

    private static let overlay = "Sources/Echoelmusic/Studio/GuideOverlay.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let keys = "Sources/Echoelmusic/Core/StudioDefaultKeys.swift"

    // MARK: - claim 1 — the door: key in the keystore, toggle in the panel, mount in the root

    func testTheGuideHasAKeyAToggleAndAMount() throws {
        let keys = try source(Self.keys)
        XCTAssertTrue(keys.contains("StudioDefault(key: \"studio.guideVisible\", value: false)"), """
            The guide's shared key left the keystore (or its fresh-install default moved \
            off `false`). H15-KEYSTORE: two views read this key — re-typing it at a use \
            site is the fresh-install divergence class that shipped H15-LOOPBARS. If the \
            founder flipped the default to `true`, update this needle AND \
            `StudioDefaultKeysTests` in the same commit.
            """)
        let studio = try source(Self.studio)
        XCTAssertTrue(studio.contains("Toggle(isOn: $guideVisible)"), """
            The guide switch is gone from EchoelStudioView. The founder's ask is \
            AN- UND AUSSCHALTBAR — an overlay nobody can switch on is a deleted feature, \
            one nobody can switch OFF is an imposition; both need this Toggle.
            """)
        let workspace = try source(Self.workspace)
        XCTAssertTrue(workspace.contains("GuideOverlay()"), """
            `GuideOverlay()` is no longer mounted in WorkspaceView's ZStack. The toggle \
            then writes a key nothing reads — the guide is silently gone while its \
            switch still renders, which is the lying-control class (#485).
            """)
    }

    // MARK: - claim 2 — the overlay obeys the freeze law and the sheet ceiling

    func testTheOverlayReadsNothingHot() throws {
        let code = try source(Self.overlay)
        XCTAssertFalse(code.contains(".sheet(") || code.contains(".fullScreenCover("), """
            GuideOverlay grew a presentation modifier. The overlay exists PRECISELY so \
            the guide costs zero of those — EchoelStudioView's chain is pinned at 14 and \
            the 10.76.34 black screen was that chain growing. Whatever needs presenting \
            here, present it as in-card content instead.
            """)
        for needle in ["cameraRPPG", "transport."] {
            XCTAssertFalse(code.contains(needle), """
                GuideOverlay now references `\(needle)` — a high-frequency source. Its \
                whole mount-safety argument (10.76.50) is that it reads ONE low-frequency \
                @AppStorage bool; a bio/playhead read here makes the ROOT chrome an \
                observer at that rate and tears down open menus. Show live values in \
                their own leaf views, never in this overlay.
                """)
        }
        XCTAssertTrue(code.contains("@AppStorage(StudioDefaultKeys.guideVisible.key)"), """
            GuideOverlay no longer reads the shared keystore key — either it re-types \
            the string (H15 divergence) or it lost its visibility switch entirely.
            """)
    }

    // MARK: - claim 3 — one content source (#416)

    func testTheContentComesFromTheOneLibrary() throws {
        let code = try source(Self.overlay)
        XCTAssertTrue(code.contains("LearnLibrary.entries(for: .guide)"), """
            GuideOverlay stopped sourcing `LearnLibrary`'s guide section. That library is \
            the ONE guarded content source (`TheGuideNamesOnlyRealControlsTests` pins its \
            control names to the shipping UI) — copy authored anywhere else can go stale \
            without any guard noticing, which is the Skeptic's named failure mode for \
            this feature ("a guide that goes stale LIES").
            """)
        XCTAssertFalse(code.contains("LearnEntry("), """
            GuideOverlay now CONSTRUCTS its own LearnEntry — authoring copy in the \
            renderer, outside the guarded library. Move the entry into \
            `LearnLibrary.guideEntries`, where the control-name guard can see it.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHTS, #343) — the premises the mount rests on

    func testTheMountSitePremisesHold() throws {
        let workspace = try source(Self.workspace)
        XCTAssertTrue(workspace.contains("FloatingVisualWindow(isPresented: $floatingVisualVisible)"), """
            The FloatingVisualWindow sibling left WorkspaceView's ZStack. It is the \
            PRECEDENT the guide overlay's mount argument cites (non-modal @AppStorage \
            sibling); if the ZStack was restructured, re-verify the guide still mounts \
            above the fullscreen visual — its first card describes that exact screen.
            """)
        let library = try source("Sources/Echoelmusic/Studio/LearnLibrary.swift")
        XCTAssertTrue(library.contains("static var guideEntries"), """
            `LearnLibrary.guideEntries` is gone — the guide's one content source. If the \
            section was renamed, move GuideOverlay's `entries(for: .guide)` call and this \
            file in the same commit.
            """)
    }

    // MARK: - source access

    private struct AnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
