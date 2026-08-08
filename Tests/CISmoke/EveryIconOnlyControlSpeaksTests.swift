// EveryIconOnlyControlSpeaksTests.swift
// Echoel — #489. A control whose whole label is a glyph must carry a spoken name.
//
// ⛔ THIS FILE EXISTS BECAUSE THE DEFECT IT WAS WRITTEN FOR DOES NOT EXIST. #489 was filed as
// "the ••• menu is the one header tile without a spoken label". It was not: `TransportOverflowMenu`
// carried `.accessibilityLabel("More — Live Colabo; Learn and news")`, 37 lines below the
// `EchoelIconTile` it labelled, and every call site of that tile was labelled.
// The finding was an artefact of MY OWN measurement, twice over, and the two failures are the
// durable part — the shipped assertion below is only their receipt.
//
// ⚠️ THE WITNESS IS GONE (#492, 2026-08-07) AND THE FINDING IS NOT. The founder asked for the
// "•••" entries as individual buttons, so `TransportOverflowMenu` was deleted and its two doors
// became `EchoelIconTile`s in `EchoelStudioView.quickDoorRow` — each with its own spoken label.
// The sentences above are therefore written in the past tense on purpose: the retraction they
// carry is about a MEASUREMENT and survives the disappearance of the control it measured. Do not
// "fix" the line numbers back in; there is nothing at them any more. Counted after the move:
// SEVEN `EchoelIconTile` call sites in `Sources/`, all seven labelled. (The "347 files" and the
// 47/22/25 block census below are the #489-time measurement and are quoted as history — the
// assertions use `>=` bounds precisely so an ordinary file add or removal does not go red.)
//
// ⭐ THE MEASUREMENT FAILURE, because it will recur in any future scan of this codebase.
//   Scanner 1 — fixed ±14-line window around the tile: 8 false positives.
//   Scanner 2 — brace-matched block, then a modifier-chain walk with a 3-line blank lookahead:
//               4 false positives (`BodyTempoField:173`, `EchoelStudioView:1837`, `:9830`,
//               `WorkspaceView:576` — every one of them labelled).
//   CAUSE — and it is specific to this repo: `SourceText.codeOnly` preserves line COUNT, so the
//   30-to-40-line ⛔/⭐ blocks this codebase writes become 30-to-40 BLANK LINES. A label can sit
//   an arbitrary number of blank lines below the block it belongs to. Any fixed window, and any
//   short blank lookahead, is unsound here BY CONSTRUCTION rather than by bad luck.
//   Scanner 3 — skip ALL blank lines when the next non-blank starts with `.`, and track paren
//   depth so a multi-line modifier does not end the chain (`BodyTempoField`'s ternary label
//   continues on a line starting with `:`, not `.`). Measured over 347 files: 47 `label:` blocks
//   holding an `Image(systemName:)`, of which 22 also render text and 25 are icon-only. Zero of
//   the 25 are mute. Widest modifier chain crossed: 25 lines.
//
// ⭐ THAT IS THE #443 CLASS — "the METHOD named in a claim is itself a claim" — committed by me
// twice inside one cycle, in the very cycle whose commit message warns about it. The counterweight
// assertions below exist so the next simplification of this walker cannot quietly re-introduce
// either failure: a short lookahead makes `maxChainGap` collapse, and a narrowed sweep makes
// `checked` collapse. Both go red before the label assertion does.
//
// ⚠️ WHAT THIS GUARD CANNOT DO, stated first so its green is not read as more than it is.
//   · Every assertion is a SOURCE-TEXT SCAN. It shows that a modifier is written, never that
//     VoiceOver speaks it, that the phrase reads well aloud, or that the control is reachable.
//     Those are device probes and all three are open (#480 paid for exactly this distinction).
//   · It only sees an icon-only control written as `… label: { Image(systemName:) }`. A bare
//     `Button { } label: { Image(…) }` on ONE line, a `Label` with a hidden title, an icon inside
//     a custom view type, and any `Image` used as a tap target without a `label:` block are all
//     invisible to it. The measured population is 25 blocks; the app has more icons than that.
//   · `accessibilityHidden` counts as satisfied. A decorative glyph inside an already-labelled
//     row is correct SwiftUI, and forbidding it would make ordinary UI work go red — the #364
//     trap, which is how a guard gets deleted instead of obeyed.
//
// ⚠️ AND THE HONEST GRADING: NONE of the four assertions is a regression. All four are green on
// the tree that preceded them, because there was no defect to fix. Their entire value is forward:
// they make "no icon-only control ships mute" a property instead of a snapshot, and they make the
// two unsound scanner shapes above go red instead of green-on-nothing. Saying that plainly is the
// #433 rule — mis-grading your own tests in the flattering direction is the same defect as
// mis-grading them in the harsh one.

