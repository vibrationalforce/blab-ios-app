// EveryLookHasAFlashBudgetTests.swift
// Echoel — no look reaches a user unbudgeted, in the BLOCKING bundle.
//
// WHY IT EXISTS (#1114). #1102 hand-wrote a blocking pin for the Dish because that commit
// knew an unbudgeted look could reach `main`. Nobody generalised it, so a sixth look would
// have inherited nothing. This is the general case: every entry a user can select must have
// a budget row, and every row's arithmetic must run inside a gate.
//
// ⛔ THIS FILE PARSED SOURCE TEXT UNTIL #1123, AND THAT IS NO LONGER NECESSARY — the change
// is worth stating because the parser was the interesting part and its absence looks like a
// loss. The budget TABLE used to be a literal array inside
// `Tests/EchoelmusicTests/FlashGuardTests.swift`, i.e. the suite no gate compiles (#208), so
// #1114 reached it the only way a blocking test could: by reading the file as text and
// re-deriving each row through the real `FlashGuard.effectiveFieldHz`. #1123 moved the DATA
// into `FlashGuard.fieldBudgets`, where it is compiled law. The claims below now read the
// law directly — strictly stronger, because a parser can only ever check what it manages to
// match, and this cannot silently match less.
//
// ⛔ ONE CLAIM WAS RETIRED WITH THE PARSER, DELIBERATELY AND NOT SILENTLY. #1114's claim 3
// pinned that `FlashGuard.ringsPhaseDamping` was the only SYMBOLIC multiplier in the table,
// so a future symbolic row could not slip past the parser unresolved. With the table typed,
// a symbolic value is just a `Double` the compiler resolves — the failure mode it guarded
// against cannot occur. Claim 3 below replaces it with the check that IS still decidable:
// the rows address distinct styles and each names a real library look.
//
// ⚠️ TWO LIMITS, unchanged and stated before the claims because a green here reads broader
// than it is:
//   · It proves each row's ARITHMETIC and the table's COMPLETENESS. It cannot prove a
//     hand-derived multiplier actually matches its shader function — that is a re-derivation
//     a human does when editing the function, and rows have been wrong before.
//   · It does NOT cover the A↔B BLEND UNION — ⭐ AND THAT IS NO LONGER AN OPEN HOLE, only a
//     boundary of THIS file. #1124 closed it: `FlashGuard.blendPhaseDamping` slows the field
//     phase while two looks coexist, and `TheBlendUnionStaysUnderTheCeilingTests` sweeps
//     every pair. This note stays because a limit that was true for two slices is worth
//     seeing repaired, and because the closing slice was found by reading exactly this
//     sentence — a named limit is a to-do that survives context loss, which an unnamed one
//     is not.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryLookHasAFlashBudgetTests: XCTestCase {

    // MARK: - 1 · Completeness

    /// The general case of #1102's per-look pin: EVERY entry the user can select must have a
    /// budget row. This is the assertion that goes red the day a sixth look lands without one.
    func testEveryLibraryLookHasABudgetRow() {
        XCTAssertFalse(LookBlendMap.library.isEmpty, "the look library is empty — nothing is selectable")
        for look in LookBlendMap.library {
            XCTAssertNotNil(FlashGuard.fieldBudget(forStyle: look.index), """
                The look "\(look.name)" (style index \(look.index)) is selectable from \
                `LookBlendMap.library` and has NO row in `FlashGuard.fieldBudgets`. A look \
                with no budget has never been checked against the 3 Hz WCAG ceiling. Add the \
                row — the multiplier is the FASTEST phase-bearing term of its shader \
                function, doubled by `folds: true` if an abs(), a square, or any non-monotone \
                map creates new extrema — in the same commit as the library row.
                """)
        }
    }

    // MARK: - 2 · The ceiling arithmetic, inside a gate

    /// Re-derives every row through the shipped `FlashGuard.effectiveFieldHz`. Until #1114
    /// this computation ran only in the suite no gate compiles.
    func testEveryBudgetRowStaysUnderTheWCAGCeiling() {
        XCTAssertGreaterThanOrEqual(FlashGuard.fieldBudgets.count, LookBlendMap.library.count, """
            There are \(FlashGuard.fieldBudgets.count) budget rows for \
            \(LookBlendMap.library.count) selectable looks. Claim 1 names which look is \
            missing; this bound is here so an EMPTIED table cannot make claim 3 vacuously \
            pass (#1114's claim-3 lesson: never let a checker cover less than it claims).
            """)
        for row in FlashGuard.fieldBudgets {
            let hz = FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                                 phaseMultiplier: row.phaseMultiplier,
                                                 folds: row.folds)
            XCTAssertEqual(hz, row.effectiveHz, accuracy: 1e-12, """
                "\(row.name)": the row's own `effectiveHz` (\(row.effectiveHz)) disagrees with \
                `FlashGuard.effectiveFieldHz` (\(hz)). They must be one computation — a row \
                that scores itself is not a check.
                """)
            XCTAssertLessThanOrEqual(hz, FlashGuard.maxFlashHz, """
                "\(row.name)" (style \(row.styleIndex)) flashes at \(hz) Hz, over the WCAG \
                ceiling of \(FlashGuard.maxFlashHz). Either the multiplier is wrong or the \
                shader function changed under it. Do NOT raise the ceiling: the epilepsy \
                limit is not a tuning knob, and there is no headroom to borrow: the \
                binding row (Rings, 2.50 Hz) would land exactly on 3.000 at a 3.0 phase cap.
                ⛔ #1130 — THIS MESSAGE SAID "Aurora already sits at exactly 3.00", WHICH \
                #1127 HAD ALREADY MADE FALSE (Aurora 3.00 → 1.75 Hz when its swell moved off \
                the clock onto the real breath signal). The CONCLUSION held, the EVIDENCE did \
                not — and an argument that names the wrong row invites the next reader to \
                check it, find Aurora at 1.75, and conclude there IS headroom.
                """)
        }
    }

    // MARK: - 3 · The rows address distinct, real looks

    func testEveryBudgetRowNamesADistinctLibraryLook() {
        var seen = Set<Int>()
        for row in FlashGuard.fieldBudgets {
            XCTAssertTrue(seen.insert(row.styleIndex).inserted, """
                Style index \(row.styleIndex) has two budget rows. \
                `FlashGuard.fieldBudget(forStyle:)` returns the FIRST match, so the second is \
                dead weight that reads like coverage — and if the two disagree, the one that \
                wins is decided by array order.
                """)
            XCTAssertTrue(LookBlendMap.library.contains { $0.index == row.styleIndex }, """
                Budget row "\(row.name)" targets style \(row.styleIndex), which is not in \
                `LookBlendMap.library`. That is not automatically wrong — a look can be \
                retired from the UI while its shader function stays compiled — but the row \
                then guards nothing a user can reach, and the retired styles (1 Cymatics, \
                4 Prism, 6 Lissajous, 8 Scope, 9 Fractal) deliberately have NO rows: this \
                table is a "selectable looks are legal" table, and claim 2 above requires \
                every row to be ≤ the ceiling. Their rates ARE derived since #1130 — written \
                at `FlashGuard.fieldBudget(forStyle:)`, not as rows — and one of them \
                (8 Scope, 3.90 Hz) is OVER the law, so adding its row would correctly turn \
                this suite red. Re-dooring Scope means calming the shader first. \
                Say which case this is at the row.
                """)
        }
    }

    /// 4 — the "no headroom" argument reads IDENTICALLY in both of its homes (#1148).
    ///
    /// #1130 corrected this sentence in the failure message above, where it had named Aurora
    /// at "exactly 3.00" after #1127 retired that row. It left the SAME stale example standing
    /// in `FlashGuard.blendPhaseDamping`'s own doc — the copy a reader of the algorithm meets
    /// first, and the one paragraph in this system that calls itself checked arithmetic. That
    /// is #456 inside one file pair: prose moves in EVERY home, not only the one being edited.
    ///
    /// ⛔ THIS IS A POSITIVE SCAN ON PURPOSE. The obvious form — assert the retired example is
    /// ABSENT from the source — is the self-referential trap that has now fired three times in
    /// this repo (#1142, #1144, #1147): the retraction must name the struck sentence, so it
    /// becomes the only remaining match and the check reads red on a correct tree. Asserting
    /// that both homes say the SAME true thing has no such failure mode.
    func testTheNoHeadroomArgumentReadsTheSameInBothHomes() throws {
        let phrase = "binding row (Rings, 2.50 Hz)"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }

        let sourcePath = root.appendingPathComponent("Sources/Echoelmusic/Core/FlashGuard.swift")
        guard let source = try? String(contentsOf: sourcePath, encoding: .utf8) else {
            return XCTFail("ANCHOR MISSING: Core/FlashGuard.swift could not be read — a missing "
                           + "anchor is a finding, not a pass.")
        }
        XCTAssertTrue(source.contains(phrase), """
            FlashGuard.blendPhaseDamping's doc no longer names the binding row in the agreed \
            words "\(phrase)". If a retune moved it, say so in BOTH homes in the same commit: \
            this file's ceiling message and that doc. A retune that touches only one leaves the \
            other as a worked example of a row that no longer exists — exactly what #1130 fixed \
            here and #1148 had to fix there.
            """)

        let selfText = (try? String(contentsOf: URL(fileURLWithPath: #filePath),
                                    encoding: .utf8)) ?? ""
        XCTAssertTrue(selfText.contains(phrase),
                      "This file stopped naming the binding row in the agreed words. The two "
                      + "homes must read identically or the pairing is not checkable.")

        // The phrase must still be TRUE, not merely present in both places: re-derive the
        // loudest single row from the shipped table rather than trusting either sentence.
        let loudest = FlashGuard.fieldBudgets.max(by: { $0.effectiveHz < $1.effectiveHz })
        XCTAssertEqual(loudest?.name, "Rings",
                       "The binding row is now \(loudest?.name ?? "none"), not Rings. Both "
                       + "homes name Rings and both are now wrong — move them together.")
        XCTAssertEqual(loudest?.effectiveHz ?? 0, 2.5, accuracy: 0.0001,
                       "The binding row's rate moved. Both homes quote 2.50 Hz; update both.")
    }
}
