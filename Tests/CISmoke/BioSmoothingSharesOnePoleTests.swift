// BioSmoothingSharesOnePoleTests.swift
// Echoel — #332. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE STRUCTURAL DEFECT, not the number: `applyBioReactive` carried TWO one-pole
// smoothers on the same clock, each with its own float literal. Both were written for a
// 60 Hz caller that has never existed — every wired bio publisher emits ~1 Hz — so both
// were the same ~60× unit error. #331 fixed one (0.92 → 0.6065, τ 12 s → 2 s) and left
// the other at 0.97, i.e. τ = 32.8 s, on the mapping the file's own comments call the main
// bio expression. #332 closed it.
//
// A private literal per accumulator is what made that split possible and invisible: two
// numbers, one clock, no relationship expressible in code. All of them now read the ONE
// local `smoothCoeff`, and this guard fails if that stops being true — a fourth smoother
// with its own constant, or one of the existing three reverted to a literal.
//
// ⛔ WHY IT IS SCOPED TO `applyBioReactive` AND NOT THE FILE. `EchoelDDSP` contains a
// SECOND, legitimate `smoothCoeff` — `0.995` in `updateSpectralEnvelope`'s per-sample
// amplitude smoother. That one is on the SAMPLE clock (48 kHz), where 0.995 is ≈ 4.2 ms
// and correct. Two different clocks genuinely need two different constants; the defect is
// two constants on ONE clock. A file-wide guard would either forbid the correct one or
// have to special-case it by value, which is a guard about numbers again. So the scope is
// the function, and the invariant is sharing — never a specific value.
//
// ⭐ IT DELIBERATELY DOES NOT PIN 0.6065. The constant's own block offers 0.75 (τ = 3.5 s)
// as a one-token revert if a device listen finds the body too twitchy — that is a tuning
// decision that belongs to the founder's ear, and a test asserting the number would turn
// it into a gate failure. What this pins is that such a revert moves ALL the accumulators
// together, which is the only way "one bio response time" can mean anything.
//
// ⚠️ WHAT IT CANNOT DO, stated because a green here is narrower than it looks: it does not
// run the DSP, and it does not know whether ~1 Hz is still the real rate — if a publisher
// is rewired faster, every constant here is wrong again and nothing in this file notices.
// It recognises exactly the textual shape `x = x * …` / `x = (x * …`, so a per-call
// smoother written differently (an `exp()`-derived coefficient, a helper call, an
// accumulator updated across two statements, or the operand-swapped `x = coeff * x`) is
// invisible to it. A third member of the 60 Hz class written that way would pass silently
// — named here and in `applyBioReactive`'s own tombstone rather than papered over.
//
// ⛔ ONE HOLE WAS REAL AND IS NOW CLOSED, and it is worth recording because the obvious
// version of this guard had it: checking only `line.contains("smoothCoeff")` accepts
// `x = x * 0.9 + smoothCoeff * y` — the shape matches, the word is present, and a private
// literal rides along beside a legitimate mention. That is a false GREEN on precisely the
// defect, which is the worst outcome a guard can have. The second condition (`* <digit>`
// is forbidden on a pole line) closes it: the three real poles multiply by `smoothCoeff`
// or by `(1.0 - smoothCoeff)`, and `* (` is not `* <digit>`.

import Foundation
import XCTest

final class BioSmoothingSharesOnePoleTests: XCTestCase {

    private static let ddsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"

    func testEveryBioSmootherReadsTheOneSharedCoefficient() throws {
        let body = try Self.codeOnly(applyBioReactiveBody())

        let poles = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { Self.isSelfUpdatingOnePole($0) }

        // Fail LOUD if the detector went blind. A rename or a reformat that stops the
        // shape from matching would otherwise leave this file green while checking
        // nothing — the false-GREEN that `DisabledReverbIsNotClaimedLiveTests` was
        // hardened against one slice earlier. Three are known to exist today
        // (brightness, filter cutoff, amplitude); more is fine, fewer is a red.
        XCTAssertGreaterThanOrEqual(poles.count, 3, """
            Expected at least 3 one-pole accumulators in `applyBioReactive`, found \
            \(poles.count). This guard recognises the literal shape `x = x * …`; if the \
            smoothers were rewritten (a helper, a computed coefficient, a two-statement \
            update), point the detector at the new spelling in the SAME commit rather \
            than deleting the file — the invariant it protects (#331/#332: one clock, one \
            coefficient) survives any spelling.
            """)

        for pole in poles {
            // TWO conditions, because `contains` alone had a false-GREEN hole that review
            // found: `x = x * 0.9 + smoothCoeff * y` matches the shape AND contains the
            // word, so a private literal could ride along beside a legitimate mention.
            // `* <digit>` is the tell — the three real poles multiply by `smoothCoeff` or
            // by `(1.0 - smoothCoeff)`, never by a bare number.
            XCTAssertTrue(pole.contains("smoothCoeff"), Self.privateCoefficientMessage(pole))
            XCTAssertNil(pole.range(of: #"\*\s*[0-9]"#, options: .regularExpression),
                         Self.privateCoefficientMessage(pole))
        }

        // One declaration, so a second local cannot re-open the split under the same name.
        let declarations = Self.occurrences(of: "let smoothCoeff", in: body)
        XCTAssertEqual(declarations, 1, """
            `applyBioReactive` declares `smoothCoeff` \(declarations) time(s); expected \
            exactly 1. Zero means the shared constant was inlined or renamed — re-point \
            this guard in the same commit. More than one means the accumulators can drift \
            apart again while every line still reads a variable called `smoothCoeff`, \
            which is the #332 defect wearing the fix's name.
            """)
    }

    // MARK: - helpers

    /// One message for both halves of the per-pole check, because they fail for the same
    /// reason and a reader hitting either needs the same instruction.
    private static func privateCoefficientMessage(_ pole: String) -> String {
        """
        A bio smoother in `applyBioReactive` carries its own coefficient instead of the \
        shared `smoothCoeff`:
        \(pole.trimmingCharacters(in: .whitespaces))
        That is exactly how #331 and #332 became two slices instead of one: two one-poles \
        on the SAME ~1 Hz bio clock, each with a private literal, so fixing one left the \
        other 32.8 s slow inside the same function with nothing to flag it. Use the \
        `smoothCoeff` declared at the top of the function — multiply by `smoothCoeff` and \
        by `(1.0 - smoothCoeff)`, never by a bare number. If this smoother genuinely runs \
        on a DIFFERENT clock (the per-sample one in `updateSpectralEnvelope` does), it \
        does not belong in this function's body.
        """
    }

    /// TRUE for `x = x * …` and `x = (x * …` — an accumulator multiplied by its own
    /// previous value, which is what a one-pole is. The backreference is the whole point:
    /// it matches only when the identifier on the left recurs immediately on the right, so
    /// an ordinary `a = b * c` is not swept in.
    private static func isSelfUpdatingOnePole(_ line: String) -> Bool {
        line.range(of: #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(?\s*\1\s*\*"#,
                   options: .regularExpression) != nil
    }

    /// Plain substring count — so `let smoothCoeff` also matches `let smoothCoeffFast`.
    /// That prefix behaviour is deliberate and worth stating rather than discovering: a
    /// second coefficient named around the first is precisely the drift this file exists
    /// to stop, and it should redden even though the exact name differs.
    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var from = text.startIndex
        while let hit = text.range(of: needle, range: from..<text.endIndex) {
            count += 1
            from = hit.upperBound
        }
        return count
    }

