// AnExportSaysWhichFormatItIsTests.swift
// Echoel — #574. The two export buttons must not hand over indistinguishable files.
//
// THE DEVICE EVIDENCE. Founder, 2026-08-13, on a v10.79.388 screen recording:
// *"Midi Export beim Klavier Button stimmt nicht, der will noch wav rausrendern"*. The clip
// shows the share sheet reading `E~_2026-08-13_Cm_71bpm_A440_Self-Observ… — Audioaufnahme ·
// 435 Byte`. The export was CORRECT: 435 bytes is a Standard MIDI File and cannot be a WAV by
// two orders of magnitude. What failed is the READING —
//   · both exports built a byte-identical stem (`sessionName` + genre), duplicated in two
//     places that could not drift apart because they were the same expression twice;
//   · the only difference was the extension, which the iOS share sheet truncates away;
//   · and iOS's own subtitle for a `.mid` file is "Audioaufnahme", because the MIDI type
//     conforms to `public.audio`.
// So a control did exactly the right thing and presented itself as the other control. That is
// the lying-control class this repo keeps paying for, and #574 repairs it in the NAME — the
// exporter was never wrong and is untouched.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): every claim here is a SOURCE-TEXT SCAN. `shareStem`,
// `renamedForShare` and `exportMIDI` are `private` members of a `View` no test bundle can
// instantiate, so behaviour cannot reach them. DEVICE PROBE, open and NOT covered: whether
// `…_Self-Observation_MIDI.mid` actually reads as MIDI in the share sheet — that is the
// founder's next clip, and it is the only thing that closes this.
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`01255b0`) and this
// tree — no local toolchain (§0):
//   · claims 1–3 are REGRESSIONS on the parent, for the reason their names give: `shareStem`
//     does not exist there, and both call sites build their own stem inline. ONE absence,
//     reported once (#486) — the missing declaration is why all three go red together.
//   · claim 4 is a COUNTERWEIGHT, green on both trees, and it is the point of the file: the
//     musical context the founder asked for on 2026-07-02 (*"das Exportieren soll gleich die
//     Tonart etc mit drin haben"*) must survive a change that is only about the format token.
//     Without it, "add a format word" and "replace the name with a format word" look the same
//     to every other assertion here.
//   · STRIPPER: **PROPHYLAKTISCH (0 of 5 verdicts flip)** — measured raw vs. stripped on both
//     trees. It stays because `EchoelStudioView`'s ⭐ block explains this fix in prose right
//     next to the code, so the raw count is one quoted signature away from being wrong.
//     ⛔ THE FIRST VERSION OF THIS LINE CLAIMED **TRAGEND (1 of 5)** and reasoned that the ⭐
//     block quotes the declaration. It quotes the NAME (`shareStem`), never the full signature
//     the anchor uses, so no needle flips. That is the #433 defect in its flattering direction —
//     booking a guard as load-bearing when it is insurance — and it is retracted here rather
//     than quietly edited, because the whole point of §3 is that the generous mistake and the
//     harsh one are the same mistake.

import Foundation
import XCTest
@testable import Echoelmusic

final class AnExportSaysWhichFormatItIsTests: XCTestCase {

    private static let studioPath = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 — one builder, not two copies of one expression

    func testBothExportsShareOneStemBuilder() throws {
        let src = try source(Self.studioPath)
        let decl = "private func shareStem(format: String) -> String {"
        XCTAssertEqual(src.components(separatedBy: decl).count - 1, 1, """
            `shareStem(format:)` is not declared exactly once in \(Self.studioPath).
            The WAV and MIDI names WERE the same expression written twice, and that is how they \
            came to be indistinguishable on screen — a duplicate cannot drift apart, so nothing \
            ever flagged that the pair had no distinguishing token at all. One builder is the \
            repair (#416). If it moved to a helper type, re-anchor this scan in the same commit \
            (#454); do not relax the count.
            """)
        XCTAssertEqual(src.components(separatedBy: "_\\(style.displayName)_").count - 1, 1, """
            The genre is interpolated into a stem in more than one place again. A second stem \
            builder is precisely the defect #574 removed.
            """)
    }

    // MARK: - claim 2 — the WAV path goes through it

    func testTheWavExportNamesItsFormat() throws {
        let src = try source(Self.studioPath)
        XCTAssertEqual(src.components(separatedBy: "\"\\(shareStem(format: ext)).\\(ext)\"")
                          .count - 1, 1, """
            The WAV share name no longer carries its format. Tagging only MIDI would leave this \
            side reading "Audioaufnahme" with no format word anywhere either — iOS truncates \
            this extension too — so the pair stays indistinguishable in the direction the \
            founder was actually looking. Symmetry is the assertion, not tidiness.
            """)
    }

    // MARK: - claim 3 — and so does the MIDI path

    func testTheMidiExportNamesItsFormat() throws {
        let src = try source(Self.studioPath)
        XCTAssertEqual(src.components(separatedBy: "\"\\(shareStem(format: \"midi\")).mid\"")
                          .count - 1, 1, """
            The MIDI share name no longer carries its format. This is the exact file the founder \
            saw presented as "Audioaufnahme"; the export itself was correct (435 bytes of real \
            MIDI), so a regression here silently restores a working control that reads as broken.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the musical context still travels

    /// Green on both trees, and the reason the file is not just three positive scans. #574 adds
    /// ONE word to a name whose whole job is to carry key, tempo, tuning and genre into a DAW.
    /// Nothing else here can tell "appended a format token" from "replaced the name with one".
    func testTheStemStillCarriesKeyTempoTuningAndGenre() throws {
        let body = try declarationBody(of: "private func shareStem(format: String) -> String",
                                       in: Self.studioPath)
        XCTAssertTrue(body.contains("session.sessionName(bpm: beatPlayer.pattern.tempo)"), """
            The export stem no longer asks `sessionName`, which is what puts the date, key, \
            tempo and A4 into the filename (founder 2026-07-02: "das Exportieren soll gleich \
            die Tonart etc mit drin haben"). A DAW-bound file that states only its format is a \
            worse trade than the ambiguity #574 set out to fix.
            """)
        XCTAssertTrue(body.contains("style.displayName"), """
            The export stem no longer carries the genre.
            """)
        XCTAssertTrue(body.contains("format.uppercased()"), """
            The format token is no longer normalised. `.mid` reaches this builder as the URL's \
            lowercase path extension while the MIDI call site passes a literal — un-normalised, \
            the two paths would stamp different-looking tokens for the same idea.
            """)
        // The sanitiser is what keeps a genre with a space or a slash from producing a path
        // component the share sheet cannot show — it predates #574 and must not be lost with it.
        XCTAssertTrue(body.contains("components(separatedBy: CharacterSet(charactersIn:"), """
            The filename sanitiser left the stem builder. A genre like "Dub Techno" would then \
            put a space into the name, and "Save & Export" an ampersand.
            """)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct ExportAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ExportAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Brace-matched, never a line window: this file is >10 000 lines and its comment blocks run
    /// 20–40 lines, so any fixed window is unsound by construction (#408).
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: key).count - 1
        guard hits == 1 else {
            throw ExportAnchorMissing(reason: """
                `\(key)` occurs \(hits)× in \(relativePath); this extraction needs exactly one so \
                it cannot silently read a different declaration.
                """)
        }
        guard let start = text.range(of: key),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw ExportAnchorMissing(reason: "no opening brace after `\(key)`")
        }
        var depth = 0
        var i = open
        var out = ""
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw ExportAnchorMissing(reason: "unbalanced braces after `\(key)` in \(relativePath)")
    }
}
