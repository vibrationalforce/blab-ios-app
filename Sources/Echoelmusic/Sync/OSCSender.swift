//
//  OSCSender.swift
//  Echoelmusic — EchoelSync module
//
//  Streams EngineBus.latestBio onto an OSC over UDP endpoint so any
//  companion tool — Resolume Arena, TouchDesigner, MadMapper, VDMX,
//  TouchOSC, Sonic Pi, TidalCycles — can subscribe to the bus
//  without knowing anything about Swift, CoreBluetooth, or HealthKit.
//
//  This is the moment Echoelmusic stops being a closed app and
//  becomes a peer in the wider live-performance toolchain.
//
//  OSC address space follows master prompt §2:
//    /echoelmusic/bio/heart/bpm     float [40..200]
//    /echoelmusic/bio/heart/hrv     float [0..1]
//    /echoelmusic/bio/breath/rate   float [4..30]
//    /echoelmusic/bio/breath/phase  float [0..1]
//    /echoelmusic/bio/coherence     float [0..1]
//    /echoelmusic/bio/motion        float [0..1]
//
//  Discrete BioEventGraph events (kind → address, args [confidence, aux]):
//    /echoelmusic/bio/event/heartbeat      float[2]  aux = inter-beat interval ms
//    /echoelmusic/bio/event/breath/inhale  float[2]
//    /echoelmusic/bio/event/breath/exhale  float[2]
//    /echoelmusic/bio/event/motion         float[2]
//    /echoelmusic/bio/event/coherence      float[2]
//    /echoelmusic/bio/event/eeg            float[2]  aux = band power
//
//  Default endpoint: localhost:8000 (same as TouchOSC default;
//  user-configurable in a later cycle).
//

