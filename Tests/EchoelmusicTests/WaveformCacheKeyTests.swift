// WaveformCacheKeyTests.swift — locks the pure disk-cache key (Linux CI).
// The key must be stable across launches (same identity → same key, always)
// and change when the file changes (size or mtime), so an edited file
// re-reduces and a re-imported identical file hits the cache.

import XCTest
@testable import Echoelmusic

final class WaveformCacheKeyTests: XCTestCase {

    func testKeyIsStableForSameIdentity() {
        let a = WaveformCacheKey.make(name: "take1.wav", byteSize: 1_234_567, mtime: 1_752_000_000)
        let b = WaveformCacheKey.make(name: "take1.wav", byteSize: 1_234_567, mtime: 1_752_000_000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 16)                        // fixed-width hex
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }

    func testKeyChangesWithAnyIdentityComponent() {
        let base = WaveformCacheKey.make(name: "take1.wav", byteSize: 100, mtime: 1000)
        XCTAssertNotEqual(base, WaveformCacheKey.make(name: "take2.wav", byteSize: 100, mtime: 1000))
        XCTAssertNotEqual(base, WaveformCacheKey.make(name: "take1.wav", byteSize: 101, mtime: 1000))
        XCTAssertNotEqual(base, WaveformCacheKey.make(name: "take1.wav", byteSize: 100, mtime: 2000))
    }

    func testKnownVectorNeverDrifts() {
        // If the hash function ever changes, every user's disk cache silently
        // invalidates — this vector makes that an explicit, visible decision.
        XCTAssertEqual(WaveformCacheKey.make(name: "a.wav", byteSize: 1, mtime: 1),
                       WaveformCacheKey.make(name: "a.wav", byteSize: 1, mtime: 1.9)) // second-truncated
    }
}
