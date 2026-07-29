#if canImport(Network)
import XCTest
@testable import Echoelmusic

@MainActor
final class ADMOSCSenderTests: XCTestCase {

    private func frame(
        hrv: Float = 0, breathPhase: Float = 0.5,
        coherence: Float = 0, motion: Float = 0
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: 60, hrvNormalized: hrv,
            breathRate: 6, breathPhase: breathPhase, coherence: coherence,
            motionEnergy: motion, source: .fallback
        )
    }

    // MARK: - Address namespace

    func testAdmMessages_addressesFollowAdmObjNamespace() {
        let msgs = ADMOSCSender.admMessages(for: frame(), object: 1)
        let addresses = msgs.map { $0.0 }
        // The three POSITION addresses are unconditional and ordered. `/gain` rides the
        // motion producer (#215) and is asserted separately below, so this stays true
        // whichever side of that gate the build is on.
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

    func testAzimuth_breathPhaseSweepsFullLeftToRight() {
        func azimuth(_ phase: Float) -> Float {
            ADMOSCSender.admMessages(for: frame(breathPhase: phase), object: 1)[0].1
        }
        XCTAssertEqual(azimuth(0.0), -180, accuracy: 0.001)   // exhale start → hard left
        XCTAssertEqual(azimuth(0.5),    0, accuracy: 0.001)   // center
        XCTAssertEqual(azimuth(1.0),  180, accuracy: 0.001)   // hard right
    }

    func testDistance_highCoherencePullsObjectClose() {
        func distance(_ coh: Float) -> Float {
            ADMOSCSender.admMessages(for: frame(coherence: coh), object: 1)[2].1
        }
        XCTAssertEqual(distance(0.0), 1, accuracy: 0.001)   // scattered → far
        XCTAssertEqual(distance(1.0), 0, accuracy: 0.001)   // coherent → close
    }

    func testElevation_hrvLiftsObject() {
        func elevation(_ hrv: Float) -> Float {
            ADMOSCSender.admMessages(for: frame(hrv: hrv), object: 1)[1].1
        }
        XCTAssertEqual(elevation(0.0), 0,  accuracy: 0.001)
        XCTAssertEqual(elevation(1.0), 60, accuracy: 0.001)
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

    func testAllValues_clampIntoAdmSpecRanges_evenForOutOfRangeInput() {
        // Deliberately overdriven bio values (e.g. unnormalized sensor glitch).
        let wild = frame(hrv: 5, breathPhase: 3, coherence: -2, motion: 9)
        let msgs = ADMOSCSender.admMessages(for: wild, object: 1)
        let azimuth = msgs[0].1, elevation = msgs[1].1, distance = msgs[2].1
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

    func testAdmMessage_encodesAsValidOSCFloat() {
        // Uses a POSITION address, which is unconditional: `/gain` now rides the motion
        // producer (#215) and would make this test disappear rather than fail.
        // breathPhase 1.0 → azimuth +180 → big-endian 0x43340000.
        let azimuth = ADMOSCSender.admMessages(for: frame(breathPhase: 1.0), object: 1)[0]
        XCTAssertEqual(azimuth.0, "/adm/obj/1/position/azimuth")
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
