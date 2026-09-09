// TheDepthLookGetsTheDishSolveTests.swift
// Echoel — every shader field that READS the dish solve is inside the gate that WRITES it.
//
// WHY IT EXISTS (#1152, measured). `MetalBioRenderer` solves `FaradayDish` once per frame and
// writes three uniforms (`dishK`, `dishStrength`, `dishHex`). #1101 introduced that solve for
// ONE consumer, `fieldDish`, and gated it on the Dish style index — correctly, with the
// justification written at the line: outside that style "nothing reads them".
//
// Slice 2 of the caustics work then wired a SECOND consumer. `styleField` hands
// `fieldDepthCaustics` the same `u_dishK` / `u_dishStrength`, deliberately — its own comment
// says "the same gravity–capillary solve `fieldDish` renders from above … one experiment
// drawn twice". The gate was not widened. The premise of a correct comment was removed by a
// later slice, and nothing was watching the premise.
//
// WHAT THAT COST, so this file's value is not abstract. `dishStrength` defaults to 0 and the
// gate held its only writer, so with Depth live and Dish not, it stayed 0 forever. In
// `fieldDepthCaustics` strength 0 ⇒ φ = 0 ⇒ det J = 1 at all three depths ⇒ `lit` = 1 ⇒
// `net` = 1 / 2.5 = 0.40 at EVERY pixel — mathematically constant, one flat grey, no caustic
// network at all. Depth is in `LookBlendMap.defaultSequence` and Dish is not, so that was the
// DEFAULT rendering of a curated look, not an edge case.
//
// ⚠️ WHY THIS DOES NOT PIN A LIST OF INDICES. A hand-written {2, 7} would be a memory, and a
// memory is exactly what failed here — the third consumer would inherit nothing, which is the
// same shape as `EveryLookHasAFlashBudgetTests`' reason for existing. Claim 1 instead DERIVES
// the reader set from `styleField`'s own dispatch: whichever bucket passes `u_dishK` is a
// reader, whatever it is called and however many there are.
//
// ⚠️ AND WHY EVERY CLAIM IS A POSITIVE SCAN. The retraction at the gate necessarily QUOTES the
// struck clause, so a negative scan for that clause would match the retraction and go red on a
// correct tree — the self-referential needle trap this repo has now paid for three times
// (#1142, #1144, #1147). Claim 3 asserts the true sentence is PRESENT; it never asserts an
// absence.

import Foundation
import XCTest

final class TheDepthLookGetsTheDishSolveTests: XCTestCase {

