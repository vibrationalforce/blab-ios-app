// TheKeypadCannotTypeWhatItCannotKeepTests.swift
// Echoel — #431. The one keypad may not display a number its own OK key would change.
//
// THE DEFECT. `EchoelNumberPad.commit()` snaps to the field's `10^-decimals` grid, and nothing
// stopped the buffer from growing past it: `append` capped only the total LENGTH at nine
// characters. On a two-place row a player typed `0.375`, read `0.375` in the 30 pt readout, and
// got `0.38`. The readout was not a preview of the commit; it was a promise the commit did not
// keep — and it is the same class of lie #427 was about one control over, where `decimals` was
// treated as display when it is really the snap grid.
//
// REACH, paren-matched over `Sources/` with whole-line comments EXCLUDED: **62 construction
// sites — 40 pass `decimals: 2`, 11 pass `0`, 10 take the 4-place default, and 1 forwards**
// (`EchoelFXView.field`, itself `decimals: Int = 2`). Three of the 62 render many rows each:
// `field`, plus `param` and `knob` in `EchoelStudioView` — both already inside the 10 defaults,
// so there is no "plus" on top of the split. The eleven `decimals: 0` rows were never exposed:
// `allowsDecimal` disables their separator key, so no `.` can enter and the cap never applies.
//
// ⛔ THE FIRST VERSION SAID "64 sites … counted rather than estimated" AND NAMED THE FX HELPER
// `param`. 64 is the raw `git grep -c` LINE count from before this slice added a third prose hit
// to it; the breakdown summed to 61, one short of its own total; and `EchoelFXView.param` does
// not exist (`param` is `EchoelStudioView`'s). `Core/EchoelDecimalText.swift` spends five lines
// warning that this command counts LINES — this was the third edition of the repo to trip on it.
//
// ⭐ THE HALF THAT IS DELIBERATELY NOT FIXED, and the discriminator that decides it. `clamped`
// can also move a committed number away from the readout — type `999` on a `0…1` row and get
// `1.0`. Extending the refusal there would be wrong, not merely larger: a fraction digit past
// the grid can never be rescued by another keystroke (nothing continues `0.375` into something
// representable at two places), while an out-of-range PREFIX is the ordinary middle of typing a
// valid number (`8` is outside `20…18000` on the way to `800`). The pad now refuses what is
// already unreachable and keeps accepting what is merely incomplete.
//
// ⚠️ WHAT THE FIX COSTS, said plainly because it changes a shipped number. Refusing the
// keystroke TRUNCATES where the snap ROUNDED: `0.375` on a two-place row committed `0.38`
// before and commits `0.37` after. And the refusal is preventive, so it also blocks the
// occasional keystroke that would have been harmless — a third `0` in `0.500` snaps back to the
// same number. Both were accepted against the repo's standing rule that a control may not show
// one number and store another (#135, #416, #427); the player can still reach `0.38` by typing
// it.
//
// ⚠️ HONEST LIMITS.
//   · TWO things are RE-DERIVED here, not one. `EchoelNumberPad.snapped` is `private`, so the
//     commit arithmetic is copied (same gap as `sameOnDisplayGrid` in the #427 guard) — and
//     `typeKeys` below is a THIRD copy of `appendDecimal`'s seeding rule. If either moves, this
//     file stays green while measuring a keypad that no longer exists. That is exactly why the
//     source scan is a separate half: the two fail for different reasons and neither replaces
//     the other.
//   · Only `testTheKeypadAsksTheRule` is RED before #431. The behavioural tests measure a pure
//     function that did not exist beforehand; they are here to stop it being loosened, not to
//     prove it was ever broken. (Strictly, against genuinely pre-#431 source the whole bundle
//     fails to compile — "red" is a statement about the counterfactual where the enum exists and
//     `append` ignores it.)
//   · This file does NOT close the empty-buffer path. `commit()` on an untouched buffer snaps
//     `initial`, and the header formats it with `String(format: "%.Nf", …)` — half-to-EVEN —
//     while the snap is half-AWAY. At an exact dyadic tie (`0.125` on a two-place row) the
//     header still reads one number and OK stores the next. Reachable via a derived binding;
//     registered as #432, deliberately not folded in here, because it is a formatter mismatch
//     rather than an entry one and wants its own measurement.
//   · Nothing here presses a key. That the pad renders, that the refusal reads as "nothing
//     happened" rather than as a stuck app, and whether truncation feels right under a thumb are
//     device questions. NEEDS-FOUNDER-VERIFY: open any FX parameter's keypad, type `0.375`, and
//     check the readout stops at `0.37` instead of showing a third place it will not keep.
//
// `Tests/CISmoke` is the blocking bundle.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheKeypadCannotTypeWhatItCannotKeepTests: XCTestCase {

    // MARK: - The wiring half (the only one that was red)

    /// `append` must consult the rule, AND must hand it the field's own `decimals`.
    ///
    /// A correct rule with no caller is the same defect with more steps — this repo has paid for
    /// that shape before. Anchored on the BINDING, not on a line: the scan takes the body of
    /// `append(_:)` and requires the call inside it, so hoisting the guard into a local still
    /// passes while deleting it does not. Comments are stripped, because this file and the source
    /// both spell the old `buffer.count < 9` rule in prose (#367: a scan that reads prose cannot
    /// fail).
    ///
    /// ⛔ THE SECOND ASSERTION EXISTS BECAUSE THE FIRST VERSION HAD ONLY THE FIRST, AND THAT WAS
    /// A HOLE THE #431 REVIEW WALKED THROUGH: with just the substring check, someone could write
    /// `acceptsDigit(after: buffer, decimals: 4)` — a constant, ignoring the row's own grid — and
    /// all six tests would stay green while every `decimals: 2` row carried the defect again. A
    /// guard over a CALL has to pin the argument that makes the call mean anything.
    func testTheKeypadAsksTheRule() throws {
        let body = try functionBody(named: "append", in: "Sources/Echoelmusic/Studio/EchoelNumberPad.swift")
        XCTAssertTrue(body.contains("NumberPadEntry.acceptsDigit"), """
            `EchoelNumberPad.append(_:)` no longer asks `NumberPadEntry.acceptsDigit`, so the \
            keypad is back to capping only the buffer LENGTH. Its body is now:

            \(body)

            That is the #431 defect: on a `decimals: 2` row the readout will show 0.375 and the \
            OK key will store 0.38. Whatever replaced the call has to keep the fraction on the \
            field's own grid.
            """)
        XCTAssertTrue(body.contains("decimals: decimals"), """
            `append(_:)` calls the rule but no longer passes the field's own `decimals`. Its \
            body is now:

            \(body)

            A constant there is the #431 defect wearing the fix's clothes: the rule would cap \
            every row at one fixed grid while the commit keeps snapping to the row's. This \
            assertion is the whole reason the scan is two lines and not one.
            """)
    }

    // MARK: - What the rule allows

    /// Every buffer the rule lets a player build commits to exactly the number it shows.
    ///
    /// This is the property the defect broke, swept rather than sampled: 0…4 places against a
    /// spread of whole parts and over-long fractions, each typed key by key through the pad's
    /// own two rules.
    func testEveryBufferTheRuleAllowsSurvivesItsOwnCommit() {
        for decimals in 0...4 {
            for whole in ["0", "1", "9", "12", "123", "1234"] {
                for fraction in ["", "1", "5", "9", "07", "99", "123", "4567", "0001"] {
                    let wholeKeys: [String] = whole.map { String($0) }
                    let fractionKeys: [String] = fraction.isEmpty
                        ? []
                        : ["."] + fraction.map { String($0) }
                    let keys = wholeKeys + fractionKeys
                    let buffer = typeKeys(keys, decimals: decimals)
                    guard let value = Double(buffer) else {
                        XCTFail("typing \(keys.joined()) at \(decimals) places built \(buffer), "
                                + "which does not parse as a number at all")
                        return
                    }
                    // The CALL is hoisted out of the message; the four interpolations stay. A
                    // literal that also had to type-check `snapCommit(...)` inside itself is the
                    // shape that made the blocking gate red once (#287) — the interpolations
                    // alone are within what this bundle already carries.
                    let committed = snapCommit(value, decimals: decimals)
                    let typedKeys = keys.joined()
                    XCTAssertEqual(committed, value, """
                        Typing \(typedKeys) on a \(decimals)-place field builds the buffer \
                        \(buffer), which the header shows verbatim — but committing it stores \
                        \(committed). The readout and the OK key disagree, which is the whole \
                        of #431.
                        """)
                }
            }
        }
    }

    /// Digits BEFORE the separator are not restricted. `decimals` says how fine the grid is,
    /// never how large the number may be — a cutoff row is `20…18000` at four places.
    func testDigitsBeforeTheSeparatorAreNotRestricted() {
        XCTAssertEqual(typeKeys(["1", "7", "9", "9", "9"], decimals: 4), "17999",
                       "The fraction cap leaked into the whole part: a cutoff row could no "
                       + "longer be typed at all.")
        XCTAssertTrue(NumberPadEntry.acceptsDigit(after: "123", decimals: 0),
                      "A `decimals: 0` row must still accept whole digits — its separator key "
                      + "is disabled, so there is no fraction to cap.")
    }

    /// The overflow cap that was already there survives the rewrite.
    func testTheOverflowCapSurvives() {
        let full = String(repeating: "1", count: NumberPadEntry.maxLength)
        XCTAssertFalse(NumberPadEntry.acceptsDigit(after: full, decimals: 4),
                       "The nine-character cap is gone; a fat-fingered run can overflow the "
                       + "field again.")
        XCTAssertTrue(NumberPadEntry.acceptsDigit(after: String(full.dropLast()), decimals: 4),
                      "The cap now bites one character early.")
    }

    // MARK: - What the rule refuses, and that the refusal earns its keep

    /// The refused keystrokes are the ones the commit would have moved.
    ///
    /// Asserted case by case with the resulting number spelled out, rather than as a blanket
    /// claim: the refusal is preventive, so it also blocks harmless keys (a third `0` in
    /// `0.500` snaps back to itself). Claiming every refusal prevents a change would be the
    /// flattering sentence and the false one.
    func testTheRefusalIsWhereTheCommitWouldHaveMoved() {
        let cases: [(buffer: String, next: String, decimals: Int, wouldBecome: Double)] = [
            ("0.37", "5", 2, 0.38),
            ("0.12", "5", 2, 0.13),
            ("1.234", "5", 3, 1.235),
            ("0.9999", "9", 4, 1.0)
        ]
        for c in cases {
            XCTAssertFalse(NumberPadEntry.acceptsDigit(after: c.buffer, decimals: c.decimals),
                           "\(c.buffer) already holds \(c.decimals) places; one more digit is a "
                           + "place the field cannot store.")
            let overlong = Double(c.buffer + c.next) ?? .nan
            XCTAssertEqual(snapCommit(overlong, decimals: c.decimals), c.wouldBecome,
                           accuracy: 1e-12,
                           "The measurement this case is built on moved: \(c.buffer)\(c.next) "
                           + "no longer commits \(c.wouldBecome) on a \(c.decimals)-place field. "
                           + "Re-derive the case before trusting the refusal above.")
        }
    }

    /// A NEGATIVE buffer behaves exactly like its positive twin.
    ///
    /// The sweep above never presses `−`, and negative is precisely where the half-away rounding
    /// and the nine-character cap could have interacted — the sign eats a slot the fraction rule
    /// does not see. Asserted rather than assumed, because "I checked it by hand" is not a test.
    func testASignedBufferIsCappedLikeItsPositiveTwin() {
        for decimals in 1...4 {
            for body in ["0.", "1.2", "12.34", "9.8765"] {
                let plain = NumberPadEntry.acceptsDigit(after: body, decimals: decimals)
                let signed = NumberPadEntry.acceptsDigit(after: "-" + body, decimals: decimals)
                XCTAssertEqual(plain, signed, """
                    At \(decimals) places the rule treats "\(body)" and "-\(body)" differently \
                    (plain: \(plain), signed: \(signed)). The minus sign is not part of the \
                    fraction and must not change how many places are left — a Transpose or a \
                    detune row would cap one digit early or late depending on its sign.
                    """)
            }
        }
    }

    /// A field asking for no fraction, or for a nonsensical one, refuses fraction digits rather
    /// than trapping. Unreachable through the UI (`allowsDecimal` disables the key) — pinned so
    /// a future caller of the pure rule cannot fall through it.
    func testAFieldWithNoFractionRefusesOne() {
        XCTAssertFalse(NumberPadEntry.acceptsDigit(after: "12.", decimals: 0),
                       "A zero-place field accepted a fraction digit it would round straight "
                       + "back off.")
        XCTAssertFalse(NumberPadEntry.acceptsDigit(after: "12.", decimals: -1),
                       "A negative `decimals` must read as \"no fraction\", not as a crash and "
                       + "not as unlimited entry.")
    }

    // MARK: - Helpers

    /// The pad's own two entry rules, replayed key by key: digits go through
    /// `NumberPadEntry.acceptsDigit`, the separator through `appendDecimal`'s guard
    /// (`decimals > 0`, at most one separator, a leading `0.` when the buffer is empty).
    private func typeKeys(_ keys: [String], decimals: Int) -> String {
        var buffer = ""
        for key in keys {
            if key == "." {
                guard decimals > 0, !buffer.contains(".") else { continue }
                buffer += buffer.isEmpty || buffer == "-" ? "0." : "."
            } else if NumberPadEntry.acceptsDigit(after: buffer, decimals: decimals) {
                buffer += key
            }
        }
        return buffer
    }

    /// `EchoelNumberPad.snapped`, re-derived — it is `private` to a `View`. See HONEST LIMITS.
    private func snapCommit(_ v: Double, decimals: Int) -> Double {
        let f = pow(10.0, Double(decimals))
        return (v * f).rounded() / f
    }

    /// The brace-matched body of `private func <name>(` in `path`, comments stripped.
    private func functionBody(named name: String, in path: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        guard let signature = code.range(of: "func \(name)(") else {
            XCTFail("`func \(name)(` is gone from \(path) — the keypad's digit entry was renamed "
                    + "or removed, so this guard can no longer see it. A guard that cannot find "
                    + "its subject must say so rather than pass.")
            return ""
        }
        guard let open = code.range(of: "{", range: signature.upperBound..<code.endIndex) else {
            XCTFail("`func \(name)(` in \(path) has no body")
            return ""
        }
        var depth = 0
        var index = open.lowerBound
        while index < code.endIndex {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.upperBound..<index]) }
            }
            index = code.index(after: index)
        }
        XCTFail("unbalanced braces after `func \(name)(` in \(path)")
        return ""
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — the wiring half of this "
                          + "file inspects source text, so it SKIPS rather than reporting a "
                          + "green it did not earn")
        }
        return root
    }
}
