// TheRetiredLooksHaveDerivedRatesTests.swift
// Echoel — the five retired looks' flash rates, in the BLOCKING bundle.
//
// #1130. `FlashGuard.fieldBudget(forStyle:)` has said since #1123 that a missing row means
// UNKNOWN, not free — and named the five retired styles (1 Cymatics, 4 Prism, 6 Lissajous,
// 8 Scope, 9 Fractal) as having "no rows precisely because nobody re-derived them". That was
// true, and it cost nothing to leave true, because no UI can select them.
//
// ⭐ DERIVING THEM FOUND ONE THAT IS OVER THE LAW. Four come out legal at the app's 2.5 Hz
// phase ceiling (Cymatics 1.25 · Prism 2.50 · Lissajous 2.50); **8 Scope comes out at
// 3.90 Hz**, above the 3 Hz WCAG general-flash limit. That is not currently reachable — no
// slider offers it and `EchoelStudioView`'s onAppear migration snaps a persisted retired
// index — but it turns a phrase that read as housekeeping ("nobody re-derived them") into a
// concrete precondition on re-dooring.
//
// ⚠️ WHY THE NUMBERS ARE DOCS AND NOT ROWS, WHICH IS THE WHOLE DESIGN POINT. `fieldBudgets`
// is a "looks a user can select are legal" table: `EveryLookHasAFlashBudgetTests` claim 3
// requires every row to be in `LookBlendMap.library`, and claim 2 requires every row to be
// ≤ the ceiling. Giving Scope a row would correctly turn the blocking suite red. So the
// derivations live at `fieldBudget(forStyle:)` and this guard pins the shader constants they
// were read from.
//
// ⚠️ THIS GUARD FORBIDS NOTHING (#364). Re-dooring any of the five is allowed and would be
// welcome; calming Scope's shader is allowed and would be the RIGHT move. Both make claim 1
// red — that is the point: the message then names the prose to pull in the same commit. A
// guard that made a look permanently unreachable would be the defect, not the safeguard.
//
// ⚠️ WHAT IS PROVEN AND WHAT IS NOT. Claim 2 is arithmetic on `FlashGuard`'s own function and
// is a proof. Claims 1, 3 and 4 are source-text pins; no test here executes MSL. Whether any
// retired look should come back at all is the founder's call, not this file's.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheRetiredLooksHaveDerivedRatesTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"
    private static let guardFile = "Sources/Echoelmusic/Core/FlashGuard.swift"
    private static let mapFile = "Sources/Echoelmusic/Studio/LookBlendMap.swift"

    /// The style indices retired from the UI. Not a copy of a list in prose — claim 3 proves
    /// each one against `LookBlendMap.library` and `FlashGuard.fieldBudgets` at runtime.
    private static let retired = [1, 4, 6, 8, 9]

    private func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 1 · The shader constants the derivations were read from

    func testTheRetiredLooksStillCarryTheConstantsTheRatesWereDerivedFrom() throws {
        let src = try read(Self.renderer)
        // (needle, which look, what it decides)
        let pins: [(String, String, String)] = [
            ("float amp = 0.7 + 0.3 * sin(phase * 0.5);",
             "1 Cymatics", "the ONLY phase term ⇒ multiplier 0.50, monotone ⇒ no fold"),
            ("float shimmer = 0.5 + 0.5 * sin(p.x * 6.0 + phase * 0.6) * cos(p.y * 5.0 - phase * 0.4);",
             "4 Prism", "a PRODUCT of two phase-bearing factors ⇒ sum sideband 0.6 + 0.4 = 1.00"),
            ("float t = phase * 0.5;",
             "6 Lissajous", "the base rate; the 0.8 partial below is SUMMED, not multiplied"),
            ("float y = sin(c * p.y * 3.14159265 + t * 0.8);",
             "6 Lissajous", "the second rate — a DIFFERENCE, so 0.5 stays the fastest, not 0.9"),
            ("return 1.0 - smoothstep(0.0, w, abs(x - y));",
             "6 Lissajous", "the ridge SWEEPS past a fixed pixel twice per cycle ⇒ folds"),
            ("float t = phase * 0.6;",
             "8 Scope", "the base rate"),
            ("+ 0.25 * sin(p.x * k * 2.0 + t * 1.3)",
             "8 Scope", "the FASTEST term, 0.6 × 1.3 = 0.78 — this is what puts Scope over"),
            ("float dist = abs(p.y - wave);",
             "8 Scope", "the beam SWEEPS past a fixed pixel twice per cycle ⇒ folds"),
            ("float t = phase * 0.3;",
             "9 Fractal", "the drift rate — deliberately NOT enough to derive a rate from"),
        ]
        for (needle, look, why) in pins {
            XCTAssertEqual(src.components(separatedBy: needle).count - 1, 1, """
                \(look): the shader line

                    \(needle)

                appears \(src.components(separatedBy: needle).count - 1)× in \(Self.renderer), \
                expected exactly 1. It decides \(why), and that derivation is written as prose \
                at `FlashGuard.fieldBudget(forStyle:)` and quoted in `LookBlendMap.library`'s \
                doc.

                THIS IS NOT A BAN ON CHANGING THE SHADER. Calming Scope is the documented \
                precondition for re-dooring it, and any of the five may come back. What this \
                claim forbids is changing the constant WITHOUT re-deriving: pull \
                `fieldBudget(forStyle:)`'s bullet list and `LookBlendMap.library`'s ⛔ note in \
                the same commit, and if the look is being re-doored, add its row too.
                """)
        }
    }

    // MARK: - 2 · The four legal rates, and Scope's illegal one, are arithmetic

    func testTheDerivedRatesAreWhatTheDocClaims() {
        // Each pair is (multiplier, folds) as derived at `fieldBudget(forStyle:)`.
        let cases: [(String, Double, Bool, Double)] = [
            ("1 Cymatics", 0.50, false, 1.25),
            ("4 Prism", 1.00, false, 2.50),
            ("6 Lissajous", 0.50, true, 2.50),
            ("8 Scope", 0.78, true, 3.90),
        ]
        for (name, multiplier, folds, expected) in cases {
            let hz = FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                                 phaseMultiplier: multiplier, folds: folds)
            XCTAssertEqual(hz, expected, accuracy: 1e-9, """
                \(name): (\(multiplier), folds: \(folds)) at the app's \
                \(FlashGuard.maxPulseRateHz) Hz phase ceiling gives \(hz) Hz, but the doc at \
                `FlashGuard.fieldBudget(forStyle:)` claims \(expected). One of the two is \
                wrong — and the doc is the one a future re-dooring will read.
                """)
        }
        // The finding, stated as an assertion so it cannot quietly stop being true.
        let scope = FlashGuard.effectiveFieldHz(phaseRateHz: FlashGuard.maxPulseRateHz,
                                                phaseMultiplier: 0.78, folds: true)
        XCTAssertGreaterThan(scope, FlashGuard.maxFlashHz, """
            Scope derives at \(scope) Hz and the WCAG ceiling is \(FlashGuard.maxFlashHz). \
            This assertion exists because the whole point of #1130 is that ONE of the five \
            retired looks is over the law. If this goes red, either the shader was calmed \
            (good — re-derive, then this claim and the prose both change) or the ceiling was \
            RAISED (never do that; the epilepsy limit is not a tuning knob).
            """)
    }

    // MARK: - 3 · They are retired: no library row, no budget row, no damping

    func testTheRetiredLooksAreUnreachableAndUnbudgeted() {
        for index in Self.retired {
            XCTAssertFalse(LookBlendMap.library.contains { $0.index == index }, """
                Style \(index) is in `LookBlendMap.library` — it has been re-doored. That is \
                allowed and this guard does not forbid it, but it now needs a \
                `FlashGuard.fieldBudgets` row (claim 3 of `EveryLookHasAFlashBudgetTests` \
                requires one for every library look), and for 8 Scope the shader must be \
                CALMED first because its derived rate is over the ceiling.
                """)
            XCTAssertNil(FlashGuard.fieldBudget(forStyle: index), """
                Style \(index) now has a budget row. If the look was re-doored, delete this \
                index from `retired` above and pull the prose at \
                `FlashGuard.fieldBudget(forStyle:)` and `LookBlendMap.library`. If it was NOT \
                re-doored, the row guards nothing a user can reach.
                """)
        }
        // The fallback the missing rows rely on, and the reason Scope matters: a SINGLE
        // unknown look gets a damping factor of exactly 1.0, because its union equals the
        // ceiling and the function damps only when the union EXCEEDS it.
        let damping = FlashGuard.blendPhaseDamping(styleA: 8, styleB: 8, blend: 0)
        XCTAssertEqual(damping, 1.0, accuracy: 1e-12, """
            A single unknown look now damps by \(damping) instead of 1.0. That is a change to \
            `blendPhaseDamping`'s semantics, not a bug fix on its own — say at the function \
            what an unknown look is now assumed to be, and update \
            `fieldBudget(forStyle:)`'s "SCOPE IS WHY THIS FALLBACK IS NOT THEORETICAL" note, \
            which argues from exactly this 1.0.
            """)
    }

    // MARK: - 4 · The prose that carries the derivations still carries them

    func testBothProseHomesStillStateTheDerivedRates() throws {
        let flashGuard = try read(Self.guardFile)
        for needle in ["(0.50, folds: false) → **1.25 Hz.**",
                       "(1.00, folds: false) → **2.50 Hz.**",
                       "(0.50, folds: true) → **2.50 Hz.**",
                       "(0.78, folds: true) → **3.90 Hz — OVER THE 3 Hz LAW.**",
                       "genuinely UNKNOWN"] {
            XCTAssertEqual(flashGuard.components(separatedBy: needle).count - 1, 1, """
                `\(Self.guardFile)` no longer states "\(needle)" exactly once. The four \
                derivations and Fractal's honest unknown are the payload of #1130 — without \
                them the numbers in claim 2 have no home a reader would find, and the file \
                falls back to the "nobody re-derived them" it replaced.
                """)
        }
        let map = try read(Self.mapFile)
        for needle in ["8 Scope comes out at 3.90 Hz",
                       "Re-adding a row is the LAST step of re-dooring"] {
            XCTAssertEqual(map.components(separatedBy: needle).count - 1, 1, """
                `\(Self.mapFile)` no longer states "\(needle)" exactly once. That doc used to \
                say retirement was "reversible by re-adding a row", which is false for Scope \
                — a future session reads it while deciding how to bring a look back, so the \
                correction has to stay next to the library, not only in `FlashGuard`.
                """)
        }
    }
}