    /// The body of `applyBioReactive`, from its declaration to whichever comes first: the
    /// next member declaration at type indentation, or the next `// MARK:`. Deliberately
    /// not a brace-counting parser — this function is ~470 lines of heavily commented code,
    /// and an over-clever bound that silently returns an EMPTY slice is the false-GREEN
    /// this bundle keeps paying for. The `XCTAssertGreaterThanOrEqual(poles.count, 3)`
    /// above is what catches a bad bound: an empty or truncated body finds zero poles and
    /// reddens.
    ///
    /// ⚠️ IT TAKES THE FIRST OF TWO MATCHES, and that is load-bearing rather than lucky.
    /// `EchoelDDSP.swift` declares `applyBioReactive` TWICE: the voice's own (the three
    /// smoothers) and, much further down, a poly wrapper that only forwards to
    /// `voices[idx].applyBioReactive`. First-match picks the right one today. If the two
    /// types are ever reordered this retargets the wrapper, finds zero poles, and reddens
    /// on the count — safe, but with a message that blames the wrong thing. Re-anchor it
    /// then rather than deleting the file.
    ///
    /// ⛔ AND IT DOES NOT `XCTSkip` ON A MISSING FUNCTION, which the first version did with
    /// a message that literally said "rather than leaving it skipping quietly" — while
    /// `XCTSkip` IS the quiet skip. A rename of `applyBioReactive` is the single most
    /// likely way this guard gets de-pointed, and it would have disarmed itself with the
    /// gate still green. That is the exact false-GREEN class this file was written against.
    /// The tree-not-reachable skip further down stays a skip: that one is about the
    /// harness, not the invariant.
    private func applyBioReactiveBody() throws -> String {
        let file = try source(Self.ddsp)
        guard let start = file.range(of: "public func applyBioReactive") else {
            XCTFail("""
                `applyBioReactive` not found in \(Self.ddsp) — renamed, moved, or its \
                access level changed. Re-point this guard in the SAME commit; the \
                invariant it protects (#331/#332: one bio clock, one shared smoothing \
                coefficient) does not depend on the spelling.
                """)
            return ""
        }
        let tail = file[start.upperBound...]
        // Every member-declaration spelling at type indentation, not just `public func`.
        // A `private func` added between this function and the next `// MARK:` would
        // otherwise spill into the slice and a self-updating line inside it would fail the
        // per-pole check — a false RED with a confusing message.
        let ends = ["\n    public func ", "\n    private func ", "\n    internal func ",
                    "\n    func ", "\n    // MARK:"]
            .compactMap { tail.range(of: $0)?.lowerBound }
        let end = ends.min() ?? tail.endIndex
        return String(tail[..<end])
    }

    /// Comments dropped — whole-line, trailing and `/* … */` — before anything is counted.
    /// Not cosmetic: `applyBioReactive`'s tombstones quote the old code verbatim (`It read
    /// \`filterCutoff * 0.97 + targetCutoff * 0.03\``), and the house style is to keep
    /// exactly those quotes. Counting `let smoothCoeff` in a future tombstone would be a
    /// false-RED on the blocking gate; matching a quoted old assignment would be a
    /// false-RED blaming a line that no longer runs.
    ///
    /// Not a Swift parser: `//` inside a string literal is stripped too. In this file that
    /// direction can only DROP candidate lines, which the count assertion above turns into
    /// a red — it cannot manufacture a green.
    private static func codeOnly(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "/*") {
            out += rest[..<open.lowerBound]
            if let close = rest.range(of: "*/", range: open.upperBound..<rest.endIndex) {
                rest = rest[close.upperBound...]
            } else {
                rest = rest[rest.endIndex...]      // unterminated: drop the tail
            }
        }
        out += rest
        return out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let slashes = line.range(of: "//") else { return String(line) }
                return String(line[..<slashes.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
