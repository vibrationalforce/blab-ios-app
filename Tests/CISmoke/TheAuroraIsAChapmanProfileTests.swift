// TheAuroraIsAChapmanProfileTests.swift
// Echoel — the Aurora look's physics, in the BLOCKING bundle.
//
// #1125 replaced a hand-shaped symmetric band with the production profile a precipitating
// electron beam actually makes in an exponential atmosphere, and gave the look the sounding
// pitch it had never received.
//
// ⛔ THE DEFECT THIS PINS WAS HIDDEN BY A TRUE SENTENCE. The old header said "Colour comes
// from the tone … a real pitch→hue aurora". True of the APP — `toneCloudColour` places the
// sounding notes — and false of the FUNCTION, which returns a scalar and never saw `toneHz`
// at all. A reader checking whether pitch reached this look found a sentence saying yes.
// That is why claim 1 pins the PARAMETER and the CALL rather than any prose about them.
//
// ⚠️ WHAT IS PROVEN AND WHAT IS NOT. Claim 2 is arithmetic on the real function transcribed
// into Swift, so the asymmetry — knife-sharp below, diffuse above — is a proof. Claims 1, 3
// and 4 are source-text pins: no test here executes MSL. Whether the curtain LOOKS like an
// aurora is a device question and stays one.
// NEEDS-FOUNDER-VERIFY: pick the Aurora look and play a rising line — the vertical rays
// should visibly multiply as the pitch climbs, and the curtain's lower edge should stay
// much crisper than its top.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAuroraIsAChapmanProfileTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(Self.renderer), encoding: .utf8)
    }

    /// The shader text with comment lines removed. Load-bearing, not tidiness: four guards in
    /// one day were falsified by a needle matching the PROSE written about the thing it
    /// measures, this file's own header included.
    private func code(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The Chapman production profile exactly as the shader writes it, unit peak at u = 0.
    private func chapman(_ u: Double) -> Double {
        let e = exp(-min(max(u, -6.0), 40.0))
        return exp(min(max(1.0 - u - e, -30.0), 0.0))
    }

    // MARK: - 1 · The sounding pitch reaches this look at all

    func testTheAuroraTakesTheSoundingPitch() throws {
        let src = code(try source())
        XCTAssertTrue(src.contains("float fieldAurora(float2 p, float toneHz,"), """
            `fieldAurora` no longer declares `toneHz`. Before #1125 it never did, while sitting \
            in LookBlendMap.defaultSequence — every user saw a look the pitch could not touch. \
            This is the same defect Slice 1 removed from fieldWater and #1117 from \
            fieldDepthCaustics; do not let it come back by dropping the parameter.
            """)
        XCTAssertTrue(src.contains("field = fieldAurora(pf, toneHz,"), """
            The dispatch in `styleField` stopped passing `toneHz` to `fieldAurora`. A parameter \
            nothing supplies is the same defect as no parameter, one line further away.
            """)
    }

    // MARK: - 2 · The profile is sharp below and diffuse above — the actual physics

    func testTheCurtainIsSharpBelowAndDiffuseAbove() {
        // Unit peak exactly at the production maximum. If this moves, the curtain's brightness
        // is no longer normalised and the flash budget's amplitude assumption is void.
        XCTAssertEqual(chapman(0), 1.0, accuracy: 1e-12,
                       "the Chapman profile must peak at exactly 1 at u = 0")

        // The asymmetry IS the look. Three scale heights below the peak the beam is absorbed
        // by a double exponential; three above it fades by a single one. Four orders of
        // magnitude apart is what makes a real curtain's lower border read as a knife edge.
        XCTAssertLessThan(chapman(-3), 1e-5, """
            the lower border is no longer sharp — q(−3) must collapse, because below the \
            production peak the surviving flux falls as e^(−e^(−u)), not as e^(−u).
            """)
        XCTAssertGreaterThan(chapman(3), 0.10, """
            the top is no longer diffuse — q(+3) must still be clearly lit. A symmetric \
            profile passes the sharpness check above and fails here, which is exactly what \
            the band this replaced did.
            """)
        XCTAssertGreaterThan(chapman(3) / chapman(-3), 1e4,
                             "the up/down contrast is the whole physical claim of this look")

        // Single-peaked, which is what makes the flash derivation's "the fold is the SWEEP"
        // reasoning hold: a pixel sees ONE maximum per pass, twice per drift cycle.
        var rising = true, falling = true
        var prev = chapman(-6)
        for i in stride(from: -5.9, through: 0.0, by: 0.1) {
            let v = chapman(i); if v < prev { rising = false }; prev = v
        }
        prev = chapman(0)
        for i in stride(from: 0.1, through: 6.0, by: 0.1) {
            let v = chapman(i); if v > prev { falling = false }; prev = v
        }
        XCTAssertTrue(rising && falling, """
            the profile is no longer single-peaked. Two maxima per pass would DOUBLE Aurora's \
            flash count — from 1.75 Hz to 3.50, straight over the 3 Hz WCAG law. (Until \
            #1127 it sat on exactly 3.00 with zero margin, so this was even less forgiving.)
            """)
    }

    // MARK: - 3 · The rays are spatial — they must not smuggle in a phase term

    func testTheRayStriationCarriesNoPhase() throws {
        let src = code(try source())
        guard let open = src.range(of: "float fieldAurora(float2 p, float toneHz,"),
              let close = src.range(of: "\n    }", range: open.upperBound ..< src.endIndex) else {
            return XCTFail("fieldAurora's body could not be located")
        }
        let body = String(src[open.upperBound ..< close.lowerBound])
        guard let rayLine = body.split(separator: "\n").first(where: { $0.contains("float ray =") }) else {
            return XCTFail("the ray striation line is gone — claim 1's pitch path has no consumer")
        }
        XCTAssertFalse(rayLine.contains("phase"), """
            the ray term now carries `phase`. `rays` multiplies a SPATIAL coordinate, exactly \
            as fieldWater's `s` does — that is why the pitch could be wired into this \
            look without reopening its flash budget at all. Adding a phase term here \
            costs margin and means re-deriving the row in the same commit.
            """)
        XCTAssertTrue(rayLine.contains("p.x"), """
            the striation stopped running vertically. Auroral rays are FIELD-ALIGNED — they \
            trace B up the picture — so the modulation belongs on x, never on y.
            """)
    }

    // MARK: - 4 · The swell comes from the body, not the clock

    func testTheSwellReadsTheBreathAndNotTheClock() throws {
        let src = code(try source())
        guard let open = src.range(of: "float fieldAurora(float2 p, float toneHz,"),
              let close = src.range(of: "\n    }", range: open.upperBound ..< src.endIndex) else {
            return XCTFail("fieldAurora's body could not be located")
        }
        let body = String(src[open.upperBound ..< close.lowerBound])
        guard let swell = body.split(separator: "\n").first(where: { $0.contains("float swell =") }) else {
            return XCTFail("""
                the swell line is gone. Before #1127 it read `0.8 + 0.2*sin(phase*0.5)` — the \
                CLOCK wearing the body's name, in a function that already received `breath` as \
                a parameter and never read it. That second phase-bearing factor is what made \
                this the app's only zero-margin row.
                """)
        }
        XCTAssertTrue(swell.contains("breath"), """
            the swell stopped reading the real breath signal. This is not a style preference: \
            `breath` is a ≤0.5 Hz BODY signal and carries no phase, which is the entire reason \
            Aurora's budget could fall from 1.20 to 0.70.
            """)
        XCTAssertFalse(swell.contains("phase"), """
            the swell reads `phase` again. That restores the 0.50 sideband, puts Aurora back on \
            exactly 3.00 Hz with zero margin, and silently falsifies the seven prose homes that \
            #1127 corrected — including `maxPulseRateHz`'s own doc.
            """)
    }

    // MARK: - 5 · Counterweight: the row that body signal bought, and who is tightest now

    func testTheAuroraBudgetRowFellToSeventy() {
        guard let row = FlashGuard.fieldBudget(forStyle: 5) else {
            return XCTFail("Aurora lost its flash budget row — nil means UNKNOWN, not free")
        }
        XCTAssertEqual(row.name, "Aurora")
        XCTAssertEqual(row.phaseMultiplier, 0.70, accuracy: 1e-12, """
            Aurora's multiplier moved. 0.70 is the drift sweep ALONE: `wave` oscillates at \
            0.35·phase and its peak crosses a fixed pixel twice per cycle. #1125 rewrote the \
            profile and deliberately left the number at 1.20; #1127 deleted the second factor \
            by giving the swell to the real breath signal. Anything that moves this again must \
            re-derive it AND carry the prose homes that quote it — `maxPulseRateHz`'s doc names \
            the binding row by name, so it goes stale silently.
            """)
        XCTAssertEqual(row.effectiveHz, 1.75, accuracy: 1e-9,
                       "Aurora should now sit at 1.75 Hz with +1.25 of margin")

        // The point of the whole slice: the app no longer HAS a zero-margin row, and the
        // tightest one is a different look. Derived from the table, never named twice.
        guard let worst = FlashGuard.fieldBudgets.max(by: { $0.effectiveHz < $1.effectiveHz }) else {
            return XCTFail("the flash budget table is empty — nothing was checked")
        }
        XCTAssertEqual(worst.name, "Rings", """
            the binding row is now \(worst.name). `maxPulseRateHz`'s doc, this file, \
            TheFlashCeilingIsOneNumberTests and TheWaterLookObeysCapillaryDispersionTests all \
            name Rings as the tightest look — #456: the prose moves in every home, not only \
            the one being edited.
            """)
        XCTAssertLessThan(worst.effectiveHz, FlashGuard.maxFlashHz, """
            some row is back ON or over the WCAG ceiling. Since #1127 every row has real \
            margin; a row sitting exactly at the limit is the state this slice existed to end.
            """)
    }
}
