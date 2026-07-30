#if canImport(Network)
import XCTest
@testable import Echoelmusic

@MainActor
final class ADMOSCSenderTests: XCTestCase {

    /// ⚠️ FULLY MEASURED BY DEFAULT since #260. Every address now rides its own channel's
    /// measurement, so a fixture that left `hrv`/`coherence` at 0 would silently delete the
    /// very messages most of these tests then indexed into. The absence half is asserted in
    /// the BLOCKING bundle (`ADMOSCAbsenceTests`); this file measures the mapping.
    private func frame(
        hrv: Float = 0.5, breathPhase: Float = 0.5,
        coherence: Float = 0.5, motion: Float = 0
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: 60, hrvNormalized: hrv,
            breathRate: 6, breathPhase: breathPhase, coherence: coherence,
            motionEnergy: motion, source: .fallback
        )
    }

    /// Look an address up by its suffix. Positional indexing broke with #260 — an omitted
    /// channel shifts every later index — and it was always the more fragile form.
    private func value(_ msgs: [(String, Float)], _ suffix: String) -> Float? {
        msgs.first { $0.0.hasSuffix(suffix) }?.1
    }

    // MARK: - Address namespace

    func testAdmMessages_addressesFollowAdmObjNamespace() {
        let msgs = ADMOSCSender.admMessages(for: frame(), object: 1)
        let addresses = msgs.map { $0.0 }
        // A fully measured frame carries all three POSITION addresses, in this order.
        // `/gain` rides the motion producer (#215) and is asserted separately below, so
        // this stays true whichever side of that gate the build is on.
        XCTAssertEqual(Array(addresses.prefix(3)), [
            "/adm/obj/1/position/azimuth",
            "/adm/obj/1/position/elevation",
            "/adm/obj/1/position/distance"
        ])
        XCTAssertEqual(addresses.contains("/adm/obj/1/gain"),
                       ModSource.motion.hasProducer,
                       "the bio arm asserts /gain exactly when something drives it")
    }

    func testAdmMessages_objectIndexIsEmbeddedAndClampedToOneBased() {
        XCTAssertTrue(ADMOSCSender.admMessages(for: frame(), object: 7)
            .allSatisfy { $0.0.hasPrefix("/adm/obj/7/") })
        // 0 / negative collapse to object 1 (ADM is 1-based).
        XCTAssertTrue(ADMOSCSender.admMessages(for: frame(), object: 0)
            .allSatisfy { $0.0.hasPrefix("/adm/obj/1/") })
    }

    // MARK: - Mapping correctness

    func testAzimuth_breathPhaseSweepsFullLeftToRight() throws {
        func azimuth(_ phase: Float) throws -> Float {
            try XCTUnwrap(value(ADMOSCSender.admMessages(for: frame(breathPhase: phase),
                                                         object: 1), "/position/azimuth"))
        }
        XCTAssertEqual(try azimuth(0.0), -180, accuracy: 0.001)   // exhale start → hard left
        XCTAssertEqual(try azimuth(0.5),    0, accuracy: 0.001)   // center
        XCTAssertEqual(try azimuth(1.0),  180, accuracy: 0.001)   // hard right
    }

    /// ⚠️ Only the OPEN end of the coherence range is a mapping question now: coherence 0
    /// means "not measured yet" and sends nothing (#260), which is asserted in the blocking
    /// bundle. What stays here is that a real coherence still pulls the object in.
    func testDistance_highCoherencePullsObjectClose() throws {
        func distance(_ coh: Float) throws -> Float {
            try XCTUnwrap(value(ADMOSCSender.admMessages(for: frame(coherence: coh),
                                                         object: 1), "/position/distance"))
        }
        XCTAssertEqual(try distance(0.01), 0.99, accuracy: 0.001)   // barely coherent → far
        XCTAssertEqual(try distance(1.0),  0,    accuracy: 0.001)   // coherent → close
    }

    func testElevation_hrvLiftsObject() throws {
        func elevation(_ hrv: Float) throws -> Float {
            try XCTUnwrap(value(ADMOSCSender.admMessages(for: frame(hrv: hrv),
                                                         object: 1), "/position/elevation"))
        }
        XCTAssertEqual(try elevation(0.01), 0.6, accuracy: 0.001)
        XCTAssertEqual(try elevation(1.0), 60,   accuracy: 0.001)
    }

    /// THE DECISION, tested on BOTH answers because the kernel takes the predicate as a
    /// parameter. Branching on `ModSource.motion.hasProducer` inside the test instead
    /// would leave the live arm permanently unreachable — prose in `if` clothing — and
    /// would silently switch off the dormant-case assertions the day a producer lands.
    func testMotionGain_isAbsentWithoutAProducer_andTheFullMappingWithOne() {
        XCTAssertNil(ADMOSCSender.motionGain(motion: 0, hasProducer: false),
                     "with nothing driving it, the bio arm asserts no gain at all — "
                     + "substituting a value would step the level at every musical rest")
        XCTAssertNil(ADMOSCSender.motionGain(motion: 0.9, hasProducer: false),
                     "and no frame can change that, because no frame carries motion")

        XCTAssertEqual(ADMOSCSender.motionGain(motion: 0, hasProducer: true),
                       ADMOSCSender.motionRestingGain,
                       "a measured body at rest sits at the resting floor")
        XCTAssertEqual(ADMOSCSender.motionGain(motion: 1, hasProducer: true), 1.0,
                       "and full movement brings the object all the way forward — the "
                       + "mapping must reach unity exactly, whatever the floor is tuned to")
    }

    /// The mapping the sender actually calls must be the one above, fed the REAL
    /// predicate. Without this the parameterised kernel could be perfect and unused.
    func testAdmMessagesUsesTheMotionGainKernelWithTheLivePredicate() {
        let msgs = ADMOSCSender.admMessages(for: frame(motion: 0.4), object: 1)
        let sent = msgs.first { $0.0 == "/adm/obj/1/gain" }?.1
        XCTAssertEqual(sent,
                       ADMOSCSender.motionGain(motion: 0.4,
                                               hasProducer: ModSource.motion.hasProducer))
    }

    // MARK: - Range safety (out-of-range bio values stay within ADM-OSC v1.0 spec)

    func testAllValues_clampIntoAdmSpecRanges_evenForOutOfRangeInput() throws {
        // Deliberately overdriven bio values (e.g. unnormalized sensor glitch). Coherence
        // is overdriven UPWARD (a negative one is an absence under #260 and would simply
        // remove the address, proving nothing about the clamp).
        let wild = frame(hrv: 5, breathPhase: 3, coherence: 4, motion: 9)
        let msgs = ADMOSCSender.admMessages(for: wild, object: 1)
        let azimuth = try XCTUnwrap(value(msgs, "/position/azimuth"))
        let elevation = try XCTUnwrap(value(msgs, "/position/elevation"))
        let distance = try XCTUnwrap(value(msgs, "/position/distance"))
        XCTAssertGreaterThanOrEqual(azimuth, -180); XCTAssertLessThanOrEqual(azimuth, 180)
        XCTAssertGreaterThanOrEqual(elevation, -90); XCTAssertLessThanOrEqual(elevation, 90)
        XCTAssertGreaterThanOrEqual(distance, 0); XCTAssertLessThanOrEqual(distance, 1)
        // Gain is optional (#215) — clamp it when present, and check the kernel directly
        // so the range guarantee is asserted for BOTH producer answers, not just today's.
        if let gain = msgs.first(where: { $0.0 == "/adm/obj/1/gain" })?.1 {
            XCTAssertGreaterThanOrEqual(gain, 0); XCTAssertLessThanOrEqual(gain, 1)
        }
        let wildGain = ADMOSCSender.motionGain(motion: 9, hasProducer: true)
        XCTAssertEqual(wildGain, 1.0, "an overdriven motion value still clamps into spec")
    }

    // MARK: - On-the-wire (reuses the audited OSC encoder)

    func testAdmMessage_encodesAsValidOSCFloat() throws {
        // Looked up by address, not by index: `/gain` rides the motion producer (#215) and
        // every position address rides its own channel's measurement (#260), so a
        // positional read here would silently encode a different parameter.
        // breathPhase 1.0 → azimuth +180 → big-endian 0x43340000.
        let msgs = ADMOSCSender.admMessages(for: frame(breathPhase: 1.0), object: 1)
        let azimuth = try XCTUnwrap(msgs.first { $0.0 == "/adm/obj/1/position/azimuth" })
        let data = OSCSender.encode(address: azimuth.0, floats: [azimuth.1])
        XCTAssertEqual(Array(data.suffix(4)), [0x43, 0x34, 0x00, 0x00])
    }

    // MARK: - Lifecycle

    @MainActor
    func testInit_defaultEndpoint() {
        let s = ADMOSCSender()
        XCTAssertEqual(s.host, "127.0.0.1")
        XCTAssertEqual(s.port, 9000)
        XCTAssertEqual(s.objectIndex, 1)
        XCTAssertFalse(s.isActive)
    }
}
#endif
