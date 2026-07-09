import XCTest
@testable import Echoelmusic

/// Verifies the pure resource-conservation policy: device pressure → quality tier
/// → concrete knobs, including the measured-FPS demotion. Runs on Linux (no UIKit).
final class AdaptiveQualityTests: XCTestCase {

    // MARK: - Default / nominal

    func testTier_NominalDischarging_IsBalanced() {
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: 0.8, charging: false)
        XCTAssertEqual(t, .balanced)
    }

    func testTier_ChargingAndCool_ReachesHigh() {
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: 0.9, charging: true)
        XCTAssertEqual(t, .high)
    }

    func testTier_UnknownBatteryChargingCool_ReachesHigh() {
        // Simulator / desktop report a negative battery level — treat as OK.
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: -1, charging: true)
        XCTAssertEqual(t, .high)
    }

    // MARK: - Thermal ceilings

    func testTier_ThermalFair_CapsAtBalanced() {
        let t = AdaptiveQuality.tier(thermal: .fair, lowPower: false,
                                     batteryLevel: 0.9, charging: true)
        XCTAssertEqual(t, .balanced, "fair thermal must block high even when charging")
    }

    func testTier_ThermalSerious_CapsAtLow() {
        let t = AdaptiveQuality.tier(thermal: .serious, lowPower: false,
                                     batteryLevel: 0.9, charging: true)
        XCTAssertEqual(t, .low)
    }

    func testTier_ThermalCritical_CapsAtMinimal() {
        let t = AdaptiveQuality.tier(thermal: .critical, lowPower: false,
                                     batteryLevel: 0.9, charging: true)
        XCTAssertEqual(t, .minimal)
    }

    // MARK: - Power / battery ceilings

    func testTier_LowPowerMode_CapsAtLow() {
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: true,
                                     batteryLevel: 0.9, charging: false)
        XCTAssertEqual(t, .low)
    }

    func testTier_VeryLowBatteryDischarging_IsMinimal() {
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: 0.05, charging: false)
        XCTAssertEqual(t, .minimal)
    }

    func testTier_LowBatteryDischarging_CapsAtLow() {
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: 0.15, charging: false)
        XCTAssertEqual(t, .low)
    }

    func testTier_LowBatteryButCharging_NotPenalised() {
        // Charging at 15% should not force Power Saver — it's recovering.
        let t = AdaptiveQuality.tier(thermal: .nominal, lowPower: false,
                                     batteryLevel: 0.15, charging: true)
        XCTAssertEqual(t, .balanced)
    }

    // MARK: - Worst-constraint-wins

    func testTier_MultipleConstraints_TakesWorst() {
        let t = AdaptiveQuality.tier(thermal: .serious, lowPower: true,
                                     batteryLevel: 0.05, charging: false)
        XCTAssertEqual(t, .minimal)
    }

    // MARK: - Settings knobs

    func testSettings_MonotonicWithTier() {
        let tiers = QualityTier.allCases.sorted()
        var lastFPS = 0
        var lastBio = 0.0
        for tier in tiers {
            let s = AdaptiveQuality.settings(for: tier)
            XCTAssertEqual(s.tier, tier)
            XCTAssertGreaterThanOrEqual(s.targetFPS, lastFPS, "FPS must not drop as tier rises")
            XCTAssertGreaterThanOrEqual(s.bioHz, lastBio, "bioHz must not drop as tier rises")
            lastFPS = s.targetFPS
            lastBio = s.bioHz
        }
    }

    func testSettings_MinimalForcesReduceMotionAndNoDonuts() {
        let s = AdaptiveQuality.settings(for: .minimal)
        XCTAssertTrue(s.reduceMotion)
        XCTAssertFalse(s.allowSpectralDonuts)
        XCTAssertLessThan(s.visualDetailScale, 1.0)
    }

    func testSettings_HighEnablesEverything() {
        let s = AdaptiveQuality.settings(for: .high)
        XCTAssertFalse(s.reduceMotion)
        XCTAssertTrue(s.allowSpectralDonuts)
        XCTAssertEqual(s.visualDetailScale, 1.0, accuracy: 0.001)
        // Display FPS is pinned at 60 (MetalBioView) and 60 is the temperature-friendly
        // ceiling; the high tier earns its keep via full detail + faster bio/OSC polls,
        // not a 120 Hz display. (A 120 target would also make the pinned-60 display read
        // as 'missing target' and spuriously demote via measured-FPS feedback.)
        XCTAssertEqual(s.targetFPS, 60)
    }

    // MARK: - Measured-FPS demotion

    func testSettings_LowMeasuredFPS_DemotesOneTier() {
        // Balanced targets 60; a sustained 30 fps (< 75% = 45) demotes to low (30 fps).
        let s = AdaptiveQuality.settings(thermal: .nominal, lowPower: false,
                                         batteryLevel: 0.8, charging: false,
                                         measuredFPS: 30)
        XCTAssertEqual(s.tier, .low)
    }

    func testSettings_HealthyMeasuredFPS_NoDemotion() {
        let s = AdaptiveQuality.settings(thermal: .nominal, lowPower: false,
                                         batteryLevel: 0.8, charging: false,
                                         measuredFPS: 58)
        XCTAssertEqual(s.tier, .balanced)
    }

    func testSettings_NoFPSReading_NoDemotion() {
        let s = AdaptiveQuality.settings(thermal: .nominal, lowPower: false,
                                         batteryLevel: 0.8, charging: false,
                                         measuredFPS: 0)
        XCTAssertEqual(s.tier, .balanced)
    }

    func testSettings_MinimalNeverDemotesBelowItself() {
        let s = AdaptiveQuality.settings(thermal: .critical, lowPower: true,
                                         batteryLevel: 0.02, charging: false,
                                         measuredFPS: 1)
        XCTAssertEqual(s.tier, .minimal)
    }
}
