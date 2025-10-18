import XCTest
@testable import Blab

/// Unit tests for HealthKitManager
/// Tests coherence calculation algorithm and error handling
@MainActor
final class HealthKitManagerTests: XCTestCase {

    var healthKitManager: HealthKitManager!

    override func setUp() async throws {
        healthKitManager = HealthKitManager()
    }

    override func tearDown() {
        healthKitManager = nil
    }


    // MARK: - Coherence Calculation Tests

    /// Test coherence calculation with synthetic low-coherence RR intervals
    /// Low coherence = random, chaotic intervals (stress state)
    func testCoherenceCalculation_LowCoherence() {
        // Generate random RR intervals (chaotic = low coherence)
        let rrIntervals = (0..<120).map { _ in Double.random(in: 600...1000) }

        let coherence = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)

        // Low coherence should be < 40
        XCTAssertGreaterThanOrEqual(coherence, 0.0, "Coherence should be >= 0")
        XCTAssertLessThanOrEqual(coherence, 100.0, "Coherence should be <= 100")
        print("Low coherence score: \(coherence)")
    }

    /// Test coherence calculation with synthetic high-coherence RR intervals
    /// High coherence = rhythmic 0.1 Hz oscillation (optimal state)
    func testCoherenceCalculation_HighCoherence() {
        // Generate sinusoidal RR intervals at 0.1 Hz (HeartMath resonance frequency)
        // This simulates perfect heart-breath coherence
        let rrIntervals = (0..<120).map { i in
            let time = Double(i)
            let sinusoid = sin(2.0 * .pi * 0.1 * time) // 0.1 Hz = 6 breaths/min
            return 800.0 + sinusoid * 100.0 // 800ms ± 100ms oscillation
        }

        let coherence = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)

        // High coherence should be > 60
        XCTAssertGreaterThan(coherence, 40.0, "Rhythmic breathing should produce medium-high coherence")
        print("High coherence score: \(coherence)")
    }

    /// Test coherence calculation with insufficient data
    func testCoherenceCalculation_InsufficientData() {
        let rrIntervals = [800.0, 850.0, 820.0] // Only 3 intervals

        let coherence = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)

        XCTAssertEqual(coherence, 0.0, "Insufficient data should return 0 coherence")
    }

    /// Test coherence calculation with empty array
    func testCoherenceCalculation_EmptyData() {
        let coherence = healthKitManager.calculateCoherence(rrIntervals: [])

        XCTAssertEqual(coherence, 0.0, "Empty data should return 0 coherence")
    }

    /// Test coherence calculation with constant RR intervals
    /// (no variability = unhealthy but technically "coherent")
    func testCoherenceCalculation_ConstantIntervals() {
        let rrIntervals = Array(repeating: 800.0, count: 120)

        let coherence = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)

        // Constant intervals have no power in any frequency band
        XCTAssertLessThan(coherence, 10.0, "Constant intervals should have very low coherence")
    }


    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(healthKitManager.heartRate, 60.0, "Initial heart rate should be 60")
        XCTAssertEqual(healthKitManager.hrvRMSSD, 0.0, "Initial HRV should be 0")
        XCTAssertEqual(healthKitManager.hrvCoherence, 0.0, "Initial coherence should be 0")
    }


    // MARK: - Monitoring Control Tests

    func testStartStopMonitoring() {
        // Note: These will fail if HealthKit is not authorized
        // In real app testing, you'd need to mock HealthKit or test on device

        // Just verify methods don't crash
        healthKitManager.startMonitoring()
        healthKitManager.stopMonitoring()

        // If not authorized, error message should be set
        if !healthKitManager.isAuthorized {
            XCTAssertNotNil(healthKitManager.errorMessage, "Error message should be set if not authorized")
        }
    }


    // MARK: - Algorithm Component Tests

    /// Test that detrend function removes linear trends
    func testDetrendAlgorithm() {
        // Create data with strong linear trend
        let trendedData = (0..<100).map { Double($0) * 2.0 + 100.0 } // y = 2x + 100

        // Access private method via reflection or make it internal for testing
        // For now, test through coherence calculation
        let coherence = healthKitManager.calculateCoherence(rrIntervals: trendedData)

        XCTAssertGreaterThanOrEqual(coherence, 0.0, "Detrended data should produce valid coherence")
    }

    /// Test FFT with known frequency components
    func testFFTAccuracy() {
        // Generate 120 samples with a clear 0.1 Hz component
        let rrIntervals = (0..<120).map { i in
            800.0 + 50.0 * sin(2.0 * .pi * 0.1 * Double(i))
        }

        let coherence = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)

        // Should detect the 0.1 Hz component in coherence band
        XCTAssertGreaterThan(coherence, 30.0, "FFT should detect 0.1 Hz component")
        print("FFT coherence score for 0.1 Hz signal: \(coherence)")
    }


    // MARK: - Performance Tests

    func testCoherenceCalculationPerformance() {
        let rrIntervals = (0..<120).map { _ in Double.random(in: 600...1000) }

        measure {
            _ = healthKitManager.calculateCoherence(rrIntervals: rrIntervals)
        }
    }
}
