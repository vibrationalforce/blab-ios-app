#if canImport(Network)
import XCTest
@testable import Echoelmusic

@MainActor
final class ArtNetSenderTests: XCTestCase {

    private func frame(
        hr: Float = 120, hrv: Float = 0.5, breathPhase: Float = 0.5, coherence: Float = 0.5
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: 6, breathPhase: breathPhase, coherence: coherence,
            motionEnergy: 0, source: .fallback
        )
    }

    // MARK: - ArtDMX packet structure

    func testArtDMXPacket_headerMatchesArtNetSpec() {
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1, channels: [0, 0]))
        // "Art-Net\0"
        XCTAssertEqual(Array(pkt[0..<8]), [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00])
        // OpCode OpOutput 0x5000, little-endian
        XCTAssertEqual(Array(pkt[8..<10]), [0x00, 0x50])
        // ProtVer 14, big-endian
        XCTAssertEqual(Array(pkt[10..<12]), [0x00, 0x0E])
        XCTAssertEqual(pkt[12], 1)      // sequence
        XCTAssertEqual(pkt[13], 0)      // physical
    }

    func testArtDMXPacket_universeSplitsIntoSubUniAndNet() {
        // universe 0x0123 → SubUni 0x23, Net 0x01
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0x0123, sequence: 5, channels: [1, 2]))
        XCTAssertEqual(pkt[14], 0x23)   // SubUni
        XCTAssertEqual(pkt[15], 0x01)   // Net
    }

    func testArtDMXPacket_lengthIsEvenBigEndianAndDataAppended() {
        // odd channel count → padded to even
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1, channels: [10, 20, 30]))
        let lenHi = Int(pkt[16]); let lenLo = Int(pkt[17])
        let length = (lenHi << 8) | lenLo
        XCTAssertEqual(length, 4, "3 channels padded to even = 4")
        XCTAssertEqual(length % 2, 0)
        XCTAssertEqual(Array(pkt[18..<22]), [10, 20, 30, 0])
        XCTAssertEqual(pkt.count, 18 + length)
    }

    func testArtDMXPacket_clampsToMax512Channels() {
        let pkt = Array(ArtNetSender.artDMXPacket(universe: 0, sequence: 1,
                                                  channels: Array(repeating: 255, count: 600)))
        let length = (Int(pkt[16]) << 8) | Int(pkt[17])
        XCTAssertEqual(length, 512)
        XCTAssertEqual(pkt.count, 18 + 512)
    }

    // MARK: - Bio → DMX mapping

    func testDmxChannels_fourChannelsInByteRange() {
        let ch = ArtNetSender.dmxChannels(for: frame())
        XCTAssertEqual(ch.count, 4)
        for c in ch { XCTAssertTrue(c <= 255) }  // UInt8 is inherently ≤255; sanity
    }

    func testDmxChannels_dimmerNeverFullyDark_andTracksCoherence() {
        let dark = ArtNetSender.dmxChannels(for: frame(coherence: 0))[0]
        let bright = ArtNetSender.dmxChannels(for: frame(coherence: 1))[0]
        XCTAssertGreaterThanOrEqual(Int(dark), Int(0.3 * 255) - 2, "always some light")
        XCTAssertGreaterThan(Int(bright), Int(dark), "more coherent = brighter")
        XCTAssertEqual(Int(bright), 255, accuracy: 2)
    }

    func testDmxChannels_breathDrivesBlue() {
        let low = ArtNetSender.dmxChannels(for: frame(breathPhase: 0))[3]
        let high = ArtNetSender.dmxChannels(for: frame(breathPhase: 1))[3]
        XCTAssertEqual(Int(low), 0, accuracy: 2)
        XCTAssertEqual(Int(high), 255, accuracy: 2)
    }

    func testDmxChannels_outOfRangeBioClampsToByte() {
        let wild = ArtNetSender.dmxChannels(for: frame(hr: 999, hrv: 5, breathPhase: -3, coherence: 9))
        XCTAssertEqual(wild.count, 4)  // all UInt8, no crash/overflow
    }

    // MARK: - 16-bit (coarse/fine) mapping

    func testDmxChannels16_eightChannels() {
        let ch = ArtNetSender.dmxChannels16(for: frame())
        XCTAssertEqual(ch.count, 8, "four params × coarse+fine pairs")
    }

    func testDmxChannels16_fullScaleBreathIsMaxWord() {
        // breathPhase 1.0 → blue pair (channels 6,7) = 0xFFFF.
        let ch = ArtNetSender.dmxChannels16(for: frame(breathPhase: 1))
        XCTAssertEqual(ch[6], 0xFF, "coarse/MSB")
        XCTAssertEqual(ch[7], 0xFF, "fine/LSB")
    }

    func testDmxChannels16_zeroBreathIsZeroWord() {
        let ch = ArtNetSender.dmxChannels16(for: frame(breathPhase: 0))
        XCTAssertEqual(ch[6], 0x00)
        XCTAssertEqual(ch[7], 0x00)
    }

    func testDmxChannels16_msbBeforeLsb_halfScale() {
        // hrvNormalized 0.5 → green pair (channels 4,5) ≈ 0x7FFF → MSB 0x7F.
        let ch = ArtNetSender.dmxChannels16(for: frame(hrv: 0.5))
        XCTAssertEqual(Int(ch[4]), 0x7F, accuracy: 1, "coarse byte ≈ half scale")
    }

    func testDmxChannels16_finerThan8bit() {
        // Two close HRV values that collapse to the SAME 8-bit byte must differ
        // in the 16-bit representation — the whole point of the precision upgrade.
        let a = ArtNetSender.dmxChannels16(for: frame(hrv: 0.5000))
        let b = ArtNetSender.dmxChannels16(for: frame(hrv: 0.5010))
        XCTAssertNotEqual([a[4], a[5]], [b[4], b[5]], "16-bit resolves a step 8-bit can't")
    }

    func testResolutionDispatch_channelCounts() {
        XCTAssertEqual(ArtNetSender.dmxChannels(for: frame(), resolution: .eightBit).count, 4)
        XCTAssertEqual(ArtNetSender.dmxChannels(for: frame(), resolution: .sixteenBit).count, 8)
    }

    // MARK: - Lifecycle

    @MainActor
    func testInit_defaultEndpoint() {
        let s = ArtNetSender()
        XCTAssertEqual(s.host, "255.255.255.255")
        XCTAssertEqual(s.port, 6454)
        XCTAssertEqual(s.universe, 0)
        XCTAssertFalse(s.isActive)
    }

    // MARK: - Flash safety: dimmer slew-limit (physical-fixture strobe guard)

    func testDimmerUnit_matchesBuilderMapping() {
        // 0.3 + 0.7·coherence, the same luminance the channel builders use.
        XCTAssertEqual(ArtNetSender.dimmerUnit(for: frame(coherence: 0)), 0.3, accuracy: 1e-6)
        XCTAssertEqual(ArtNetSender.dimmerUnit(for: frame(coherence: 1)), 1.0, accuracy: 1e-6)
    }

    func testApplyDimmer_overwritesLuminanceLeavesColour() {
        // 8-bit: ch0 = dimmer; colour channels (1..3) untouched.
        var ch = ArtNetSender.dmxChannels(for: frame(coherence: 1))   // dimmer byte ≈ 255
        let colourBefore = Array(ch[1...3])
        ArtNetSender.applyDimmer(&ch, resolution: .eightBit, dimmer: 0.0)
        XCTAssertEqual(Int(ch[0]), 0, "dimmer overwritten")
        XCTAssertEqual(Array(ch[1...3]), colourBefore, "colour channels unchanged")
    }

    func testApplyDimmer_16bit_writesCoarseAndFine() {
        var ch = ArtNetSender.dmxChannels16(for: frame(coherence: 1))
        ArtNetSender.applyDimmer(&ch, resolution: .sixteenBit, dimmer: 1.0)
        XCTAssertEqual(ch[0], 0xFF, "coarse")
        XCTAssertEqual(ch[1], 0xFF, "fine")
    }

    func testFlashGuard_slewCapsLuminanceStep() {
        // A 0→1 jump must be capped per step so physical lights can't strobe.
        let stepped = FlashGuard.limitedLuminance(from: 0.0, to: 1.0, maxDelta: 0.08)
        XCTAssertEqual(stepped, 0.08, accuracy: 1e-9)
        // Reaching full from dark takes many steps (≥ ~12 → ≥0.4 s at 30 Hz → <3 Hz).
        var v = 0.0, steps = 0
        while v < 1.0 - 1e-9 && steps < 1000 { v = FlashGuard.limitedLuminance(from: v, to: 1.0, maxDelta: 0.08); steps += 1 }
        XCTAssertGreaterThanOrEqual(steps, 12)
    }

    // MARK: - L1 Grand Master + Blackout (masteredDimmer law)

    func testMasteredDimmer_blackoutWinsOverEverything() {
        XCTAssertEqual(ArtNetSender.masteredDimmer(1.0, grandMaster: 1, blackout: true), 0)
        XCTAssertEqual(ArtNetSender.masteredDimmer(0.5, grandMaster: 0.1, blackout: true), 0)
    }

    func testMasteredDimmer_grandMasterScalesLinearly() {
        XCTAssertEqual(ArtNetSender.masteredDimmer(0.8, grandMaster: 0.5, blackout: false),
                       0.4, accuracy: 1e-6)
        XCTAssertEqual(ArtNetSender.masteredDimmer(0.8, grandMaster: 1, blackout: false),
                       0.8, accuracy: 1e-6)
        XCTAssertEqual(ArtNetSender.masteredDimmer(0.8, grandMaster: 0, blackout: false), 0)
    }

    func testMasteredDimmer_clampsAndGuardsBadInput() {
        XCTAssertEqual(ArtNetSender.masteredDimmer(2.0, grandMaster: 2.0, blackout: false), 1)
        XCTAssertEqual(ArtNetSender.masteredDimmer(0.6, grandMaster: .nan, blackout: false),
                       0.6, accuracy: 1e-6, "non-finite master reads as full")
        XCTAssertEqual(ArtNetSender.masteredDimmer(-1, grandMaster: 0.5, blackout: false), 0)
    }

    // MARK: - Shared slew decision (ArtNet AND sACN — flash guarantee on both)

    func testSlewedDimmer_blackoutIsInstantZero() {
        // A blackout cut is one edge, not a strobe → 0 regardless of anchor.
        XCTAssertEqual(FlashGuard.slewedDimmer(from: 1.0, to: 1.0, blackout: true), 0)
        XCTAssertEqual(FlashGuard.slewedDimmer(from: -1, to: 0.9, blackout: true), 0)
    }

    func testSlewedDimmer_firstFrameLandsAtTarget() {
        // No history (anchor < 0) → the target, nothing to ramp from.
        XCTAssertEqual(FlashGuard.slewedDimmer(from: -1, to: 0.75, blackout: false),
                       0.75, accuracy: 1e-6)
    }

    func testSlewedDimmer_blackoutReleaseRampsFromDark_neverSnaps() {
        // THE sACN bug this guards (workflow B11): after a blackout the anchor is
        // 0, so the return to full must ramp ≤0.08/tick, not jump 0→full.
        let firstAfterRelease = FlashGuard.slewedDimmer(from: 0.0, to: 1.0, blackout: false)
        XCTAssertEqual(firstAfterRelease, 0.08, accuracy: 1e-9,
                       "un-blackout must step, not snap to full")
        var v: Float = 0, steps = 0
        while v < 1.0 - 1e-6 && steps < 1000 {
            v = FlashGuard.slewedDimmer(from: v, to: 1.0, blackout: false); steps += 1
        }
        XCTAssertGreaterThanOrEqual(steps, 12, "full fade ≥0.4 s at 30 Hz → <3 Hz")
    }
}
#endif
