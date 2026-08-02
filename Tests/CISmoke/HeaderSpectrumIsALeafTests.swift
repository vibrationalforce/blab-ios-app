// HeaderSpectrumIsALeafTests.swift
// Echoel — the live spectrum in the always-on header may not observe from the header. #384.
//
// WHAT THIS GUARDS, and it is the single most dangerous placement in the app for a live read.
// The founder asked on 2026-08-02 for the Field panel's colour bars to appear top-left in the
// brand header ("Die Farbbalken links oben neben Echoelmusic in angepasster Form"). The header
// is `WorkspaceView.topBar` — the ROOT chrome, an ancestor of every surface. The 10.76.50 freeze
// was caused by exactly this shape: `topBar` read `cameraRPPG.waveform` directly to feed a
// header tile, so `WorkspaceView.body` rebuilt ~10×/s and tore down any open `.menu` Picker in
// the instrument BELOW it. Three earlier audits scoped to `EchoelStudioView`, found it clean,
// and missed the read one level up. `AnyView` is not an observation boundary; only a separate
// `View` struct is.
//
// So the law this pins is: the strip is a LEAF. Its `TimelineView`, its `Canvas` and every read
// of `AudioEngine` live inside `HeaderSpectrumStrip`'s own body, and `topBar` contains none of
// them — it may only NAME the type.
//
// ⭐ IT ALSO PINS THE CENTRING SHAPE, and that is not a style preference. The founder's other
// half of the same sentence was "Echoelmusic wieder in die Mitte". The obvious way to centre a
// title in a bar is a `ZStack` with the title on its own layer — and that is precisely what was
// REMOVED on 2026-08-01, because a `ZStack` gives its layers no collision avoidance: as Dynamic
// Type grew the centred title, it grew straight THROUGH the mark and the monitor tiles, with
// `minimumScaleFactor` only bounding how far. The chrome is capped at `.accessibility1` (#262),
// not at `.xxLarge`, so that overlap was reachable. The safe centring is the three-column
// `HStack`: both flanks take `.frame(maxWidth: .infinity)`, split the slack evenly, and give way
// before anything overlaps. Re-introducing a `ZStack` here would restore the look and the bug
// together, which is why the absence is asserted rather than left to memory.
//
// ⚠️ HONEST LIMITS. Source-text scan; there is no simulator in the blocking bundle. It proves
// the read is SPELLED inside the leaf and that the header does not contain the churning
// constructs — never that no Picker tears down on a device, and never that the bars are legible
// at 110 pt of width. NEEDS-FOUNDER-VERIFY: start biofeedback, play, then open the Genre or Key
// menu in the surface below and leave it open for several seconds. Does it stay open? And:
// does the strip read as a spectrum at that size, or as texture?
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class HeaderSpectrumIsALeafTests: XCTestCase {

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let strip = "Sources/Echoelmusic/Studio/HeaderSpectrumStrip.swift"
    private static let topBarDeclaration = "private var topBar: some View"

    /// The header mounts the strip, and does nothing live itself.
    func testTheHeaderMountsTheStripWithoutObservingIt() throws {
        let source = try codeLines(Self.workspace)
        let bar = try topBar(source)

        XCTAssertTrue(bar.contains { $0.contains("HeaderSpectrumStrip()") }, """
            `topBar` no longer mounts `HeaderSpectrumStrip`. The founder asked for the Field \
            panel's colour bars to appear top-left beside the wordmark (2026-08-02); without \
            this line the header has an empty left flank again and the centred title has \
            nothing to balance against. If the strip was deliberately removed, this guard \
            should be deleted in the same commit rather than left to fail.
            """)

        // The churning constructs. Each is enough on its own to register the ROOT header — and
        // therefore the whole app — as a high-frequency observer.
        for construct in ["TimelineView", "Canvas", "copyLatestOutputSamples", "EchoelRealFFT"] {
            let leaked = bar.filter { $0.contains(construct) }
            XCTAssertTrue(leaked.isEmpty, """
                `\(construct)` appeared inside `WorkspaceView.topBar`: \
                \(leaked.map { $0.trimmingCharacters(in: .whitespaces) }). \
                This body is the ROOT chrome — an ancestor of every surface in the app. A \
                per-frame construct here rebuilds `WorkspaceView.body` at its frame rate, and \
                every rebuild tears down any open `.menu` Picker in the instrument below: the \
                10.76.50 freeze, which took four attempts to find because three audits scoped \
                to `EchoelStudioView` and the read was one level up. The strip must stay a \
                separate `View` struct that reads the engine in ITS OWN body.
                """)
        }
    }

    /// The leaf really does hold the read — the other half of the same law.
    ///
    /// ⛔ WITHOUT THIS, THE TEST ABOVE PASSES ON A BROKEN FIX. "The header contains no
    /// `Canvas`" is also true of a strip that draws nothing, or of one that takes its values as
    /// a parameter from the parent — which would be the freeze all over again, since the parent
    /// would then be the one observing. Asserting the read's PRESENCE in the leaf is what makes
    /// the pair meaningful.
    func testTheLeafHoldsTheLiveRead() throws {
        let source = try codeLines(Self.strip)
        for construct in ["@Environment(AudioEngine.self)", "copyLatestOutputSamples", "TimelineView"] {
            XCTAssertTrue(source.contains { $0.contains(construct) }, """
                `HeaderSpectrumStrip` no longer contains `\(construct)`. The point of this type \
                is to be the observation boundary: it exists so that the live audio read happens \
                HERE and not in the header that hosts it. A strip that receives its values from \
                `topBar` instead would move the observation back into the root and re-create the \
                menu freeze while this file still looked correct.
                """)
        }
    }

    /// The centred title uses the collision-free shape, not the one that was removed.
    func testTheTitleIsCentredWithoutAZStack() throws {
        let source = try codeLines(Self.workspace)
        let bar = try topBar(source)

        let stacks = bar.filter { $0.contains("ZStack") }
        XCTAssertTrue(stacks.isEmpty, """
            A `ZStack` is back in `topBar`: \
            \(stacks.map { $0.trimmingCharacters(in: .whitespaces) }). \
            That is the shape this header was moved AWAY from on 2026-08-01, and the reason is \
            a real defect, not taste: a `ZStack` gives its layers no collision avoidance, so a \
            centred title on its own layer grows straight through the logo mark and the monitor \
            tiles as Dynamic Type raises it — and the chrome is capped at `.accessibility1` \
            (#262), not at `.xxLarge`, so that size is reachable. Centre the brand block with \
            two `.frame(maxWidth: .infinity)` flanks instead; there the slack yields first and \
            nothing can overlap at any size.
            """)

        // Two flanks, both greedy: that is what puts the brand block in the middle. One would
        // push it to an edge; none would leave it hugging the leading side again.
        let greedy = bar.filter { $0.contains("maxWidth: .infinity") }
        XCTAssertEqual(greedy.count, 2, """
            Expected exactly two `.frame(maxWidth: .infinity)` flanks in `topBar` (the spectrum \
            strip on the left, the monitor cluster on the right), found \(greedy.count): \
            \(greedy.map { $0.trimmingCharacters(in: .whitespaces) }). \
            Both are what centre the brand block: they split the leftover width evenly, so the \
            title sits in the geometric middle and both sides compress before anything overlaps. \
            With one, the block is pushed to an edge; with three — for instance if the modifier \
            were applied to each monitor tile instead of to their cluster — the tiles spread \
            across the bar and the middle moves.
            """)
    }

    // MARK: - Reading the source

    private func topBar(_ source: [String]) throws -> ArraySlice<String> {
        try window(source, from: Self.topBarDeclaration, file: "WorkspaceView")
    }

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural — the house idiom in this bundle. Not a line count (the rationale block above
    /// `topBar` is already 30+ lines and grew twice while this slice was being written) and not
    /// "stop at the next `private var`" (a guess about what the NEXT declaration's author will
    /// type). Here the stakes are concrete: `WorkspaceView` is 1000+ lines and the member after
    /// `topBar` is `openWebsite()`, so a window that ran on would report unrelated lines under
    /// this test's name.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly this
    /// indentation plus `}` would end the window early. `topBar` contains no such literal.
    private func window(_ source: [String], from declaration: String,
                        file: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from \(file) — if the header was restructured this \
                test should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` in \(file) has no closing brace at its own indentation — the \
                file was reformatted or the member restructured, and reading on would inspect \
                the wrong lines
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments.
    ///
    /// ⚠️ Load-bearing here, checkably: the rationale block inside `topBar` NAMES the constructs
    /// this test forbids ("Inlining its `TimelineView`/`Canvas` here …"), and the strip's own
    /// header quotes `masterLevel` and the freeze it causes. An unfiltered scan would find those
    /// warnings and report the very leak they exist to prevent.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent(Self.workspace).path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
