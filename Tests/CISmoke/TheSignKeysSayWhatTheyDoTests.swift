// TheSignKeysSayWhatTheyDoTests.swift
// Echoel — #488. Blocking bundle.
//
// ⭐ THE DEFECT, AND WHY IT SURVIVED. `EchoelNumberPad` is the ONE numeric keypad in the app:
// every `EchoelValueField` opens it, so it is the single most-used control surface there is.
// Its − and + keys had NO `accessibilityLabel`, and SwiftUI names an `Image(systemName:)`
// button after its SF Symbol. VoiceOver therefore announced "minus" and "plus" — on a keypad,
// the words for SUBTRACT and ADD — on two keys that set a SIGN and never touch the magnitude.
//
// It is not a hypothetical confusion. `EchoelValueField` installs an
// `accessibilityAdjustableAction`, so swipe-up/down on the very row that opened this pad
// genuinely DOES increment and decrement. The app has both affordances; these two keys were
// wearing the other one's words.
//
// ⭐ THE LAYER IS THE POINT, and it is the #480 lesson paid a second time one day later. An
// accessibility label is invisible while VoiceOver is off — no screenshot, no design pass and
// no UI review would ever have shown it. That is how a missing name survived on the app's most
// central control while the visible layer beside it (the `decimalKey` two lines below, which
// has both a label AND a catalog entry) was carefully argued over.
//
// ⭐ THE SECOND HALF IS A BEHAVIOUR CHANGE AND IS THE HONEST ONE. `+` is now gated on
// `allowsNegative` exactly as `−` always was. `setSign(negative: false)` only strips a leading
// minus, and on a non-negative range no minus can exist — `−` is disabled, `append` adds digits
// only, `appendDecimal` never writes one. So `+` was a key a finger could press that provably
// could not change anything: the lying-control class (#135/#160/#164).
//
// ⚠️ MEASURED BEFORE CHANGING IT, with the method stated because the method is a claim too
// (#443). Paren-matched over `Sources/`, comment lines excluded, and the three forwarding
// helpers resolved — `EchoelFXView.field`, `EchoelStudioView.param` and `knob` take the range
// as their THIRD POSITIONAL argument, so a `range:` scan reports ZERO negative rows and is
// simply wrong. Resolved properly: **118 rows carry a resolvable range and exactly 3 can go
// negative** — Flanger Feedback (−0.95…0.95), Compressor Threshold (−48…0 dB), Limiter Ceiling
// (−12…0 dB), all in `EchoelFXView`. On those three nothing changes. On the other 115 the PAIR
// now dims together, which reads as "this field has no sign" instead of one dim key beside a
// live one that does nothing.
//
// ⚠️ THE TRADE, stated because it is visible on almost every field: two dimmed cells instead of
// one. Accepted on the house rule that a control may not offer an action it cannot perform.
//
// ⚠️ HONEST GRADING, counted rather than remembered (#433 — getting this wrong in EITHER
// direction is the defect, and the flattering direction is the tempting one).
// · `NumberPadEntry.signed` is created by THIS commit, so the four behaviour methods could
//   never have been red: they are FORWARD guards against a later "simplify", not regressions.
//   Saying otherwise would be the #470 mistake.
// · The two label scans ARE regressions: on the parent tree `signKey` carries no
//   `accessibilityLabel` at all.
// · The `+`-gating scan is a regression: the parent reads `negative ? allowsNegative : true`.
// · The 3-signed-rows scan and the "no arithmetic verbs" scan are COUNTERWEIGHTS, green on
//   both trees. They exist because the two obvious later edits are (a) "the pad has a sign
//   pair that is dead everywhere, delete it" — which would be true only until someone adds a
//   signed row back, and false today — and (b) "just call them minus and plus", which is the
//   exact defect this slice removes.
//
// ⚠️ AND THE CATALOG HALF IS ASSERTED, not assumed. Both labels are bare literals, so they bind
// to the non-generic `LocalizedStringKey` overload — the same binding the `decimalKey` comment
// spells out. #267's rule is that an i18n commit which adds an UNTRANSLATED string is a
// regression wearing the right label, so the guard requires both keys to exist in
// `Localizable.xcstrings` with a German translation, not merely to be non-empty in English.
//
// ⚠️ WHAT THIS FILE CANNOT DO, first: nothing here renders. `EchoelNumberPad` is behind
// `#if canImport(SwiftUI)` and `signKey` is `private`, so every UI claim is a SOURCE-TEXT SCAN.
// That VoiceOver actually speaks these words, that a dimmed key reads as "no sign" rather than
// "broken", and that the pad is reachable at all are device checks and all remain open.
//
// ⚠️ `SourceText.codeOnly` (#453) is LOAD-BEARING here, measured rather than claimed: the ⛔/⭐
// blocks this slice writes onto `signKey` quote `"minus"`, `"plus"` and
// `negative ? allowsNegative : true` verbatim in prose. Under a scanner that kept comments the
// arithmetic-verb scan would be red on CORRECT code and the `+`-gating scan green on the old
// spelling. This is the same collision #486 hit: a repo that writes down what it removed will
// always trip a negative scan on its own obituary.

