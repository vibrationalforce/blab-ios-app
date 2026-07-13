//
//  LightFixtureGroup.swift
//  Echoelmusic — Sync (EchoelLux L2)
//
//  A PURE, socket-free model that composes ONE DMX universe buffer from N fixtures,
//  each at its own start channel, all scaled by one Grand Master and cut together by
//  Blackout. This extends the L1 master law (ArtNetSender.masteredDimmer — one
//  fixture) to a whole rig, but stays free of any Network type so it needs no
//  `#if canImport(Network)`: it emits raw channel bytes and lets the sender do the
//  resolution/packet encoding later.
//
//  Deterministic (no RNG, no wall clock), bounded (buffer clamped to the 512-channel
//  DMX universe), and Codable with `decodeIfPresent` so a legacy light config decodes
//  byte-identically. NOTHING consumes this yet — Release stays bit-identical (the
//  senders are un-wired; the opt-in group path is a separate reversible cycle).
//

import Foundation

/// One lighting fixture placed on a DMX universe: a 1-based start channel carrying a
/// unit dimmer, followed by its colour channels (RGB / RGBW / … — any length).
public struct LightFixture: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity for UI/diffing — folded, never `Hasher` (process-stable).
    public var id: UUID
    /// 1-based DMX address of this fixture's FIRST (dimmer) channel.
    public var startChannel: Int
    /// Dimmer, unit [0…1] (scaled by the group master before it hits the wire).
    public var dimmerUnit: Float
    /// Colour channel bytes written immediately after the dimmer (e.g. R,G,B).
    public var colour: [UInt8]

    public init(id: UUID = UUID(), startChannel: Int, dimmerUnit: Float, colour: [UInt8]) {
        self.id = id
        self.startChannel = startChannel
        self.dimmerUnit = LightFixtureGroup.clampUnit(dimmerUnit)
        self.colour = colour
    }

    private enum CodingKeys: String, CodingKey { case id, startChannel, dimmerUnit, colour }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            startChannel: try c.decodeIfPresent(Int.self, forKey: .startChannel) ?? 1,
            dimmerUnit: try c.decodeIfPresent(Float.self, forKey: .dimmerUnit) ?? 1,
            colour: try c.decodeIfPresent([UInt8].self, forKey: .colour) ?? [])
    }
}

/// A group of fixtures sharing one Grand Master + Blackout (the L1 master law, fanned
/// out to N fixtures). Pure value type; `compose` builds the universe buffer.
public struct LightFixtureGroup: Codable, Sendable, Equatable {

    /// The DMX universe channel ceiling (1 universe = 512 slots).
    public static let universeSize = 512

    public var fixtures: [LightFixture]
    /// Master level [0…1] scaling every fixture's dimmer.
    public var grandMaster: Float
    /// Cuts ALL dimmers to 0 (colour bytes stay) — an instant edge, not a strobe.
    public var blackout: Bool

    public init(fixtures: [LightFixture] = [], grandMaster: Float = 1, blackout: Bool = false) {
        self.fixtures = fixtures
        self.grandMaster = Self.clampUnit(grandMaster)
        self.blackout = blackout
    }

    private enum CodingKeys: String, CodingKey { case fixtures, grandMaster, blackout }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fixtures: try c.decodeIfPresent([LightFixture].self, forKey: .fixtures) ?? [],
            grandMaster: try c.decodeIfPresent(Float.self, forKey: .grandMaster) ?? 1,
            blackout: try c.decodeIfPresent(Bool.self, forKey: .blackout) ?? false)
    }

    // MARK: - Compose (pure)

    /// The L1 master law (blackout wins; else Grand Master scales the dimmer linearly),
    /// re-implemented inline so the model needs no Network-guarded ArtNetSender type.
    public static func masteredDimmer(_ dimmer: Float, grandMaster: Float, blackout: Bool) -> Float {
        guard !blackout else { return 0 }
        let gm = clampUnit(grandMaster)
        return clampUnit(dimmer) * gm
    }

    /// Compose one DMX universe buffer: each fixture writes its mastered dimmer byte at
    /// its (1-based) start channel, then its colour bytes immediately after. The buffer
    /// grows to the highest channel any fixture touches, CLAMPED to 512; channels beyond
    /// the universe (or non-positive addresses) are dropped, never crash. Overlapping
    /// fixtures let the later one win at the shared channel (idiomatic DMX patching).
    public func composeUniverse() -> [UInt8] {
        // Size to the highest channel actually written WITHIN the universe. A fixture
        // whose start channel is outside [1…512] writes nothing and must not inflate the
        // buffer with zeros; a fixture straddling the ceiling is clamped at 512.
        var maxChannel = 0
        for f in fixtures where f.startChannel >= 1 && f.startChannel <= Self.universeSize {
            let end = Swift.min(f.startChannel + f.colour.count, Self.universeSize)  // last channel used
            maxChannel = Swift.max(maxChannel, end)
        }
        let size = maxChannel   // already ≤ universeSize
        guard size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        for f in fixtures where f.startChannel >= 1 && f.startChannel <= Self.universeSize {
            let mastered = Self.masteredDimmer(f.dimmerUnit, grandMaster: grandMaster, blackout: blackout)
            let dimIdx = f.startChannel - 1                       // 1-based → 0-based
            if dimIdx < size { buffer[dimIdx] = Self.byte(mastered) }
            for (i, c) in f.colour.enumerated() {
                let idx = dimIdx + 1 + i
                if idx < size { buffer[idx] = c }
            }
        }
        return buffer
    }

    // MARK: - Helpers

    static func clampUnit(_ x: Float) -> Float { Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1) }
    static func byte(_ unit: Float) -> UInt8 { UInt8(clampUnit(unit) * 255) }
}
