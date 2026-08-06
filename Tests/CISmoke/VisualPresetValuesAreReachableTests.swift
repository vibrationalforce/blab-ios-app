// VisualPresetValuesAreReachableTests.swift
// Echoel — #427. A preset chip must be reachable by hand from the row that shows its value.
//
// WHAT CHANGED AND WHY IT NEEDS A GUARD. `EchoelValueField` defaults to `decimals: 4`, and six
// of the seven rows in `visualAdjustFields` were taking that default: Energy, Intensity, Motion,
// Spread, Hue, Saturation all offered FOUR decimal places for values whose whole travel is 0…1
// or 0…1.5. That is not a display nicety — `ScrubPrecision.snapped` uses `decimals` as the SNAP
// GRID, so those rows stored to 0.0001 while every FX parameter, the master volume and the
// weather mixers in this same app store to 0.01. #427 gives the six an explicit `decimals: 2`,
// which is the value the rest of the app already uses for a 0…1 control.
//
// ⭐ THE RISK THE CHANGE INTRODUCES IS NOT "less precision", IT IS AN UNREACHABLE PRESET. The
// visual preset chip stays lit only while the six values still MATCH the preset
// (`sameOnDisplayGrid`, four places). Coarsening a row's grid means the row can no longer land
// on a value that is not on that grid — so a preset carrying a third decimal would become a
// chip the user can leave and never get back by hand, with nothing failing anywhere. Today all
// of `VisualPreset.factory` is representable at two places; this file is what makes a future
// preset that is not a RED TEST instead of a silent one-way door.
//
// ⚠️ THE FLOAT→DOUBLE STEP IS PART OF THE MEASUREMENT, not noise to wave away. `VisualPreset`
// stores `Float`, the rows are `Double`, and `applyVisualPreset` writes `Double(p.intensity)` —
// so the stored number is e.g. 0.44999998807907104, never the literal 0.45. That offset is ~1e-8
// and the comparison the app makes is at 1e-4, four orders coarser, so it cannot decide
// anything. The check below is therefore run on the CONVERTED value, exactly as the app holds
// it, rather than on the literal — a test on the literal would be measuring a number the app
// never has.
//
// ⚠️ HONEST LIMITS.
//   · `sameOnDisplayGrid` is `private` to `EchoelStudioView`, so the predicate is RE-DERIVED
//     here. If someone changes the app's comparison to a different number of places, this file
//     stays green while the real answer moves. That is a real gap and the reason the source scan
//     below exists at all: the two halves fail for different reasons, and neither replaces the
//     other.
//   · The scan is source text. It proves each row SPELLS a decimals value; it cannot prove the
//     row renders, that the chip re-lights on a device, or that two places is the right choice
//     for a human finger. NEEDS-FOUNDER-VERIFY: pick a visual preset, nudge Intensity, nudge it
//     back — does the chip come back lit?
//   · It says nothing about the OTHER rows in the app that still take the 4-place default, and
//     the honest count is bigger than the obvious one: TEN call sites, but two of those are the
//     `param`/`knob` helpers in `EchoelStudioView`, which render SEVENTEEN rows in the Sound
//     panel between them (nine of those are `0…1`). So it is twenty-five rows, not ten —
//     twenty-four reachable, since `PianoRollView`'s "Vel" is in a doorless file. Of the eight
//     direct sites, two want four decimals on purpose (A4 concert pitch and the locked tempo
//     both say "editable to 0.0001" in their own comments), which is exactly why this is NOT
//     written as an app-wide rule: a blanket `decimals: 2` would break those two. Scoped to one
//     panel deliberately; the rest is registered, not silently swept.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest
@testable import Echoelmusic

final class VisualPresetValuesAreReachableTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let fieldsDeclaration = "private var visualAdjustFields: some View"

    /// Every row in the visual panel states its own grid instead of inheriting one.
    ///
    /// RED BEFORE #427: six of the seven calls carried no `decimals:` at all.
    func testEveryVisualRowSaysHowManyDecimalsItShows() throws {
        let calls = try valueFieldCalls()

        // The scan must not be able to pass by finding nothing. Seven rows ship today
        // (Energy · Intensity · Detail · Motion · Spread · Hue · Saturation); if the panel is
        // rewritten with fewer, that is a decision someone makes with this line in front of them.
        XCTAssertEqual(calls.count, 7, """
            `visualAdjustFields` no longer holds seven `EchoelValueField` rows — it holds \
            \(calls.count). This guard is about the DEFAULT grid leaking into this panel, so a \
            changed row count means the premise moved and the expectation belongs in the same \
            commit as the change, not left to fail later.
            """)

        for call in calls {
            XCTAssertNotNil(decimals(in: call), """
                A visual row takes `EchoelValueField`'s default `decimals: 4`:

                \(call)

                Four decimals on a 0…1 control is both a display of noise and a 0.0001 snap \
                grid, which is finer than any other 0…1 row in the app (every FX parameter, the \
                master volume and the weather mixers are `decimals: 2`). Pass the value \
                explicitly. If four really is wanted here, say `decimals: 4` out loud — this \
                guard is about the row stating its grid, not about the number 2.
                """)
        }
    }

    /// Every shipped preset value can be typed or dragged to on the grid its own row uses.
    func testEveryFactoryPresetValueIsReachableFromItsRow() throws {
        let grids = try decimalsByLabel()

        for preset in VisualPreset.factory {
            try assertReachable(Double(preset.intensity), label: "Intensity",
                                grids: grids, preset: preset.name)
            try assertReachable(Double(preset.detail), label: "Detail",
                                grids: grids, preset: preset.name)
            try assertReachable(Double(preset.motion), label: "Motion",
                                grids: grids, preset: preset.name)
            try assertReachable(Double(preset.spread), label: "Spread",
                                grids: grids, preset: preset.name)
            if let hue = preset.hue {
                try assertReachable(Double(hue), label: "Hue", grids: grids, preset: preset.name)
            }
            if let saturation = preset.saturation {
                try assertReachable(Double(saturation), label: "Saturation",
                                    grids: grids, preset: preset.name)
            }
        }
    }

    /// The reachability predicate has teeth — a third decimal really does fail it.
    ///
    /// Without this, a bug in `landsOnPresetValue` (or a `decimals` parse that silently returned
    /// a huge number) would make the test above green for every input, which is the failure mode
    /// this bundle has paid for before: a guard that cannot fail.
    func testTheReachabilityCheckCanFail() {
        // 0.825 is the smallest kind of value that breaks: it rounds to 0.83 on a two-place
        // grid, which is half a hundredth away — 50× the 1e-4 the app compares at.
        XCTAssertFalse(landsOnPresetValue(0.825, decimals: 2),
                       "A three-decimal value must NOT read as reachable from a two-decimal row.")
        XCTAssertTrue(landsOnPresetValue(0.82, decimals: 2),
                      "A two-decimal value must read as reachable from a two-decimal row.")
        XCTAssertFalse(landsOnPresetValue(14.5, decimals: 0),
                       "A half-step must NOT read as reachable from a whole-number row.")
    }

    // MARK: - The predicate

    /// Can the row land exactly on `value`, as far as the app's own comparison can tell?
    ///
    /// Two steps, in the order the app performs them: `ScrubPrecision.snapped` is what the field
    /// writes (`EchoelValueField.apply`), and four-place rounding is what
    /// `EchoelStudioView.sameOnDisplayGrid` uses to decide whether the preset chip stays lit.
    ///
    /// The clamp bounds are deliberately wide: `VisualPreset.init` already clamps every value
    /// into its row's range, so a range clamp here would be a no-op that could only introduce a
    /// second, drifting copy of those bounds. This function measures the GRID and nothing else.
    private func landsOnPresetValue(_ value: Double, decimals: Int) -> Bool {
        let snapped = ScrubPrecision.snapped(value, lowerBound: -.greatestFiniteMagnitude,
                                             upperBound: .greatestFiniteMagnitude,
                                             decimals: decimals)
        return (snapped * 10_000).rounded() == (value * 10_000).rounded()
    }

    private func assertReachable(_ value: Double, label: String,
                                 grids: [String: Int], preset: String) throws {
        let decimals = try XCTUnwrap(grids[label], """
            No `EchoelValueField` labelled "\(label)" was found in `visualAdjustFields`, so this \
            test cannot know which grid the value \(value) has to land on. Either the row was \
            renamed (update this table in the same commit) or it is gone (then the preset field \
            it edits is unreachable, which is the very thing this file exists to catch).
            """)

        // Hoisted out of the message: this bundle has made the blocking gate red once already
        // with an expression the type-checker could not afford inside a string literal (#287).
        let landed = ScrubPrecision.snapped(value, lowerBound: -.greatestFiniteMagnitude,
                                            upperBound: .greatestFiniteMagnitude,
                                            decimals: decimals)

        XCTAssertTrue(landsOnPresetValue(value, decimals: decimals), """
            Preset "\(preset)" carries \(label) = \(value), which the row cannot land on: it \
            shows \(decimals) decimals, so `ScrubPrecision.snapped` moves the value to \(landed).

            The consequence is a ONE-WAY DOOR in the UI and nothing else fails: tapping the \
            preset chip still applies the value, but the moment the user nudges any of the six \
            rows the chip goes out, and no amount of dragging brings it back — \
            `sameOnDisplayGrid` compares at four places and the row can only produce grid \
            values. Fix by choosing a preset value on the row's grid, not by widening the \
            comparison.
            """)
    }

    // MARK: - Source reading

    /// `decimals:` for each labelled row in `visualAdjustFields`.
    private func decimalsByLabel() throws -> [String: Int] {
        var table: [String: Int] = [:]
        for call in try valueFieldCalls() {
            guard let label = label(in: call), let d = decimals(in: call) else { continue }
            table[label] = d
        }
        return table
    }

    /// Every `EchoelValueField(...)` call inside `visualAdjustFields`, whole call, parens matched.
    ///
    /// Paren-matched rather than line-based on purpose: four of the seven rows wrap, and three of
    /// those carry a trailing `onChange: { … }` closure — a line-based scan would read the first
    /// line of a wrapped call, find no `decimals:` on it, and report a defect that is not there.
    /// (The mirror of the #413 lesson: the unit of a source claim is the BINDING, not the line.)
    private func valueFieldCalls() throws -> [String] {
        let block = try visualAdjustFieldsBlock()
        let chars = Array(block)
        let needle = Array("EchoelValueField(")
        var calls: [String] = []
        var i = 0

        while i + needle.count <= chars.count {
            guard Array(chars[i..<(i + needle.count)]) == needle else { i += 1; continue }
            var depth = 0
            var j = i + needle.count - 1          // sits on the opening paren
            var end: Int?
            while j < chars.count {
                if chars[j] == "(" { depth += 1 }
                else if chars[j] == ")" {
                    depth -= 1
                    if depth == 0 { end = j; break }
                }
                j += 1
            }
            guard let close = end else {
                XCTFail("An `EchoelValueField(` call in `visualAdjustFields` has no matching "
                        + "closing paren — the scan cannot read it, so it reports rather than "
                        + "skipping.")
                break
            }
            calls.append(String(chars[i...close]))
            i = close + 1
        }
        return calls
    }

    /// The body of `visualAdjustFields`, comments stripped, braces matched.
    private func visualAdjustFieldsBlock() throws -> String {
        let source = try codeLines(Self.studio)
        guard let start = source.firstIndex(where: { $0.contains(Self.fieldsDeclaration) }) else {
            XCTFail("`\(Self.fieldsDeclaration)` is gone from \(Self.studio). If the visual "
                    + "panel was restructured, this guard moves with it in the same commit.")
            return ""
        }

        var depth = 0
        var opened = false
        var block: [String] = []
        for line in source[start...] {
            block.append(line)
            for ch in line {
                if ch == "{" { depth += 1; opened = true }
                else if ch == "}" { depth -= 1 }
            }
            if opened && depth == 0 { break }
        }
        return block.joined(separator: "\n")
    }

    private func label(in call: String) -> String? {
        quotedValue(after: "label:", in: call)
    }

    private func decimals(in call: String) -> Int? {
        guard let range = call.range(of: "decimals:") else { return nil }
        let digits = call[range.upperBound...]
            .drop(while: { $0 == " " })
            .prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private func quotedValue(after key: String, in call: String) -> String? {
        guard let found = call.range(of: key) else { return nil }
        let rest = call[found.upperBound...].drop(while: { $0 == " " })
        guard rest.first == "\"" else { return nil }
        let body = rest.dropFirst().prefix(while: { $0 != "\"" })
        return body.isEmpty ? nil : String(body)
    }

    // MARK: - Files

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — the scan half of this "
                          + "test inspects source text, so it SKIPS rather than reporting a "
                          + "green it did not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment.
    ///
    /// Load-bearing: the doc block above `visualAdjustFields` and the ⛔ note inside it both
    /// SPELL `EchoelValueField` and `decimals:` in prose. A scan that read comments would count
    /// sentences as rows.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
