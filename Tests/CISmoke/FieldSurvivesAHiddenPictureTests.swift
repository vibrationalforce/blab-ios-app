// FieldSurvivesAHiddenPictureTests.swift
// Echoel — #311. The Field's self-play generator (the arp) must not stop when the player
// hides the visual.
//
// ⭐ THE DEFECT, AND WHY IT IS A LIFETIME BUG RATHER THAN AN AUDIO BUG. Founder 2026-07-31:
// *"die arps soll immer hörbar sein und nicht nur, wenn das Visual Fenster auf ist."* The
// generator is a `CADisplayLink` owned by `TouchInstrumentUIView`. That view is a
// `UIViewRepresentable` mounted as an OVERLAY on `FloatingVisualWindow`'s picture card, and
// its `startAutoPlay` deliberately requires `window != nil` (`didMoveToWindow` stops the link
// when the view leaves the hierarchy — that guard is right, it stops an invisible surface
// ticking forever). `WorkspaceView` mounted the whole window behind
// `if floatingVisualVisible { … }`, so hiding the PICTURE tore down the view, which stopped
// the link, which stopped the ARP. A view was driving the instrument — the coupling class
// that has already cost this repo twice (the `PianoRollView`-publishes-`MusicalFrame`
// mistake, the 10 Hz reads in ancestors).
//
// ⚠️ THE PRECEDENT MATTERS MORE THAN THE FIX. `FloatingVisualWindow.visualLayer`'s own doc
// had ALREADY reasoned this out once, for the external-screen trigger (#206): *"hiding the
// window takes the phone's PLAY SURFACE with it"*, and chose swap-the-layer /
// keep-the-window. The visibility toggle is the same trap through a different door, and it
// was answered the opposite way in a different file. This file exists so the two answers
// cannot drift apart again.
//
// ⛔ HONEST LIMIT — READ BEFORE TRUSTING A GREEN. This is a SOURCE SCAN. It proves the mount
// is unconditional and inert-when-hidden as WRITTEN. It cannot prove that SwiftUI keeps a
// representable's `UIView` in the window under `.opacity(0)` (it does, but that is an
// assertion about UIKit, not about this text), nor that the arp is audible on a device. The
// ear is the founder's; device-verify is open.
//
// ⚠️ WHY A SOURCE SCAN AT ALL: the mount is inside a `private var body` of a view, there is
// no simulator in this environment, and `@testable import` grants `internal`, not `private`.
// House pattern — see `SoundPanelReflowsTests`, `ChipStripScrollsToSelectionTests`,
// `SaveDoorNamingTests`.

import Foundation
import XCTest

final class FieldSurvivesAHiddenPictureTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

    /// ⭐ THE HEADLINE. Repo-wide, because the assertion is about the SHAPE of the mount, not
    /// about which file currently holds it — a guard pinned to a file goes falsely red on an
    /// ordinary extraction and falsely green afterwards (the `390ca79` lesson). The anchor
    /// test below is the one that names a file, and it names exactly one.
    func testHidingTheVisualDoesNotUnmountTheWindowThatHostsTheField() throws {
        let all = try allSourceLines()
        let conditional = all.filter { $0.contains("if ") && $0.contains("floatingVisualVisible {") }
        XCTAssertTrue(conditional.isEmpty, """
        `FloatingVisualWindow` is mounted conditionally again:
        \(conditional.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        That line stops the arp. `TouchInstrumentUIView`'s self-play `CADisplayLink` requires \
        `window != nil`; unmounting the window removes the view, `didMoveToWindow` calls \
        `stopAutoPlay()`, and the Field goes silent the moment the player hides the picture — \
        which is precisely the founder report this file exists for (#311).

        To hide the picture, keep the window and make it INERT (opacity / allowsHitTesting / \
        accessibilityHidden), and drop the renderer inside `visualLayer`. See the ⭐ #311 \
        block at the mount site.
        """)
    }

    /// The other half of "unconditional": inert. Without these three the fix trades a silent
    /// arp for an invisible full-screen view that eats touches and reads itself out to
    /// VoiceOver — a worse bug than the one being fixed, and one nobody would connect to this
    /// commit.
    func testTheHiddenWindowIsInertAndNotMerelyTransparent() throws {
        let all = try allSourceLines()
        let required = [
            ".opacity(floatingVisualVisible ? 1 : 0)",
            ".allowsHitTesting(floatingVisualVisible)",
            ".accessibilityHidden(!floatingVisualVisible)"
        ]
        for fragment in required {
            XCTAssertTrue(all.contains { $0.contains(fragment) }, """
            `\(fragment)` is gone from the `FloatingVisualWindow` mount.

            The window is now always mounted (#311), so each of these three carries a job that \
            used to be done by simply not existing: opacity hides it, `allowsHitTesting` stops \
            it swallowing every touch on the screen, `accessibilityHidden` stops VoiceOver \
            reading a picture that is not there. Removing one leaves a bug that looks unrelated \
            to this change.
            """)
        }
    }

    /// ⛔ THE EXPENSIVE HALF, and the one a later cycle is most likely to "simplify" away. An
    /// always-mounted window with a live `MetalBioView` behind `.opacity(0)` renders 60 fps of
    /// picture nobody can see — the founder's bug traded for a battery bug, invisible in every
    /// test and every screenshot. `visualLayer` must therefore branch on `!isPresented` FIRST.
    func testTheHiddenWindowRendersNoMetalLayerAtAll() throws {
        let layer = try visualLayerBody()
        XCTAssertTrue(layer.contains { $0.contains("if !isPresented {") }, """
        `visualLayer` no longer has its `if !isPresented` branch.

        Without it the hidden window keeps a live `MetalBioView`. The window is mounted \
        permanently since #311, so "hidden" now has to mean "renders nothing" — it is no \
        longer achieved by teardown. This also upholds the GPU law (ONE `MetalBioView` \
        app-wide, decisions.csv 2026-07-03).
        """)
        // The renderer must live in `liveVisual`, i.e. OUTSIDE the branch scanned above.
        let inLayer = layer.filter { $0.contains("MetalBioView(") }
        XCTAssertTrue(inLayer.isEmpty, """
        `visualLayer` constructs a `MetalBioView` directly:
        \(inLayer.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        It belongs in `liveVisual`, which only the visible, non-yielded branch reaches. \
        Constructing it in `visualLayer` risks a renderer on the hidden path.
        """)
        let file = try codeLines(Self.window)
        let renderers = file.filter { $0.contains("MetalBioView(") }
        XCTAssertEqual(renderers.count, 1, """
        expected exactly ONE `MetalBioView(` in \(Self.window), found \(renderers.count).

        A second renderer in this file means a second live Metal path on the same surface, \
        which is the documented black-immersive failure (GPU law). The one that belongs here \
        is `liveVisual`'s.
        """)
    }

    /// ONE driver, and one anchor naming where each symbol lives. The count matters on its own:
    /// a second `TouchInstrumentView` mounted "so the arp keeps playing when the window is
    /// closed" would double every generated note — the obvious wrong fix for #311, and the one
    /// worth making impossible rather than merely discouraged.
    func testThereIsExactlyOnePlaySurfaceAndOneWindow() throws {
        let all = try allSourceLines()

        let surfaces = all.filter { $0.contains("TouchInstrumentView(") }
        XCTAssertEqual(surfaces.count, 1, """
        expected exactly ONE `TouchInstrumentView(` construction in Sources, found \
        \(surfaces.count):
        \(surfaces.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        Two mounted surfaces means two self-play display links firing the same cells into the \
        same synth — every generated note doubled, heard as a flam, with nothing failing. If a \
        second surface is genuinely wanted, only ONE may carry `autoPlay:`, and this test must \
        be rewritten to say so rather than have its number raised.
        """)
        XCTAssertTrue(try codeLines(Self.window).contains { $0.contains("TouchInstrumentView(") }, """
        the play surface is no longer mounted in \(Self.window).

        If it moved, move this anchor with it — and re-check the #311 chain at its new home: \
        the self-play link lives only while that view is in a window.
        """)

        let windows = all.filter { $0.contains("FloatingVisualWindow(isPresented:") }
        XCTAssertEqual(windows.count, 1, """
        expected exactly ONE `FloatingVisualWindow(isPresented:` construction in Sources, \
        found \(windows.count).

        The window owns the app's single Metal path AND the play surface; a second one \
        duplicates both.
        """)
        XCTAssertTrue(try codeLines(Self.workspace).contains { $0.contains("FloatingVisualWindow(isPresented:") }, """
        the visual window is no longer mounted in \(Self.workspace).

        If it moved, move this anchor with it — and carry the three inertness modifiers along, \
        or #311 comes straight back.
        """)
    }

    // MARK: - Source access

    /// Lines of `visualLayer`, from its declaration to the next member declaration. Scoping is
    /// load-bearing: `isPresented` appears elsewhere in this 1000-line file (the close button),
    /// and a whole-file match would pass on that while the branch itself had been reverted.
    private func visualLayerBody() throws -> [String] {
        let lines = try codeLines(Self.window)
        guard let start = lines.firstIndex(where: { $0.contains("private func visualLayer(") }) else {
            XCTFail("""
            `visualLayer` is gone from \(Self.window) — that is the one place deciding whether \
            the hidden window renders. If it was renamed, move this guard with it.
            """)
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") || $0.hasPrefix("    @ViewBuilder") }
            ?? lines.endIndex
        return Array(lines[start..<end])
    }

    /// Every non-comment line of every Swift file under `Sources/`. The repo-wide scans above
    /// need this so they survive an ordinary extraction of the mount into another file.
    private func allSourceLines() throws -> [String] {
        let root = try repoRoot().appendingPathComponent("Sources")
        var out: [String] = []
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot enumerate \(root.path)")
        }
        for case let url as URL in walk where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") })
        }
        XCTAssertFalse(out.isEmpty, "no Swift source read — a green here would be meaningless")
        return out
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this test inspects source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Load-bearing: the ⭐ blocks this
    /// slice added QUOTE the very fragments these tests match (`if floatingVisualVisible {`,
    /// `MetalBioView`), so without the filter the guards would pass on their own explanation
    /// after the code it explains had been reverted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
