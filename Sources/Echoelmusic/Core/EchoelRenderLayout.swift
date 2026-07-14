// EchoelRenderLayout.swift
// The speaker/ring geometry EchoelRender reads to render a SpatialScene onto physical
// loudspeakers — the Swift model for docs/dev/ECHOEL_RENDER_LAYOUT.md (spec v1.0).
//
// The base is byte-for-byte IEM AllRADecoder `LoudspeakerLayout` JSON (so any Echoel
// layout imports straight into IEM/Grapes); everything physical (channel routing,
// sub/shaker groups, per-channel calibration, fallback) lives in a separate optional
// `EchoelRender` block that IEM tools ignore. A file WITHOUT that block is still valid
// (a plain IEM layout). Pure value types, Foundation-only (P4 portable core): Codable,
// Sendable, unit-tested on every platform — this is DATA ONLY, it activates nothing on
// the audio graph; the (flag-gated) renderer consumes it later.
//
// Coordinate convention (identical to IEM — never diverge): azimuth 0 = front,
// +90 = LEFT, -90 = right (right-handed); elevation 0 = ear level, + = up.

import Foundation

// MARK: - Base schema (IEM-compatible)

/// One loudspeaker in the IEM base layout. Capitalized JSON keys keep the round-trip
/// byte-compatible with IEM AllRADecoder / Grapes.
public struct Loudspeaker: Codable, Sendable, Equatable {
    public var azimuth: Double
    public var elevation: Double
    public var radius: Double
    public var isImaginary: Bool
    public var channel: Int
    public var gain: Double

    private enum CodingKeys: String, CodingKey {
        case azimuth = "Azimuth", elevation = "Elevation", radius = "Radius"
        case isImaginary = "IsImaginary", channel = "Channel", gain = "Gain"
    }

    public init(azimuth: Double, elevation: Double = 0, radius: Double = 1,
                isImaginary: Bool = false, channel: Int, gain: Double = 1) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.radius = radius
        self.isImaginary = isImaginary
        self.channel = channel
        self.gain = gain
    }

    // Legacy/partial files decode with sensible defaults (radius 1, gain 1, real).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        azimuth = try c.decodeIfPresent(Double.self, forKey: .azimuth) ?? 0
        elevation = try c.decodeIfPresent(Double.self, forKey: .elevation) ?? 0
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 1
        isImaginary = try c.decodeIfPresent(Bool.self, forKey: .isImaginary) ?? false
        channel = try c.decode(Int.self, forKey: .channel)
        gain = try c.decodeIfPresent(Double.self, forKey: .gain) ?? 1
    }
}

/// The IEM `LoudspeakerLayout` object.
public struct LoudspeakerLayout: Codable, Sendable, Equatable {
    public var name: String
    public var loudspeakers: [Loudspeaker]

    private enum CodingKeys: String, CodingKey { case name = "Name", loudspeakers = "Loudspeakers" }

    public init(name: String, loudspeakers: [Loudspeaker]) {
        self.name = name
        self.loudspeakers = loudspeakers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        loudspeakers = try c.decodeIfPresent([Loudspeaker].self, forKey: .loudspeakers) ?? []
    }

    /// Real (non-imaginary) loudspeakers — the ones that actually radiate.
    public var realSpeakers: [Loudspeaker] { loudspeakers.filter { !$0.isImaginary } }
    /// True when the layout is a flat ring (every real speaker at ear level).
    public var isPlanar: Bool { realSpeakers.allSatisfy { abs($0.elevation) < 0.001 } }
    /// True when an imaginary floor/ceiling speaker is present (AllRAD triangulation).
    public var hasImaginarySpeaker: Bool { loudspeakers.contains { $0.isImaginary } }
    /// The Channel numbers of the real speakers.
    public var realChannels: Set<Int> { Set(realSpeakers.map(\.channel)) }
    public var allChannels: Set<Int> { Set(loudspeakers.map(\.channel)) }
}

// MARK: - EchoelRender extension block

