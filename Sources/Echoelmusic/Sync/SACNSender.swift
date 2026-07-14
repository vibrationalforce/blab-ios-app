//
//  SACNSender.swift
//  Echoelmusic — EchoelSync / EchoelLux
//
//  Native sACN / ANSI E1.31 output over UDP (port 5568) — the streaming-ACN
//  standard for DMX over IP, the second open lighting standard alongside
//  Art-Net (completes EchoelLux for large rigs). No SDK, no dependency: builds
//  the full E1.31 Data Packet by hand and sends via Network.framework.
//
//  iOS NOTE (important): sACN is multicast by spec (239.255.{uniHi}.{uniLo}),
//  but iOS gates multicast send/receive behind the special, Apple-approval-only
//  `com.apple.developer.networking.multicast` entitlement. E1.31 ALSO permits
//  UNICAST to a specific receiver, which most consoles/nodes accept and which
//  works on iOS with just Local Network permission (already declared). So we
//  ship UNICAST by default (host + universe). `multicastHost(universe:)` is
//  provided for when the multicast entitlement is granted.
//
//  Bio → DMX mapping is shared with ArtNetSender (`dmxChannels`) so both
//  standards drive the same bio-reactive fixture. Epilepsy-safe by construction
//  (smooth continuous fades, ≤3 Hz — see ArtNetSender).
//
//  E1.31 Data Packet (638 bytes for a full 512-slot universe):
//    Root layer (38) · Framing layer (77) · DMP layer (10 + 1 start code + 512).
//

