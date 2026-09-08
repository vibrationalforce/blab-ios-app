// EveryLookHasAFlashBudgetTests.swift
// Echoel — #1114: no look reaches a user without a flash budget, and every budget in the
// table is re-derived against the WCAG ceiling by a BLOCKING gate.
//
// WHAT THIS GUARDS, and why it is new. The per-look flash budget table lives in
// `Tests/EchoelmusicTests/FlashGuardTests.swift` — the NON-BLOCKING suite (#208: no gate
// compiles it). Until this file, the only blocking protection was PER LOOK and written by
// hand: `TheWaterDishIsLitLikeTheExperimentTests` claim 7 pins that *the Dish* has both a
// library row and a budget row, because #1102 knew an unbudgeted look could reach `main`.
// Nothing generalised it. A SIXTH look added tomorrow inherits no protection at all — the
// author has to remember, and the gate stays green if they do not. That is the gap this
// closes, and it is closed BEFORE the next look rather than after it (`Core/WaterCaustics`
// #1113 is the physics of exactly such a look, sitting in the tree with no caller yet).
//
// KIND (§1): **MIXED, labelled per claim.** Claim 1 is a SOURCE-TEXT SCAN of the budget
// table plus an END-TO-END read of the shipped `LookBlendMap.library`. Claim 2 is END-TO-END
// BEHAVIOUR — it parses the table's rows and drives the real `FlashGuard.effectiveFieldHz`,
// so the WCAG arithmetic that today only runs in the non-blocking suite now runs in a gate.
// Claim 3 is a SOURCE-TEXT SCAN that keeps claim 2 from silently covering less than it says.
//
// §3 grading against the parent tree: claims 1–3 are COUNTERWEIGHTS — green on both trees,
// which is the point of the file. It is not a regression guard; it is the missing general
// case of a per-look guard that already exists. 0 regressions, 0 anchor absences, 0 forward
// guards, 3 counterweights.
//
// ⚠️ WHAT THIS DOES NOT PROVE, stated before the claim (§1). It does NOT prove a multiplier
// is the right one for its shader function. Those numbers are hand-derived prose about the
// fastest phase-bearing term, and only two rows are tied to the shader by a guard at all
// (Rings via `FlashGuard.ringsPhaseDamping`, Dish via `TheWaterDishIsLitLikeTheExperimentTests`).
// A row that says 0.40 for a function that actually multiplies two phase-bearing factors
// would pass every assertion here. This file proves COMPLETENESS and the CEILING ARITHMETIC,
// not correctness of the derivation — a real remaining gap, named rather than papered over.
//
// ⚠️ It also does not cover the A↔B BLEND. `LookBlendMap` crossfades two looks at once and
// the union of two phase spectra is not the max of two budgets; the shipped default sequence
// puts the zero-margin look (Aurora, exactly 3.00 Hz) inside that union. Out of scope here
// and worth its own slice.

import Foundation
import XCTest
@testable import Echoelmusic

final class EveryLookHasAFlashBudgetTests: XCTestCase {

    /// The budget table's home. Deliberately a hard failure if it moves — a guard that
    /// silently skips when its subject is renamed is the defect this bundle exists against.
    private static let budgetTable = "Tests/EchoelmusicTests/FlashGuardTests.swift"

