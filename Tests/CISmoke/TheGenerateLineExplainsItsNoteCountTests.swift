// TheGenerateLineExplainsItsNoteCountTests.swift
// Echoel — #413. The `generate[…]` breadcrumb printed the note COUNT and nothing that
// produces it.
//
// ⭐ WHY THAT COST A WHOLE ANALYSIS PASS. Founder device log 2488 shows five automatic
// re-seeds of one session reporting 5 → 25 → 13 → 13 → 13 notes. To rule out the obvious
// suspect I had to reconstruct, by hand and from timestamps, that at the 25-note generate the
// freshest published bio frame was ~14 s old against the camera's 6 s `freshnessWindow` — so
// no body reached the composer. That is a diagnosis the LINE should have made in one glance,
// and it is the #401 situation one layer over: a breadcrumb that reports an outcome without
// the inputs that decide it can only ever start an investigation, never end one.
//
// ⭐ FIVE DRIVERS, NOT ONE. The count has five independent sources, and naming fewer would be
// the same partial answer dressed as an explanation — the failure this file's sibling #416 was
// corrected for on the same day:
//   · `genre`   — `MusicStyle` carries the `harmonicProfile` (progression length, chord tones
//                 per chord, `sustainedDrone`, `arpeggiated`) plus `chordArticulation` and the
//                 bass/pad rhythms, and those decide how many notes a bar holds. A genre change
//                 between two generates moves the count with nothing else changing.
//                 ⛔ The first version of this bullet named `trapMelody`/`ambientMelody`/
//                 `dubMelody` as the per-genre count formulas. All three are RETIRED — every
//                 style routes through `composeHarmonic` in `BioComposer.compose`, and the
//                 functions' own docs say "unused, reversible". The correction is kept rather
//                 than erased: it is the kind of stale that sends the next reader into dead
//                 code with plausible-looking numbers.
//   · `body`    — whether `makeComposerInput` found a USABLE frame. Deliberately NOT the same
//                 question as the visual line's `bio=`: that one asks `freshBio(maxAge: 5)`,
//                 this one is the composer's per-source window (camera/BLE 6 s, watch and
//                 HealthKit 90 s, Oura 600 s). Two questions that have looked like one number
//                 in every log so far.
//   · `busy`    — the autonomic density term from `BioComposer.musicalState`.
//   · `tScale` — the tempo thinning: `densityScale` coarsens the arp step and the inner pulse
//                 gap once it drops below 0.8, which is above 109 BPM (`(84/bpm)^0.85 = 0.8`).
//                 ⛔ An earlier draft of this bullet cited `ambientMelody`'s
//                 `density = busy * (0.6 + 0.8 * liveliness)` — retired, reaches no take. The
//                 reason this file names its evidence instead of its intuition.
//   · `live`    — the Mood panel's Liveliness knob, which since #418 SHIFTS the threshold both
//                 decisions above compare `busy` against (`BioComposer.densityThreshold`). It
//                 was in this list, was removed as provably inert, and came back within the same
//                 cycle when it got a reader — the full history is on `requiredFields` below,
//                 including the part that stays true: on the 8 `sustained` genres (the default
//                 `.selfObservation` among them) it still moves nothing (#419).
//
// ⛔ HONEST LIMITS, exhaustive as far as I can make it:
//   · All three tests are SOURCE SCANS. They prove the line is written and that it recomputes
//     `busy` from the composer's own pure function; they cannot prove the string reaches
//     `echoel_diag.log` (that is a device read) and they cannot prove the printed `busy`
//     EQUALS the one `compose` used. That equality holds by construction — same pure
//     function, same `input` — and construction is exactly what a later edit can break. The
//     stronger guard would need `compose` to return the state it used; that is a return-type
//     change and a separate slice.
//   · The scan matches the five field names as they appear in the source literal. Renaming a
//     field in the literal AND here in the same commit passes, which is correct (the names are
//     the contract, not the spelling of any one of them) but means this cannot catch a rename
//     that makes the log less legible.
//   · Nothing here says the five drivers are COMPLETE, and that bullet has already been cashed:
//     it read "if a fifth is found, this file should grow rather than be trusted as an
//     inventory" — #418 found the fifth within the day and the file grew. Read the list as the
//     drivers traced so far, never as an inventory.

import Foundation
import XCTest