import Foundation
import XCTest

final class EveryIconOnlyControlSpeaksTests: XCTestCase {

    // MARK: - the sweep

    /// One icon-only `label: { … }` block found in `Sources/`.
    private struct IconBlock {
        let where_: String
        let hasVisibleText: Bool
        let labelled: Bool
        let chainGap: Int
    }

    /// The whole result of one sweep, so every assertion below measures the SAME pass.
    private struct Sweep {
        var files = 0
        var blocks: [IconBlock] = []
    }

    private func sweep() throws -> Sweep {
        var result = Sweep()
        for url in try swiftFilesUnderSources() {
            result.files += 1
            let raw = try String(contentsOf: url, encoding: .utf8)
            let lines = SourceText.codeOnly(raw).components(separatedBy: "\n")
            let name = url.lastPathComponent
            result.blocks.append(contentsOf: blocks(in: lines, file: name))
        }
        return result
    }

    private func blocks(in lines: [String], file: String) -> [IconBlock] {
        var found: [IconBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // `} label: {` and `label: {` both end the line with a brace. An inline
            // `label: { Image(…) }` does not, and is deliberately out of scope (see the header).
            if !trimmed.hasSuffix("{") || !trimmed.contains("label:") {
                i += 1
                continue
            }
            let indent = leadingSpaces(line)
            guard let close = closingBrace(lines, openAt: i, indent: indent) else {
                i += 1
                continue
            }
            let body = lines[(i + 1)..<close].joined(separator: "\n")
            if !body.contains("Image(systemName:") {
                i += 1
                continue
            }
            let hasText = body.contains("Text(") || body.contains("Label(")
            let walk = chain(lines, from: close + 1)
            let labelled = walk.text.contains("accessibilityLabel")
                || walk.text.contains("accessibilityHidden")
            found.append(IconBlock(where_: "\(file):\(i + 1)",
                                   hasVisibleText: hasText,
                                   labelled: hasText ? true : labelled,
                                   chainGap: walk.consumed))
            i = close + 1
        }
        return found
    }

    private func leadingSpaces(_ line: String) -> Int {
        var n = 0
        for c in line {
            if c == " " { n += 1 } else { break }
        }
        return n
    }

    /// The first line that is exactly `}` at the SAME indent as the `label: {` that opened it.
    /// Bounded at 80 lines: a longer icon label is not one, and an unbounded search would pair a
    /// stray brace far below with the wrong block.
    private func closingBrace(_ lines: [String], openAt: Int, indent: Int) -> Int? {
        var j = openAt + 1
        let limit = min(openAt + 81, lines.count)
        while j < limit {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            if t == "}" && leadingSpaces(lines[j]) == indent { return j }
            j += 1
        }
        return nil
    }

    /// Walk the modifier chain that follows a closed block.
    ///
    /// ⛔ The two rules here are the whole point of the file, and each one killed a scanner:
    ///  1. A BLANK line is consumed only when the next non-blank line starts with `.` — comment
    ///     blocks become blank runs of arbitrary length after `SourceText.codeOnly`, so a fixed
    ///     lookahead of any size is wrong.
    ///  2. While paren depth is positive the line is consumed unconditionally — a multi-line
    ///     modifier's continuation need not start with `.` (a wrapped ternary starts with `:`).
    private func chain(_ lines: [String], from start: Int) -> (text: String, consumed: Int) {
        var collected: [String] = []
        var depth = 0
        var k = start
        while k < lines.count {
            let cur = lines[k]
            let t = cur.trimmingCharacters(in: .whitespaces)
            if depth > 0 {
                collected.append(cur)
                depth += parenDelta(cur)
                k += 1
                continue
            }
            if t.isEmpty {
                if nextNonBlankStartsWithDot(lines, after: k) {
                    collected.append(cur)
                    k += 1
                    continue
                }
                break
            }
            if t.hasPrefix(".") {
                collected.append(cur)
                depth += parenDelta(cur)
                k += 1
                continue
            }
            break
        }
        return (collected.joined(separator: "\n"), k - start)
    }

    private func parenDelta(_ line: String) -> Int {
        var d = 0
        for c in line {
            if c == "(" { d += 1 }
            if c == ")" { d -= 1 }
        }
        return d
    }

