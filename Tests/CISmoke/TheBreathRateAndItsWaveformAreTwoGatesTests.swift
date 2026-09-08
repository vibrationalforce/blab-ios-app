// TheBreathRateAndItsWaveformAreTwoGatesTests.swift
// Echoel — one gate was covering two different measurements. BLOCKING bundle.
//
// #1140. `hasMeasuredBreath` asks about `breathRate`, and `OSCSender`'s own comment explains
// why it cannot ask about the phase: 0 is a meaningful position, so the phase cannot answer
// the question about itself. That reasoning is correct for the camera and BLIND to a source
// that has a real rate and no waveform at all.
//
// `HealthKitBioPublisher` is exactly that source. It reads a genuine respiratory rate from
// HealthKit (`processBreathRateSamples`, 2…60/min) while `EchoelBioEngine.breathPhase` never
// leaves its 0.5 default — nothing writes it outside `startFallbackMode`, and that runs ONLY
// in the `else` branch, when HealthKit is UNAVAILABLE. So on a Watch the gate opened on a
// constant.
//
// ⭐ THE SHARPEST COST WAS ON THE PATH THAT ARGUED HARDEST AGAINST IT. `ADMOSCSender` sent
// `(0.5·2−1)·180` = azimuth 0°, asserting the immersive object was dead centre front,
// permanently, as a measurement — in a file whose own comment says "this arm's whole rule is
// that it asserts only what was measured". A law stated in prose two lines above the line that
// broke it.
//
// ⚠️ WHAT THIS SLICE DELIBERATELY DOES NOT TOUCH, named so nobody reads the change as wider
// than it is:
//   · `ArtNetSender.dmxChannels` has NO breath gate at all and never had one — it writes
//     `byte(clampUnit(f.breathPhase))` unconditionally. That is not an oversight to fold in
//     here: a DMX universe carries a value in every slot, so "send nothing" is not available
//     and the fix needs a DEFINED rest value, which is a separate decision. Claim 4 pins that
//     it stays ungated so this note cannot rot into a false claim of coverage.
//   · The PICTURE. `breathPhaseForSound` already returns 0.5 when unmeasured and HealthKit's
//     frozen value IS 0.5, so the rendered frame is identical either way. Gating there would
//     add a branch and change nothing.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Giving HealthKit a real breath waveform is the better
// fix and makes claim 2 red on purpose; the message names the prose to pull in the same commit.

import XCTest

final class TheBreathRateAndItsWaveformAreTwoGatesTests: XCTestCase {

    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let osc = "Sources/Echoelmusic/Sync/OSCSender.swift"
    private static let adm = "Sources/Echoelmusic/Sync/ADMOSCSender.swift"
    private static let artnet = "Sources/Echoelmusic/Sync/ArtNetSender.swift"
    private static let engine = "Sources/Echoelmusic/Bio/EchoelBioEngine.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func code(_ rel: String) throws -> String {
        let path = try root().appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: rel)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · The predicate exists, in one place, with the demo generator included

    func testTheWaveformPredicateIsDeclaredOnceAndNamesBothProducers() throws {
        let bus = try code(Self.bus)
        XCTAssertEqual(
            count("public var providesBreathWaveform: Bool { self == .cameraPPG || self == .fallback }",
                  in: bus), 1, """
            `BioSource.providesBreathWaveform` is gone or its membership changed. Exactly two \
            sources derive a moving breath waveform today: the camera (`RespirationEstimator`) \
            and the demo generator. `.fallback` belongs on the YES side even though it is \
            synthetic — `isSynthetic` answers "is it a body" and this answers "is there a \
            waveform"; two questions, two properties, deliberately not merged.
            """)
        XCTAssertEqual(count("hasMeasuredBreath && source.providesBreathWaveform", in: bus), 1, """
            `hasMeasuredBreathWaveform` no longer conjoins the rate gate with the source \
            capability. Both halves are needed: the rate gate still rejects the three \
            publishers that write a hard 0, and the capability rejects a real rate with no \
            waveform behind it.
            """)
    }

    // MARK: - 2 · The two egress paths that ASSERT a phase use the new gate

    func testTheAssertingEgressPathsGateOnTheWaveform() throws {
        let osc = try code(Self.osc)
        XCTAssertEqual(count("if frame.hasMeasuredBreathWaveform {", in: osc), 1, """
            `/echoelmusic/bio/breath/phase` is no longer behind the waveform gate. Under the \
            rate gate alone a Watch session sends a constant 0.5 forever; an integrator \
            receiving it cannot tell it from a performer holding their breath.
            """)
        XCTAssertEqual(count("msgs.append((\"/echoelmusic/bio/breath/rate\", [frame.breathRate]))",
                             in: osc), 1, """
            The breath RATE line is gone. HealthKit genuinely measures it — this slice \
            separates two gates, it does not withdraw a real measurement.
            """)

        let adm = try code(Self.adm)
        XCTAssertEqual(count("if f.hasMeasuredBreathWaveform, f.breathPhase.isFinite {", in: adm), 1, """
            The ADM-OSC azimuth is no longer behind the waveform gate. This is the line that \
            sent azimuth 0° as a permanent asserted position on every Watch session, in the \
            file whose own comment forbids putting an invented number in someone's rig.
            """)
    }

    // MARK: - 3 · The premise: HealthKit really has no waveform writer

    func testNothingWritesTheBreathPhaseOutsideTheFallbackBranch() throws {
        let engine = try code(Self.engine)
        XCTAssertEqual(count("self.snapshot.breathPhase =", in: engine), 1, """
            `EchoelBioEngine.snapshot.breathPhase` now has \
            \(count("self.snapshot.breathPhase =", in: engine)) writers, not 1. The whole \
            premise of #1140 is that the ONLY writer sits inside `startFallbackMode`, which \
            runs when HealthKit is ABSENT — so a HealthKit session publishes the 0.5 default \
            forever. A second writer may have fixed that properly, in which case
            `providesBreathWaveform` should gain `.healthKit` and this guard, the predicate's \
            doc and `OSCSender`'s comment all move in the same commit (#456).
            """)
        XCTAssertEqual(count("public var breathPhase: Double = 0.5", in: engine), 2, """
            The 0.5 default on the engine's snapshot changed. That literal is the constant a \
            Watch session was publishing as a measured position.
            """)
    }

    // MARK: - 4 · COUNTERWEIGHT — what is NOT covered, pinned so the note cannot rot

    func testTheArtNetBreathChannelIsStillUngatedOnPurpose() throws {
        let artnet = try code(Self.artnet)
        XCTAssertEqual(count("byte(clampUnit(f.breathPhase))", in: artnet), 1, """
            The Art-Net 8-bit breath channel changed shape. This guard's header states it is \
            deliberately NOT covered by #1140 — a DMX universe carries a value in every slot, \
            so "send nothing" is unavailable and the fix needs a defined rest value, which is \
            its own decision. If it has now been gated or given a rest value, that header \
            paragraph is stale and must be pulled in the same commit.
            """)
        XCTAssertEqual(count("word(clampUnit(f.breathPhase))", in: artnet), 1, """
            The Art-Net 16-bit breath channel changed shape — same reasoning as above.
            """)
    }
}
