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
// ⛔ HONEST LIMITS — READ BEFORE TRUSTING A GREEN. This is a SOURCE SCAN. It proves the mount
// is unconditional and inert-when-hidden as WRITTEN. It cannot prove either of the two
// SwiftUI assumptions the fix rests on, and the second is the bigger one:
//   1. that a representable's `UIView` stays in its `UIWindow` under an ancestor `.opacity(0)`
//      (it does — but that is a claim about UIKit, not about this text);
//   2. that flipping `visualLayer`'s `_ConditionalContent` branch from `liveVisual(wv)` to
//      `Color.clear` does NOT re-create the `.overlay`'s subtree. The overlay hangs off the
//      MODIFIED content, so its identity should survive — but if SwiftUI ever rebuilds it,
//      `didMoveToWindow()` fires with `window == nil`, `stopAutoPlay()` runs, and #311 is back
//      WITH EVERY TEST IN THIS FILE STILL GREEN. That is a device-verify item in its own
//      right, distinct from "is the arp audible".
// Neither can it prove the arp is audible. The ear is the founder's.
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

    /// The construction the whole file is about. Everything else is derived from the line that
    /// matches this, so a rename of the VIEW fails in exactly one place with one message.
    private static let mountCall = "FloatingVisualWindow(isPresented:"

    // MARK: - The mount

    /// ⭐ THE HEADLINE.
    ///
    /// ⛔ WHY THIS IS NOT A REPO-WIDE `contains("if ") && contains("<flag> {")` ANY MORE — the
    /// first version was, and the review showed it failing its own header in BOTH directions:
    ///   · it hard-coded the identifier `floatingVisualVisible`, so a rename of that flag (an
    ///     ordinary refactor — the canonical key already lives in `StudioDefaultKeys`) made this
    ///     test pass VACUOUSLY while the inertness test below went red pointing at the wrong
    ///     problem. Falsely green and falsely red from one rename is precisely the `390ca79`
    ///     shape this file's header cites as its reason for existing;
    ///   · and it scanned all of `Sources/`, so any unrelated future `if <flag> { … }` — a
    ///     label, a shortcut, an analytics line — would redden a test about MOUNTING.
    /// Now the flag NAME is read out of the mount line itself, and the conditional scan is
    /// scoped to the file that holds the mount. Rename the flag and both tests follow it.
    func testHidingTheVisualDoesNotUnmountTheWindowThatHostsTheField() throws {
        let (file, flag) = try mountSite()
        let lines = try codeLines(file)
        let conditional = lines.filter { $0.contains("if ") && $0.contains("\(flag) {") }
        XCTAssertTrue(conditional.isEmpty, """
        `FloatingVisualWindow` is mounted conditionally again in \(file):
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
    /// commit. Built from the flag name found above, so a rename cannot split the two tests.
    func testTheHiddenWindowIsInertAndNotMerelyTransparent() throws {
        let (file, flag) = try mountSite()
        let lines = try codeLines(file)
        let required = [
            ".opacity(\(flag) ? 1 : 0)",
            ".allowsHitTesting(\(flag))",
            ".accessibilityHidden(!\(flag))"
        ]
        for fragment in required {
            XCTAssertTrue(lines.contains { $0.contains(fragment) }, """
            `\(fragment)` is missing from \(file).

            The window is now always mounted (#311), so each of these three carries a job that \
            used to be done by simply not existing: opacity hides it, `allowsHitTesting` stops \
            it swallowing every touch on the screen, `accessibilityHidden` stops VoiceOver \
            reading a picture that is not there. Removing one leaves a bug that looks unrelated \
            to this change.
            """)
        }
    }

    // MARK: - What a permanently mounted window must not cost

    /// ⛔ THE EXPENSIVE HALF, and the one a later cycle is most likely to "simplify" away. An
    /// always-mounted window with a live `MetalBioView` behind `.opacity(0)` renders 60 fps of
    /// picture nobody can see — the founder's bug traded for a battery bug, invisible in every
    /// test and every screenshot. `visualLayer` must therefore branch on `!isPresented` FIRST,
    /// and its hidden branch must yield a SHAPE (`Color.clear`), not `EmptyView()`: the
    /// `.overlay` carrying the play surface measures itself against the frame this branch
    /// accepts, and the geometry has to be identical hidden and visible or a generated note's
    /// normalized coordinates would move when the picture is toggled.
    func testTheHiddenWindowRendersNoMetalLayerAndKeepsTheCardGeometry() throws {
        let layer = try visualLayerBody()
        XCTAssertTrue(layer.contains { $0.contains("if !isPresented {") }, """
        `visualLayer` no longer has its `if !isPresented` branch, or it is no longer FIRST.

        Without it the hidden window keeps a live `MetalBioView`. The window is mounted \
        permanently since #311, so "hidden" now has to mean "renders nothing" — it is no \
        longer achieved by teardown.
        """)
        XCTAssertTrue(layer.contains { $0.contains("Color.clear") }, """
        `visualLayer`'s hidden branch no longer yields `Color.clear`.

        `EmptyView()` would pass the branch test above and silently change the card's geometry: \
        only a shape accepts the `maxWidth/maxHeight: .infinity` frame that the play-surface \
        overlay is measured against. A moved surface means a generated note lands on a \
        different scale degree after a hide/show — a wrong NOTE that still sits in the key, \
        which no legality test can see.
        """)
        let inLayer = layer.filter { $0.contains("MetalBioView(") }
        XCTAssertTrue(inLayer.isEmpty, """
        `visualLayer` constructs a `MetalBioView` directly:
        \(inLayer.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))

        It belongs in `liveVisual`, which only the visible, non-yielded branch reaches. \
        Constructing it in `visualLayer` risks a renderer on the hidden path.
        """)
        // ⛔ FILE-SCOPED, AND SAID SO. The first version's message called this "the GPU law
        // (ONE MetalBioView app-wide)" — it is not: `Sources/` holds three constructions today
        // (this file, `EchoelStudioView`, `ExternalDisplayScene`), and only ONE of them can be
        // live at a time by other means. A file-scoped count dressed as an app-wide guarantee
        // is the false-assurance class this repo logs as a defect in its own right.
        let renderers = try codeLines(Self.window).filter { $0.contains("MetalBioView(") }
        XCTAssertEqual(renderers.count, 1, """
        expected exactly ONE `MetalBioView(` in \(Self.window), found \(renderers.count).

        This file must own exactly one renderer — the one in `liveVisual`. A second here would \
        put two live Metal paths on the SAME surface, which is the documented black-immersive \
        failure. (This does not, and cannot, verify the app-wide one-renderer rule: two other \
        files construct one too, and their exclusivity is enforced elsewhere.)
        """)
    }

    /// ⛔ THE HAZARD THE FIRST VERSION OF #311 CREATED AND DID NOT GUARD. `.opacity(0)` and
    /// `.allowsHitTesting(false)` do NOT suppress sheet presentation. This window's two share
    /// sheets are driven by ASYNC completions (a recorder stop, an `AVAssetExportSession`) that
    /// outlive a hide, so once the window stopped being unmounted, an INVISIBLE window could
    /// present a sheet on top of whatever modal the instrument had open — the documented
    /// "two modals true at once → invisible tap-blocking layer" hang, from an ordinary user
    /// sequence. Both sheets must therefore go through the holding wrapper.
    func testNoSheetCanPresentFromTheHiddenWindow() throws {
        let lines = try codeLines(Self.window)
        let sheets = lines.filter { $0.contains(".sheet(item:") }
        XCTAssertFalse(sheets.isEmpty, "no `.sheet(item:` found in \(Self.window) — move this guard")
        for sheet in sheets {
            XCTAssertTrue(sheet.contains("heldWhileHidden("), """
            a sheet in \(Self.window) presents from an unguarded binding:
            \(sheet.trimmingCharacters(in: .whitespaces))

            Since #311 this window is never unmounted, so a `$binding` here can present while \
            the window is invisible — over an open panel, or over a fullScreenCover. Route it \
            through `heldWhileHidden(_:)`, which returns nil for the ITEM while keeping the \
            `@State`, so the share waits for the picture to come back instead of being lost.
            """)
        }
    }

    // MARK: - One driver

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

        let windows = all.filter { $0.contains(Self.mountCall) }
        XCTAssertEqual(windows.count, 1, """
        expected exactly ONE `\(Self.mountCall)` construction in Sources, found \(windows.count).

        The window owns the app's single Metal path AND the play surface; a second one \
        duplicates both.
        """)
    }

    // MARK: - Source access

    /// The file holding the mount, and the visibility flag it is driven by, both read out of
    /// the source rather than hard-coded. This is what lets a rename of the flag carry through
    /// every test above instead of splitting them into one false green and one false red.
    private func mountSite() throws -> (file: String, flag: String) {
        for path in try swiftSourcePaths() {
            for line in try codeLines(path) {
                // `FloatingVisualWindow(isPresented: $someFlag)` → `someFlag`.
                // guard-let rather than `!` on the call range: this file is in the BLOCKING
                // bundle, so a crash here reads as an infrastructure failure rather than as
                // the finding it would actually be.
                guard let call = line.range(of: Self.mountCall),
                      let dollar = line.range(of: "$", range: call.upperBound..<line.endIndex)
                else { continue }
                let name = line[dollar.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                guard !name.isEmpty else { continue }
                return (path, String(name))
            }
        }
        XCTFail("""
        no `\(Self.mountCall)` construction found in Sources at all.

        The floating visual window is the app's only Metal path AND the host of the Field play \
        surface. If it was renamed, update `mountCall` here in the same commit.
        """)
        throw XCTSkip("mount site not found")
    }

    /// Lines of `visualLayer`, from its declaration to the next member declaration. Scoping is
    /// load-bearing: `isPresented` appears elsewhere in this file (the close button), and a
    /// whole-file match would pass on that while the branch itself had been reverted.
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

    /// Every Swift file under `Sources/`, repo-relative.
    private func swiftSourcePaths() throws -> [String] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot enumerate \(sources.path)")
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var out: [String] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            out.append(url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path)
        }
        XCTAssertFalse(out.isEmpty, "no Swift source found — a green here would be meaningless")
        return out.sorted()
    }

    /// Every code line of every Swift file under `Sources/`. The count assertions need this so
    /// they survive an ordinary extraction of a mount into another file.
    private func allSourceLines() throws -> [String] {
        var out: [String] = []
        for path in try swiftSourcePaths() { out.append(contentsOf: try codeLines(path)) }
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

    /// Every line of `path` with comments removed — whole-line AND trailing.
    ///
    /// ⚠️ THE TRAILING HALF IS NOT COSMETIC. The ⭐ blocks this slice added QUOTE the very
    /// fragments these tests match (`if <flag> {`, `MetalBioView`, `TouchInstrumentView`), so
    /// without stripping, a guard could pass on its own explanation after the code it explains
    /// had been reverted — and a single `foo() // see TouchInstrumentView(autoPlay:)` would
    /// push the one-surface count to 2 and go falsely red. The quote-parity check is the cheap
    /// approximation of "is this `//` inside a string literal": count the `"` before it, and
    /// only cut on an even count. Escaped quotes inside literals would fool it; none of the
    /// files scanned here contain one on a line with a `//`, and a wrong cut can only ever
    /// REMOVE text — i.e. cost a match, never invent one.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func stripComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" { quotes += 1 }
            if ch == "/", previous == "/", quotes % 2 == 0 {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = ch
            index = line.index(after: index)
        }
        return line
    }
}
