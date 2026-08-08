// MultipeerSession.swift
// Echoel — Live Colabo (nearby, peer-to-peer). The DMMW "Live Collaboration"
// pillar's first concrete capability: two phones on the same Wi-Fi/AWDL find each
// other and SHARE a full session (the Codable Project — style·key·tempo·patch·
// notes·drums) with one tap, so collaborators can jam off the same starting point.
//
// Apple's MultipeerConnectivity only — NO external dependency. Real-time tempo/
// phase lock (Ableton Link) is a separate, device-verified step; this is the
// dependency-free, fully-buildable foundation.
//
// Concurrency (mirrors MIDIInput): an @MainActor @Observable class whose MC
// delegate methods are `nonisolated` (MC calls them off-main) and hop back via
// `Task { @MainActor [weak self] in }`. MCPeerID is not Sendable, so it crosses
// the hop inside an explicit @unchecked Sendable box. MCSession/MCPeerID are
// created once and held as immutable `nonisolated let` (MCSession is internally
// thread-safe for send/connectedPeers), so the off-main invitation handler is safe.

#if canImport(MultipeerConnectivity)
import Foundation
import Observation
// @preconcurrency: MultipeerConnectivity's delegate types (MCSession/MCPeerID/…) are
// not Sendability-audited; this suppresses the cross-actor Sendable warnings on the
// nonisolated delegate hops under -strict-concurrency=complete + -warnings-as-errors
// (same as PolarH10BioPublisher's `@preconcurrency import CoreBluetooth`).
@preconcurrency import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif

/// Ferries a non-Sendable reference (MCPeerID) across an actor hop. Safe because
/// MCPeerID is immutable and only used on the main actor after the hop.
private struct UncheckedBox<T>: @unchecked Sendable { let value: T }

/// A peer the browser has found and we could invite.
public struct DiscoveredPeer: Identifiable, Equatable, Sendable {
    public let id: String            // displayName (unique enough for a nearby session)
    public var name: String { id }
}

/// An incoming invitation awaiting the user's EXPLICIT consent. Never auto-accepted
/// (App Store audit 2026-07-16, 5.1.1/5.1.2): while colab is live the user may be
/// sharing live bio readings — WHO receives them is the user's call, not any nearby
/// device's. `respond` wraps MC's invitationHandler; call it exactly once.
public struct PendingInvitation: Identifiable {
    public let id = UUID()
    public let peerName: String
    let respond: (Bool) -> Void
}

@MainActor
@Observable
public final class MultipeerSession: NSObject {

    /// ≤15 chars, lowercase letters/digits/hyphens (MC requirement). "echoel-colab" = 12.
    public static let serviceType = "echoel-colab"

    // MARK: - Observed state
    public private(set) var isLive = false
    public private(set) var connectedPeerNames: [String] = []
    public private(set) var discovered: [DiscoveredPeer] = []
    /// Set when a peer sends us a session — the UI offers to load/import it.
    public private(set) var incoming: ColabPayload?
    /// Set when a nearby device asks to join — the UI shows an Accept/Decline
    /// card; nothing connects until the user answers (never auto-accepted).
    public private(set) var pendingInvitation: PendingInvitation?
    /// Last status line for the UI (e.g. "Shared with 2 peers").
    public private(set) var status: String = "Off"
    /// Live bio per connected peer (E5): display name → last reading AND when it
    /// arrived here. Shown SIDE BY SIDE with our own — never combined into a
    /// cross-person score (decision 2026-06-20). Cleared on disconnect/stop.
    /// Updates arrive at the sender's ~2.5 Hz — read this only in leaf views
    /// (render safety).
    ///
    /// ⚠️ IT IS `PeerReading` AND NOT `BioPeek` ON PURPOSE (#508). A bare peek has no
    /// time on it, so every reader would have to invent its own answer to "is this peer
    /// still sending?" — and the honest answer is not derivable from the numbers. Ask
    /// `PeerReading.live(at:)`; never render `.peek` directly. That one substitution is
    /// what keeps a pocketed phone from showing a perfectly steady pulse on someone
    /// else's screen for the rest of the session.
    public private(set) var peerReadings: [String: PeerReading] = [:]

    /// Called when a session payload arrives (e.g. import into the library / load live).
    public var onReceiveSession: ((ColabPayload) -> Void)?