#if canImport(Network)
import Foundation
import Network
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class SACNSender {

    /// Receiver IP (unicast). For multicast (entitlement required) set this to
    /// `SACNSender.multicastHost(universe:)`.
    public var host: String {
        didSet { Self.persistTarget(host, port, universe); reconnectIfActive() }
    }

    /// E1.31 port is fixed at 5568 by the standard, kept configurable.
    public var port: UInt16 {
        didSet { Self.persistTarget(host, port, universe); reconnectIfActive() }
    }

    /// 1-based E1.31 universe (1…63999). 0 is invalid in sACN.
    public var universe: Int {
        didSet { Self.persistTarget(host, port, universe) }   // packet content, no socket change
    }

    /// DMX value resolution (shared with Art-Net): 16-bit coarse/fine pairs by
    /// default for professional precision, 8-bit for legacy fixtures.
    public var resolution: ArtNetSender.DMXResolution = .sixteenBit

    public private(set) var isActive = false
    public private(set) var lastSentTimestamp: TimeInterval = 0

    /// L1 Grand Master + Blackout — same law as Art-Net
    /// (`ArtNetSender.masteredDimmer`): blackout wins, master scales. Live
    /// state, not persisted; the PatchbayView "Licht" section drives both
    /// senders together.
    public var grandMaster: Float = 1
    public var blackout = false

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private let loop = PollingLoop()
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1
    @ObservationIgnored private var lastSentGrandMaster: Float = 1
    @ObservationIgnored private var lastSentBlackout = false
    /// Slew anchor for the flash guard (−1 = uninitialised → first frame lands
    /// at target). Mirrors ArtNetSender: the mastered dimmer ramps ≤0.08/tick so
    /// a Blackout release (or a Grand-Master jump) can never strobe physical
    /// fixtures — the ≤3 Hz / W3C-WCAG flash hard law applies to sACN too.
    @ObservationIgnored private var lastDimmer: Float = -1
    @ObservationIgnored private var sequence: UInt8 = 0
    /// Sender CID — stable per instance (E1.31 requires a unique component id).
    @ObservationIgnored private let cid: [UInt8]

    public init(host: String = "192.168.1.100", port: UInt16 = 5568, universe: Int = 1) {
        let d = UserDefaults.standard
        self.host = d.string(forKey: Self.hostKey) ?? host
        let p = d.integer(forKey: Self.portKey)
        self.port = (p > 0 && p <= 65_535) ? UInt16(p) : port
        let u = d.integer(forKey: Self.universeKey)
        self.universe = (u >= 1 && u <= 63_999) ? u : Swift.max(1, universe)
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: UUID().uuid) { raw in
            for i in 0..<16 { bytes[i] = raw[i] }
        }
        self.cid = bytes
    }

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        connect()
        isActive = true
        loop.start(interval: .milliseconds(33)) { [weak self] in   // ~30 Hz, smooth
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

    // MARK: - Target persistence + live reconnect

    private static let hostKey = "net.sacn.host"
    private static let portKey = "net.sacn.port"
    private static let universeKey = "net.sacn.universe"
    private static func persistTarget(_ host: String, _ port: UInt16, _ universe: Int) {
        let d = UserDefaults.standard
        d.set(host, forKey: hostKey)
        d.set(Int(port), forKey: portKey)
        d.set(universe, forKey: universeKey)
    }
    /// A host/port edit takes effect immediately while the output is live (connect()
    /// otherwise only runs in start()): drop the old socket, reconnect. Idle ⇒ no-op.
    private func reconnectIfActive() {
        guard isActive else { return }
        connection?.cancel()
        connect()
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
        // Music drives the COLOUR when sounding (SpectralColor), bio otherwise.
        // Dedup on the chosen source's timestamp. (sACN shares Art-Net's mapping.)
        let music = bus.freshMusical(maxAge: 1.5)
        let sourceTimestamp: TimeInterval
        var channels: [UInt8]
        let dimmer: Float
        if let m = music, m.isSounding {
            sourceTimestamp = m.timestamp
            channels = MusicMediaMap.dmxChannels(forMusic: m, resolution: resolution)
            dimmer = MusicMediaMap.dimmerUnit(forMusic: m)
        } else if let frame = bus.latestBio {
            sourceTimestamp = frame.timestamp
            channels = ArtNetSender.dmxChannels(for: frame, resolution: resolution)
            dimmer = ArtNetSender.dimmerUnit(for: frame)
        } else {
            return
        }
        let mastered = ArtNetSender.masteredDimmer(dimmer, grandMaster: grandMaster, blackout: blackout)
        // Send when the source is fresh, the master state moved, OR the slew ramp
        // hasn't reached its target yet — so a paused source can't freeze a fade
        // mid-ramp, and a blackout is never blocked. (Mirrors ArtNetSender.)
        let masterMoved = grandMaster != lastSentGrandMaster || blackout != lastSentBlackout
        let slewSettling = lastDimmer >= 0 && abs(mastered - lastDimmer) > 0.001
        guard sourceTimestamp != lastFrameTimestamp || masterMoved || slewSettling else { return }
        lastFrameTimestamp = sourceTimestamp
        lastSentGrandMaster = grandMaster
        lastSentBlackout = blackout
        // Hard flash guarantee for PHYSICAL fixtures: slew-limit the dimmer so
        // even a Blackout release or a pathological jump ramps up from dark
        // instead of snapping (~0.08/tick → full fade ≥0.4 s, ~1.2 Hz max). Same
        // shared decision as ArtNetSender — identical guarantee on both protocols.
        let limited = FlashGuard.slewedDimmer(from: lastDimmer, to: mastered, blackout: blackout)
        lastDimmer = limited
        ArtNetSender.applyDimmer(&channels, resolution: resolution, dimmer: limited)
        let packet = Self.e131Packet(universe: universe, sequence: sequence, cid: cid, channels: channels)
        sequence = sequence &+ 1   // wraps 0…255 (0 is valid in E1.31)
        send(packet)
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    private func send(_ data: Data) {
        guard let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Pure kernels (testable without a socket)

    /// The spec multicast group for a universe: 239.255.{high}.{low}.
    public static func multicastHost(universe: Int) -> String {
        let u = Swift.max(1, universe)
        return "239.255.\((u >> 8) & 0xFF).\(u & 0xFF)"
    }

    /// Builds a full E1.31 Data Packet (always 512 slots). `channels` is padded
    /// to 512 with zeros. `cid` must be 16 bytes. Pure — unit-testable.
    public static func e131Packet(universe: Int, sequence: UInt8, cid: [UInt8], channels: [UInt8]) -> Data {
        let slotCount = 512
        var slots = channels
        if slots.count < slotCount { slots += Array(repeating: 0, count: slotCount - slots.count) }
        if slots.count > slotCount { slots = Array(slots.prefix(slotCount)) }
        let cid16 = cid.count == 16 ? cid : Array((cid + Array(repeating: 0, count: 16)).prefix(16))
        let uni = Swift.max(1, universe)

        let total = 126 + slotCount                 // 638
        func flagsLen(_ pduLen: Int) -> [UInt8] {   // 0x7 high nibble + 12-bit length
            let v = 0x7000 | (pduLen & 0x0FFF)
            return [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }

        var d = Data()
        // ---- Root layer (38) ----
        d.append(contentsOf: [0x00, 0x10])          // Preamble size
        d.append(contentsOf: [0x00, 0x00])          // Postamble size
        d.append(contentsOf: [0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00]) // "ASC-E1.17"
        d.append(contentsOf: flagsLen(total - 16))  // Root flags+length
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x04]) // Vector ROOT_E131_DATA
        d.append(contentsOf: cid16)                 // CID (16)
        // ---- Framing layer (77) ----
        d.append(contentsOf: flagsLen(total - 38))  // Framing flags+length
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x02]) // Vector E131_DATA_PACKET
        var name = Array("Echoelmusic".utf8); name = Array((name + Array(repeating: 0, count: 64)).prefix(64))
        d.append(contentsOf: name)                  // Source Name (64)
        d.append(100)                               // Priority
        d.append(contentsOf: [0x00, 0x00])          // Sync address
        d.append(sequence)                          // Sequence number
        d.append(0x00)                              // Options
        d.append(contentsOf: [UInt8((uni >> 8) & 0xFF), UInt8(uni & 0xFF)]) // Universe (BE)
        // ---- DMP layer (10 + 513) ----
        d.append(contentsOf: flagsLen(total - 115)) // DMP flags+length
        d.append(0x02)                              // Vector DMP_SET_PROPERTY
        d.append(0xA1)                              // Address type & data type
        d.append(contentsOf: [0x00, 0x00])          // First property address
        d.append(contentsOf: [0x00, 0x01])          // Address increment
        let propCount = slotCount + 1               // 513 (start code + 512)
        d.append(contentsOf: [UInt8((propCount >> 8) & 0xFF), UInt8(propCount & 0xFF)])
        d.append(0x00)                              // DMX start code
        d.append(contentsOf: slots)                 // 512 slots
        return d
    }
}
#endif