/// A channel reference that is either a logical index (`1`) or a named output
/// (`"sub"`, `"subA"`) — the `groups.*.channels` arrays mix both.
public enum ChannelRef: Codable, Sendable, Equatable, Hashable {
    case index(Int)
    case named(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .index(i) }
        else { self = .named(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .index(let i): try c.encode(i)
        case .named(let s): try c.encode(s)
        }
    }
    /// The integer channel if this is an index, else nil (a named output).
    public var intValue: Int? { if case .index(let i) = self { return i } else { return nil } }
    /// The channelMap key this ref uses ("1" for an index, the name for a named output).
    public var mapKey: String { switch self { case .index(let i): return String(i); case .named(let s): return s } }
}

public struct CoordinateSystem: Codable, Sendable, Equatable {
    public var azimuthZero: String?
    public var azimuthPositive: String?
    public var rightHanded: Bool?
    public var distanceUnit: String?
}

public struct RenderVenue: Codable, Sendable, Equatable {
    public var name: String?
    public var date: String?
    public var notes: String?
}

public struct OutputConfig: Codable, Sendable, Equatable {
    public var device: String?
    public var sampleRate: Int?
    /// logical channel key ("1", "sub") → physical interface output (1-based).
    public var channelMap: [String: Int]?
}

public struct SpeakerGroup: Codable, Sendable, Equatable {
    public var channels: [ChannelRef]
    public var role: String?
    public var coupling: String?
    public var crossoverHz: Double?
    public var cardioid: Bool?
    public var lowpassHz: Double?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channels = try c.decodeIfPresent([ChannelRef].self, forKey: .channels) ?? []
        role = try c.decodeIfPresent(String.self, forKey: .role)
        coupling = try c.decodeIfPresent(String.self, forKey: .coupling)
        crossoverHz = try c.decodeIfPresent(Double.self, forKey: .crossoverHz)
        cardioid = try c.decodeIfPresent(Bool.self, forKey: .cardioid)
        lowpassHz = try c.decodeIfPresent(Double.self, forKey: .lowpassHz)
    }
    private enum CodingKeys: String, CodingKey {
        case channels, role, coupling, crossoverHz, cardioid, lowpassHz
    }
    /// Only the integer channels of this group (named outputs like "sub" excluded).
    public var indexChannels: [Int] { channels.compactMap(\.intValue) }
}

public struct RenderGroups: Codable, Sendable, Equatable {
    public var ring: SpeakerGroup?
    public var subs: SpeakerGroup?
    public var shakers: SpeakerGroup?
}

public struct SpeakerCalibration: Codable, Sendable, Equatable {
    public var distanceM: Double?
    public var delayMs: Double?
    public var gainTrimDb: Double?
    public var limiterPeakDb: Double?
    public var limiterRmsDb: Double?
    public var model: String?
}

public struct DistanceModel: Codable, Sendable, Equatable {
    public var gain: Bool?
    public var airAbsorption: Bool?
    public var delayBasedDistance: Bool?
}

public struct RenderConfig: Codable, Sendable, Equatable {
    public var panner: String?          // "vbap" | "ambisonics"
    public var ambisonicsOrder: Int?
    public var diffusionFloorHz: Double?
    public var defaultFocus: Double?
    public var distanceModel: DistanceModel?

    /// True when this layout is driven by the Ambisonics decoder (needs a full
    /// triangulation incl. an imaginary floor speaker for a planar ring).
    public var usesAmbisonics: Bool { (panner ?? "vbap").lowercased() == "ambisonics" }
}

public struct StereoFallback: Codable, Sendable, Equatable {
    public var left: [Int]
    public var right: [Int]
}

public struct RenderFallback: Codable, Sendable, Equatable {
    public var stereo: StereoFallback?
}

/// The optional `EchoelRender` top-level block — routing, calibration, groups, fallback.
public struct EchoelRenderExtension: Codable, Sendable, Equatable {
    public var specVersion: String?
    public var coordinateSystem: CoordinateSystem?
    public var venue: RenderVenue?
    public var output: OutputConfig?
    public var groups: RenderGroups?
    public var speakers: [String: SpeakerCalibration]?
    public var render: RenderConfig?
    public var fallback: RenderFallback?
}

// MARK: - Top-level document

