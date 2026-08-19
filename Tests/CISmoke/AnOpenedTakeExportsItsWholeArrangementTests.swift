// AnOpenedTakeExportsItsWholeArrangementTests.swift
// Echoel — #623: opening a saved take must restore its ARRANGEMENT, not just the one
// bar that happened to be sounding when it was saved.
//
// WHAT THIS GUARDS (Ultra-Audit 2026-08-19, MIDI Rank 3 — the second half of the
// founder's "Midi Export geht nicht"). `open(_:)` restored the take with
// `pianoRoll.load(p.notes)`, and `load(_:)` CLEARS `arrangementBars` by contract (a
// launched clip is one bar). `arrangementForExport()` then takes its
// `guard arrangementBars.count > 1 else { return (notes, 1) }` branch, so an eight-bar
// take exported as ONE bar — and that one bar is the worst possible choice, because
// `Project.notes` is whatever `loadArrangement` last staged, i.e. bar 0 with
// `IntroAttenuation` baked in. ⚠️ #623b (review L9): that is the COMMON case, not the
// only one — once the transport has wrapped a bar, `trigger` writes the true unsoftened
// `arrangementBars[k]` into `notes` and `pattern.onStop` re-primes from the unsoftened
// bar 0, so a take saved mid-playback exports one UNsoftened bar. Short either way;
// softened only when saved before the first wrap. The export was short, usually also
// softened, while reporting success: the diag line reads "… 1 bars" rather than naming a failure. #217 had
// already persisted the raw bars (`Project.rawTake` → `rebakeSource`) and restored them
// into `lastRawTake`; they simply never reached the roll until a Mix fader was nudged
// (`rebalanceTake()`). This slice installs them at open, through the same machinery.
//
// KIND (§1): TWO KINDS, deliberately — the first time this file family has had a
// behavioural half.
//   · claims 1-3 are BEHAVIOURAL: they drive the real `PianoRollModel` and prove the
//     defect shape and the fix shape as PROPERTIES, not spellings. They would hold if
//     every identifier in `open(_:)` were renamed.
//   · claims 4-6 are a SOURCE-TEXT SCAN of the call site, because `open(_:)` is a
//     `private` method of a view no test in this bundle can instantiate (the
//     `AutosaveSlotTests` limit, stated the same way). That the founder's opened take
//     exports eight bars is still a device probe.
//
// GRADING (#433, against the pre-#623 parent):
//   · claim 1 (`load` alone exports one bar) is GREEN on both trees — it pins the
//     CONTRACT the fix routes around, not the fix. A counterweight.
//   · claims 2-3 are GREEN on both trees too: `loadArrangement` already behaved this
//     way; #623 changes only WHO calls it. Naming them FORWARD would be the #433
//     failure in the flattering direction.
//   · claims 4-6 are the FORWARD half and are red on the parent: the call-site count
//     (ONE there, TWO here), its multi-bar condition, and the ORDER against the
//     `hasComposed` write. The ORDER check is a discriminator of its own (#367) — a
//     refactor that moved the install BELOW the flag write would leave every count
//     green and re-open the exact case #622b had to rescue with a fader nudge.
//
// ⛔ THE FIRST VERSION OF THIS FILE ASSERTED `pianoRoll.loadArrangement(` == 1 AND WAS
// GREEN ON THE PARENT — a §0 transcription caught it before the commit, which is the
// entire reason §0 runs against BOTH trees. `generate()` has called that verb since
// #174; the parent has ONE call site, not zero. Two consequences were baked into the
// same mistake: the count was inverted, and the ORDER check compared against the
// FILE-WIDE first `hasComposed` write, which is `rebalanceTake()`'s (#622b) — far
// above `open(_:)` — so it read False on a correct tree. Both are fixed by scoping the
// order check to a double-anchored `open(_:)` span (#621b) and leaving only the count
// file-wide. That `generate()` already reaches for the same verb is not an accident to
// route around: it is the argument that this is the install verb (#616).
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH**
// (0 of 8 source verdicts flip raw vs stripped, on EITHER tree — the denominator
// is every `XCTAssert` from `testOpenInstallsTheRestoredBarsBeforeItJudgesTheFlag`
// to the end of the file, i.e. the scan test plus the two anchor checks in `span`).
//
// ⛔ THIS DENOMINATOR HAS BEEN WRONG TWICE AND THE SECOND TIME WAS THE CORRECTION.
// It read 8 (eyeballed), was "corrected" to 7 on review, and #623b's own new
// assertion put it back at 8 — so the review's 7 was right about the tree it read
// and stale by the time the fix landed. The lesson is not the number: it is that a
// hand-counted total in a header that RETRACTS an unmeasured count reproduces the
// defect it is apologising for. The counting RULE is now written down above so the
// next reader re-derives it in one command instead of trusting a digit. ⛔ The first version of
// this header claimed "TRAGEND (2 of 3)" and reasoned it out instead of measuring it —
// the #623 call-site comment does discuss both `loadArrangement` and `hasComposed`, but
// it names them WITHOUT the receiver (`pianoRoll.`) and without the full assignment
// spelling, so neither needle matches in prose. Reasoning about a stripper is not
// measuring one; the §0 transcription prints both columns for exactly this reason.
//
// ⚠️ #364: installing through a DIFFERENT verb is not forbidden. What is forbidden
// silently is going back to a bare `load(p.notes)` with no arrangement install, or
// letting the install drift below the flag write. The failure messages say so.

