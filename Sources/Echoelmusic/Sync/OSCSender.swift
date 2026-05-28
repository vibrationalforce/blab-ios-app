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

    public var host: String

    public var port: UInt16

    public private(set) var isActive = false

    /// Mach-time of the last message sent. Lets the UI render an
    /// activity dot without spawning timers.
    public private(set) var lastSentTimestamp: TimeInterval = 0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var connection: NWConnection?

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var lastFrameTimestamp: TimeInterval = -1

    public init(host: String = "localhost", port: UInt16 = 8000) {
        self.host = host
        self.port = port
    }

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        connect()
        isActive = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                self.sendIfFresh(from: bus)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
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
        guard let frame = bus.latestBio else { return }
        guard frame.timestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = frame.timestamp
        send(frame: frame)
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    private func send(frame: BioSampleFrame) {
        send(address: "/echoelmusic/bio/heart/bpm",    floats: [frame.heartRateBPM])
        send(address: "/echoelmusic/bio/heart/hrv",    floats: [frame.hrvNormalized])
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