    /// Rows whose multiplier is a SYMBOL rather than a literal, with the value to use.
    /// Claim 3 pins this set, so a future symbolic row cannot slip past claim 2 unparsed.
    private static let symbolicMultipliers: [String: Double] = [
        "FlashGuard.ringsPhaseDamping": FlashGuard.ringsPhaseDamping
    ]

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Sources/Echoelmusic").path) {
                return url
            }
        }
        throw XCTSkip("repo root not found from \(#filePath)")
    }

    private func tableSource() throws -> String {
        let path = try repoRoot().appendingPathComponent(Self.budgetTable).path
        guard FileManager.default.fileExists(atPath: path) else {
            XCTFail("""
            The per-look flash budget table is not at \(Self.budgetTable) any more. It was \
            MOVED or renamed, and this guard — the only blocking one that checks every look \
            has a budget — cannot see it. Point this constant at the new home in the SAME \
            commit that moves the table; do not delete this file to make the red go away.
            """)
            return ""
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Every row of the table, as (name, multiplier), parsed from source. Rows whose
    /// multiplier is symbolic are resolved through `symbolicMultipliers`.
    private func parsedRows(_ source: String) -> [(name: String, multiplier: Double, folds: Bool)] {
        var rows: [(String, Double, Bool)] = []
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Skip the comment lines that carry example tuples in prose.
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
            guard let open = line.range(of: "(\""), let closeQuote = line.range(of: "\"", range: open.upperBound ..< line.endIndex)
            else { continue }
            let name = String(line[open.upperBound ..< closeQuote.lowerBound])
            let rest = line[closeQuote.upperBound...]
            guard rest.hasPrefix(",") else { continue }
            let fields = rest.dropFirst()
                .split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2 else { continue }
            let multiplierToken = fields[0]
            let foldsToken = fields[1].hasPrefix("true") ? "true" : (fields[1].hasPrefix("false") ? "false" : "")
            guard !foldsToken.isEmpty else { continue }
            let value = Double(multiplierToken) ?? Self.symbolicMultipliers[multiplierToken]
            guard let multiplier = value else { continue }
            rows.append((name, multiplier, foldsToken == "true"))
        }
        return rows.map { (name: $0.0, multiplier: $0.1, folds: $0.2) }
    }

    // MARK: - 1 · Completeness (SOURCE-TEXT SCAN + the shipped library)

    /// The general case of #1102's per-look pin: EVERY entry the user can select must have a
    /// budget row. This is the assertion that goes red the day a sixth look lands without one.
    func testEveryLibraryLookHasABudgetRow() throws {
        let source = try tableSource()
        guard !source.isEmpty else { return }
        XCTAssertFalse(LookBlendMap.library.isEmpty, "the look library is empty — nothing is selectable")
        for look in LookBlendMap.library {
            XCTAssertTrue(source.contains("(\"\(look.name)\","), """
            The look "\(look.name)" (style index \(look.index)) is selectable from \
            `LookBlendMap.library` and has NO row in the flash budget table at \
            \(Self.budgetTable). A look with no budget has never been checked against the \
            3 Hz WCAG ceiling, and the table is in the NON-BLOCKING suite, so nothing else \
            will tell you. Add the row — the multiplier is the FASTEST phase-bearing term of \
            its shader function, doubled by `folds: true` if an abs() or a square folds it — \
            in the same commit as the library row.
            """)
        }
    }

    // MARK: - 2 · The ceiling arithmetic, now inside a gate (END-TO-END BEHAVIOUR)

    /// Re-derives every parsed row through the shipped `FlashGuard.effectiveFieldHz` at the
    /// shipped phase-rate cap and asserts the WCAG ceiling. This computation exists today
    /// only in the suite no gate compiles.
    func testEveryBudgetRowStaysUnderTheWCAGCeiling() throws {
        let source = try tableSource()
        guard !source.isEmpty else { return }
        let rows = parsedRows(source)
        XCTAssertGreaterThanOrEqual(rows.count, LookBlendMap.library.count, """
        Parsed only \(rows.count) budget rows but the library has \(LookBlendMap.library.count) \
        looks. The table's row FORMAT changed and this guard is now reading less than it \
        claims. Fix the parser in the same commit, do not lower this bound.
        """)
        for row in rows {
            let hz = FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                                 phaseMultiplier: row.multiplier,
                                                 folds: row.folds)
            XCTAssertLessThanOrEqual(hz, FlashGuard.maxFlashHz, """
            Look "\(row.name)" computes \(hz) Hz at the shipped phase cap \
            (\(FlashGuard.maxPulseRateHz) Hz × \(row.multiplier)\(row.folds ? ", folded ×2" : "")), \
            above the \(FlashGuard.maxFlashHz) Hz WCAG 2.3.1 ceiling. This is a photosensitive \
            seizure risk, not a style question. Either lower the look's phase multiplier in \
            the shader or take the look out of the library.
            """)
        }
    }

    // MARK: - 3 · The parser cannot silently cover less than it says (SOURCE-TEXT SCAN)

    /// A row whose multiplier is a symbol is invisible to `Double(...)`. Exactly one such
    /// symbol exists today; pinning the set means a new one goes red here instead of quietly
    /// dropping its look out of claim 2.
    func testTheOnlySymbolicMultiplierIsTheRingsDamping() throws {
        let source = try tableSource()
        guard !source.isEmpty else { return }
        XCTAssertEqual(Self.symbolicMultipliers.count, 1)
        XCTAssertNotNil(Self.symbolicMultipliers["FlashGuard.ringsPhaseDamping"])
        // Every `FlashGuard.` token used as a multiplier inside the table must be one we resolve.
        for rawLine in source.split(separator: "\n") {
            let line = String(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
            guard line.contains("(\""), line.contains("FlashGuard.") else { continue }
            let known = Self.symbolicMultipliers.keys.contains { line.contains($0) }
            XCTAssertTrue(known, """
            A budget row uses a FlashGuard symbol this guard does not resolve: \(line.trimmingCharacters(in: .whitespaces))
            Add it to `symbolicMultipliers` so claim 2 keeps covering every row, otherwise \
            that look silently drops out of the ceiling check.
            """)
        }
    }
}