    private func nextNonBlankStartsWithDot(_ lines: [String], after k: Int) -> Bool {
        var m = k + 1
        while m < lines.count {
            let t = lines[m].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t.hasPrefix(".") }
            m += 1
        }
        return false
    }

    // MARK: - the assertion

    /// An icon has no text. If nothing names it, VoiceOver falls back to the SF Symbol name —
    /// which is a token like `ellipsis` or `slider.horizontal.3`, i.e. an implementation detail
    /// read aloud as if it were the control's purpose (#488 paid for exactly that on the number
    /// pad's sign keys, where the fallback words named arithmetic the keys do not do).
    func testEveryIconOnlyControlSpeaks() throws {
        let s = try sweep()
        let mute = s.blocks.filter { !$0.labelled }.map { $0.where_ }
        XCTAssertEqual(mute, [], """
            These icon-only controls carry no `.accessibilityLabel` and are not \
            `.accessibilityHidden`: \(mute.joined(separator: ", ")).

            An icon-only control has no text, so VoiceOver reads the SF Symbol name — an \
            implementation token, spoken as though it were the purpose. Add a label that names \
            what the control DOES, in the words the visible UI already uses.

            ⛔ Do NOT satisfy this by adding `.accessibilityHidden(true)` to a real control. \
            Hidden is correct only for a decorative glyph inside an already-labelled row; on a \
            tappable control it removes it from VoiceOver entirely, which is worse than the \
            wrong word this guard exists to prevent.
            """)
    }

    /// #367/#343 counterweight: a sweep that examines nothing is green on nothing. Measured on the
    /// tree that introduced this file: 347 files walked, 47 `label:` blocks holding an
    /// `Image(systemName:)`, of which 25 are icon-ONLY and 22 also render text. The floor is well
    /// below the measurement on purpose — pinning 25 would make ordinary UI work go red (#364).
    func testTheSweepActuallyExaminedIconOnlyControls() throws {
        let s = try sweep()
        XCTAssertGreaterThan(s.files, 200, """
            Only \(s.files) Swift files walked under Sources/Echoelmusic. The sweep is pointed at \
            the wrong tree, so every green below proves nothing.
            """)
        let iconOnly = s.blocks.filter { !$0.hasVisibleText }.count
        XCTAssertGreaterThanOrEqual(iconOnly, 15, """
            The sweep found only \(iconOnly) icon-ONLY `label: { Image(systemName:) }` blocks \
            (\(s.blocks.count) blocks in total); 25 icon-only were measured when this guard was \
            written. Either the detector stopped matching the shape the app writes, or the icon \
            controls moved into a helper this scan cannot see. Fix the detector — do NOT lower \
            this floor, which would convert a broken scan into a permanent green.
            """)
    }

    /// The mechanism assertion, and the one that pins the lesson. The label of the `•••` menu sits
    /// 37 source lines below its tile, separated by a ⛔ block that `codeOnly` turns into a blank
    /// run. Any walker with a bounded blank lookahead reports that labelled control as mute.
    func testTheChainWalkCrossesALongCommentGap() throws {
        let s = try sweep()
        let widest = s.blocks.map { $0.chainGap }.max() ?? 0
        XCTAssertGreaterThanOrEqual(widest, 12, """
            The widest modifier chain this walk crossed was \(widest) lines; 25 were measured when \
            this guard was written. That number collapsing means the blank-line rule in `chain` \
            was narrowed back to a bounded lookahead — the exact shape that produced four false \
            positives before this file existed. Comment blocks in this repo become blank runs of \
            arbitrary length after `SourceText.codeOnly`; the walk must skip ALL of them whenever \
            the next non-blank line starts with `.`.
            """)
    }

    /// The other counterweight. A block that renders `Text(` alongside its icon is not icon-only —
    /// SwiftUI derives a name from the text — and demanding a label there would make every ordinary
    /// labelled button go red. Measured: 22 of the 25 blocks are in this class, so this is the
    /// majority case and not an edge one.
    func testBlocksWithVisibleTextAreExempt() throws {
        let s = try sweep()
        let withText = s.blocks.filter { $0.hasVisibleText }.count
        XCTAssertGreaterThanOrEqual(withText, 10, """
            Only \(withText) of \(s.blocks.count) blocks carry visible `Text(`/`Label(`; 22 were \
            measured. If that collapsed, the exemption stopped matching and this guard is about to \
            demand a redundant `.accessibilityLabel` on every ordinary labelled button — which is \
            how a guard gets deleted instead of obeyed (#364).
            """)
    }

    // MARK: - source access

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting a \
                green this file did not earn.
                """)
        }
        return root
    }

    private func swiftFilesUnderSources() throws -> [URL] {
        let dir = try repoRoot().appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(at: dir,
                                                        includingPropertiesForKeys: nil) else {
            throw XCTSkip("could not enumerate Sources/Echoelmusic")
        }
        let urls = walk.compactMap { $0 as? URL }
        return urls.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    }
}
