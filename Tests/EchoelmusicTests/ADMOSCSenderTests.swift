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
        XCTAssertEqual(addresses, [
            "/adm/obj/1/position/azimuth",
            "/adm/obj/1/position/elevation",
            "/adm/obj/1/position/distance",
            "/adm/obj/1/gain"
        ])
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

    /// #215 — the motion→gain mapping is DORMANT while nothing measures motion, and this
    /// test is written so it flips with the product rather than pinning today's answer
    /// forever. It asserts the branch that `ModSource.motion.hasProducer` selects, not a
    /// literal: the day a CoreMotion producer lands, the modulated arm below is what must
    /// hold, and this test starts checking it without being edited.
    ///
    /// The old version asserted `gain(0.0) == 0.3` unconditionally. That was a green test
    /// pinning a defect in place: with no producer, 0.3 was not a resting level but the
    /// ONLY level the object could ever have — every Echoel object arriving in a house
    /// rig 10.5 dB down, with no control in the app to lift it.
    func testGain_isUnityWhileMotionHasNoProducer_andModulatedOnceItDoes() {
        func gain(_ motion: Float) -> Float {
            ADMOSCSender.admMessages(for: frame(motion: motion), object: 1)[3].1
        }
        if ModSource.motion.hasProducer {
            XCTAssertEqual(gain(0.0), ADMOSCSender.motionRestingGain, accuracy: 0.001,
                           "a measured body at rest sits at the resting floor")
            XCTAssertEqual(gain(1.0), 1.0, accuracy: 0.001,
                           "full movement brings the object all the way forward")
        } else {
            XCTAssertEqual(gain(0.0), 1.0, accuracy: 0.001,
                           "with no producer the object is unmodulated and belongs at "
                           + "unity — the renderer's own gain stage is the one control")
            XCTAssertEqual(gain(0.9), 1.0, accuracy: 0.001,
                           "and no frame can move it, because no frame carries motion")
        }
    }

    /// The floor is not deleted, only bypassed — and its value is the one that keeps the
    /// live mapping bit-identical to the expression it replaced (`0.3 + m * 0.7`, where
    /// the 0.7 is `1 - 0.3`). If someone retunes the constant, this says out loud that
    /// the second coefficient follows it.
    func testRestingGainIsTheFloorOfAFullRangeMapping() {
        XCTAssertEqual(ADMOSCSender.motionRestingGain, 0.3, accuracy: 0.0001)
        XCTAssertGreaterThan(ADMOSCSender.motionRestingGain, 0)
        XCTAssertLessThan(ADMOSCSender.motionRestingGain, 1)
    }

    // MARK: - Range safety (out-of-range bio values stay within ADM-OSC v1.0 spec)

    func testAllValues_clampIntoAdmSpecRanges_evenForOutOfRangeInput() {
        // Deliberately overdriven bio values (e.g. unnormalized sensor glitch).
        let wild = frame(hrv: 5, breathPhase: 3, coherence: -2, motion: 9)
        let msgs = ADMOSCSender.admMessages(for: wild, object: 1)
        let azimuth = msgs[0].1, elevation = msgs[1].1, distance = msgs[2].1, gain = msgs[3].1
        XCTAssertGreaterThanOrEqual(azimuth, -180); XCTAssertLessThanOrEqual(azimuth, 180)
        XCTAssertGreaterThanOrEqual(elevation, -90); XCTAssertLessThanOrEqual(elevation, 90)
        XCTAssertGreaterThanOrEqual(distance, 0); XCTAssertLessThanOrEqual(distance, 1)
        XCTAssertGreaterThanOrEqual(gain, 0); XCTAssertLessThanOrEqual(gain, 1)
    }

    // MARK: - On-the-wire (reuses the audited OSC encoder)

    func testAdmMessage_encodesAsValidOSCFloat() {
        // /adm/obj/1/gain at motion=1.0 → gain 1.0 → big-endian 0x3F800000 tail.
        let gain = ADMOSCSender.admMessages(for: frame(motion: 1.0), object: 1)[3]
        let data = OSCSender.encode(address: gain.0, floats: [gain.1])
        XCTAssertEqual(Array(data.suffix(4)), [0x3F, 0x80, 0x00, 0x00])
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
