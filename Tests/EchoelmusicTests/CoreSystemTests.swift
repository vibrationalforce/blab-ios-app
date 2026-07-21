#if canImport(AVFoundation)
// CoreSystemTests.swift
// Echoelmusic — Phase 1 Test Coverage
//
// Tests for core infrastructure: NumericExtensions,
// AudioConstants, TuningReference, MusicalNote

import XCTest
@testable import Echoelmusic


// MARK: - VideoFrameQueue Tests

final class VideoFrameQueueTests: XCTestCase {

    func testEnqueueDequeueFrame() {
        let queue = VideoFrameQueue(capacity: 4)
        queue.enqueue(textureHandle: 1, presentationTime: 0.033, width: 1920, height: 1080)

        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 1)

        let frame = queue.dequeue()
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.textureHandle, 1)
        XCTAssertEqual(frame?.width, 1920)
        XCTAssertEqual(frame?.height, 1080)
        XCTAssertEqual(frame?.frameNumber, 0)
    }

    func testFrameNumberIncrement() {
        let queue = VideoFrameQueue(capacity: 8)
        queue.enqueue(textureHandle: 1, presentationTime: 0.0, width: 100, height: 100)
        queue.enqueue(textureHandle: 2, presentationTime: 0.033, width: 100, height: 100)

        let first = queue.dequeue()
        let second = queue.dequeue()
        XCTAssertEqual(first?.frameNumber, 0)
        XCTAssertEqual(second?.frameNumber, 1)
    }
}

// MARK: - BioDataQueue Tests

final class BioDataQueueTests: XCTestCase {

    func testEnqueueDequeueSample() {
        let queue = BioDataQueue(capacity: 8)
        queue.enqueue(heartRate: 72.0, hrvCoherence: 65.0, breathPhase: 0.5)

        XCTAssertFalse(queue.isEmpty)
        let sample = queue.dequeue()
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.heartRate, 72.0)
        XCTAssertEqual(sample?.hrvCoherence, 65.0)
        XCTAssertEqual(sample?.breathPhase, 0.5)
    }

    func testNormalizedCoherence() {
        let queue = BioDataQueue(capacity: 4)
        queue.enqueue(heartRate: 70, hrvCoherence: 50.0, breathPhase: 0.0)
        let sample = queue.dequeue()
        XCTAssertEqual(sample?.normalizedCoherence ?? -1, 0.5, accuracy: 0.01)
    }
}

// MARK: - NumericExtensions Tests

final class NumericExtensionsTests: XCTestCase {

    func testClampedWithinRange() {
        XCTAssertEqual(5.clamped(to: 0...10), 5)
        XCTAssertEqual(0.5.clamped(to: 0.0...1.0), 0.5)
    }

    func testClampedBelowRange() {
        XCTAssertEqual((-5).clamped(to: 0...10), 0)
        XCTAssertEqual((-0.1).clamped(to: 0.0...1.0), 0.0)
    }

    func testClampedAboveRange() {
        XCTAssertEqual(15.clamped(to: 0...10), 10)
        XCTAssertEqual(1.5.clamped(to: 0.0...1.0), 1.0)
    }

    func testMappedFloatingPoint() {
        let result = 0.5.mapped(from: 0.0...1.0, to: 0.0...100.0)
        XCTAssertEqual(result, 50.0, accuracy: 0.001)
    }

