// TheDeployNoteNamesRealDoorsTests.swift
// Echoel — #820: the build note sent the founder to a chip that does not exist.
//
// WHY THIS EXISTS. `.deploy/release` is the ONE document the founder follows with the phone in
// hand. v10.79.419's note said "Visual-Panel → Full screen". There is no chip called "Visual";
// the strip reads **Sound · FX · Mix · Master · Mood · Tempo · Field · Save/Export**, and the
// visual surface is behind **Field**. Two of its three new paths were fine and the third was
// unfollowable — the exact cost #816 measured on the device checklist, on the document that
// matters most, written by the same session that had just fixed the checklist.
//
// ⭐ IT ALSO EXPOSED A GAP, not just an error: the note said "then send the diagnostics log" and
// never said WHERE it is (Save/Export → "Diagnostics" → Share). That is the single most
// important pending action in the project, and four builds shipped without the path.
//
// ⛔ THREE DRAFTS OF THIS GUARD FAILED BEFORE IT WORKED, all found by DRIVING, none by reading:
// 1. A scan for `Visual-Panel` matched the corrected note's own retraction of that name (#491).
//    The note is phrased to avoid the hyphenated form rather than teaching this guard an
//    exemption — an exemption is a hole someone else walks through later.
// 2. The corrected note writes paths as `**Master**-Chip`, so the emphasis markers sit between
//    the word and the hyphen and a naive scan found ZERO tokens: a guard passing vacuously,
//    forever, on a document it never read (#808). Emphasis is stripped first, and claim 2
//    asserts it found something.
// 3. A scripted edit anchored on `var tokens: Set<String> = []` — a line the replacement's own
//    new helper also contained — and ate two claims. Same self-collision family as 1: **an
//    anchor that the new text also matches is not an anchor.**
//
// #364 — NOTHING HERE FORBIDS A RENAME. If a chip is relabelled, claim 1 goes red on purpose and
// names the note as the prose to pull along in the same commit.
//
// KIND (§1): **REGRESSION, source-text scans.** Claim 2 driven against the v419 note: it finds
// `Visual` and fails; against the corrected note it finds four tokens and passes.

import XCTest

final class TheDeployNoteNamesRealDoorsTests: XCTestCase {

    /// The chip strip as shipped. Pinned here so a rename cannot silently make claim 2 weaker.
    private static let expectedLabels = [
        "Bio", "Tempo", "Sound", "Mix", "FX", "Master", "Mood", "Save/Export", "Field", "Video"
    ]

    private func root() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read. This guard fails rather "
                    + "than skips (§4) — a missing anchor is a finding, not a pass.")
            return ""
        }
        return contents
    }

    /// The `StudioMenu.label` switch, read line by line from its declaration to the next member.
    /// Deliberately a plain state machine: this repo has no local Swift toolchain, so clever
    /// Substring index arithmetic is a thing nobody can check before CI.
    private func shippedLabels() throws -> [String] {
        let view = try text("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        var labels: [String] = []
        var inside = false
        var sawDeclaration = false
        for line in view.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inside {
                if trimmed.hasPrefix("var label: String") { inside = true; sawDeclaration = true }
                continue
            }
            if trimmed.hasPrefix("var ") { break }
            guard trimmed.hasPrefix("case ."),
                  let openQuote = trimmed.range(of: "return \"") else { continue }
            let tail = trimmed[openQuote.upperBound...]
            guard let closeQuote = tail.firstIndex(of: "\"") else { continue }
            labels.append(String(tail[..<closeQuote]))
        }
        if !sawDeclaration {
            XCTFail("ANCHOR MISSING: `var label: String` is gone from EchoelStudioView — the "
                    + "chip labels moved. Re-anchor this guard; do not let it skip (#454).")
        }
        return labels
    }

    /// Capitalised words the note uses as a path, e.g. `Master-Chip` or `Field-Panel`.
    private func pathTokens(in note: String) -> Set<String> {
        var found: Set<String> = []
        for marker in ["-Chip", "-Panel"] {
            for piece in note.components(separatedBy: marker).dropLast() {
                var word = ""
                for character in piece.reversed() {
                    guard character.isLetter || character == "/" else { break }
                    word.insert(character, at: word.startIndex)
                }
                if let first = word.first, first.isUppercase { found.insert(word) }
            }
        }
        return found
    }

    // 1 — the chip strip is the one this guard thinks it is.
    func testTheChipLabelsAreTheOnesThisGuardChecksAgainst() throws {
        XCTAssertEqual(try shippedLabels(), Self.expectedLabels, """
            The chip labels changed. That is allowed (#364) — but `.deploy/release` sends the \
            founder along these names with the phone in hand, so the note has to be corrected \
            in the SAME commit, and this list with it.
            """)
    }

    // 2 — every door the build note names is a door that exists.
    func testEveryPathInTheBuildNoteNamesARealChip() throws {
        let labels = try shippedLabels()
        let note = try text(".deploy/release").replacingOccurrences(of: "*", with: "")
        let tokens = pathTokens(in: note)
        XCTAssertFalse(tokens.isEmpty, """
            The build note names no `X-Chip`/`X-Panel` path at all. Either the note stopped \
            giving the founder a route, or this scan can no longer match its formatting — the \
            second is how a guard passes forever on a document it never read (#808).
            """)
        for token in tokens.sorted() {
            XCTAssertTrue(labels.contains(token), """
                The build note sends the founder to "\(token)", which is not a chip. The strip \
                reads \(labels.joined(separator: " · ")). This is the document read with the \
                phone in hand — a path that cannot be followed costs a device session (#816).
                """)
        }
    }

    // 3 — the note says where the diagnostics log is, because that ask gates everything else.
    func testTheBuildNoteSaysWhereTheDiagnosticsLogIs() throws {
        let note = try text(".deploy/release")
        guard note.contains("Diagnose-Log") || note.contains("diagnostics log") else { return }
        XCTAssertTrue(note.contains("Diagnostics"), """
            The note asks for the diagnostics log without naming the door that produces it. \
            The path is Save/Export → "Diagnostics" → Share; four builds shipped without it \
            while the log was the one thing being waited on.
            """)
    }

    /// 4 — the note tells the next session HOW to list what this build made testable (#1150).
    ///
    /// `founder-verify.py --since <sha>` has existed since #931 and lived ONLY inside the
    /// script. CLAUDE.md names the tool, not the flag, and the place a session actually writes
    /// a build note pointed at neither. With a three-digit backlog that is the difference
    /// between a pointed device session and the same unsorted wall every time.
    ///
    /// ⛔ POSITIVE SCAN, for the #1148 reason: asserting an instruction is PRESENT has no
    /// self-referential failure mode, while asserting one is absent does.
    func testTheBuildNoteSaysHowToListWhatThisBuildMadeTestable() throws {
        let note = try text(".deploy/release")
        XCTAssertTrue(note.contains("founder-verify.py --since"), """
            The build note no longer prints the command that lists the asks this build made \
            newly testable. Without it the founder gets the whole backlog every round, which \
            is how a checklist stops being read. If the flag was renamed, rename it here in \
            the same commit — this file and the note are the only two homes it has.
            """)
    }
}
