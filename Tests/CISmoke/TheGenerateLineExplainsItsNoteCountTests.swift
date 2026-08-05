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
// ⭐ FOUR DRIVERS, NOT ONE. The count has four independent sources, and naming fewer would be
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
//   · `live` / `tScale` — mood liveliness and the tempo thinning, the two terms that sit BESIDE
//                 `busy` inside `composeHarmonic`: liveliness raises the octave-lift and
//                 ornament probabilities, `densityScale` coarsens the arp step and the inner
//                 pulse gap above roughly 106 BPM. (An earlier draft cited
//                 `ambientMelody`'s `density = busy * (0.6 + 0.8 * liveliness)` — that
//                 function is retired and reaches no take.)
//
// ⛔ HONEST LIMITS, exhaustive as far as I can make it:
//   · Both tests are SOURCE SCANS. They prove the line is written and that it recomputes
//     `busy` from the composer's own pure function; they cannot prove the string reaches
//     `echoel_diag.log` (that is a device read) and they cannot prove the printed `busy`
//     EQUALS the one `compose` used. That equality holds by construction — same pure
//     function, same `input` — and construction is exactly what a later edit can break. The
//     stronger guard would need `compose` to return the state it used; that is a return-type
//     change and a separate slice.
//   · The scan matches the four field names as they appear in the source literal. Renaming a
//     field in the literal AND here in the same commit passes, which is correct (the names are
//     the contract, not the spelling of any one of them) but means this cannot catch a rename
//     that makes the log less legible.
//   · Nothing here says the four drivers are COMPLETE. They are the four I could trace; if a
//     fifth is found, this file should grow rather than be trusted as an inventory.

import Foundation
import XCTest

final class TheGenerateLineExplainsItsNoteCountTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The four names the line must carry. `notes` is deliberately absent — it was always
    /// there and is the value being explained, not part of the explanation.
    private static let requiredFields = ["genre=", "body=", "busy=", "live=", "tScale="]

    // MARK: - The line says what set the count

    /// ⭐ THE HEADLINE. Every driver must appear inside the ONE breadcrumb literal that starts
    /// `generate[`, not merely somewhere in the file — a value computed and never printed is
    /// the same blind log with extra steps.
    func testTheGenerateBreadcrumbNamesEveryDensityDriver() throws {
        let line = try generateBreadcrumbLine()
        // `generateBreadcrumbLine` has ALREADY reported the real defect (missing or
        // duplicated anchor) via `XCTFail`. Returning here keeps that one precise failure
        // instead of burying it under five derived ones about an empty string.
        guard !line.isEmpty else { return }
        for field in Self.requiredFields {
            XCTAssertTrue(line.contains(field), """
            the `generate[…]` breadcrumb no longer prints `\(field)`.

            That line is read in `echoel_diag.log` with no source beside it, so every value it \
            omits is a question a device log cannot answer. #413 exists because the count was \
            printed alone and five re-seeds reading 5 → 25 → 13 notes could not be attributed \
            to anything. If a driver genuinely stopped driving, delete it from \
            `requiredFields` IN THE SAME COMMIT that removes it from the composer — do not \
            drop it from the line and leave this list claiming it.

            The line found was:
            \(line)
            """)
        }
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

    /// Non-empty lines with whole-line and trailing comments removed. Load-bearing here: the
    /// doc block above the new code quotes every one of these field names on purpose, and
    /// without stripping, prose would satisfy every assertion in this file.
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