    // MARK: - MC objects (immutable references; MCSession is internally thread-safe)
    // MCSession/MCPeerID are NOT Sendable, so a plain `nonisolated let` is illegal.
    // The reference is immutable and only the off-main advertiser invitation handler
    // touches `mcSession` (a thread-safe MC call), so `nonisolated(unsafe)` is correct.
    private let myPeerID: MCPeerID
    private nonisolated(unsafe) let mcSession: MCSession

    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    /// displayName → MCPeerID, so the UI can invite by name (MainActor-only).
    @ObservationIgnored private var peerIDs: [String: MCPeerID] = [:]

    public override init() {
        // @MainActor init, so UIDevice (MainActor API) is directly accessible.
        #if canImport(UIKit)
        let raw = UIDevice.current.name
        #else
        let raw = ProcessInfo.processInfo.hostName
        #endif
        let name = String(raw.prefix(63))
        let id = MCPeerID(displayName: name.isEmpty ? "Echoelmusic" : name)
        self.myPeerID = id
        self.mcSession = MCSession(peer: id, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        self.mcSession.delegate = self
    }

    // MARK: - Lifecycle

    /// Begin advertising AND browsing so any two Echoel devices discover each other.
    public func start() {
        guard !isLive else { return }
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        let br = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        br.delegate = self
        advertiser = adv
        browser = br
        adv.startAdvertisingPeer()
        br.startBrowsingForPeers()
        isLive = true
        status = "Looking for nearby Echoelmusic…"
    }

    public func stop() {
        // Never leave an MC invitation handler dangling — decline it so the
        // inviter gets an answer instead of a 20 s timeout.
        pendingInvitation?.respond(false)
        pendingInvitation = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        mcSession.disconnect()
        isLive = false
        discovered.removeAll()
        peerIDs.removeAll()
        connectedPeerNames.removeAll()
        peerReadings.removeAll()
        status = "Off"
    }

    /// Invite a discovered peer (by display name) into the session.
    public func invite(_ name: String) {
        guard let peer = peerIDs[name], let browser else { return }
        browser.invitePeer(peer, to: mcSession, withContext: nil, timeout: 20)
        status = "Inviting \(name)…"
    }

    /// Send a whole session to every connected peer.
    public func share(project: Project) {
        let payload = ColabPayload(kind: "session", senderName: myPeerID.displayName, project: project)
        guard let data = payload.encoded() else { return }
        let peers = mcSession.connectedPeers
        guard !peers.isEmpty else { status = "No peers connected"; return }
        do {
            try mcSession.send(data, toPeers: peers, with: .reliable)
            status = "Shared with \(peers.count) peer\(peers.count == 1 ? "" : "s")"
        } catch {
            status = "Share failed"
        }
    }

    /// Clear the incoming-session prompt after the UI handles it.
    public func clearIncoming() { incoming = nil }

    /// The user's answer to the pending join request. Responds to MC exactly
    /// once and clears the card; a no-op when nothing is pending.
    public func respondToInvitation(accept: Bool) {
        guard let pending = pendingInvitation else { return }
        pendingInvitation = nil
        pending.respond(accept)
        if accept {
            status = "Joining \(pending.peerName)…"
        } else if isLive {
            status = connectedPeerNames.isEmpty ? "Looking for nearby Echoelmusic…" : status
        }
    }

    /// Surface an invitation for explicit consent. One at a time: a newer
    /// invitation DECLINES the previous pending one (an unanswered MC handler
    /// would dangle into the inviter's timeout). Internal for tests.
    func handleInvitation(from name: String, respond: @escaping (Bool) -> Void) {
        pendingInvitation?.respond(false)
        pendingInvitation = PendingInvitation(peerName: name, respond: respond)
        status = "\(name) wants to join"
    }

    /// Stream one live bio reading to every connected peer (E5). Unreliable
    /// transport by design — a lost telemetry frame is worthless a moment later;
    /// never let it queue behind a session transfer. The cadence is
    /// `PeerReading.sendInterval`, and the receiver's staleness window is derived
    /// from it (#508), so a drop is expected and a silence is meaningful.
    ///
    /// ⛔ THIS TOOK A `BioPeek` UNTIL #511, and that is why the App Store 5.1.3 egress
    /// gate could only live at the CALL SITE: a peek carries no source, so this method
    /// had nothing to check. The note that stood here registered the fix and named its
    /// price ("moving it would need this signature to take the frame rather than the
    /// peek"); it is paid. Taking the FRAME means the rule is applied by the thing that
    /// sends, not by whoever remembers — and `BioPeek.egressible(from:)` is the one
    /// place that decides it, calling `BioEgressPolicy` rather than restating it (#186).
    ///
    /// ⚠️ Do NOT add a `sendBio(_ peek: BioPeek)` overload back "for convenience". The
    /// whole point is that a peek can no longer reach the wire without a source having
    /// been asked about first.
    public func sendBio(_ frame: BioSampleFrame) {
        guard let peek = BioPeek.egressible(from: frame) else { return }
        let peers = mcSession.connectedPeers
        guard !peers.isEmpty else { return }
        let payload = ColabPayload(kind: "bio", senderName: myPeerID.displayName, bio: peek)
        guard let data = payload.encoded() else { return }
        try? mcSession.send(data, toPeers: peers, with: .unreliable)
    }

    // MARK: - MainActor handlers (called from the nonisolated delegates)

    private func handleFound(_ peerID: MCPeerID) {
        peerIDs[peerID.displayName] = peerID
        if !discovered.contains(where: { $0.id == peerID.displayName }) {
            discovered.append(DiscoveredPeer(id: peerID.displayName))
        }
    }

    private func handleLost(_ name: String) {
        peerIDs[name] = nil
        discovered.removeAll { $0.id == name }
    }

    private func handleStateChange(_ name: String, connected: Bool) {
        if connected {
            if !connectedPeerNames.contains(name) { connectedPeerNames.append(name) }
            discovered.removeAll { $0.id == name }
            status = "Connected to \(name)"
        } else {
            connectedPeerNames.removeAll { $0 == name }
            peerReadings[name] = nil
            if connectedPeerNames.isEmpty && isLive { status = "Looking for nearby Echoelmusic…" }
        }
    }

    private func handleData(_ data: Data) {
        guard let payload = ColabPayload.decode(data) else { return }
        // Bio pings update the per-peer reading quietly — no incoming prompt,
        // no status churn (they arrive continuously while a peer shares).
        if payload.kind == "bio", let peek = payload.bio {
            // Stamped with OUR clock at the moment it arrived (#508). The peek carries
            // no time, and a sender field could not report the failures that matter —
            // a dropped link, a backgrounded app, a peer that crashed. Only arrival
            // here can distinguish a peer still breathing from one that went quiet.
            peerReadings[payload.senderName] = PeerReading(peek: peek,
                                                           arrivedAt: CFAbsoluteTimeGetCurrent())
            return
        }
        incoming = payload
        onReceiveSession?(payload)
        status = "Session received from \(payload.senderName)"
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        let connected = (state == .connected)
        Task { @MainActor [weak self] in self?.handleStateChange(name, connected: connected) }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.handleData(data) }
    }

    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser (invitations require explicit user consent)

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                       didReceiveInvitationFromPeer peerID: MCPeerID,
                                       withContext context: Data?,
                                       invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // NEVER auto-accept (App Store audit 2026-07-16): while colab is live the
        // user may be streaming live bio to connected peers — a silent join would
        // hand that stream to any nearby device. Hop to the MainActor and surface
        // an Accept/Decline card; the handler (non-Sendable closure) crosses the
        // hop boxed, and `mcSession` is the nonisolated(unsafe) immutable ref MC
        // accepts from any thread. If the user never answers, MC's own inviter
        // timeout (20 s) resolves it; stop() declines a still-pending card.
        let name = peerID.displayName
        let handlerBox = UncheckedBox(value: invitationHandler)
        // MCSession is non-Sendable — box it across the hop like MCPeerID
        // (immutable ref; MC accepts the handler's session from any thread).
        let sessionBox = UncheckedBox(value: mcSession)
        Task { @MainActor [weak self] in
            self?.handleInvitation(from: name) { accept in
                handlerBox.value(accept, accept ? sessionBox.value : nil)
            }
        }
    }
}

// MARK: - Browser

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let box = UncheckedBox(value: peerID)
        Task { @MainActor [weak self] in self?.handleFound(box.value) }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor [weak self] in self?.handleLost(name) }
    }
}

#endif
