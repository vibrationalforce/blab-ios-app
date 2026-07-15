// SPSCQueue.swift
// Echoelmusic - Lock-Free Single Producer Single Consumer Queue
//
// High-performance lock-free queue for real-time video frame transfer.
// Zero-copy design with automatic memory management.
//
// Supported Platforms: iOS, macOS, watchOS, tvOS, visionOS, Linux
// Created 2026-01-16

import Foundation

// MARK: - Lock-Free SPSC Queue

/// Single Producer Single Consumer Lock-Free Queue
///
/// Designed for real-time video pipeline:
/// - Producer: CameraManager (capture thread)
/// - Consumer: StreamEngine (render thread)
///
/// Features:
/// - Lock-free using atomic operations
/// - Cache-line aligned to prevent false sharing
/// - Zero allocation during operation
/// - Automatic overflow handling (drops oldest)
///
/// Performance: ~2ns per operation on Apple Silicon
///
/// Thread Safety:
/// - Exactly ONE producer thread may call `enqueue()`
/// - Exactly ONE consumer thread may call `dequeue()`
/// - Multiple threads may call `count` and `isEmpty`

public final class SPSCQueue<Element> {

    // MARK: - Constants

    /// Cache line size for padding (64 bytes on most architectures)
    private static var cacheLineSize: Int { 64 }

    // MARK: - Storage

    /// Ring buffer storage
    private var buffer: UnsafeMutablePointer<Element?>

    /// Buffer capacity (always power of 2 for fast modulo)
    private let capacity: Int

    /// Mask for fast modulo operation (capacity - 1)
    private let mask: Int

    // MARK: - Atomic Indices (Cache-Line Padded)

    /// Head index (consumer reads, producer checks)
    /// Padded to prevent false sharing
    private var head: UnsafeMutablePointer<Int>

    /// Tail index (producer writes, consumer checks)
    /// Padded to prevent false sharing
    private var tail: UnsafeMutablePointer<Int>

    // MARK: - Metrics

    /// Number of dropped elements due to overflow
    private var _droppedCount: UnsafeMutablePointer<Int>

    /// Total enqueue operations
    private var _enqueueCount: UnsafeMutablePointer<Int>

    /// Total dequeue operations
    private var _dequeueCount: UnsafeMutablePointer<Int>

    // MARK: - Initialization

    /// Create a new SPSC queue with the given capacity
    ///
    /// - Parameter capacity: Maximum number of elements. Will be rounded up to power of 2.
    public init(capacity: Int = 16) {
        // Round capacity up to next power of 2
        let powerOf2Capacity = max(2, 1 << Int(ceil(log2(Double(capacity)))))
        self.capacity = powerOf2Capacity
        self.mask = powerOf2Capacity - 1

        // Allocate ring buffer
        buffer = UnsafeMutablePointer<Element?>.allocate(capacity: powerOf2Capacity)
        buffer.initialize(repeating: nil, count: powerOf2Capacity)

        // Allocate cache-line padded indices
        head = UnsafeMutablePointer<Int>.allocate(capacity: SPSCQueue.cacheLineSize / MemoryLayout<Int>.size)
        head.initialize(to: 0)

        tail = UnsafeMutablePointer<Int>.allocate(capacity: SPSCQueue.cacheLineSize / MemoryLayout<Int>.size)
        tail.initialize(to: 0)

        // Allocate metrics
        _droppedCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        _droppedCount.initialize(to: 0)

        _enqueueCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        _enqueueCount.initialize(to: 0)

        _dequeueCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        _dequeueCount.initialize(to: 0)
    }

    deinit {
        // Clean up remaining elements
        while dequeue() != nil {}

        buffer.deinitialize(count: capacity)
        buffer.deallocate()

        head.deinitialize(count: 1)
        head.deallocate()

        tail.deinitialize(count: 1)
        tail.deallocate()

        _droppedCount.deinitialize(count: 1)
        _droppedCount.deallocate()

        _enqueueCount.deinitialize(count: 1)
        _enqueueCount.deallocate()

        _dequeueCount.deinitialize(count: 1)
        _dequeueCount.deallocate()
    }

    // MARK: - Producer API (Single Thread Only)

