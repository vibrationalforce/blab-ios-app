// ColabPayload.swift
// Echoel — the wire format for Live Colabo (nearby peer-to-peer session sharing).
// Kept OUTSIDE the MultipeerConnectivity gate so it's pure Foundation/Codable and
// ci.yml can execute its round-trip test on Linux (MultipeerConnectivity is iOS-only).
// Forward-compatible (optional fields) so a newer sender never breaks an older receiver.

import Foundation

/// One person's live bio numbers for the side-by-side Colabo display
/// (kind "bio", ecosystem plan E5). Each person sees their OWN values next to
/// each other — never combined into a cross-person score (decision 2026-06-20:
/// no cross-person coherence readout; connected music-making yes, "group sync
/// score" no). `0` means "not available", mirroring `BioSampleFrame`.
public struct BioPeek: Codable, Sendable, Equatable {
    public var bpm: Float
    public var coherence: Float       // 0…1; 0 = not available
    public var hrvNormalized: Float   // 0…1
    public var breathRate: Float      // breaths/min; 0 = not available

    public init(bpm: Float, coherence: Float, hrvNormalized: Float, breathRate: Float) {
        self.bpm = bpm
        self.coherence = coherence
        self.hrvNormalized = hrvNormalized
        self.breathRate = breathRate
    }
}

public struct ColabPayload: Codable, Sendable, Equatable {
    public var kind: String          // "session" | "bio"; reserved: "tempo", "chat"…
    public var senderName: String
    public var project: Project?
    /// Live bio reading (kind "bio"). Optional so older receivers ignore it.
    public var bio: BioPeek?

    public init(kind: String, senderName: String, project: Project? = nil, bio: BioPeek? = nil) {
        self.kind = kind; self.senderName = senderName; self.project = project; self.bio = bio
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data) -> ColabPayload? {
        try? JSONDecoder().decode(ColabPayload.self, from: data)
    }
}
