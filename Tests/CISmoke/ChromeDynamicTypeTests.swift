// ChromeDynamicTypeTests.swift
// Echoel — the always-visible chrome must not cap the text size a low-vision user set.
//
// WHAT THIS GUARDS (#232 C). `WorkspaceView` clamps its chrome Group — brand header,
// CompositionHeaderStrip — with `.dynamicTypeSize(...)`. Behind that clamp sit Genre, Key,
// Scale, Tone system and A4: controls that are on screen at all times. Until 2026-07-30 the
// ceiling was `.xxLarge`, the largest NON-accessibility size, so a user on AX1…AX5 got no
// enlargement at all there.
//
// ⛔ THE LIST WAS THREE BARS UNTIL #456 and it named Play/Stop and tempo as living behind the
// clamp. Both statements are now false, and they went false in two steps rather than one:
// #289 took Play/Stop into the instrument, #411 took the tempo field, and #456 dissolved the
// bar that had held them. Everything that migrated is now OUTSIDE this ceiling — see the note
// on `TransportPositionView` in `WorkspaceView.swift`, which records what that costs.
//
// ⛔ THE FIRST VERSION OF THIS HEADER ALSO SAID the clamp capped the app's own pinch zoom.
// FALSE: `StudioZoom` is applied inside `EchoelStudioView`, which mounts under `SurfaceHost`
// — a SIBLING of the clamped Group, not a descendant — and `.dynamicTypeSize` only writes
// downward. The pinch zoom never reached the chrome and still does not.
//
// The clamp existed for a real reason: the three bars were `.frame(height:)`, so bigger text
// overflowed a box that could not grow. The fix removed the reason (heights are minimums now)
// and then raised the ceiling. Three things must stay true together, which is what this file
// checks: the ceiling is an accessibility size, no bar is pinned again, and each bar keeps the
// `fixedSize` that stops it competing with the instrument for free space.
//
// ⚠️ WHY A SOURCE SCAN AND NOT A LAYOUT TEST. There is no simulator in this environment and
// the blocking bundle is `Tests/CISmoke`; a SwiftUI layout assertion cannot run here. The
// realistic regression is textual — someone re-pins `.frame(height: 44)` to make a row line up,
// or lowers the ceiling to make something fit — and a textual check catches exactly that. It
// does NOT check that the layout looks right at AX1; nothing here can. Read the ceiling itself
// as unfinished: AX4/AX5 users are still served AX1, deliberately, because nobody has seen
// those sizes on a device. Do not read a green here as "the chrome is accessible".
//
// ⚠️ SECOND HONEST LIMIT: it scans SOURCE TEXT. If the checkout is not at the path this file
// was compiled from, it SKIPS rather than passes — a silent pass on an unscanned tree is the
// `continue-on-error` lie the `doctor` skill exists to catch.

import Foundation
import XCTest

