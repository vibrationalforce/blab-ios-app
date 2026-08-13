import XCTest
@testable import Echoelmusic

@MainActor
final class SequencerTests: XCTestCase {

    var engine: PatternEngine!

    override func setUp() async throws {
        engine = PatternEngine()
    }

    override func tearDown() async throws {
        engine.stop()
        engine = nil
    }

    // MARK: - Initial state

    func testInit_notPlaying() {
        XCTAssertFalse(engine.isPlaying)
    }

    func testInit_currentStep_zero() {
        XCTAssertEqual(engine.currentStep, 0)
    }

    func testInit_tempo_isDefault() {
        XCTAssertEqual(engine.tempo, PatternEngine.defaultTempo, accuracy: 0.001)
    }

    func testInit_grid_8tracks() {
        XCTAssertEqual(engine.steps.count, PatternEngine.trackCount)
    }

    func testInit_grid_16stepsPerTrack() {
        for track in engine.steps {
            XCTAssertEqual(track.count, PatternEngine.stepCount)
        }
    }

    func testInit_grid_allOff() {
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    // MARK: - toggleStep

    func testToggleStep_inBounds_flipsOnce() {
        engine.toggleStep(track: 0, step: 0)
        XCTAssertTrue(engine.steps[0][0])
    }

    func testToggleStep_inBounds_flipsTwice() {
        engine.toggleStep(track: 0, step: 0)
        engine.toggleStep(track: 0, step: 0)
        XCTAssertFalse(engine.steps[0][0])
    }

    func testToggleStep_negativeTrack_noOp() {
        engine.toggleStep(track: -1, step: 0)
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    func testToggleStep_trackOutOfRange_noOp() {
        engine.toggleStep(track: PatternEngine.trackCount, step: 0)
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    func testToggleStep_negativeStep_noOp() {
        engine.toggleStep(track: 0, step: -1)
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    func testToggleStep_stepOutOfRange_noOp() {
        engine.toggleStep(track: 0, step: PatternEngine.stepCount)
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    // MARK: - setStep

    func testSetStep_on_setsTrue() {
        engine.setStep(track: 3, step: 5, on: true)
        XCTAssertTrue(engine.steps[3][5])
    }

    func testSetStep_off_setsFalse() {
        engine.setStep(track: 3, step: 5, on: true)
        engine.setStep(track: 3, step: 5, on: false)
        XCTAssertFalse(engine.steps[3][5])
    }

    func testSetStep_outOfRange_noOp() {
        engine.setStep(track: 99, step: 99, on: true)
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    // MARK: - clear

    func testClear_allStepsOff() {
        engine.toggleStep(track: 0, step: 0)
        engine.toggleStep(track: 7, step: 15)
        engine.clear()
        XCTAssertTrue(engine.steps.flatMap { $0 }.allSatisfy { $0 == false })
    }

    func testClear_doesNotChangeTempo() {
        engine.setTempo(140, source: .user)
        engine.clear()
        XCTAssertEqual(engine.tempo, 140, accuracy: 0.001)
    }

    // MARK: - setTempo

    func testSetTempo_inRange_setsExactly() {
        engine.setTempo(140.0, source: .user)
        XCTAssertEqual(engine.tempo, 140.0, accuracy: 0.001)
    }

    func testSetTempo_belowMin_clampsToMin() {
        engine.setTempo(20.0, source: .user)
        XCTAssertEqual(engine.tempo, PatternEngine.minTempo, accuracy: 0.001)
    }

    func testSetTempo_aboveMax_clampsToMax() {
        engine.setTempo(500.0, source: .user)
        XCTAssertEqual(engine.tempo, PatternEngine.maxTempo, accuracy: 0.001)
    }

    // MARK: - play / stop

    func testPlay_setsIsPlaying() {
        engine.play()
        XCTAssertTrue(engine.isPlaying)
    }

    func testPlay_resetsCurrentStepToZero() {
        engine.play()
        XCTAssertEqual(engine.currentStep, 0)
    }

    func testPlay_idempotent() {
        engine.play()
        engine.play()
        XCTAssertTrue(engine.isPlaying)
    }

    func testStop_resetsIsPlaying() {
        engine.play()
        engine.stop()
        XCTAssertFalse(engine.isPlaying)
    }

    func testStop_resetsCurrentStep() {
        engine.play()
        engine.stop()
        XCTAssertEqual(engine.currentStep, 0)
    }

    func testStop_idempotent() {
        engine.stop()
        engine.stop()
        XCTAssertFalse(engine.isPlaying)
    }

    // MARK: - onStep callback wiring

    func testOnStep_canBeAssigned() {
        // Compile-time sanity: callback signature is (Int, Int) -> Void
        engine.onStep = { _, _ in }
        XCTAssertNotNil(engine.onStep)
    }

    // MARK: - Groove: the bar's "one" is anchored

    func testGroovedVelocity_theOneIsStrongestBeat() {
        // Founder ("die Eins zu erkennen"): step 0 (the bar downbeat) must be the
        // loudest grooved (non-accented) hit — louder than beats 2·3·4 (steps 4·8·12),
        // an 8th (step 2) and an off-16th (step 1) — so the ear anchors to the one.
        let one    = PatternEngine.groovedVelocity(track: 0, step: 0)
        let beat3  = PatternEngine.groovedVelocity(track: 0, step: 8)
        let eighth = PatternEngine.groovedVelocity(track: 0, step: 2)
        let ghost  = PatternEngine.groovedVelocity(track: 0, step: 1)
        XCTAssertGreaterThan(one, beat3)
        XCTAssertGreaterThan(one, eighth)
        XCTAssertGreaterThan(one, ghost)
        XCTAssertGreaterThan(beat3, ghost)
        XCTAssertLessThanOrEqual(one, PatternEngine.accentVelocity)   // stays under a drawn accent
    }
}