#if canImport(Network)
import Foundation
import Network
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class OSCSender {

    public var host: String {
        didSet { Self.persistTarget(host, port); reconnectIfActive() }
    }

    public var port: UInt16 {
        didSet { Self.persistTarget(host, port); reconnectIfActive() }
    }

    public private(set) var isActive = false

    /// Mach-time of the last message sent. Lets the UI render an
    /// activity dot without spawning timers.
    public private(set) var lastSentTimestamp: TimeInterval = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var connection: NWConnection?

    @ObservationIgnored
    private let loop = PollingLoop()

    @ObservationIgnored
    private var lastFrameTimestamp: TimeInterval = -1

    public init(host: String = "localhost", port: UInt16 = 8000) {
        let d = UserDefaults.standard
        self.host = d.string(forKey: Self.hostKey) ?? host
        let p = d.integer(forKey: Self.portKey)
        self.port = (p > 0 && p <= 65_535) ? UInt16(p) : port
    }

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        connect()
        isActive = true
        loop.start(interval: .milliseconds(100)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.sendIfFresh(from: bus)
            self.drainAndSendEvents(from: bus)
        }
    }

    public func stop() {
        loop.stop()
        connection?.cancel()
        connection = nil
        isActive = false
    }

    // MARK: - Target persistence + live reconnect

    private static let hostKey = "net.osc.host"
    private static let portKey = "net.osc.port"
    private static func persistTarget(_ host: String, _ port: UInt16) {
        let d = UserDefaults.standard
        d.set(host, forKey: hostKey)
        d.set(Int(port), forKey: portKey)
    }
    /// A host/port edit takes effect immediately while the output is live (connect()
    /// otherwise only runs in start()): drop the old socket, reconnect to the new
    /// endpoint. Idle ⇒ no-op; the next start() uses the value.
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
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp
        send(frame: frame)
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    /// Sends the latest discrete bio event if it is newer than the one we
    /// last forwarded. Reads the `@MainActor` snapshot (`latestBioEvent`),
    /// not the lock-free `bioEvents` queue, so it never contends with the
    /// audio-thread consumer for that SPSC queue. At the 100 ms tick cadence,
    /// events closer together than 100 ms collapse to the most recent — fine
    /// for heartbeat/breath/motion rates; a return channel can tighten this later.
    /// Drains the `bioEvents` SPSC queue and sends EVERY discrete event at full
    /// resolution — so PolarH10 per-RR `.heartbeat` events (and breath/motion
    /// onsets) reach external tools with correct timing instead of being lost to
    /// the single-slot snapshot between 100 ms ticks (audit 2026-06-09, defect 2/5).
    /// OSCSender is the SOLE consumer of this queue; producers enqueue on the
    /// main actor, so this main-run-loop drain is serialized and SPSC-safe. The
    /// synth's breath path reads the independent `latestBioEvent` snapshot and is
    /// unaffected.
    private func drainAndSendEvents(from bus: EngineBus) {
        var sentAny = false
        while let event = bus.bioEvents.dequeue() {
            send(event: event)
            sentAny = true
        }
        if sentAny { lastSentTimestamp = CFAbsoluteTimeGetCurrent() }
    }

    private func send(event: BioEvent) {
        send(address: Self.address(for: event.kind), floats: [event.confidence, event.aux])
    }

    /// Stream one modulation-matrix output value out as
    /// `/echoelmusic/mod/<key>` (e.g. `/echoelmusic/mod/seq.tempo`), so an
    /// external tool can react to the same modulation the app applies. No-op
    /// until the sender is active.
    public func sendModulation(key: String, value: Float) {
        guard isActive else { return }
        send(address: "/echoelmusic/mod/\(key)", floats: [value])
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    /// OSC address for a discrete bio event, mirroring the continuous
    /// `/echoelmusic/bio/*` space with an `/event/` segment. Pure mapping,
    /// unit-testable without a socket.
    public static func address(for kind: BioEvent.Kind) -> String {
        switch kind {
        case .heartbeat:         return "/echoelmusic/bio/event/heartbeat"
        case .breathInhaleOnset: return "/echoelmusic/bio/event/breath/inhale"
        case .breathExhaleOnset: return "/echoelmusic/bio/event/breath/exhale"
        case .motionPeak:        return "/echoelmusic/bio/event/motion"
        case .coherenceShift:    return "/echoelmusic/bio/event/coherence"
        case .eegBurst:          return "/echoelmusic/bio/event/eeg"
        }
    }

    private func send(frame: BioSampleFrame) {
        send(address: "/echoelmusic/bio/heart/bpm",    floats: [frame.heartRateBPM])
        send(address: "/echoelmusic/bio/heart/hrv",    floats: [frame.hrvNormalized])
        // Precise un-normalized RMSSD (ms) for instrument-grade external tools
        // (TouchDesigner / Resolume / Max). Only sent when the source provides
        // a real value (>0) so consumers never read a synthesized number.
        if frame.hrvRMSSDms > 0 {
            send(address: "/echoelmusic/bio/heart/rmssd", floats: [frame.hrvRMSSDms])
            send(address: "/echoelmusic/bio/heart/sdnn",  floats: [frame.hrvSDNNms])
            send(address: "/echoelmusic/bio/heart/pnn50", floats: [frame.hrvPNN50])
        }
        send(address: "/echoelmusic/bio/breath/rate",  floats: [frame.breathRate])
        send(address: "/echoelmusic/bio/breath/phase", floats: [frame.breathPhase])
        send(address: "/echoelmusic/bio/coherence",    floats: [frame.coherence])
        send(address: "/echoelmusic/bio/motion",       floats: [frame.motionEnergy])
    }

    private func send(address: String, floats: [Float]) {
        guard let conn = connection else { return }
        let data = Self.encode(address: address, floats: floats)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - OSC 1.0 encoding (testable kernel)

    /// Encode one OSC message: null-terminated address + 4-byte padded,
    /// type tag string (",f" / ",ff" / ...) + 4-byte padded, then
    /// each float as big-endian 32-bit.
    public static func encode(address: String, floats: [Float]) -> Data {
        var data = Data()
        data.append(paddedOSCString(address))
        let tags = "," + String(repeating: "f", count: floats.count)
        data.append(paddedOSCString(tags))
        for f in floats {
            var be = f.bitPattern.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Append a null terminator then pad to the next 4-byte boundary.
    private static func paddedOSCString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }
}
#endif