import XCTest
@testable import Echoelmusic

final class TheSignKeysSayWhatTheyDoTests: XCTestCase {

    // MARK: - behaviour (forward guards on the hoisted rule, never red on the parent)

    /// `−` on an empty buffer seeds it, so the next digit lands negative.
    func testMinusOnAnEmptyBufferSeedsTheSign() {
        XCTAssertEqual(NumberPadEntry.signed("", negative: true), "-")
        XCTAssertEqual(NumberPadEntry.signed("", negative: false), "")
    }

    /// The magnitude is never touched — the whole reason the labels say "make negative"
    /// rather than "minus".
    func testTheSignKeysNeverChangeTheDigits() {
        for buffer in ["7", "0.5", "18000", "-42", "-0.375"] {
            let digits = buffer.hasPrefix("-") ? String(buffer.dropFirst()) : buffer
            XCTAssertEqual(NumberPadEntry.signed(buffer, negative: true), "-" + digits,
                           "− must set the sign of \(buffer), not alter it")
            XCTAssertEqual(NumberPadEntry.signed(buffer, negative: false), digits,
                           "+ must set the sign of \(buffer), not alter it")
        }
    }

    /// Idempotent on both sides. The obvious "simplification" is a TOGGLE
    /// (`hasPrefix("-") ? drop : prepend`), which would make the second press of − undo the
    /// first — two keys behaving as one, on a pad whose whole point is that they are two.
    func testPressingTheSameSignTwiceIsTheSameAsOnce() {
        for buffer in ["", "5", "-5", "-0.5"] {
            for negative in [true, false] {
                let once = NumberPadEntry.signed(buffer, negative: negative)
                XCTAssertEqual(NumberPadEntry.signed(once, negative: negative), once,
                               "sign(\(buffer), negative: \(negative)) must be idempotent")
            }
        }
    }

    /// `+` on a minus-only buffer returns to empty rather than leaving a stranded `"-"`.
    func testPlusOnAMinusOnlyBufferClearsIt() {
        XCTAssertEqual(NumberPadEntry.signed("-", negative: false), "")
        XCTAssertEqual(NumberPadEntry.signed("-", negative: true), "-")
    }

    // MARK: - the labels (regressions)

    /// Both branches carry a spoken label.
    func testBothSignKeysCarryASpokenLabel() throws {
        let body = try signKeyBody()
        XCTAssertTrue(body.contains("accessibilityLabel"), """
            `signKey` has no `accessibilityLabel`, so VoiceOver names the button after its SF
            Symbol — "minus" / "plus", the words for arithmetic these keys do not do (#488).

            signKey body scanned (comments blanked by SourceText.codeOnly):
            \(body)
            """)
        for word in ["Make negative", "Make positive"] {
            XCTAssertTrue(body.contains(word), "`signKey` must speak \"\(word)\" (#488)")
        }
    }

    /// COUNTERWEIGHT. The tempting later edit is "name them after the glyph". These keys set a
    /// sign; the row that opened the pad is what increments and decrements
    /// (`EchoelValueField`'s `accessibilityAdjustableAction`). Naming them for arithmetic puts
    /// the two affordances under one set of words again.
    func testTheLabelsDoNotClaimArithmetic() throws {
        let body = try signKeyBody()
        // Only the label arguments, not the SF Symbol names — `Image(systemName: "minus")` is
        // correct and stays. Anchored on the label call so the symbol line cannot trip it.
        guard let labelRange = body.range(of: ".accessibilityLabel(") else {
            throw AnchorMissing(reason: """
                `.accessibilityLabel(` not found in `signKey` — the previous assertion should \
                have caught that. If the label moved to a modifier this scan cannot see, move \
                this check with it rather than deleting it (#488).
                """)
        }
        let labels = String(body[labelRange.lowerBound...])
        for verb in ["Subtract", "subtract", "Add ", "Decrease", "decrease",
                     "Increase", "increase", "Minus", "Plus"] {
            XCTAssertFalse(labels.contains(verb), """
                The sign keys are spoken as "\(verb)". They set the SIGN and never change the
                magnitude — the increment/decrement affordance is the adjustable action on the
                row itself. Name the effect (#488).
                """)
        }
    }

