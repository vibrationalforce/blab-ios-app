// TheVisualBreathIsGatedTests.swift
// Echoel — the ONE live visual breath read, in the BLOCKING bundle.
//
// #1133. `BioSampleFrame.breathPhase` has no unknown sentinel of its own — 0 is a real
// position (exhale start) — so every consumer must gate on `hasMeasuredBreath`, and
// `EngineBus` says exactly that: "anything DISPLAYING a breath value must gate on this."
// Three SOUND consumers do it through `breathPhaseForSound`. The renderer, the one live
// VISUAL consumer, read the raw value and shaped it with `sin(π·x)`.
//
// ⭐ WHAT THAT COST ON A SHIPPED PATH. `PolarH10BioPublisher` and
// `FaceExpressionBioPublisher` write the literal `breathPhase: 0` on every frame — neither
// derives respiration at all — and the camera's pulse-hold republish forwards a held phase
// with `breathRate: 0`. Through the hump, 0 maps to 0: the shader's `spread` pinned at its
// narrowest 0.85 and Aurora's swell at its floor 0.80, permanently, for a fully wired real
// source. The picture froze at full exhale and nothing on screen could say so. This is the
// same defect `breathPhaseForSound` was written to fix on the audio side, one surface over
// — the #496/#1131 shape again: one channel corrected, its neighbour not.
//
// ⚠️ WHY THE FIX IS NOT "USE `breathPhaseForSound` HERE", AND CLAIM 3 EXISTS TO PROVE IT.
// That accessor also returns 0.5 when unmeasured, so it LOOKS like the fix — but it returns
// a PHASE, and this call site feeds phases through the hump, where 0.5 becomes
// `sin(π/2) = 1.0`: the WIDEST spread and the FULLEST swell. It would have swapped one wrong
// extreme for the other. The neutral has to be chosen for the SHAPED value, so the gate
// skips the shaping and hands over the same 0.5 the no-frame branch already uses.
//
// ⚠️ WHAT IS NOT FIXED HERE, said plainly so nobody reads more into it. On the camera path
// `breathPhase` carries `RespirationEstimator.amplitude` — a normalised SINE position
// (1 = inhale peak, 0.5 = inhale onset, 0 = exhale trough), not the sawtooth the field's
// contract promises. Through the hump a sine peaks at MID-breath and falls to zero at BOTH
// lung extremes, so what the founder sees swelling is not the inhale. That is a SECOND defect
// on the same line and it is deliberately not touched here: it needs a decision about what
// the contract should be, not a gate.
//
// ⛔ THIS PARAGRAPH SAID "an ENVELOPE" AND SO DID `EngineBus`, WHICH IS WHERE I TOOK IT FROM;
// #1135 measured the estimator and both were wrong. The CONCLUSION above survives unchanged —
// mid-breath peak, dark at both extremes, double rate — but the reason does not, and the
// reason is the half that decides the repair: an envelope would carry no phase, while this
// sine does, so honouring the contract is a shift of terms the estimator already holds
// (`lastCrossT`, `periodEMA`) rather than a new estimator. The corrected derivation lives on
// `EngineBus.breathPhase`; the arithmetic is pinned by
// `TheBreathPhaseIsASineNotAnEnvelopeTests`.
//
// ⚠️ PROVEN vs NOT. Claim 3 is arithmetic and is a proof. Claims 1, 2 and 4 are source-text
// pins. Whether the picture now rests where it should is the founder's eye —
// NEEDS-FOUNDER-VERIFY: with the chest strap (which never measures breath) the visual should
// sit mid-width and mid-swell instead of at its narrowest and dimmest.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVisualBreathIsGatedTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"

    private func code(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: relativePath)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · The visual read consults hasMeasuredBreath

    func testTheRendererGatesItsBreathReadOnAMeasurement() throws {
        let view = try code(Self.renderer)
        XCTAssertEqual(count("breath: bio.map { $0.hasMeasuredBreath", in: view), 1, """
            The renderer's `breath:` argument no longer opens with the `hasMeasuredBreath` \
            gate. `breathPhase` has no unknown sentinel — 0 is exhale start — so an ungated \
            read cannot tell a performer at full exhale from a source that never measures \
            breath at all, and two shipped publishers (Polar strap, face camera) write the \
            literal 0 on every frame.
            """)
        XCTAssertEqual(count("breath: bio.map { sin(Float.pi", in: view), 0, """
            The raw, ungated shaping is back. That is the #1133 defect verbatim: it pins \
            `spread` at 0.85 and Aurora's swell at 0.80 for every frame from a source that \
            does not derive respiration.
            """)
        XCTAssertEqual(count("sin(Float.pi * min(max($0.breathPhase, 0), 1))", in: view), 1, """
            The `sin(π·x)` hump is gone. It is not decoration: feeding the raw wrapping phase \
            to the shader made the figure saw-collapse ~30 % at every cycle wrap (audit #4). \
            Removing it re-opens that, and the gate above does not cover it.
            """)
    }

    // MARK: - 2 · One named neutral, used at BOTH absences

    func testBothAbsencesRenderIdentically() throws {
        let view = try code(Self.renderer)
        XCTAssertEqual(count("private static let neutralVisualBreath: Float = 0.5", in: view), 1, """
            The named neutral is gone or changed. A literal at the call site would be the \
            defect this constant replaced: the value is a CHOICE about where the picture \
            rests, and it has to be arguable at one place.
            """)
        XCTAssertEqual(count("Self.neutralVisualBreath", in: view), 2, """
            The neutral is used \(count("Self.neutralVisualBreath", in: view))× — expected \
            exactly 2: the unmeasured-breath branch and the no-frame branch. If they diverge, \
            a body with no breath sensor and no body at all render differently, which is the \
            exact inconsistency `coherenceForSound` removed for its own channel one field up.
            """)
    }

    // MARK: - 3 · The arithmetic that rejects the obvious fix

    func testTheAccessorsOwnNeutralWouldHaveBeenTheOtherExtreme() {
        let hump: (Float) -> Float = { sin(Float.pi * $0) }
        // What the shader does with the shaped value.
        let spread: (Float) -> Float = { 0.85 + $0 * 0.35 }
        let auroraSwell: (Float) -> Float = { 0.80 + 0.20 * $0 }

        XCTAssertEqual(hump(0), 0, accuracy: 1e-6, """
            `sin(π·0)` is no longer 0. The whole finding rests on it: the two hard-zero \
            publishers land here, and 0 is the shader's narrowest spread and dimmest swell.
            """)
        XCTAssertEqual(hump(0.5), 1, accuracy: 1e-6, """
            `sin(π·0.5)` is no longer 1. This is why `breathPhaseForSound` — which returns \
            0.5 when unmeasured — is the WRONG accessor at this call site: through the hump \
            its neutral becomes the widest, fullest extreme.
            """)
        // Both extremes are worse than the chosen rest, measured against the spread dial's
        // own neutral of 1.0 (the shader multiplies this by `u.spread`).
        let restingSpread = spread(0.5)
        XCTAssertLessThan(abs(restingSpread - 1.0), abs(spread(hump(0)) - 1.0), """
            The chosen rest (spread \(restingSpread)) is no closer to the dial's neutral 1.0 \
            than the frozen-exhale extreme \(spread(hump(0))). Re-derive the constant.
            """)
        XCTAssertLessThan(abs(restingSpread - 1.0), abs(spread(hump(0.5)) - 1.0), """
            The chosen rest (spread \(restingSpread)) is no closer to the dial's neutral 1.0 \
            than the accessor's-neutral extreme \(spread(hump(0.5))) — the near-miss fix.
            """)
        XCTAssertEqual(auroraSwell(0.5), 0.90, accuracy: 1e-6, """
            Aurora's swell at the resting breath is no longer mid-scale. #1127 gave that swell \
            to the real breath signal; if the mapping changed, this file's claim that an \
            unmeasured body rests mid-scale changed with it.
            """)
    }

    // MARK: - 4 · COUNTERWEIGHTS — the reason the gate exists, and the sound side it must not absorb

    func testTheSoundConsumersKeepTheirOwnAccessorAndTheZeroWritersStillWriteZero() throws {
        for (file, needle) in [
            ("Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift", "breathPhase: frame.breathPhaseForSound"),
            ("Sources/Echoelmusic/Tools/PolySynthVoice.swift", "breathPhase: frame.breathPhaseForSound"),
            ("Sources/Echoelmusic/Studio/AlwaysOnBioChannel.swift", "return frame.breathPhaseForSound"),
        ] {
            XCTAssertEqual(count(needle, in: try code(file)), 1, """
                \(file) no longer reads `breathPhaseForSound`. The visual gate added by #1133 \
                is NOT a reason to unify the two — the sound side feeds a PHASE to a cosine \
                swell, the visual side feeds it through a hump, and the same 0.5 means \
                different things on each side. Unifying them silently moves one.
                """)
        }
        for file in ["Sources/Echoelmusic/Bio/PolarH10BioPublisher.swift",
                     "Sources/Echoelmusic/Bio/FaceExpressionBioPublisher.swift"] {
            XCTAssertEqual(count("breathPhase: 0", in: try code(file)), 1, """
                \(file) no longer writes `breathPhase: 0`. If it started deriving respiration, \
                that is good news and this claim should go — but the #1133 note at the \
                renderer names this publisher as the reason the gate exists, so pull that \
                prose in the same commit.
                """)
        }
        XCTAssertEqual(count(
            "public var hasMeasuredBreath: Bool { Self.plausibleBreathRate.contains(breathRate) }",
            in: try code(Self.bus)), 1, """
            The gate itself moved. It deliberately tests `breathRate`, not `breathPhase` — \
            because the phase has no unknown value to test. A gate rewritten to consult the \
            phase would be true for a real exhale-start and false for nothing.
            """)
    }
}
