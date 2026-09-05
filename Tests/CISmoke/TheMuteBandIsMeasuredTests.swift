import XCTest
@testable import Echoelmusic

/// #1016 — the brightness band where the app can neither lock nor explain itself is now COUNTED,
/// so the next device log can answer the question that decides a parked founder call.
///
/// WHY IT EXISTS. `canLockNow` refuses at `brightness >= 0.6`; the coaching classifier's flood
/// test, `isWashedOut`, only fires above `0.72`. Between those the machine has ruled out a lock
/// while `PulseCue.tooBright` ("Press a little lighter") is unreachable, so the cue falls to
/// `.finding` and, after 45 s, latches `.stalled` — whose strings send the performer to try
/// another finger or WARM THEIR HAND. For a first-run user that is the difference between the
/// instrument working and the instrument appearing broken, and the remedy on screen is not
/// merely absent but pointing the wrong way.
///
/// ⚠️ THIS SLICE CHANGES NO BEHAVIOUR AND IS NOT THE FIX. The wording change is founder-gated
/// (#304/#410) and could swap one wrong sentence for another — this same file attributes the
/// 0.6–0.8 range to finger lightening and re-grip, not to flooding. The audit that raised it
/// asked for a MEASUREMENT first, and claim 4 pins that the counter stays exactly that.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. Whether brightness actually rests in the band on the founder's
/// device, and for how long, is what the log will say — not this guard. NEEDS-FOUNDER-VERIFY at
/// the foot of the file.
///
/// GRADING (written after transcription, which corrected my guess for the third time this
/// session). Claims **1 and 3** are RED on `HEAD` — they name constructs this commit introduces.
/// Claims **2, 4 and 5** are GREEN on BOTH, for three different reasons worth separating:
///   · **2** is green because the pairing it pins was already correct — `HEAD` reads 14/14, the
///     worktree 16/16. It is a GENERAL guard that happens to arrive with this slice, not a claim
///     about it, and green-on-both is what a general guard should look like.
///   · **5** is green because it measures two thresholds this commit does not touch. That is
///     what makes it a usable counterweight.
///   · **4** is green on `HEAD` VACUOUSLY — `muteBand` does not exist there, so it finds nothing
///     and passes for the wrong reason. Said out loud because a claim that cannot fail is the
///     failure mode this repo names (#808); here it becomes real the moment the counters exist,
///     which is now.
/// The pattern, three slices in a row: a claim's colour follows its NEEDLE, never the commit's
/// subject — and "counterweight" describes its JOB, not its colour.
final class TheMuteBandIsMeasuredTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — the measurement reaches the log at all. A counter nobody prints measures nothing.
    func testTheBreadcrumbCarriesTheMuteBand() throws {
        let text = try source(Self.publisher)
        XCTAssertTrue(text.contains("mute=%d/%d"), """
            The rPPG breadcrumb no longer prints the mute band. The whole point of #1016 is that \
            a device log can answer "did brightness rest between the lock ceiling and the \
            washout test, and for how long" without a human counting `bright=` lines that are \
            printed once every two seconds.
            """)
    }

    // 2 — CRASH CLASS, and nothing pinned it before. `String(format:)` with more specifiers than
    //     arguments reads past the varargs list. This line has grown five times.
    func testTheBreadcrumbFormatMatchesItsArgumentCount() throws {
        let text = try source(Self.publisher)
        guard let start = text.range(of: "\"rPPG: finger=") else {
            return XCTFail("ANCHOR MISSING: the rPPG breadcrumb format string.")
        }
        let tail = text[start.upperBound...]
        guard let endQuote = tail.range(of: "\","),
              let endCall = tail.range(of: "))") else {
            return XCTFail("ANCHOR MISSING: the breadcrumb's closing quote or call.")
        }
        let format = String(tail[..<endQuote.lowerBound])
        let argText = String(tail[endQuote.upperBound..<endCall.lowerBound])

        var specifiers = 0
        var index = format.startIndex
        while let percent = format[index...].firstIndex(of: "%") {
            var cursor = format.index(after: percent)
            while cursor < format.endIndex, "-#0123456789.".contains(format[cursor]) {
                cursor = format.index(after: cursor)
            }
            if cursor < format.endIndex, "@dfs".contains(format[cursor]) { specifiers += 1 }
            guard cursor < format.endIndex else { break }
            index = format.index(after: cursor)
        }

        // Split on top-level commas only: the first argument is a ternary whose branches are
        // string literals, and a naive split counts `: "no"` as an argument of its own. That
        // exact miscount happened while writing this guard, which is why it is spelled out.
        var arguments = 0
        var depth = 0
        var inString = false
        var pending = false
        for character in argText {
            if character == "\"" { inString.toggle() }
            guard !inString else { pending = true; continue }
            if character == "(" || character == "[" { depth += 1 }
            if character == ")" || character == "]" { depth -= 1 }
            if character == "," && depth == 0 {
                if pending { arguments += 1 }
                pending = false
            } else if !character.isWhitespace {
                pending = true
            }
        }
        if pending { arguments += 1 }

        XCTAssertEqual(specifiers, arguments, """
            The rPPG breadcrumb has \(specifiers) format specifiers and \(arguments) arguments.

            `String(format:)` reads past its varargs list when the format asks for more than it \
            is given — a crash in the one code path that exists to diagnose crashes. This line \
            has grown five times and nothing pinned the pairing until now.
            """)
    }

    // 3 — the band uses the ACTIVE ceiling. Using the 0.6 constant instead would under-report
    //     the first ~6 s, where the strict 0.28 ceiling makes the band far wider — and those
    //     seconds are exactly the first-run experience the audit is about.
    func testTheBandIsMeasuredAgainstTheActiveCeiling() throws {
        let text = try source(Self.publisher)
        XCTAssertTrue(text.contains("let inMuteBand = fingerDetected && bright >= ceiling && !saturating"), """
            The mute-band test no longer reads the `ceiling` local that the lock decision itself \
            is judged against. Substituting `maxLockBrightness` would silently exclude the \
            strict-window seconds — the widest part of the band and the part a first-run user \
            actually meets.
            """)
    }

    // 4 — COUNTERWEIGHT, and the most important one: this is a MEASUREMENT. The counters must
    //     appear only where they are written and printed, never in a branch that changes what
    //     the app does. A diagnostic that starts deciding things is no longer a diagnostic.
    func testTheCountersDecideNothing() throws {
        let text = try source(Self.publisher)
        var offenders: [String] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("muteBand"), !line.hasPrefix("//"), !line.hasPrefix("///") else { continue }
            let allowed = line.hasPrefix("@ObservationIgnored")
                || line.hasPrefix("muteBandTicks =")
                || line.hasPrefix("muteBandPeakTicks =")
                || line.hasPrefix("if muteBandTicks > muteBandPeakTicks")
                || line.hasPrefix("self.muteBandTicks,")
            if !allowed { offenders.append("line \(index + 1): \(line)") }
        }
        XCTAssertTrue(offenders.isEmpty, """
            The mute-band counters are now read somewhere that is not their own update or the \
            breadcrumb:
            \(offenders.joined(separator: "\n"))

            That is ALLOWED as a deliberate change (#364) — but it turns a diagnostic into a \
            decision, and the doc block on `muteBandTicks` plus this file's header both say it \
            decides nothing. Move that prose in the same commit.
            """)
    }

    // 5 — COUNTERWEIGHT. The two thresholds that DEFINE the band are unchanged, so the closed
    //     interval the docs state stays true. If either moves, the prose describing the band
    //     (and the audit finding built on it) must move with it.
    func testTheTwoThresholdsThatDefineTheBandAreUnchanged() throws {
        let text = try source(Self.publisher)
        XCTAssertTrue(text.contains("nonisolated private static let maxLockBrightness: Float = 0.6"), """
            The lock ceiling moved. It is the LOWER edge of the mute band; the doc block on \
            `muteBandTicks` states the band as closed at 0.6, and this guard's own header \
            reasons from it.
            """)
        XCTAssertTrue(text.contains("brightness > 0.72 || red > 0.92"), """
            The washout test moved. It is the UPPER edge of the mute band — and the audit \
            finding this measurement exists to settle is defined by the gap between the two.
            """)
    }

    // NEEDS-FOUNDER-VERIFY: run a normal take with a finger on the lens and share the diagnostics
    // log. Read the `mute=now/peak` field: `0/0` for the whole take means the band never fires on
    // this device and the parked wording change has nothing to fix. A large peak sitting beside
    // `cue=Finding` is the defect, and THEN the wording question is worth your time.
}