final class ChromeDynamicTypeTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Comments are dropped because the
    /// commit that made this change QUOTES the old `.frame(height: 50)` spellings in its own
    /// prose so the history stays legible — matching those would fail on the fix itself.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"

    /// The sizes that are NOT an accessibility size. Any of them as the chrome ceiling means a
    /// low-vision user gets nothing, which is the defect.
    private static let nonAccessibilityCeilings = [
        "DynamicTypeSize.xSmall", "DynamicTypeSize.small", "DynamicTypeSize.medium",
        "DynamicTypeSize.large", "DynamicTypeSize.xLarge", "DynamicTypeSize.xxLarge",
        "DynamicTypeSize.xxxLarge"
    ]

    /// The other spelling of the same thing. `.environment(\.dynamicTypeSize, …)` is invisible
    /// to a `.dynamicTypeSize(` grep and would silently re-cap the chrome while every
    /// assertion below still passed — so it is banned outright in the chrome's own file
    /// rather than parsed.
    private static let clampByEnvironment = #"environment(\.dynamicTypeSize"#

    func testTheChromeCeilingIsAnAccessibilitySize() throws {
        let lines = try codeLines(Self.workspace)
        XCTAssertFalse(lines.contains { $0.contains(Self.clampByEnvironment) },
                       "the chrome sets the type size through `.environment(\\.dynamicTypeSize, …)`. "
                       + "That is the same clamp under a name this file cannot read; use "
                       + "`.dynamicTypeSize(...)` so there is one spelling to check.")
        let clamps = lines.filter { $0.contains(".dynamicTypeSize(") }
        XCTAssertEqual(clamps.count, 1,
                       "expected exactly ONE Dynamic Type clamp in WorkspaceView.swift; found "
                       + "\(clamps.count). A second clamp means two ceilings disagree and the "
                       + "lower one silently wins:\n\(clamps.joined(separator: "\n"))")
        let clamp = try XCTUnwrap(clamps.first)
        XCTAssertTrue(clamp.contains("DynamicTypeSize.accessibility"),
                      "the chrome ceiling is not an accessibility size — every AX user is "
                      + "capped below the smallest accessibility step, on Play/Stop, tempo, "
                      + "Key and Scale: \(clamp)")
        for bad in Self.nonAccessibilityCeilings {
            XCTAssertFalse(clamp.contains(bad),
                           "the chrome ceiling names \(bad): \(clamp)")
        }
    }

    /// The three chrome bars: the design height, and the token that proves the bar is still
    /// MOUNTED. The token matters as much as the number — #251's lesson is that a guard which
    /// stays green while the guarded thing is deleted is worse than no guard, and without it
    /// removing `CompositionHeaderStrip()` from the Group would pass as long as some
    /// `.frame(minHeight: 40)` survived anywhere in this 800-line file.
    ///
    /// ⛔ THE TABLE HELD THREE ROWS UNTIL #456 AND IT WENT RED WHEN ONE OF THEM WAS DELETED —
    /// which is the guard working, not failing. `TransportBar` dissolved on the founder's
    /// 2026-08-07 arrows; its `.frame(minHeight: 44)` and its `TransportBar()` mount both
    /// left the file, so three assertions here fired at once. The row is removed in the
    /// commit that answers them, per this doc's own instruction ("update this expectation in
    /// the same commit — do not delete the check").
    ///
    /// ⚠️ AND THE COST OF FINDING IT LATE IS THE REAL LESSON: `Echoelmusic CI/CD Pipeline`
    /// reports `failure` on EVERY push while #396 lives, so this red was indistinguishable
    /// from the host death without reading per-test names in the job log. Before deleting a
    /// chrome element, `git grep` it in `Tests/CISmoke` — not only in `Sources/`.
    private static let chromeBars = [(bar: "topBar", height: 50, mount: "topBar"),
                                     (bar: "CompositionHeaderStrip", height: 40,
                                      mount: "CompositionHeaderStrip()")]

    func testTheChromeBarsCanGrowWithTheirText() throws {
        let lines = try codeLines(Self.workspace)
        for spec in Self.chromeBars {
            XCTAssertTrue(lines.contains { $0.contains(spec.mount) },
                          "\(spec.bar) is no longer mounted (`\(spec.mount)` is gone). Every "
                          + "other assertion here would still pass, which is exactly why this "
                          + "one exists.")
            // Both spellings that restore the pin: replacing the modifier, and ADDING a second
            // one beside the surviving minHeight. The second is what someone actually writes
            // when a row needs to line up again, and it is the one a naive check misses.
            XCTAssertFalse(lines.contains { $0.contains(".frame(height: \(spec.height)") },
                           "\(spec.bar) pins .frame(height: \(spec.height)…) again. A fixed "
                           + "height under the raised Dynamic Type ceiling does not shrink the "
                           + "text — the text overflows and the next bar's opaque background "
                           + "paints over it, which is worse than the clamp this replaced.")
            XCTAssertFalse(lines.contains { $0.contains("maxHeight: \(spec.height)") },
                           "\(spec.bar) caps at maxHeight: \(spec.height). Beside the surviving "
                           + "minHeight that is the fixed height again, spelled so the other "
                           + "assertions stay green.")
            XCTAssertTrue(lines.contains { $0.contains(".frame(minHeight: \(spec.height))") },
                          "\(spec.bar) no longer carries .frame(minHeight: \(spec.height)). If "
                          + "the bar was deliberately resized, update this expectation in the "
                          + "same commit — do not delete the check.")
        }
    }

    /// `fixedSize` is not cosmetic here and is not covered by the height checks: without it a
    /// bar hosting an `EchoelValueField` reports infinite vertical flexibility (the scrub
    /// layer is a bare `Rectangle`), and the VStack then splits free space between the bar and
    /// the instrument — at the DEFAULT text size, for every user. Whoever deletes it will be
    /// deleting a line that looks redundant.
    func testEachChromeBarStaysInflexible() throws {
        let lines = try codeLines(Self.workspace)
        // Adjacency, not a count. A count would be wrong twice over: this file already had
        // vertical `fixedSize` calls that have nothing to do with the chrome (a first version
        // asserted `== 3` and would have gone red on arrival), and a count cannot see ORDER —
        // `fixedSize` must sit BEFORE the frame, or the frame's proposal reaches the child
        // first and the floor stops bounding anything. Whole-line comments are already
        // dropped, so the two modifiers are neighbours in this list even with prose between
        // them in the source.
        for spec in Self.chromeBars {
            let frame = ".frame(minHeight: \(spec.height))"
            guard let i = lines.firstIndex(where: { $0.contains(frame) }), i > 0 else {
                XCTFail("\(spec.bar): no `\(frame)` to anchor the fixedSize check against — "
                        + "the height assertion above should have caught this first")
                continue
            }
            XCTAssertTrue(lines[i - 1].contains(".fixedSize(horizontal: false, vertical: true)"),
                          "\(spec.bar) lost the `.fixedSize(horizontal: false, vertical: true)` "
                          + "directly above `\(frame)`. Without it the bar reports infinite "
                          + "vertical flexibility (its EchoelValueField's scrub layer is a bare "
                          + "Rectangle) and splits the screen with SurfaceHost — at the DEFAULT "
                          + "text size, for every user. Line above was: \(lines[i - 1])")
        }
    }

    /// ⭐ #348 — THE HEADER MUST NOT STACK ITS TITLE ON TOP OF ITS TILES.
    ///
    /// Founder, 2026-08-01, circling the empty space left of the wordmark: *"Was kann hier jetzt
    /// noch hin?"* The answer was "nothing — move the title into it", and the reason is in this
    /// file's subject rather than in taste. `topBar` was a `ZStack`: an optically centred title
    /// on one layer, and the row holding the mark and the three output monitors on another. A
    /// `ZStack` performs no collision avoidance, so as the text grows the title grows straight
    /// THROUGH the tiles — and since #232 C the chrome ceiling is `.accessibility1`, not
    /// `.xxLarge`, so it now grows a lot further than it used to. `minimumScaleFactor(0.7)` only
    /// bounds how far it goes, it does not stop it.
    ///
    /// In an `HStack` the slack is what yields, so the two can no longer overlap at any text
    /// size. That property is invisible in a screenshot at the default size, which is exactly why
    /// it needs a guard rather than a comment.
    ///
    /// ⛔ THE MECHANISM CHANGED WITH #384 AND THIS GUARD WENT RED — correctly, and it is worth
    /// recording which half was stale. #348 built the row as TWO columns with a
    /// `Spacer(minLength: 8)` pushing the monitors to the trailing edge, and this test pinned
    /// that spelling. On 2026-08-02 the founder asked for the wordmark back in the MIDDLE, which
    /// a two-column row cannot do: a `Spacer` gives all the slack to one side. The bar is now
    /// three columns — greedy flank, brand, greedy flank — and a `Spacer` in it would compete
    /// with those flanks for the same slack and quietly pull the "centre" off centre. So the
    /// assertion is inverted rather than deleted: the SUBJECT (title and monitors can never
    /// overlap) is unchanged and still carried by the two assertions above it; what is banned is
    /// now the `Spacer`, not its absence. The exact flank COUNT is pinned once, in
    /// `HeaderSpectrumIsALeafTests.testTheTitleIsCentredWithoutAZStack` — not duplicated here,
    /// so a future layout change has one number to update and not two.
    func testTheHeaderLaysOutInARowSoTheTitleCannotOverlapTheMonitors() throws {
        let bar = try topBarSource()
        XCTAssertFalse(bar.contains { $0.contains("ZStack") }, """
            `topBar` is a `ZStack` again. Its layers do not avoid each other, so the wordmark \
            and the output monitors share the same space and simply overlap once the text \
            grows — silently, and only at accessibility sizes nobody screenshots. Lay the bar \
            out as an `HStack` with a `Spacer` between brand and monitors.
            """)
        XCTAssertTrue(bar.contains { $0.contains("HStack(spacing: 8) {") }, """
            `topBar` no longer opens with an `HStack`. If the layout was deliberately changed, \
            update this guard together with the change — do not delete it; the ZStack it \
            replaced shipped a real Dynamic Type overlap.
            """)
        let spacers = bar.filter { $0.contains("Spacer(") || $0.contains("Spacer()") }
        XCTAssertTrue(spacers.isEmpty, """
            A `Spacer` is back in `topBar`: \
            \(spacers.map { $0.trimmingCharacters(in: .whitespaces) }). Since #384 the bar is \
            three columns and both flanks carry `.frame(maxWidth: .infinity)`; a `Spacer` \
            competes with them for the same leftover width, so the brand block stops sitting in \
            the geometric middle — silently, and by an amount that depends on how much slack \
            there happens to be. Use the flanks' alignment to place things, not a Spacer.
            """)
        XCTAssertEqual(bar.filter { $0.contains("HStack(spacing: 8) {") }.count, 3, """
            `topBar` no longer has exactly three `HStack(spacing: 8)` (the bar itself, the brand \
            block, the monitor cluster). The bar's own spacing is what guarantees a gap between \
            the wordmark and the first tile now that the `Spacer` is gone — an HStack spacing \
            cannot be consumed by a greedy child, which is precisely why it replaced one.
            """)
    }

    /// The brand mark and the wordmark are ONE door, so they must be ONE control. As two buttons
    /// they were two VoiceOver stops for the same action, which the old code papered over with
    /// `.accessibilityHidden(true)` on the mark. Counting the calls is the durable form of that:
    /// a second `openWebsite()` in this bar means the split is back.
    func testTheBrandIsOneControlAndNotTwo() throws {
        let bar = try topBarSource()
        let opens = bar.filter { $0.contains("openWebsite()") }.count
        XCTAssertEqual(opens, 1, """
            `topBar` calls `openWebsite()` \(opens) time(s); exactly one is expected. Two means \
            the mark and the wordmark are separate buttons again — the same door announced \
            twice, which is why the previous version had to hide one of them from VoiceOver.
            """)
        XCTAssertFalse(bar.contains { $0.contains("accessibilityHidden(true)") }, """
            Something in `topBar` is hidden from VoiceOver. In this bar that has only ever been \
            the workaround for the duplicate brand button; if a NEW element genuinely needs \
            hiding, say why here and update this guard in the same commit.
            """)
    }

    /// The `topBar` property's code lines (whole-line comments already dropped), from its
    /// declaration to the `}` at member indentation. Scoped deliberately: `WorkspaceView` has
    /// other `ZStack`s that are perfectly correct, so a file-wide grep would be a guard that
    /// fires on unrelated work and gets switched off.
    private func topBarSource() throws -> [String] {
        let lines = try codeLines(Self.workspace)
        guard let start = lines.firstIndex(where: { $0.contains("private var topBar: some View {") }) else {
            throw XCTSkip("""
                `topBar` not found in \(Self.workspace) — skipping rather than reporting a green \
                this file did not earn. If the header was renamed, re-point this helper.
                """)
        }
        let rest = lines[(start + 1)...]
        guard let end = rest.firstIndex(where: { $0 == "    }" }) else {
            throw XCTSkip("no member-indentation `}` closes `topBar` — the slice would be wrong")
        }
        return Array(lines[(start + 1)..<end])
    }

    func testTheValueBoxIsAFloorAndNotACeiling() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        XCTAssertTrue(lines.contains { $0.contains(".frame(minHeight: boxHeight)") },
                      "EchoelValueField pins its box height again. `boxHeight` means 'match "
                      + "the neighbouring buttons' — a floor. As a ceiling the taller content "
                      + "overflows the box that exists to show it, and the chrome's A4 field "
                      + "(104×30) is the case that made it visible.")
        XCTAssertFalse(lines.contains { $0.contains(".frame(height: boxHeight)") },
                       "EchoelValueField still has the fixed-height spelling somewhere — two "
                       + "frames on one box means the stricter one decides.")
        XCTAssertFalse(lines.contains { $0.contains("maxHeight: boxHeight") },
                       "EchoelValueField caps at maxHeight: boxHeight. Beside the minHeight "
                       + "that is the old pin restored in the one spelling both assertions "
                       + "above would have let through.")
    }

    /// The WIDTH half. It is a separate defect from the height and it was introduced BY the
    /// ceiling raise, so it belongs in the same guard: the number carries
    /// `.minimumScaleFactor(0.5)` and the unit label does not, so in a box of fixed width the
    /// growing unit steals width from the number until the number hits its floor and
    /// truncates. Worst case in the app is Concert pitch A4 — `440.0000 Hz` in 104 pt — which
    /// demands roughly 0.39 at `.accessibility1`, below the floor.
    func testTheCompactBoxWidthGrowsWithTheText() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelValueField.swift")
        XCTAssertTrue(lines.contains { $0.contains("@ScaledMetric(relativeTo: .body) private var compactWidthProbe") },
                      "the compact `boxWidth` no longer scales with Dynamic Type. A fixed "
                      + "width under the raised ceiling truncates the value it is there to "
                      + "show — the height fix alone is half a fix.")
        XCTAssertFalse(lines.contains { $0.contains(".frame(width: boxWidth ?? valueWidth)") },
                       "the compact width is pinned again (`boxWidth ?? valueWidth`): "
                       + "`valueWidth` scales, the literal beside it does not.")
    }
}
