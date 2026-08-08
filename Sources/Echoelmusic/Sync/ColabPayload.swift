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

/// One peer's last reading, and WHEN it arrived HERE.
///
/// #508. `BioPeek` carries no time at all, so a receiver holding one cannot tell a peer
/// who is still breathing into their phone from a peer whose phone went into a pocket
/// ten minutes ago — the numbers just stand there, perfectly steady, on someone else's
/// screen. That is #503/#507's defect on the one surface where the stale number belongs
/// to a DIFFERENT PERSON, and that is what makes it worse here: your own held pulse is
/// at least yours, while a held peer pulse is a claim about a body you cannot see.
///
/// ⭐ THE STAMP IS ARRIVAL, NEVER A SENDER FIELD, and that is the load-bearing choice.
/// A `sentAt` on `BioPeek` would need a wire change, would be blank from every older
/// sender, and — the part that decides it — could not report the failures that actually
/// happen: a dropped Wi-Fi link, a backgrounded app, a peer that crashed. A sender
/// cannot tell you that it stopped sending. Only the receiver can notice.
///
/// ⚠️ The stamp lives WITH the value rather than in a parallel `[String: TimeInterval]`
/// (#416): two dictionaries would be two things to clear on every disconnect and stop
/// path, and the day one of them is missed the row lies again.
public struct PeerReading: Sendable, Equatable {

    /// How often a sharing peer sends one reading. ONE definition: `LiveColaboView`'s
    /// stream loop sleeps for exactly this, and `staleAfter` below is DERIVED from it,
    /// so changing the cadence moves the window with it instead of leaving one tuned
    /// for a rate nobody sends any more.
    public static let sendInterval: TimeInterval = 0.4

    /// Silence longer than this stops a row claiming a live peer. Derived: eight
    /// consecutive missed sends. The transport is deliberately `.unreliable` (a lost
    /// telemetry frame is worthless a moment later), so single drops are ordinary and
    /// a two-frame window would make every row flicker on normal Wi-Fi jitter.
    ///
    /// ⚠️ It is NOT a copy of `BioSource.freshnessWindow`, deliberately: it answers a
    /// DIFFERENT question. The sender already applied the freshness window to its own
    /// body before it sent anything; this window asks whether the NETWORK is still
    /// delivering. Reusing the 6 s here would double-count one question and answer the
    /// other never. The honest total latency is therefore the sum: up to the sender's
    /// own window, plus this one, from the last real measurement to a blanked row.
    public static let staleAfter: TimeInterval = sendInterval * 8

    public let peek: BioPeek
    /// `CFAbsoluteTimeGetCurrent()` at the moment this frame arrived on THIS device —
    /// never a sender clock. Two phones are not clock-synchronised.
    public let arrivedAt: TimeInterval

    public init(peek: BioPeek, arrivedAt: TimeInterval) {
        self.peek = peek
        self.arrivedAt = arrivedAt
    }

    /// The reading while it is still arriving; `nil` once the peer has gone quiet.
    ///
    /// The −1 s skew tolerance is not invented here — it is the same allowance
    /// `EngineBus.usableBio()` applies to its own frames, asked the same way rather
    /// than minted a second time (#416/#426). Non-finite inputs make every comparison
    /// false and therefore read as GONE: the safe direction, because blanking a row is
    /// cheaper than asserting a live person from a number nothing can date.
    public func live(at now: TimeInterval) -> BioPeek? {
        let age = now - arrivedAt
        guard age <= Self.staleAfter, age >= -1 else { return nil }
        return peek
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