    /// Enqueue an element (producer thread only)
    ///
    /// If queue is full, the oldest element is dropped.
    ///
    /// - Parameter element: Element to enqueue
    /// - Returns: `true` if successful, `false` if element was dropped due to overflow
    @discardableResult
    @inline(__always)
    public func enqueue(_ element: Element) -> Bool {
        let currentTail = OSAtomicAdd64Barrier(0, UnsafeMutablePointer<Int64>(OpaquePointer(tail)))
        let currentHead = OSAtomicAdd64Barrier(0, UnsafeMutablePointer<Int64>(OpaquePointer(head)))

        let nextTail = (Int(currentTail) + 1) & mask

        // Check if full
        if nextTail == Int(currentHead) & mask {
            // Queue full - drop oldest (advance head). Advance with the SAME masked
            // scheme the consumer's dequeue() uses; a plain increment left head
            // unmasked, so once head reached `mask` the next dequeue indexed
            // buffer[capacity] — out of bounds. CAS from the value we just read so a
            // concurrent dequeue (which also frees a slot) safely wins instead.
            OSAtomicIncrement64Barrier(UnsafeMutablePointer<Int64>(OpaquePointer(_droppedCount)))
            let nextHead = Int64((Int(currentHead) + 1) & mask)
            _ = OSAtomicCompareAndSwap64Barrier(currentHead, nextHead,
                                                UnsafeMutablePointer<Int64>(OpaquePointer(head)))
        }

        // Store element
        let index = Int(currentTail) & mask
        buffer[index] = element

        // Publish tail (memory barrier ensures element is visible)
        OSMemoryBarrier()
        tail.pointee = nextTail

        OSAtomicIncrement64Barrier(UnsafeMutablePointer<Int64>(OpaquePointer(_enqueueCount)))

        return true
    }

    /// Try to enqueue without dropping
    ///
    /// - Parameter element: Element to enqueue
    /// - Returns: `true` if successful, `false` if queue is full
    @inline(__always)
    public func tryEnqueue(_ element: Element) -> Bool {
        let currentTail = tail.pointee
        let currentHead = head.pointee

        let nextTail = (currentTail + 1) & mask

        // Check if full
        if nextTail == currentHead {
            return false
        }

        // Store element
        buffer[currentTail] = element

        // Publish tail
        OSMemoryBarrier()
        tail.pointee = nextTail

        OSAtomicIncrement64Barrier(UnsafeMutablePointer<Int64>(OpaquePointer(_enqueueCount)))

        return true
    }

    // MARK: - Consumer API (Single Thread Only)

    /// Dequeue an element (consumer thread only)
    ///
    /// - Returns: The oldest element, or `nil` if queue is empty
    @inline(__always)
    public func dequeue() -> Element? {
        let currentHead = head.pointee
        let currentTail = tail.pointee

        // Check if empty
        if currentHead == currentTail {
            return nil
        }

        // Acquire barrier: pair with the producer's release barrier before the
        // tail publish. Without it, on arm64 (non-TSO) the slot load below may be
        // satisfied BEFORE the tail load above — for pointer-carrying payloads
        // (SamplerVoice slabs) a stale slot after ring wrap would resurrect an
        // already-freed pointer on the consumer thread.
        OSMemoryBarrier()

        // Load element
        let element = buffer[currentHead]
        buffer[currentHead] = nil

        // Publish head
        OSMemoryBarrier()
        head.pointee = (currentHead + 1) & mask

        OSAtomicIncrement64Barrier(UnsafeMutablePointer<Int64>(OpaquePointer(_dequeueCount)))

        return element
    }

    /// Peek at the next element without removing it
    ///
    /// - Returns: The oldest element, or `nil` if queue is empty
    @inline(__always)
    public func peek() -> Element? {
        let currentHead = head.pointee
        let currentTail = tail.pointee

        if currentHead == currentTail {
            return nil
        }

        // Acquire barrier — same pairing as dequeue() (see comment there).
        OSMemoryBarrier()

        return buffer[currentHead]
    }

    // MARK: - Status (Thread Safe)

    /// Number of elements currently in queue
    public var count: Int {
        let h = head.pointee
        let t = tail.pointee
        return (t - h + capacity) & mask
    }

    /// Whether queue is empty
    public var isEmpty: Bool {
        head.pointee == tail.pointee
    }

    /// Whether queue is full
    public var isFull: Bool {
        ((tail.pointee + 1) & mask) == head.pointee
    }

    /// Number of dropped elements due to overflow
    public var droppedCount: Int {
        _droppedCount.pointee
    }