public struct EchoelRenderLayout: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var loudspeakerLayout: LoudspeakerLayout
    public var echoelRender: EchoelRenderExtension?

    private enum CodingKeys: String, CodingKey {
        case name = "Name", description = "Description"
        case loudspeakerLayout = "LoudspeakerLayout", echoelRender = "EchoelRender"
    }

    public init(name: String, description: String? = nil,
                loudspeakerLayout: LoudspeakerLayout,
                echoelRender: EchoelRenderExtension? = nil) {
        self.name = name
        self.description = description
        self.loudspeakerLayout = loudspeakerLayout
        self.echoelRender = echoelRender
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        loudspeakerLayout = try c.decode(LoudspeakerLayout.self, forKey: .loudspeakerLayout)
        echoelRender = try c.decodeIfPresent(EchoelRenderExtension.self, forKey: .echoelRender)
    }

    // MARK: Parse helpers

    /// Parse a layout from JSON data. Throws the underlying `DecodingError` on bad JSON.
    public static func decode(from data: Data) throws -> EchoelRenderLayout {
        try JSONDecoder().decode(EchoelRenderLayout.self, from: data)
    }

    /// Encode back to IEM-compatible JSON (the base block round-trips into IEM tools).
    public func encoded(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try enc.encode(self)
    }

    // MARK: - Validation (spec §6)

    /// A single validation problem (empty result from `validate()` = the layout is sound).
    public struct Issue: Equatable, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    /// The ring channels (integer) declared in the EchoelRender block, if any.
    public var ringChannels: [Int] { echoelRender?.groups?.ring?.indexChannels ?? [] }

    /// Validate against the spec's rules. Returns every problem found (empty = valid).
    /// A file with NO `EchoelRender` block is valid (a plain IEM layout) — only the base
    /// geometry is checked in that case.
    public func validate() -> [Issue] {
        var issues: [Issue] = []
        let layoutChannels = loudspeakerLayout.realChannels

        // Base geometry: azimuths of real speakers should be distinct (a doubled angle
        // means two boxes fight for the same image).
        let azis = loudspeakerLayout.realSpeakers.map { ($0.azimuth * 100).rounded() / 100 }
        if Set(azis).count != azis.count {
            issues.append(Issue("Duplicate azimuth among real loudspeakers — the stage image will collapse."))
        }

        guard let ext = echoelRender else { return issues }   // plain IEM layout: done.
        let channelMapKeys = Set(ext.output?.channelMap?.keys.map { $0 } ?? [])
        let mapHasKeys = ext.output?.channelMap != nil

        // Rule: every ring channel must have a Loudspeaker (by Channel) AND a channelMap entry.
        for ch in ringChannels {
            if !layoutChannels.contains(ch) {
                issues.append(Issue("ring channel \(ch) has no matching Loudspeaker (Channel \(ch)) in LoudspeakerLayout."))
            }
            if mapHasKeys, !channelMapKeys.contains(String(ch)) {
                issues.append(Issue("ring channel \(ch) is missing from output.channelMap."))
            }
        }

        // Rule: subs/shakers channels must NOT appear in LoudspeakerLayout (never panned).
        for group in [ext.groups?.subs, ext.groups?.shakers].compactMap({ $0 }) {
            for ch in group.indexChannels where layoutChannels.contains(ch) {
                issues.append(Issue("channel \(ch) is a sub/shaker but also appears in LoudspeakerLayout — subs are never panned."))
            }
        }

        // Rule: fallback.stereo.left/right may only reference ring channels.
        if let stereo = ext.fallback?.stereo {
            let ring = Set(ringChannels)
            for ch in stereo.left + stereo.right where !ring.contains(ch) {
                issues.append(Issue("fallback.stereo references channel \(ch), which is not a ring channel."))
            }
        }

        // Rule: a planar ring in Ambisonics mode needs an imaginary floor speaker.
        if ext.render?.usesAmbisonics == true,
           loudspeakerLayout.isPlanar, !loudspeakerLayout.hasImaginarySpeaker {
            issues.append(Issue("planar ring in Ambisonics mode needs an imaginary floor loudspeaker (Elevation -90, IsImaginary true) for a unique triangulation."))
        }

        return issues
    }

    /// Convenience: the layout is sound (no validation issues).
    public var isValid: Bool { validate().isEmpty }
}
