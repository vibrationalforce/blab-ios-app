import XCTest
@testable import Echoelmusic

/// #993 — a failed WAV export says so where the button that ran it lives.
///
/// WHY IT EXISTS. Success is loud: a share sheet opens. Failure was a sentence inside the
/// Save & Export dropdown, and the button that starts the export has not been in that panel
/// since #482 lifted it onto the always-visible front plate (`quickActionRow`). So a user who
/// pressed Record and got nothing had no reason to open a chip on a different surface, and the
/// control was indistinguishable from a dead button. The line's own #216 comment justified the
/// old home with "sits where the user is already looking" — true when it was written, false for
/// the ten slices since.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. It renders no SwiftUI, so whether the sentence is legible on
/// the plate is the NEEDS-FOUNDER-VERIFY at the foot of this file. What it pins is that the
/// sentence has exactly ONE home, that the home is the plate, and that moving it did not thin it.
///
/// ⚠️ HONEST GRADING. Transcribed against both trees, only claim 1 is LOAD-BEARING (green on
/// the worktree, red on `HEAD`). Claims 2, 3 and 4 are green on both by design: they are
/// counterweights against the ways this particular repair goes wrong LATER — a second copy
/// creeping back in, the line being promoted to an `.alert` against the ceiling, or the
/// sentence losing its suffix or its VoiceOver label in a future re-indent. A counterweight
/// that was already true is not a passing test dressed up as work; it is the half of the
/// change that has no diff.
///
/// It deliberately does NOT re-assert the presentation-modifier counts. Those are pinned once,
/// in `ResetSoundClearsWhatTheLaunchLineReportsTests` (#479) — a second copy of one number is
/// #416, and the whole point of this slice is that a sentence with two homes rots in one of them.
final class TheExportFailureSpeaksAtTheButtonTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let needle = "if let reason = exportFailure {"

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

    /// The lines of a `{ … }` member starting at the line that opens it, brace-counted.
    private func memberBody(from marker: String, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else { return nil }
        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            out.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth <= 0 && out.count > 1 { break }
        }
        return out.joined(separator: "\n")
    }

    // 1 — the sentence is on the FRONT PLATE, beside the control that ran the attempt.
    func testTheFailureLineRendersOnTheFrontPlate() throws {
        let text = try source(Self.studio)
        guard let plate = memberBody(from: "private var startControlRow: some View {", in: text) else {
            return XCTFail("ANCHOR MISSING: `private var startControlRow: some View {` — "
                           + "re-derive this guard.")
        }
        XCTAssertTrue(plate.contains(Self.needle), """
            The export-failure sentence left the front plate. The Record button lives in \
            `quickActionRow` two lines above it; a failure reported anywhere else is a button \
            that looks dead, because the SUCCESS path opens a share sheet and the failure path \
            would show nothing at all. If the button moves again, move this line with it — do \
            not put the sentence back behind a chip.
            """)
    }

    // 2 — exactly ONE home (#416). The move is only worth anything if the old copy went.
    func testTheSentenceHasExactlyOneHome() throws {
        let text = try source(Self.studio)
        let homes = text.components(separatedBy: Self.needle).count - 1
        XCTAssertEqual(homes, 1, """
            Expected exactly one render site for the export-failure sentence, found \(homes). \
            Two homes is how the old one rotted: it kept a #216 comment claiming it "sits \
            where the user is already looking" for ten slices after the button left that panel. \
            One status, one address.
            """)
    }

    // 3 — it stays a plain line. The chain is at its ceiling and this app has already crashed
    // THROUGH it (black screen, 10.76.34). The counts themselves are pinned in
    // `ResetSoundClearsWhatTheLaunchLineReportsTests` — named here, not copied.
    func testTheFailureStaysAPlainLineAndNotAnAlert() throws {
        let text = try source(Self.studio)
        guard let range = text.range(of: Self.needle) else {
            return XCTFail("ANCHOR MISSING: the export-failure block — re-derive this guard.")
        }
        // No fixed character window: the block carries a long ⛔ note explaining the move, and
        // a capped prefix stopped reaching the label the moment that note was written — the
        // guard then failed on a CORRECT tree, which is the #988 defect in miniature.
        let after = String(text[range.lowerBound...])
        guard let end = after.range(of: ".accessibilityLabel(\"Export failed.") else {
            return XCTFail("ANCHOR MISSING: the block's accessibility label — re-derive this guard.")
        }
        let body = String(after[..<end.upperBound])
        XCTAssertFalse(body.contains(".alert("), """
            The export failure was turned into an `.alert`. The body's presentation chain is at \
            its ceiling and adding to it is the documented cause of the 10.76.34 black screen \
            (SIGSEGV at first render, before any view appears). A plain line costs zero \
            modifiers and zero state.
            """)
    }

    // 4 — COUNTERWEIGHT: moving a sentence is where it quietly loses half of itself. The
    // suffix and the VoiceOver label are the two halves a re-indent drops without a compiler
    // noticing, and the suffix is the one thing true of all six exporter failure reasons.
    func testTheMoveDidNotThinTheSentence() throws {
        let text = try source(Self.studio)
        XCTAssertTrue(text.contains("Text(\"\\(reason). Nothing was saved.\")"), """
            The rendered failure sentence lost its "Nothing was saved." suffix. That clause is \
            the one fact true of all six of `LoopExporter`'s failure reasons, and it is what \
            tells the user there is no half-written file to hunt for.
            """)
        XCTAssertTrue(text.contains(".accessibilityLabel(\"Export failed. \\(reason). Nothing was saved.\")"), """
            The failure line lost its accessibility label. VoiceOver would then read the \
            reason with no indication that it IS a failure — on the surface a blind user \
            reaches after pressing a button that appeared to do nothing.
            """)
    }

    // NEEDS-FOUNDER-VERIFY: force an export failure (easiest: set the loop length so the
    // too-long message fires) and look at the front plate under the six tiles. Say whether the
    // sentence is readable there and whether it crowds the plate — it renders only while a
    // failure stands, so an idle plate should look exactly as it did before.
}