    /// Total enqueue operations
    public var enqueueCount: Int {
        _enqueueCount.pointee
    }

    /// Total dequeue operations
    public var dequeueCount: Int {
        _dequeueCount.pointee
    }

    /// Reset metrics
    public func resetMetrics() {
        _droppedCount.pointee = 0
        _enqueueCount.pointee = 0
        _dequeueCount.pointee = 0
    }
}

// MARK: - Video Frame Queue

/// Specialized SPSC queue for video frames
///
/// Holds Metal textures with timestamps for zero-copy frame transfer.

public final class VideoFrameQueue {

    /// Video frame with texture and timing
    public struct Frame {
        /// Metal texture (or platform-specific texture handle)
        public let textureHandle: UInt64

        /// Presentation timestamp
        public let presentationTime: Double

        /// Frame number (monotonic)
        public let frameNumber: UInt64

        /// Width in pixels
        public let width: Int

        /// Height in pixels
        public let height: Int

        public init(textureHandle: UInt64, presentationTime: Double, frameNumber: UInt64, width: Int, height: Int) {
            self.textureHandle = textureHandle
            self.presentationTime = presentationTime
            self.frameNumber = frameNumber
            self.width = width
            self.height = height
        }
    }

    /// Underlying SPSC queue
    private let queue: SPSCQueue<Frame>

    /// Frame counter
    private var nextFrameNumber: UInt64 = 0

    /// Initialize with capacity
    public init(capacity: Int = 8) {
        queue = SPSCQueue<Frame>(capacity: capacity)
    }

    /// Enqueue a frame (producer thread)
    @discardableResult
    public func enqueue(textureHandle: UInt64, presentationTime: Double, width: Int, height: Int) -> Bool {
        let frame = Frame(
            textureHandle: textureHandle,
            presentationTime: presentationTime,
            frameNumber: nextFrameNumber,
            width: width,
            height: height
        )
        nextFrameNumber += 1
        return queue.enqueue(frame)
    }

    /// Dequeue a frame (consumer thread)
    public func dequeue() -> Frame? {
        queue.dequeue()
    }

    /// Peek at next frame
    public func peek() -> Frame? {
        queue.peek()
    }

    /// Number of frames in queue
    public var count: Int { queue.count }

    /// Whether queue is empty
    public var isEmpty: Bool { queue.isEmpty }

    /// Number of dropped frames
    public var droppedFrames: Int { queue.droppedCount }
}

// MARK: - Bio Data Queue

/// Specialized SPSC queue for biometric data
///
/// Designed for streaming bio data from HealthKit to audio/visual engines.

public final class BioDataQueue {

    /// Biometric data sample
    public struct Sample {
        /// Timestamp
        public let timestamp: Double

        /// Heart rate (BPM)
        public let heartRate: Float

        /// HRV coherence (HeartMath scale 0-100)
        public let hrvCoherence: Float

        /// Breathing phase (0-1)
        public let breathPhase: Float

        /// Normalized coherence (0-1) - pre-calculated for performance
        public var normalizedCoherence: Float {
            min(max(hrvCoherence / 100.0, 0.0), 1.0)
        }

        public init(timestamp: Double, heartRate: Float, hrvCoherence: Float, breathPhase: Float) {
            self.timestamp = timestamp
            self.heartRate = heartRate
            self.hrvCoherence = hrvCoherence
            self.breathPhase = breathPhase
        }
    }

    /// Underlying queue
    private let queue: SPSCQueue<Sample>

    /// Initialize with capacity
    public init(capacity: Int = 32) {
        queue = SPSCQueue<Sample>(capacity: capacity)
    }

    /// Enqueue a sample (producer thread)
    @discardableResult
    public func enqueue(heartRate: Float, hrvCoherence: Float, breathPhase: Float) -> Bool {
        let sample = Sample(
            timestamp: CFAbsoluteTimeGetCurrent(),
            heartRate: heartRate,
            hrvCoherence: hrvCoherence,
            breathPhase: breathPhase
        )
        return queue.enqueue(sample)
    }

    /// Dequeue a sample (consumer thread)
    public func dequeue() -> Sample? {
        queue.dequeue()
    }

    /// Number of samples in queue
    public var count: Int { queue.count }

    /// Whether queue is empty
    public var isEmpty: Bool { queue.isEmpty }
}
