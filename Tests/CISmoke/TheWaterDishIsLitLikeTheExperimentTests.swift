// TheWaterDishIsLitLikeTheExperimentTests.swift
// Echoel — #1101: the water dish reaches the shader, and the shader draws the experiment's light.
//
// WHAT THIS GUARDS. Slice W1 (#1100) pinned the physics of a dish of water on a speaker in
// `Core/FaradayDish`. This slice gives it its ONE production caller (`MetalBioView`'s draw
// loop) and a field function, `fieldDish`, in the shader slot that held the retired Plasma
// look. The claims here are the joints a later edit can silently break:
//   · the CPU solves `FaradayDish` for the EASED tone and eases only the STRENGTH (the
//     luminance-bearing quantity) — a snapped strength would step a full-screen luminance;
//   · the three results cross to the GPU as the LAST three floats of BOTH uniform structs, in
//     the same order — a layout mismatch renders garbage, not an error, and no gate sees it;
//   · slot 2 dispatches to `fieldDish` with those three uniforms;
//   · the field's only phase-bearing term is `sin(phase * 0.4)` — the flash budget (0.4,
//     folds: false → 1.00 Hz) is derived from that one line and must move with it;
//   · silence is a MIRROR: the field mixes from a lamp reflection into the caustic net by
//     `strength`, so a quiet bar cannot ripple.
//
// KIND (§1): claims 1–5 are **SOURCE-TEXT SCANS** over `MetalBioView.swift` (the shader is a
// string literal and the draw loop is `private`); claim 6 is END-TO-END on `FaradayDish`.
// §3: on the parent tree claims 1–5 are red (no `fieldDish`, no dish uniforms) and claim 6 does
// not compile (`latticeHexagonality` is new) — nothing here has a parent verdict.
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether it LOOKS like the founder's photo. That is a device
// probe, and it waits for Slice W3's door (`LookBlendMap.library` row + flash-budget row in one
// commit). Until then style 2 is unreachable: a persisted 2 is snapped to the sequence's first
// look on appear, so nothing a user can reach changed in this slice.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheWaterDishIsLitLikeTheExperimentTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func code() throws -> String {
        SourceText.codeOnly(try String(contentsOfFile: repoRoot().appendingPathComponent(Self.view).path,
                                       encoding: .utf8))
    }

    private func raw() throws -> String {
        try String(contentsOfFile: repoRoot().appendingPathComponent(Self.view).path, encoding: .utf8)
    }

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

    // MARK: - 1 · The CPU solves the physics for the eased tone and eases only the strength

    func testTheDrawLoopSolvesTheDishForTheEasedToneAndEasesTheStrength() throws {
        let c = try code()
        XCTAssertEqual(occurrences(of: "FaradayDish.response(driveHz: Double(uniforms.toneHz),", in: c), 1, """
            the draw loop no longer solves `FaradayDish` for the EASED `uniforms.toneHz` (or does \
            so twice). The lattice must glide with the pitch exactly as the Water look does; \
            solving for `target.toneHz` would snap the ripple spacing on every note change.
            """)
        XCTAssertTrue(c.contains("drive: Double(dishDriveTarget))"), """
            the dish is no longer driven by `dishDriveTarget` (music level + finger energy). \
            The threshold comparison in `FaradayDish` is what makes a quiet bar a mirror; feed \
            it a constant and every pitch below the reach ripples forever.
            """)
        XCTAssertTrue(c.contains("dishDriveTarget = min(max(musicLevel + 0.5 * touchE, 0), 1)"), """
            the drive is no longer the live master level plus half the finger energy, clamped \
            0…1. `FaradayDish.response` clamps too, but the CHANNEL is the claim: the dish must \
            follow what actually sounds, not a dial.
            """)
        XCTAssertTrue(c.contains("uniforms.dishStrength = Self.ease(uniforms.dishStrength,"), """
            `dishStrength` is no longer EASED. It multiplies a full-screen luminance; a note \
            onset that snapped it from 0 to 1 would be a dark→bright step over the whole \
            picture, i.e. a flash candidate. Ease it (tau 0.5 s, slower than `intensity`).
            """)
        XCTAssertTrue(c.contains("tau: 0.5, dt: dt)"), "the dish strength's time constant line is gone")
        XCTAssertTrue(c.contains("FaradayDish.latticeHexagonality("), """
            the lattice symmetry no longer comes from `FaradayDish.latticeHexagonality`. The \
            square→hexagon direction is measured physics; its mapping has ONE home in the core.
            """)
    }

    // MARK: - 2 · The three uniforms are the tail of BOTH structs, in the same order

    func testTheDishUniformsAreTheTailOfBothStructsInTheSameOrder() throws {
        let r = try raw()
        // Swift side: the three `var`s follow `structureAmt` and nothing follows them but `}`.
        guard let swiftStruct = r.range(of: "private struct BioUniforms {"),
              let swiftEnd = r.range(of: "\n}\n", range: swiftStruct.upperBound ..< r.endIndex)
        else { return XCTFail("BioUniforms struct not found") }
        let swift = SourceText.codeOnly(String(r[swiftStruct.lowerBound ..< swiftEnd.upperBound]))
        let swiftVars = swift.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("var ") }
            .map { String($0.dropFirst(4).prefix { $0 != ":" }) }
        XCTAssertEqual(Array(swiftVars.suffix(4)), ["structureAmt", "dishK", "dishStrength", "dishHex"], """
            the Swift `BioUniforms` no longer ends with structureAmt · dishK · dishStrength · \
            dishHex, in that order; found \(swiftVars.suffix(4)). The MSL struct is pinned to \
            the same tail below — move both or the GPU reads the wrong floats.
            """)
        // MSL side: the same three names close the `Uniforms` struct.
        XCTAssertTrue(r.contains("float textureAmt; float glitterAmt; float structureAmt;\n                      float dishK; float dishStrength; float dishHex; };"), """
            the MSL `Uniforms` no longer ends with `structureAmt; dishK; dishStrength; dishHex; };`. \
            Metal has no layout check against `MemoryLayout<BioUniforms>.stride` — a mismatch \
            here silently renders garbage on device.
            """)
    }

    // MARK: - 3 · Slot 2 is the dish, fed those three uniforms

    func testSlotTwoDispatchesToTheDishWithItsThreeUniforms() throws {
        let c = try code()
        XCTAssertEqual(occurrences(of: "else if (si < 2.5)  field = fieldDish(pf, u_dishK, u_dishStrength, u_dishHex, phase, coh);", in: c), 1, """
            `styleField`'s slot-2 bucket no longer calls `fieldDish(pf, u_dishK, u_dishStrength, \
            u_dishHex, phase, coh)`. The dish lives in the former Plasma slot; every comment home \
            that names slot 2 (LookBlendMap, EchoelStudioView, BioUniforms, update()) says so — \
            if the slot moved, move them all (#456).
            """)
        XCTAssertEqual(occurrences(of: "u.dishK, u.dishStrength, u.dishHex)", in: c), 2, """
            `styleField` is not handed the three dish uniforms at BOTH call sites (A and B look). \
            With one missing, blending INTO the dish renders it with stale or zero uniforms.
            """)
        XCTAssertEqual(occurrences(of: "float fieldDish(float2 p, float k, float strength, float hex, float phase, float coh) {", in: c), 1,
                       "`fieldDish`'s signature changed — re-check the dispatch line and this file's pins")
    }

    // MARK: - 4 · The only phase-bearing term is pinned — the flash budget hangs on it

    func testTheFieldsOnlyPhaseTermIsTheSlowBreatheAndNothingFolds() throws {
        let c = try code()
        guard let start = c.range(of: "float fieldDish("),
              let end = c.range(of: "\n    }\n", range: start.upperBound ..< c.endIndex)
        else { return XCTFail("fieldDish body not found") }
        let body = String(c[start.lowerBound ..< end.upperBound])
        XCTAssertEqual(occurrences(of: "phase", in: body) - occurrences(of: "float phase", in: body), 1, """
            `fieldDish` reads `phase` more (or less) than once. Its flash budget — (0.4, \
            folds: false) → 1.00 Hz — is derived from exactly ONE phase-bearing term; a second \
            one is a sideband and the budget row must be re-derived, not assumed.
            """)
        XCTAssertTrue(body.contains("float breathe = 0.85 + 0.15 * sin(phase * 0.4);"), """
            the dish's phase term is no longer `0.85 + 0.15 * sin(phase * 0.4)`. The multiplier \
            0.4 IS the budget (0.4 × 2.5 Hz = 1.00 Hz); the 0.15 swing is what keeps `c` inside \
            0…0.88. Change either and re-derive the row in `FlashGuardTests` in the same commit.
            """)
        XCTAssertFalse(body.contains("abs("), "an abs() on a phase-bearing quantity FOLDS the rate — re-derive the budget")
        XCTAssertTrue(body.contains("float caustic = (1.0 - c) / (1.0 - c * h);"), """
            the caustic law changed. 1/(1 − c·h) is the linearised lens law of a lit dish floor \
            and is MONOTONE in c at fixed h, which is why the single phase term does not fold.
            """)
        XCTAssertTrue(body.contains("clamp(0.88 * strength * breathe, 0.0, 0.88)"), """
            `c` is no longer capped below 1. At c → 1 the caustic 1/(1 − c·h) is unbounded at a \
            crest — a white-out, and a division that can reach zero.
            """)
    }

    // MARK: - 5 · Silence is a mirror

    func testASilentSpeakerShowsTheLampInAStillSurface() throws {
        let c = try code()
        guard let start = c.range(of: "float fieldDish("),
              let end = c.range(of: "\n    }\n", range: start.upperBound ..< c.endIndex)
        else { return XCTFail("fieldDish body not found") }
        let body = String(c[start.lowerBound ..< end.upperBound])
        XCTAssertTrue(body.contains("float mirror = 0.55 + 0.30 * exp(-dot(p, p) * 2.5);"), """
            the flat-surface term is gone. Below the Faraday threshold a real dish is a MIRROR \
            of the lamp — a soft central reflection, no ripples. Without this the field has \
            nothing to show at strength 0 and the founder's "silence = flat" reading is lost.
            """)
        XCTAssertTrue(body.contains("return clamp(mix(mirror, net, clamp(strength, 0.0, 1.0)), 0.0, 1.0);"), """
            the field no longer mixes mirror → caustic net by `strength`. That mix is what makes \
            silence flat and a loud bass note a lattice; any other gate re-couples the picture \
            to a dial instead of to the threshold physics.
            """)
    }

    // MARK: - 6 · The hexagonality the shader receives is the core's, with its direction

    func testTheShaderReceivesASymmetryThatRisesWithPitch() throws {
        let low = try XCTUnwrap(FaradayDish.response(driveHz: 60, drive: 1))
        let mid = try XCTUnwrap(FaradayDish.response(driveHz: 261.63, drive: 1))
        let high = try XCTUnwrap(FaradayDish.response(driveHz: 880, drive: 1))
        let h = [low, mid, high].map { FaradayDish.latticeHexagonality(capillaryFraction: $0.capillaryFraction) }
        XCTAssertEqual(h[0], 0, "a 60 Hz bass dish must be drawn as squares")
        XCTAssertGreaterThan(h[1], 0.8, "middle C must be mostly hexagonal (measured 0.916)")
        XCTAssertEqual(h[2], 1, accuracy: 1e-9, "880 Hz must be fully hexagonal")
        XCTAssertTrue(h[0] <= h[1] && h[1] <= h[2], "symmetry must not fall with pitch — the measured direction is up")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