    func testMappedFromZeroRange() {
        // Zero-width source range should return lower bound of target
        let result = 5.0.mapped(from: 5.0...5.0, to: 0.0...100.0)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testMappedBinaryInteger() {
        let result = 50.mapped(from: 0...100, to: 0...200)
        XCTAssertEqual(result, 100)
    }

    func testLerp() {
        XCTAssertEqual(0.0.lerp(to: 10.0, amount: 0.5), 5.0, accuracy: 0.001)
        XCTAssertEqual(0.0.lerp(to: 10.0, amount: 0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(0.0.lerp(to: 10.0, amount: 1.0), 10.0, accuracy: 0.001)
    }
}

// MARK: - AudioConstants Tests

final class AudioConstantsTests: XCTestCase {

    func testBufferSizes() {
        XCTAssertEqual(AudioConstants.ultraLowLatencyBuffer, 128)
        XCTAssertEqual(AudioConstants.lowLatencyBuffer, 256)
        XCTAssertEqual(AudioConstants.normalBuffer, 512)
        XCTAssertEqual(AudioConstants.highQualityBuffer, 1024)
    }

    func testCarrierFrequencies() {
        XCTAssertEqual(AudioConstants.standardCarrierFrequency, 440.0)
        XCTAssertEqual(AudioConstants.alternativeCarrierFrequency, 432.0)
    }

    func testBrainwaveFrequencies() {
        XCTAssertEqual(AudioConstants.Brainwave.delta, 2.0)
        XCTAssertEqual(AudioConstants.Brainwave.theta, 6.0)
        XCTAssertEqual(AudioConstants.Brainwave.alpha, 10.0)
        XCTAssertEqual(AudioConstants.Brainwave.beta, 20.0)
        XCTAssertEqual(AudioConstants.Brainwave.gamma, 40.0)
    }

    func testBrainwaveRanges() {
        XCTAssertTrue(AudioConstants.Brainwave.deltaRange.contains(2.0))
        XCTAssertTrue(AudioConstants.Brainwave.thetaRange.contains(6.0))
        XCTAssertTrue(AudioConstants.Brainwave.alphaRange.contains(10.0))
        XCTAssertTrue(AudioConstants.Brainwave.betaRange.contains(20.0))
        XCTAssertTrue(AudioConstants.Brainwave.gammaRange.contains(40.0))
    }

    func testCoherenceNormalize() {
        XCTAssertEqual(AudioConstants.Coherence.normalize(50.0 as Double), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioConstants.Coherence.normalize(0.0 as Double), 0.0, accuracy: 0.001)
        XCTAssertEqual(AudioConstants.Coherence.normalize(100.0 as Double), 1.0, accuracy: 0.001)
    }

    func testCoherenceNormalizeClamps() {
        XCTAssertEqual(AudioConstants.Coherence.normalize(-10.0 as Double), 0.0, accuracy: 0.001)
        XCTAssertEqual(AudioConstants.Coherence.normalize(150.0 as Double), 1.0, accuracy: 0.001)
    }

    func testCoherenceNormalizeFloat() {
        let result: Float = AudioConstants.Coherence.normalize(75.0 as Float)
        XCTAssertEqual(result, 0.75, accuracy: 0.01)
    }

    func testCoherenceDenormalize() {
        XCTAssertEqual(AudioConstants.Coherence.denormalize(0.5), 50.0, accuracy: 0.001)
        XCTAssertEqual(AudioConstants.Coherence.denormalize(1.0), 100.0, accuracy: 0.001)
    }

    func testCoherenceThresholds() {
        XCTAssertTrue(AudioConstants.Coherence.isLowCoherence(30.0))
        XCTAssertFalse(AudioConstants.Coherence.isLowCoherence(50.0))
        XCTAssertTrue(AudioConstants.Coherence.isHighCoherence(70.0))
        XCTAssertFalse(AudioConstants.Coherence.isHighCoherence(50.0))
    }

    func testAmplitudeRanges() {
        XCTAssertLessThanOrEqual(AudioConstants.minAmplitude, AudioConstants.defaultAmplitude)
        XCTAssertLessThanOrEqual(AudioConstants.defaultAmplitude, AudioConstants.maxSafeAmplitude)
    }

    func testBreathingConstants() {
        XCTAssertEqual(AudioConstants.Breathing.coherenceBreathsPerMinute, 6.0)
        XCTAssertEqual(AudioConstants.Breathing.inhaleDuration + AudioConstants.Breathing.exhaleDuration,
                       AudioConstants.Breathing.cycleDuration, accuracy: 0.01)
    }
}

// MARK: - MusicalNote Tests

final class MusicalNoteTests: XCTestCase {

    func testA4FromFrequency() {
        let note = MusicalNote.fromFrequency(440.0)
        XCTAssertEqual(note.name, "A")
        XCTAssertEqual(note.octave, 4)
        XCTAssertEqual(note.midiNumber, 69)
        XCTAssertEqual(note.displayName, "A4")
    }

    func testMiddleCFromFrequency() {
        let note = MusicalNote.fromFrequency(261.63)
        XCTAssertEqual(note.name, "C")
        XCTAssertEqual(note.octave, 4)
        XCTAssertEqual(note.midiNumber, 60)
    }

    func testZeroFrequency() {
        let note = MusicalNote.fromFrequency(0)
        XCTAssertEqual(note.name, "-")
        XCTAssertEqual(note.frequency, 0)
    }

    func testNegativeFrequency() {
        let note = MusicalNote.fromFrequency(-100)
        XCTAssertEqual(note.name, "-")
    }

    func testCustomReferenceA4() {
        // With A4=432, 432 Hz should be A4
        let note = MusicalNote.fromFrequency(432.0, referenceA4: 432.0)
        XCTAssertEqual(note.name, "A")
        XCTAssertEqual(note.octave, 4)
    }

    func testNoteNames() {
        XCTAssertEqual(MusicalNote.noteNames.count, 12)
        XCTAssertEqual(MusicalNote.noteNames.first, "C")
        XCTAssertEqual(MusicalNote.noteNames.last, "B")
    }
}
#endif