    // MARK: - the honesty gate (regression)

    /// `+` must be gated exactly as `−` is: on a non-negative range neither key can do
    /// anything, so neither may look live.
    func testPlusIsGatedLikeMinus() throws {
        let body = try signKeyBody()
        XCTAssertTrue(body.contains("let enabled = allowsNegative"), """
            The `+` key is enabled on rows whose range cannot go below zero. There it strips a
            leading minus that can never exist (`−` is disabled, `append` adds digits only,
            `appendDecimal` writes none) — a control that provably cannot change anything
            (#135/#160/#164). Gate the PAIR on `allowsNegative` (#488).

            signKey body scanned:
            \(body)
            """)
        XCTAssertFalse(body.contains("negative ? allowsNegative : true"),
                       "the old asymmetric gate is back — see #488")
    }

    // MARK: - the data premise (counterweight)

    /// COUNTERWEIGHT, and the one that keeps this slice honest over time. The sign pair is
    /// justified by rows that CAN go negative. Today there are exactly three, all in
    /// `EchoelFXView`. If the last one ever goes, this turns red rather than leaving a pair of
    /// keys that are dead on every field in the app — at which point the right move is a
    /// decision about the pair, not a quiet green.
    func testAtLeastOneShippedRowCanStillGoNegative() throws {
        let source = try fxSource()
        let signed = ["-0.95...0.95", "-48...0", "-12...0"]
        let present = signed.filter { source.contains($0) }
        XCTAssertFalse(present.isEmpty, """
            No row in `EchoelFXView` carries a negative lower bound any more, so `allowsNegative`
            is false everywhere and the − / + pair is dead on every field in the app. That is a
            decision (keep the keys for a future signed row, or remove them), not a silent
            state (#488). Expected any of: \(signed).
            """)
    }

    // MARK: - the catalog (regression on the de half)

    /// #267: adding an untranslated user-facing string is a regression wearing the right label.
    func testBothLabelsAreInTheCatalogWithGerman() throws {
        let json = try catalogJSON()
        guard let strings = json["strings"] as? [String: Any] else {
            return XCTFail("`Localizable.xcstrings` has no `strings` object")
        }
        for key in ["Make negative", "Make positive"] {
            let german = ((((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?
                ["de"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            XCTAssertFalse(german?.isEmpty ?? true, """
                "\(key)" has no German translation in `Localizable.xcstrings`. A bare literal
                binds to the `LocalizedStringKey` overload, so an uncatalogued one ships as
                English to a German VoiceOver user — the #267 rule that an i18n commit adding
                an untranslated string is a regression wearing the right label (#488).
                """)
        }
    }

    // MARK: - source access

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relative: String) throws -> String {
        let path = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(repoRoot().path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func fxSource() throws -> String {
        try read("Sources/Echoelmusic/Studio/EchoelFXView.swift")
    }

    /// The body of `signKey(negative:)` INCLUDING the modifiers chained after its closing
    /// brace, up to the next `private` declaration — the label lives on the modifier chain,
    /// not inside the `keyButton` closure.
    ///
    /// Anchored on the declaration and terminated on the NEXT declaration rather than on a
    /// brace count, because the label is outside the braces. Fails rather than skips when the
    /// anchor moves: a skip PASSES CI, which would disarm every scan in this file (#484).
    private func signKeyBody() throws -> String {
        let source = try read("Sources/Echoelmusic/Studio/EchoelNumberPad.swift")
        guard let start = source.range(of: "private func signKey(negative: Bool) -> some View {")
        else {
            throw AnchorMissing(reason: """
                `private func signKey(negative: Bool) -> some View {` not found — renamed or \
                reflowed. Move this anchor in the same commit; do not delete the checks (#488).
                """)
        }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    private ") else {
            throw AnchorMissing(reason: """
                No following `private` declaration after `signKey` — it is now the last member \
                of the type and this scan would widen to the rest of the file. Re-anchor (#488).
                """)
        }
        return String(rest[..<end.lowerBound])
    }

    private func catalogJSON() throws -> [String: Any] {
        let path = repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/Resources/Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("string catalog not present under \(repoRoot().path)")
        }
        let data = try Data(contentsOf: path)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnchorMissing(reason: "`Localizable.xcstrings` is not a JSON object")
        }
        return obj
    }
}