final class TheGenerateLineExplainsItsNoteCountTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The five names the line must carry. `notes` is deliberately absent — it was always
    /// there and is the value being explained, not part of the explanation.
    ///
    /// ⛔ `live=` WAS HERE, WAS DELETED HOURS LATER, AND IS BACK — and all three were correct at
    /// the time. Deleted because every read of `mood.liveliness` in the composer then sat either
    /// in the callerless `ambientMelody` or inside `if profile.leadDensity > 0`, and all 33
    /// shipped genres set `leadDensity: 0.0` (the invariant `LeadRoleAbsenceTests` pins in this
    /// same bundle) — a guard demanding it would have forced the log to print a number that could
    /// not move the count. Back because #418 gave it a reachable reader
    /// (`BioComposer.densityThreshold`, shifting both live density decisions) in the same cycle.
    /// The honest limit travels with it: both decisions sit behind `!sustained`, and 8 of the 16
    /// offered genres — the default `.selfObservation` included — never reach them (#419). So
    /// `live=` is a driver on SOME genres, which is why this list demands it and the block above
    /// `densityText` says which.
    ///
    /// **Lehre: this list is only true for the commit it was written in.** A fix that gives a
    /// dead value a reader has to walk back to the diagnostic that declared it dead.
    private static let requiredFields = ["genre=", "body=", "busy=", "tScale=", "live="]

    // MARK: - The line says what set the count

    /// ⭐ THE HEADLINE, IN TWO LINKED HALVES. Every driver must appear in the density literal,
    /// AND that literal must be interpolated into the ONE breadcrumb that opens `generate[` —
    /// a value computed and never printed is the same blind log with extra steps, and a
    /// breadcrumb that interpolates an empty name prints nothing at all.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST ASSERTED ALL FIVE FIELDS ON THE BREADCRUMB LINE ITSELF
    /// AND WOULD HAVE BEEN RED ON CORRECT CODE. `codeLines` keeps PHYSICAL lines, and the source
    /// deliberately hoists the literal into its own `densityText` statement one line above the
    /// call — the very hoist the source comment defends, because folding it into a literal that
    /// already carries ten interpolations is the #287 (`3379bb3`) type-checker shape that turned
    /// the blocking gate red. So the scan's own assumption ("one statement = one line") was
    /// defeated by the fix it was written to protect. The lesson is not "widen the scan": it is
    /// that a source scan must follow the BINDING, not the line, whenever the thing it measures
    /// is allowed to be hoisted — and this repo hoists on purpose, repeatedly.
    func testTheGenerateBreadcrumbNamesEveryDensityDriver() throws {
        let literal = try densityLiteralLine()
        // `densityLiteralLine` has ALREADY reported the real defect (missing or duplicated
        // anchor) via `XCTFail`. Returning here keeps that one precise failure instead of
        // burying it under five derived ones about an empty string.
        guard !literal.isEmpty else { return }
        for field in Self.requiredFields {
            XCTAssertTrue(literal.contains(field), """
            the density line no longer builds `\(field)`.

            The `generate[…]` breadcrumb is read in `echoel_diag.log` with no source beside it, \
            so every value it omits is a question a device log cannot answer. #413 exists \
            because the count was printed alone and five re-seeds reading 5 → 25 → 13 notes \
            could not be attributed to anything. If a driver genuinely stopped driving, delete \
            it from `requiredFields` IN THE SAME COMMIT that removes it from the composer — do \
            not drop it from the line and leave this list claiming it.

            The literal found was:
            \(literal)
            """)
        }
    }

    /// The other half: the literal above is worthless if nothing prints it. This pins the
    /// BINDING — the breadcrumb must interpolate `densityText` by name — which is what makes
    /// the two-line split safe to assert across.
    func testTheBreadcrumbActuallyPrintsTheDensityLine() throws {
        let line = try generateBreadcrumbLine()
        guard !line.isEmpty else { return }
        XCTAssertTrue(line.contains("\\(densityText)"), """
        the `generate[…]` breadcrumb no longer interpolates `densityText`, so the density \
        fields are computed and thrown away.

        This is the failure mode the sibling test cannot see on its own: the literal can be \
        perfectly formed and simply not reach the log. If the value was renamed, rename it \
        here in the SAME commit; if it was genuinely dropped, delete both halves rather than \
        leaving one asserting a line that no longer exists.

        The breadcrumb line found was:
        \(line)
        """)
    }

    /// The `busy` it prints must come from the composer's own pure definition, fed with the
    /// SAME `input` the composer received. A locally re-derived approximation would drift from
    /// the real term silently, and a breadcrumb that reports a number the engine did not use is
    /// worse than one that reports nothing — this repo files that as a lying control.
    func testBusyIsRecomputedFromTheComposersOwnDefinition() throws {
        let lines = try codeLines(Self.studio)
        let callsState = lines.contains { $0.contains("BioComposer.musicalState(") }
        XCTAssertTrue(callsState, """
        nothing in `EchoelStudioView` calls `BioComposer.musicalState` any more, so the `busy=` \
        the breadcrumb prints is derived some other way.

        `musicalState` is the ONE place the autonomic density term is defined (`compose` reads \
        it too). Any second derivation is a number that can disagree with the music while \
        looking authoritative in the log.
        """)

        let fedFromInput = lines.contains { $0.contains("coherence: input.coherence") }
        XCTAssertTrue(fedFromInput, """
        `BioComposer.musicalState` is called, but not with `input.coherence` — so it may be fed \
        something other than the exact input the composer got.

        Equality with the composer's own `busy` holds only because both calls read the same \
        `input`. Feed it a live publisher read, a rounded copy or a different frame and the \
        printed number becomes an independent measurement that merely looks like the one that \
        made the music.
        """)
    }

    // MARK: - Source access

    /// The ONE line that builds the density literal, anchored on its opening field rather than
    /// on `let densityText` — the declaration wraps onto its own line for width, so the `let`
    /// and the literal are two physical lines and only the second carries the names.
    private func densityLiteralLine() throws -> String {
        let lines = try codeLines(Self.studio)
        let hits = lines.filter { $0.contains("\"genre=\\(") }
        guard hits.count == 1, let line = hits.first else {
            XCTFail("""
            expected exactly one line opening the density literal (`"genre=\\(`) in \
            \(Self.studio), found \(hits.count).

            Zero means the literal was renamed, reshaped or removed and this file is measuring \
            nothing. More than one means two places build a density string and a reader of \
            `echoel_diag.log` cannot tell which one produced a line.
            """)
            return ""
        }
        return line
    }

    /// The one breadcrumb literal that opens `generate[`. Asserts uniqueness rather than taking
    /// the first hit: a scan anchored on a string that matches twice measures the wrong one
    /// (#408 made that mistake and was caught by running).
    private func generateBreadcrumbLine() throws -> String {
        let lines = try codeLines(Self.studio)
        let hits = lines.filter { $0.contains("breadcrumb(\"generate[") }
        guard hits.count == 1, let line = hits.first else {
            XCTFail("""
            expected exactly one `breadcrumb("generate[` line in \(Self.studio), found \
            \(hits.count).

            Zero means the breadcrumb was renamed or removed and this file is measuring \
            nothing. More than one means there are two generate logs and a reader of \
            `echoel_diag.log` cannot tell which produced a line.
            """)
            return ""
        }
        return line
    }

    /// Repo root from this file's compile-time path. Skips rather than passing when the tree is
    /// absent — a green earned without reading source is the dishonesty this bundle exists to
    /// prevent.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — these scans cannot report a green")
        }
        return root
    }

    /// Non-empty lines with whole-line and trailing comments removed.
    ///
    /// ⛔ THIS DOC CLAIMED THE STRIPPING WAS "LOAD-BEARING because the doc block quotes every one
    /// of these field names". It is not, and the claim is the exact species this file was written
    /// to catch: a rationale that reads well and was never checked. No comment in
    /// `EchoelStudioView.swift` contains any of the four anchors (`"genre=\(`,
    /// `breadcrumb("generate[`, `BioComposer.musicalState(`, `coherence: input.coherence`), so
    /// every assertion here passes with or without stripping today. It stays because the source
    /// block above the code is long, dense and quotes neighbouring identifiers freely — one
    /// future sentence citing an anchor verbatim would silently disarm a guard. DEFENSIVE, not
    /// load-bearing, and the difference is worth writing down.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let r = line.range(of: "//") {
                let before = line[line.startIndex..<r.lowerBound]
                if before.filter({ $0 == "\"" }).count % 2 == 0 {
                    line = String(before)
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }
}
