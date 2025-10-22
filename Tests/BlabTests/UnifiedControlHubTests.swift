import XCTest
@testable import Blab

/// Tests for UnifiedControlHub
@MainActor
final class UnifiedControlHubTests: XCTestCase {

    var sut: UnifiedControlHub!

    override func setUp() async throws {
        try await super.setUp()
        sut = UnifiedControlHub(audioEngine: nil)
    }

    override func tearDown() async throws {
        sut.stop()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertEqual(sut.activeInputMode, .automatic)
        XCTAssertTrue(sut.conflictResolved)
    }

    // MARK: - Control Loop Tests

    func testStart() {
        sut.start()

        // Wait a bit for control loop to run
        let expectation = XCTestExpectation(description: "Control loop starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Control loop should be running (frequency > 0)
        XCTAssertGreaterThan(sut.controlLoopFrequency, 0)
    }

    func testStop() {
        sut.start()

        // Wait for control loop to start
        let startExpectation = XCTestExpectation(description: "Control loop starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        sut.stop()

        // Wait for control loop to stop
        let stopExpectation = XCTestExpectation(description: "Control loop stops")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 1.0)

        // Frequency should drop to 0 or near 0 after stopping
        XCTAssertLessThan(sut.controlLoopFrequency, 10)
    }

    func testControlLoopFrequency() {
        sut.start()

        // Wait for control loop to stabilize
        let expectation = XCTestExpectation(description: "Control loop stabilizes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Control loop should be near 60 Hz (within ±10 Hz tolerance)
        let stats = sut.statistics
        XCTAssertGreaterThan(stats.frequency, 50)
        XCTAssertLessThan(stats.frequency, 70)
    }

    // MARK: - Statistics Tests

    func testStatistics() {
        sut.start()

        let expectation = XCTestExpectation(description: "Get statistics")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let stats = sut.statistics
        XCTAssertGreaterThan(stats.frequency, 0)
        XCTAssertEqual(stats.targetFrequency, 60.0)
        XCTAssertEqual(stats.activeInputMode, .automatic)
        XCTAssertTrue(stats.conflictResolved)
    }

    func testStatisticsRunningAtTarget() {
        sut.start()

        // Wait for control loop to stabilize
        let expectation = XCTestExpectation(description: "Control loop stabilizes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let stats = sut.statistics
        XCTAssertTrue(stats.isRunningAtTarget, "Control loop should be running at target frequency")
    }

    // MARK: - Generative Visuals

    func testSubmitGenerativeVisualRequestPublishesExperience() {
        let request = GenerativeVisualRequest(
            prompt: "Bioluminescent plaza",
            importedAssets: [
                .init(
                    kind: .image,
                    traits: [.architectural],
                    dominantColors: [
                        .init(hue: 0.45, saturation: 0.6, brightness: 0.8)
                    ],
                    metadata: ["subject": "museum façade"]
                )
            ],
            targetMediums: [.facadeProjection, .hologram],
            preferredTechnologies: [.projectionMapping],
            enableAudioReactivity: true,
            enableBioSignalModulation: false
        )

        let experience = sut.submitGenerativeVisualRequest(request)

        XCTAssertNotNil(sut.generativeVisualExperience)
        XCTAssertEqual(experience.summary.mediums, [.facadeProjection, .hologram])
    }

    func testRegenerateUsesLastRequestWhenNoneProvided() {
        let request = GenerativeVisualRequest(
            prompt: "Holographic garden",
            importedAssets: [
                .init(kind: .video, traits: [.holographic], dominantColors: [], metadata: [:])
            ],
            targetMediums: [.hologram],
            preferredTechnologies: [],
            enableAudioReactivity: true,
            enableBioSignalModulation: true
        )

        sut.submitGenerativeVisualRequest(request)
        sut.regenerateGenerativeVisualExperience()

        XCTAssertEqual(sut.generativeVisualExperience?.summary.mediums, [.hologram])
    }

    // MARK: - Utility Tests

    func testMapRange() {
        // Test linear mapping
        let result1 = sut.mapRange(0.5, from: 0...1, to: 0...100)
        XCTAssertEqual(result1, 50, accuracy: 0.01)

        let result2 = sut.mapRange(0.0, from: 0...1, to: 200...8000)
        XCTAssertEqual(result2, 200, accuracy: 0.01)

        let result3 = sut.mapRange(1.0, from: 0...1, to: 200...8000)
        XCTAssertEqual(result3, 8000, accuracy: 0.01)

        // Test clamping
        let result4 = sut.mapRange(-0.5, from: 0...1, to: 0...100)
        XCTAssertEqual(result4, 0, accuracy: 0.01, "Should clamp to minimum")

        let result5 = sut.mapRange(1.5, from: 0...1, to: 0...100)
        XCTAssertEqual(result5, 100, accuracy: 0.01, "Should clamp to maximum")
    }

    // MARK: - Input Mode Tests

    func testInputModeAutomatic() {
        XCTAssertEqual(sut.activeInputMode, .automatic)
    }

    // MARK: - Performance Tests

    func testControlLoopPerformance() {
        measure {
            sut.start()

            let expectation = XCTestExpectation(description: "Control loop runs")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)

            sut.stop()
        }
    }
}
