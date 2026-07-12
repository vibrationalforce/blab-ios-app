//
//  ADMOSCSender.swift
//  Echoelmusic — EchoelSync module
//
//  Bridges the live bio bus to ADM-OSC — the open Audio-Definition-Model-over-
//  OSC standard (github.com/immersive-audio-live/ADM-OSC) for object-based
//  audio positioning. Adamson FletcherMachine, L-ISA, d&b Soundscape, Spat,
//  Nuendo etc. all speak it, so this one bridge makes Echoel a bio-reactive
//  OBJECT SOURCE for any immersive rig — body drives an audio object's position
//  and gain in the room, live, over an open standard. No SDK, no new dependency:
//  reuses OSCSender.encode(address:floats:).
//
//  This is opt-in (not every user has an immersive renderer); started from the
//  Sync tab, off by default. See scratchpads/SPEC_ADM_OSC_BRIDGE.md.
//
//  ADM-OSC v1.0 namespace (one 1-based object index `n`):
//    /adm/obj/{n}/position/azimuth     float  -180 … +180  (degrees)
//    /adm/obj/{n}/position/elevation   float   -90 … +90   (degrees)
//    /adm/obj/{n}/position/distance    float     0 … 1     (normalized)
//    /adm/obj/{n}/gain                 float     0 … 1     (linear, ≤ 1.0)
//
//  Default bio → object mapping (all four are existing BioSampleFrame fields):
//    breath phase → azimuth    sound sweeps L↔R with the breath
//    coherence    → distance   coherent = pulled close; scattered = far
//    HRV          → elevation  calm lifts the object
//    motion       → gain       movement brings it forward
//

#if canImport(Network)
import Foundation
import Network
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class ADMOSCSender {

    /// Renderer host. FletcherMachine / immersive consoles are usually a LAN box.
    public var host: String

    /// Renderer OSC port. ADM-OSC renderers typically listen on a port distinct
    /// from TouchOSC's 8000 — default 9000, user-configurable.
    public var port: UInt16

    /// 1-based ADM object index this bio source drives.
    public var objectIndex: Int

    public private(set) var isActive = false

    /// CFAbsoluteTime of the last datagram sent — lets the UI render an activity
    /// dot without a timer (mirrors OSCSender).
    public private(set) var lastSentTimestamp: TimeInterval = 0

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private let loop = PollingLoop()
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1

    public init(host: String = "127.0.0.1", port: UInt16 = 9000, objectIndex: Int = 1) {
        self.host = host
        self.port = port
        self.objectIndex = max(1, objectIndex)
    }

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        connect()
        isActive = true
        loop.start(interval: .milliseconds(50)) { [weak self] in   // ~20 Hz for smooth motion
            guard let self, let bus = self.bus else { return }
            self.sendIfFresh(from: bus)
        }
    }

    public func stop() {
        loop.stop()
        connection?.cancel()
        connection = nil
        isActive = false
    }

    // MARK: - Connection

    private func connect() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: .main)
        self.connection = conn
    }

    // MARK: - Subscriber tick

    private func sendIfFresh(from bus: EngineBus) {
        // Music drives the object POSITION when sounding (pitch→azimuth/elevation,
        // level→distance/gain), bio otherwise — bio stays the co-modulator. Dedup on
        // the chosen source's timestamp so a music-only change still moves the object.
        let music = bus.freshMusical(maxAge: 1.5)
        let sourceTimestamp: TimeInterval
        let messages: [(String, Float)]
        if let m = music, m.isSounding {
            sourceTimestamp = m.timestamp
            messages = MusicMediaMap.admMessages(forMusic: m, object: objectIndex)
        } else if let frame = bus.latestBio {
            sourceTimestamp = frame.timestamp
            messages = Self.admMessages(for: frame, object: objectIndex)
        } else {
            return
        }
        guard sourceTimestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = sourceTimestamp
        for (address, value) in messages {
            send(address: address, floats: [value])
        }
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    private func send(address: String, floats: [Float]) {
        guard let conn = connection else { return }
        // Reuse the audited OSC 1.0 encoder — ADM-OSC is plain OSC on the wire.
        let data = OSCSender.encode(address: address, floats: floats)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Scene-driven send (S2 — no callers yet, bio subscriber stays default)

    /// Pushes an entire SpatialScene through the open socket in the given
    /// dialect (ADM-OSC or IEM). Formatting is the pure
    /// `SpatialSceneOSCFormatter` (golden-file tested); this method only
    /// moves bytes. Nothing calls it today — the live bio→object subscriber
    /// above remains the only active behaviour until the spatialEngine flag
    /// path lands, so Release is bit-identical.
    public func send(scene: SpatialScene, dialect: SpatialOSCDialect = .admOSC) {
        guard connection != nil else { return }
        for message in SpatialSceneOSCFormatter.messages(for: scene, dialect: dialect) {
            send(address: message.address, floats: [message.value])
        }
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    // MARK: - Pure mapping kernel (testable without a socket)

    /// Maps a bio frame to the ADM-OSC (address, value) pairs for object `n`.
    /// Pure value-in/value-out — unit-tested without a socket, like `encode`.
    /// All values are clamped into their ADM-OSC v1.0 ranges.
    public static func admMessages(for f: BioSampleFrame, object n: Int) -> [(String, Float)] {
        let idx = max(1, n)
        let prefix = "/adm/obj/\(idx)"
        // breath phase [0..1] → azimuth [-180..180]: L↔R sweep with the breath
        let azimuth = clamp((f.breathPhase * 2 - 1) * 180, -180, 180)
        // coherence [0..1] → distance [0..1]: coherent pulls close (small distance)
        let distance = clamp(1 - f.coherence, 0, 1)
        // HRV [0..1] → elevation [-90..90]: calm lifts (use upper hemisphere 0..60)
        let elevation = clamp(f.hrvNormalized * 60, -90, 90)
        // motion [0..1] → gain [0..1]: movement brings the object forward
        let gain = clamp(0.3 + f.motionEnergy * 0.7, 0, 1)
        return [
            ("\(prefix)/position/azimuth", azimuth),
            ("\(prefix)/position/elevation", elevation),
            ("\(prefix)/position/distance", distance),
            ("\(prefix)/gain", gain)
        ]
    }

    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(v, lo), hi)
    }
}
#endif