// #623b (review L8): file-level `canImport(SwiftUI)`, the family convention
// (`FXSpreadRowTests`) — `PianoRollModel` lives inside that guard in `PianoRollView.swift`,
// so a bundle built without SwiftUI would not compile the behavioural half. Harmless in
// today's CI (CISmoke builds only via the macOS Xcode target), which is exactly why it was
// missed; the convention exists so the next platform does not have to discover it.
#if canImport(SwiftUI)
import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class AnOpenedTakeExportsItsWholeArrangementTests: XCTestCase {

    private func studioLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Three distinct one-note bars, so "which bar did I get" is answerable by pitch.
    private func threeBars() -> [[Note]] {
        [[Note(pitch: 60, startStep: 0, role: .lead)],
         [Note(pitch: 62, startStep: 0, role: .lead)],
         [Note(pitch: 64, startStep: 0, role: .lead)]]
    }

    /// 1 — COUNTERWEIGHT (green on both trees): the CONTRACT that makes the bug
    /// possible. `load(_:)` ends cycling, so restoring a take through it alone can only
    /// ever export one bar. This is not a defect in `load(_:)` — it is why the install
    /// has to be its own line at the call site.
    func testLoadingOnlyTheSoundingBarExportsOneBar() {
        let model = PianoRollModel()
        model.loadArrangement(threeBars(), playing: false)
        XCTAssertEqual(model.arrangementForExport().bars, 3, "precondition")
        // What `open(_:)` does with `p.notes` — the saved sounding bar, nothing else.
        model.load([Note(pitch: 60, startStep: 0, role: .lead)])
        XCTAssertEqual(model.arrangementForExport().bars, 1, """
            `load(_:)` no longer clears the arrangement. That is a CONTRACT change, not \
            an improvement here: a launched clip is one bar by definition and the roll \
            would keep cycling a stale take. If it changed on purpose, #623's install \
            line in `open(_:)` may be redundant — check before deleting it.
            """)
    }

    /// 2 — the fix SHAPE: installing the raw bars restores the full export.
    func testInstallingTheRawBarsRestoresTheWholeArrangement() {
        let model = PianoRollModel()
        model.load([Note(pitch: 60, startStep: 0, role: .lead)])
        XCTAssertEqual(model.arrangementForExport().bars, 1, "precondition")
        model.loadArrangement(threeBars(), playing: false)
        let out = model.arrangementForExport()
        XCTAssertEqual(out.bars, 3, """
            installing an N-bar arrangement no longer makes the export N bars — this is \
            the property #623 rests on (Ultra-Audit MIDI Rank 3: an opened 8-bar take \
            exported 1 bar).
            """)
        XCTAssertEqual(out.notes.count, 3, "every bar's notes must reach the export")
    }

    /// 3 — and the exported bars are NOT the softened ones. This is the half that makes
    /// Rank 3 worse than "short": the single bar it did export was `IntroAttenuation`'s
    /// one-shot opening bar, so the file was quiet as well as truncated.
    func testTheExportedBarsAreNotTheSoftenedOpeningBar() {
        let model = PianoRollModel()
        var bars = threeBars()
        bars[0][0].velocity = 0.9
        model.loadArrangement(bars, playing: false)
        let sounding = model.notes.first { $0.pitch == 60 }
        XCTAssertEqual(sounding?.velocity ?? Float.nan,
                       0.9 * IntroAttenuation.leadFactor, accuracy: 1e-6, """
            the staged opening bar lost its softening — `IntroAttenuation` is what makes \
            the SAVED `Project.notes` unfit to be the export source, which is the \
            premise of this whole slice.
            """)
        let exported = model.arrangementForExport().notes.first { $0.pitch == 60 }
        XCTAssertEqual(exported?.velocity ?? Float.nan, 0.9, accuracy: 1e-6, """
            the export now carries the one-shot opening softening — `arrangementBars` \
            must stay the TRUE bars. Exporting the softened bar is exactly the file the \
            founder got back from an opened take.
            """)
    }

    /// 4-7 — the CALL SITE. Source-text, because `open(_:)` is private to a view this
    /// bundle cannot instantiate.
    ///
    /// ⚠️ #623b (review W1): the ORDER claim below buys the honest flag on the STOPPED
    /// branch only. `loadArrangement(playing: true)` writes `arrangementBars` and
    /// `pendingNotes` and leaves `notes` alone by design, so with the transport running
    /// the flag reads `!p.notes.isEmpty` exactly as before #623. Nothing here can pin
    /// that — it is a property of the model call, not of the call site's order — so it is
    /// STATED rather than asserted, and the source comment carries the same retraction.
    func testOpenInstallsTheRestoredBarsBeforeItJudgesTheFlag() throws {
        let lines = try studioLines()

        XCTAssertEqual(lines.filter { $0.contains("pianoRoll.loadArrangement(") }.count, 2, """
            the number of `pianoRoll.loadArrangement(` call sites changed. There are TWO: \
            `generate()` (since #174 — it installs the bars it just composed) and \
            `open(_:)` (#623 — it installs `p.rebakeSource`, so an opened take exports \
            all its bars instead of the single softened one). A third caller is legal: \
            update this count in the same commit and say what it installs.
            """)

        // The multi-bar condition: a one-bar rawTake must NOT be re-installed, or a
        // single-bar take's sounding notes get replaced for zero export gain (the
        // export already returns `(notes, 1)` there). #217's "opening a take sounds
        // bit-identical" promise survives untouched for those takes because of it.
        XCTAssertTrue(lines.contains { $0.contains("take.bars.count > 1") }, """
            the install lost its multi-bar condition. Without it a single-bar take gets \
            its sounding notes re-glued at the CURRENT faders on open — a change in what \
            the take sounds like, bought for no export benefit at all.
            """)
        // #623b (review W4): the SECOND condition, and the one that stops this slice
        // from being a regression. `bars.count > 1` guards the OUTER array only, while
        // `RawTake`'s decoder can drop every note inside a bar and keep its position —
        // so `[[], [x], [y]]` reaches here, the stopped branch stages an EMPTY bar 0
        // into `notes`, and `hasComposed` goes false for a take that opened ARMED before
        // #623. The install would disarm a take it had just made exportable.
        XCTAssertTrue(lines.contains { $0.contains("take.bars.first?.isEmpty == false") }, """
            the install lost its non-empty-first-bar condition (#623b, review W4). \
            Without it a rawTake whose bar 0 decoded empty — representable, because \
            `RawTake` keeps bar positions and drops unreadable notes inside a bar — makes \
            the stopped branch stage `IntroAttenuation.apply([])` into `notes`, so the \
            `hasComposed` snapshot below reads FALSE and the take opens grey. That take \
            opened ARMED before #623: the install must never be able to empty the roll.
            """)

        // ORDER, scoped to open(_:) by TWO unique anchors (#621b). File-wide indices are
        // useless here: the first `hasComposed = !pianoRoll.notes.isEmpty` in the file is
        // `rebalanceTake()`'s (#622b), thousands of lines ABOVE open() — comparing against
        // it read False on a correct tree in transcription.
        let w = try span(lines,
                         from: "private func open(_ p: Project)",
                         to: "if let savedToneSystem = p.toneSystemID")
        let install = w.indices.filter { w[$0].contains("pianoRoll.loadArrangement(") }
        XCTAssertEqual(install.count, 1, """
            `open(_:)` no longer installs the restored arrangement exactly once — that \
            line IS #623 (Ultra-Audit MIDI Rank 3: an opened 8-bar take exported 1 \
            softened bar).
            """)
        let flag = w.indices.filter { w[$0].contains("hasComposed = !pianoRoll.notes.isEmpty") }
        XCTAssertEqual(flag.count, 1, """
            `open(_:)`'s honest `hasComposed` write is gone or duplicated — \
            `AnOpenedEmptyTakeCannotArmTheExportTests` owns the file-wide count; this \
            file needs open()'s single write so the order below means something.
            """)
        if let i = install.first, let f = flag.first {
            XCTAssertLessThan(i, f, """
                the arrangement install moved BELOW `open(_:)`'s `hasComposed` write. The \
                flag is a snapshot of `pianoRoll.notes`, so the install must happen \
                first — otherwise a take with empty `notes` and a surviving `rawTake` \
                opens grey while its full arrangement sits loaded and exportable, which \
                is precisely the state #622b had to rescue with a Mix-fader nudge.
                """)
        }
    }

    /// TWO unique anchors → the span between them (#621b: fixed windows age as the law
    /// comments around them grow, and this call site carries ~30 lines of them).
    private func span(_ lines: [String], from start: String, to end: String) throws -> ArraySlice<String> {
        let s = lines.indices.filter { lines[$0].contains(start) }
        XCTAssertEqual(s.count, 1, """
            `\(start)` is no longer unique in EchoelStudioView — re-anchor this check \
            before trusting it (#408).
            """)
        let e = lines.indices.filter { lines[$0].contains(end) }
        XCTAssertEqual(e.count, 1, """
            end anchor `\(end)` is no longer unique in EchoelStudioView — re-anchor \
            (#408).
            """)
        guard let si = s.first, let ei = e.first, si < ei else {
            throw XCTSkip("the \(start) → \(end) span is gone — reported by the anchors above")
        }
        return lines[si ... ei]
    }
}
#endif
