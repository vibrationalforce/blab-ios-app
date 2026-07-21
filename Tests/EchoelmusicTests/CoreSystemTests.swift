#if canImport(AVFoundation)
// CoreSystemTests.swift
// Echoelmusic — Phase 1 Test Coverage
//
// Tests for core infrastructure: VideoFrameQueue, BioDataQueue, NumericExtensions.
// (AudioConstants / MusicalNote tests removed 2026-07-21: AudioConstants was
//  replaced by AudioConfiguration and MusicalNote is now a {frequencyHz,
//  amplitude} chord note — the old pitch/name API no longer exists.)

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

#endif