    private static let metalView = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func raw(_ relativePath: String) throws -> String {
        let path = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            XCTFail("ANCHOR MISSING: \(relativePath) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// The style index of every `styleField` bucket whose field call takes `u_dishK`.
    ///
    /// `styleField` dispatches with half-open bands written as `si < N.5`, so the bucket that
    /// upper bound belongs to is index `N.5 - 0.5`. Parsing the dispatch rather than the field
    /// functions is deliberate: a function that merely MENTIONS the uniform in a comment is not
    /// a reader; the argument list at the call site is.
    private func dishSolveReaderIndices(in source: String) -> Set<Int> {
        var found: Set<Int> = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.contains("field = field"), s.contains("u_dishK"),
                  let siRange = s.range(of: "si < ") else { continue }
            let rest = s[siRange.upperBound...]
            let digits = rest.prefix { $0.isNumber || $0 == "." }
            guard let bound = Double(digits) else { continue }
            found.insert(Int((bound - 0.5).rounded()))
        }
        return found
    }

    // MARK: - 1 · Every reader the shader has is a style the gate lets through

    /// The load-bearing claim. It goes red the day a THIRD field function is handed the dish
    /// solve without the CPU gate learning about it — which is precisely how Depth shipped flat.
    func testEveryShaderReaderOfTheDishSolveIsInsideTheCPUGate() throws {
        let src = try raw(Self.metalView)
        guard !src.isEmpty else { return }

        let readers = dishSolveReaderIndices(in: src)
        XCTAssertFalse(readers.isEmpty, """
            No `styleField` dispatch line was found passing `u_dishK` to a field function. \
            Either the dish solve lost all its consumers (then this file and the solve itself \
            should go together) or the dispatch was reformatted and this parser stopped \
            matching. A parser that matches nothing is a finding, never a pass.
            """)

        // The gate's own bands, read from the source rather than remembered.
        var gated: Set<Int> = []
        for name in ["dishStyleIndex", "depthCausticsStyleIndex"] {
            guard let decl = src.range(of: "static let \(name): Float = ") else { continue }
            let digits = src[decl.upperBound...].prefix { $0.isNumber }
            if let v = Int(digits) { gated.insert(v) }
        }

        for index in readers.sorted() {
            XCTAssertTrue(gated.contains(index), """
                Shader style index \(index) is handed `u_dishK` / `u_dishStrength` by \
                `styleField`, but `MetalBioRenderer.rendersFromDishSolve` does not cover it — \
                so on any frame where that look is live WITHOUT another gated look, the \
                `FaradayDish` solve never runs and those uniforms hold their defaults \
                (`dishK` 25, `dishStrength` 0).

                THAT IS NOT "SLIGHTLY OFF". With strength 0 the caustics determinant is 1 at \
                every depth, so the field is a CONSTANT across the whole screen — a flat wash, \
                the exact defect #1152 repaired for Depth.

                Repair: name the index next to `dishStyleIndex` / `depthCausticsStyleIndex` and \
                widen `rendersFromDishSolve`, in the SAME commit as the shader change. Then \
                re-derive that look's `FlashGuard` row only if the new terms carry the PHASE — \
                a music-level envelope and a pitch do not.

                Gate covers: \(gated.sorted()) · shader readers: \(readers.sorted())
                """)
        }
    }

    // MARK: - 2 · The gate asks the mirror, not `==`

    /// `LookBlendMap.rendersAsRings` had to be retracted for claiming to mirror the renderer
    /// while testing equality. This pins that the dish gate did not repeat it.
    func testTheGateAsksTheShaderMirrorForBothStyleSlots() throws {
        let src = try raw(Self.metalView)
        guard !src.isEmpty else { return }

        XCTAssertTrue(src.contains("private static func rendersFromDishSolve(_ index: Float) -> Bool"), """
            `rendersFromDishSolve` is gone or renamed. It is the one place that answers "would \
            the renderer hand this style the dish solve", and it answers by mirroring \
            `styleField`'s half-open buckets after the same [0, 9] clamp — not by `==`.
            """)
        XCTAssertTrue(src.contains("Self.rendersFromDishSolve(uniforms.style)"), """
            The per-frame gate no longer asks `rendersFromDishSolve` for the PRIMARY style.
            """)
        XCTAssertTrue(src.contains("Self.rendersFromDishSolve(uniforms.styleB)"), """
            The per-frame gate no longer asks `rendersFromDishSolve` for the B style. Both \
            slots matter: a blend renders BOTH fields, so the solve has to run when either \
            side reads it.
            """)
    }

    // MARK: - 3 · The two homes tell the same true story

    /// POSITIVE scan (see the header): the retraction is present at the gate, and the shader's
    /// own claim that Depth renders the dish's surface is present at the field function. Two
    /// homes, one fact. No claim of absence anywhere in this file.
    func testBothHomesSayTheDepthLookRendersTheDishSurface() throws {
        let src = try raw(Self.metalView)
        guard !src.isEmpty else { return }

        XCTAssertTrue(src.contains("THE SURFACE IS THE DISH'S"), """
            `fieldDepthCaustics` no longer states that its surface IS the dish's. That sentence \
            is the DESIGN INTENT the CPU gate is built to satisfy; if the looks were genuinely \
            separated, the gate must stop covering Depth in the same commit.
            """)
        XCTAssertTrue(src.contains("#1152"), """
            The retraction at the dish gate is gone. It records that "nothing reads them" was \
            true when written and false when shipped, and that the cost was a constant 0.40 \
            field. Keep it: the next reader's instinct will be to narrow this gate again for \
            the same performance reason that was correct the first time.
            """)
    }
}
