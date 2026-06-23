// ColabPayload.swift
// Echoel — the wire format for Live Colabo (nearby peer-to-peer session sharing).
// Kept OUTSIDE the MultipeerConnectivity gate so it's pure Foundation/Codable and
// ci.yml can execute its round-trip test on Linux (MultipeerConnectivity is iOS-only).
// Forward-compatible (optional fields) so a newer sender never breaks an older receiver.

import Foundation

public struct ColabPayload: Codable, Sendable, Equatable {
    public var kind: String          // "session" today; reserved for "tempo", "chat"…
    public var senderName: String
    public var project: Project?

    public init(kind: String, senderName: String, project: Project? = nil) {
        self.kind = kind; self.senderName = senderName; self.project = project
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data) -> ColabPayload? {
        try? JSONDecoder().decode(ColabPayload.self, from: data)
    }
}
