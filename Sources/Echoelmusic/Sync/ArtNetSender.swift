//
//  ArtNetSender.swift
//  Echoelmusic — EchoelSync / EchoelLux
//
//  Native Art-Net (ArtDMX) output over UDP — the open, royalty-free lighting
//  control standard (DMX-512 over IP, port 6454). No SDK, no dependency: builds
//  the ArtDMX packet by hand and sends it via Network.framework, the same way
//  OSCSender/ADMOSCSender stream bio out. Makes the body drive stage lighting:
//  a bio-reactive fixture (dimmer + RGB) that breathes with you.
//
//  Doctrine fit: Art-Net is a documented wire protocol (Artistic Licence) —
//  exactly the "speak open standards, depend on nothing" lane. sACN/E1.31 is a
//  natural follow-up (same idea, multicast).
//
//  SAFETY (CLAUDE.md / W3C WCAG): max 3 Hz flash. Bio is a slow signal and we
//  send smoothed continuous values (no strobing), so the dimmer fades rather
//  than flashes — within the epilepsy limit by construction.
//
//  ArtDMX packet (Art-Net 4):
//    "Art-Net\0" (8) · OpCode 0x5000 LE (2) · ProtVer 14 BE (2) · Sequence (1)
//    · Physical (1) · SubUni (1) · Net (1) · LengthHi/Lo BE (2) · Data[Length]
//

#if canImport(Network)
import Foundation
import Network
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class ArtNetSender {

    /// Art-Net node host. Unicast to the node's IP is most reliable; limited
    /// broadcast (255.255.255.255) reaches every node on the LAN.
    public var host: String {
        didSet { Self.persistTarget(host, port, universe); reconnectIfActive() }
    }

    /// Art-Net port is fixed at 6454 by the standard, but kept configurable.
    public var port: UInt16 {
        didSet { Self.persistTarget(host, port, universe); reconnectIfActive() }
    }

    /// 15-bit Art-Net port address (Net<<8 | SubUni). Universe 0 by default.
    public var universe: Int {
        didSet { Self.persistTarget(host, port, universe) }   // packet content, no socket change
    }

    /// DMX value resolution per parameter. 16-bit uses paired coarse/fine
    /// channels (65 536 steps) for smooth, professional fades; 8-bit (256 steps)
    /// is the legacy mode for simple fixtures. Defaults to 16-bit precision.
    /// Selectable since #730 (`PatchbayView`'s Light section, one Picker for both
    /// protocols); before that it had no writer anywhere in the repository.
    ///
    /// ⚠️ THE `didSet` IS NOT DECORATION (#732). `sendIfFresh` has a HOLD branch that
    /// reuses `lastChannels` when no allowed source is available, so a Blackout or
    /// Grand-Master move is still honoured (L1). That array is sized for the
    /// resolution in force when it was built. While nothing could write this
    /// property the sizes could never disagree; the moment a door existed, flipping
    /// it mid-hold left the held array at a stride the encoders no longer use.
    /// Re-encoding — rather than clearing — is what keeps the L1 guarantee.
    ///
    /// ⛔ AND THE TWO QUANTITIES #732 WROTE HERE WERE BOTH TOO MILD (#733). It said
    /// "one tick" and "until the next fresh frame (~1 s)". Measured:
    ///   · NOT one tick. The hold branch stores its own input straight back
    ///     (`channels = lastChannels`, then `lastChannels = channels`), so without
    ///     this `didSet` the wrongly-sized array is re-stored on EVERY hold tick —
    ///     33 ms apart, not once.
    ///   · NOT ~1 s, and there is no clock in it. The bio branch above reads
    ///     `bus.latestBio`, the RAW snapshot, with no freshness window, and nothing
    ///     ever sets it back to nil. So the hold branch is reached only when there
    ///     is no sounding music AND no bio frame from an egress-ALLOWED source has
    ///     ever arrived — and `BioEgressPolicy` gates HealthKit/Watch/ring sources
    ///     permanently, by SOURCE and not by age. For an operator on a wrist source
    ///     there is no "next fresh frame": clearing would have frozen the blackout
    ///     for the rest of the session. The decision was right and the reasoning
    ///     understated it in both directions.
    public var resolution: DMXResolution = .sixteenBit {
        didSet { lastChannels = Self.reencode(lastChannels, from: oldValue, to: resolution) }
    }

    public enum DMXResolution: String, Sendable, CaseIterable {
        case eightBit  = "8-bit"
        case sixteenBit = "16-bit"
    }

    public private(set) var isActive = false
    public private(set) var lastSentTimestamp: TimeInterval = 0

    /// L1 Grand Master (every lighting desk's first fader): scales the dimmer
    /// of everything Echoel sends, 0…1. Live state, not persisted — a fresh
    /// launch always starts at full (predictable for the operator).
    public var grandMaster: Float = 1
    /// L1 Blackout: forces the dimmer to 0 NOW (a one-off cut to dark is not a
    /// flash; the RETURN to light rides the normal slew-limiter, so it can
    /// never strobe). Colour channels keep streaming so un-blackout is seamless.
    public var blackout = false

    /// #1006 — how many identical fixtures this stream addresses, and how far apart they sit.
    ///
    /// Default 1, so the wire is byte-identical to every build before this pair existed. The
    /// fan happens AFTER the dimmer and colour slews below, never before: `FlashGuard`
    /// smooths the ONE block, and copying an already-safe block is what keeps the 3 Hz
    /// ceiling a guarantee instead of N independent histories to get right.
    ///
    /// ADDRESSING, not spatial differentiation — all fixtures receive the SAME colour,
    /// because this arm produces exactly one. `spacing` 0 means back-to-back.
    public var fixtureCount: Int = 1
    public var fixtureSpacing: Int = 0


    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private let loop = PollingLoop()
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1
    @ObservationIgnored private var sequence: UInt8 = 1
    /// Last dimmer (luminance) value actually sent, for the flash slew-limiter.
    /// -1 = none yet. Reset on stop so a restart doesn't slew from a stale value.
    @ObservationIgnored private var lastDimmer: Float = -1
    /// Per-channel colour slew anchor (R,G,B in 0…1; empty = no history yet).
    /// Reset on stop so a restart doesn't ramp the hue from a stale value.
    @ObservationIgnored private var lastColour: [Float] = []
    /// Master state as of the last packet — a Grand-Master/Blackout change must
    /// send even when the source timestamp is unchanged (a stale bio source
    /// must never block a blackout).
    @ObservationIgnored private var lastSentGrandMaster: Float = 1
    @ObservationIgnored private var lastSentBlackout = false
    /// Last RAW colour channels + dimmer target actually chosen (pre-master,
    /// pre-slew). Held so a tick with NO fresh/allowed source can still honor a
    /// Blackout / Grand-Master move from the last lit state (L1 — a stale or
    /// egress-gated source must never freeze a blackout). Empty = never lit yet.
    @ObservationIgnored private var lastChannels: [UInt8] = []
    @ObservationIgnored private var lastTarget: Float = 0

    public init(host: String = "255.255.255.255", port: UInt16 = 6454, universe: Int = 0) {
        let d = UserDefaults.standard
        self.host = d.string(forKey: Self.hostKey) ?? host
        let p = d.integer(forKey: Self.portKey)
        self.port = (p > 0 && p <= 65_535) ? UInt16(p) : port
        // universe persists as stored+1 so a legitimate 0 is distinguishable from "unset".
        let u = d.integer(forKey: Self.universeKey)
        self.universe = u > 0 ? (u - 1) : max(0, universe)
    }

    public func start(subscribing bus: EngineBus) {
        guard !isActive else { return }
        self.bus = bus
        connect()
        isActive = true
        // The interval is FlashGuard's, not this file's (#372): the flash cap below is
        // derived from the same constant, so a change here cannot outrun the safety bound.
        loop.start(interval: .milliseconds(FlashGuard.senderTickMilliseconds)) { [weak self] in
            guard let self, let bus = self.bus else { return }
            self.sendIfFresh(from: bus)
        }
    }

    public func stop() {
        loop.stop()
        connection?.cancel()
        connection = nil
        isActive = false
        lastDimmer = -1
        lastColour = []
    }

    // MARK: - Target persistence + live reconnect

    private static let hostKey = "net.artnet.host"
    private static let portKey = "net.artnet.port"
    private static let universeKey = "net.artnet.universe"
    private static func persistTarget(_ host: String, _ port: UInt16, _ universe: Int) {
        let d = UserDefaults.standard
        d.set(host, forKey: hostKey)
        d.set(Int(port), forKey: portKey)
        d.set(universe + 1, forKey: universeKey)   // +1 so a valid universe 0 ≠ "unset"
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
        // Allow sending to a broadcast address (255.255.255.255) as well as unicast.
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: params)
        conn.start(queue: .main)
        self.connection = conn
    }

    // MARK: - Subscriber tick

    private func sendIfFresh(from bus: EngineBus) {
        // Music drives the COLOUR when it's sounding (pitch/chord → SpectralColor),
        // bio drives it otherwise — bio stays the co-modulator. Dedup on the chosen
        // source's timestamp so a music-only change still updates the fixture.
        let music = bus.freshMusical(maxAge: 1.5)
        let useMusic = music?.isSounding ?? false
        let sourceTimestamp: TimeInterval
        var channels: [UInt8]
        let target: Float
        if useMusic, let m = music {
            sourceTimestamp = m.timestamp
            channels = MusicMediaMap.dmxChannels(forMusic: m, resolution: resolution)
            target = MusicMediaMap.dimmerUnit(forMusic: m)
        } else if let frame = bus.latestBio, BioEgressPolicy.allowsEgress(frame.source) {
            // 5.1.3: a HealthKit/Watch/ring-sourced frame must not drive a network
            // fixture (unicast DMX leaves the device). Such a frame is treated as
            // no-bio here — the light holds its last state (same gate OSC/ADM apply).
            sourceTimestamp = frame.timestamp
            channels = Self.dmxChannels(for: frame, resolution: resolution)
            target = Self.dimmerUnit(for: frame)
        } else if !lastChannels.isEmpty {
            // No fresh/allowed source, but the rig is already lit: hold the last
            // colour and keep running the master/slew logic below so a Blackout or
            // Grand-Master move is honored NOW (L1 — a stale/gated source must never
            // freeze a blackout). The guard uses the unchanged timestamp, so this
            // only emits while master state moves or the slew is still settling.
            // Held channels are always from an allowed source (a gated frame never
            // reaches the store below), so nothing new egresses.
            sourceTimestamp = lastFrameTimestamp
            channels = lastChannels
            target = lastTarget
        } else {
            return
        }
        // Remember the RAW colour + target so a later no-source tick can still
        // honor master/blackout from the held state.
        lastChannels = channels
        lastTarget = target
        // Grand Master scales the target; Blackout cuts to 0 instantly (and
        // resets the slew anchor, so the return to light ramps up from dark).
        let mastered = Self.masteredDimmer(target, grandMaster: grandMaster, blackout: blackout)
        // Send when the source is fresh, the master state moved, or the slew
        // ramp hasn't reached its target yet (a paused source must not freeze
        // a fade mid-ramp, and must never block a blackout).
        let masterMoved = grandMaster != lastSentGrandMaster || blackout != lastSentBlackout
        let slewSettling = lastDimmer >= 0 && abs(mastered - lastDimmer) > 0.001
        guard sourceTimestamp != lastFrameTimestamp || masterMoved || slewSettling else { return }
        lastFrameTimestamp = sourceTimestamp
        lastSentGrandMaster = grandMaster
        lastSentBlackout = blackout
        // Hard flash guarantee for PHYSICAL fixtures: slew-limit the dimmer
        // (luminance) channel so even a pathological input jump can never strobe
        // the lights. The step is `FlashGuard.senderTickDelta` — a per-SECOND
        // luminance velocity resolved at THIS loop's interval (#372), so halving
        // the interval above halves the step instead of doubling the flash rate.
        // At today's 33 ms that is the same 0.08 as before → full fade ≥0.4 s.
        let limited = FlashGuard.slewedDimmer(from: lastDimmer, to: mastered, blackout: blackout,
                                              maxDelta: FlashGuard.senderTickDelta)
        lastDimmer = limited
        Self.applyDimmer(&channels, resolution: resolution, dimmer: limited)
        // Slew the COLOUR channels too — a fast hue swing at high dimmer would
        // otherwise strobe even though the dimmer is rate-limited (Law 6 gap).
        Self.applySlewedColour(&channels, resolution: resolution, last: &lastColour,
                               maxDelta: FlashGuard.senderTickDelta)
        let fanned = DMXFixtureFan.fanned(channels, count: fixtureCount, spacing: fixtureSpacing)
        let packet = Self.artDMXPacket(universe: universe, sequence: sequence, channels: fanned)
        sequence = sequence == 255 ? 1 : sequence &+ 1   // 1...255, 0 = disabled
        send(packet)
        lastSentTimestamp = CFAbsoluteTimeGetCurrent()
    }

    private func send(_ data: Data) {
        guard let conn = connection else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Pure kernels (testable without a socket)

    /// Maps a bio frame to a 4-channel fixture: dimmer + R + G + B (0...255).
    /// Smooth, continuous values — no strobing (epilepsy-safe by construction).
    ///   ch1 dimmer = 0.3 + 0.7·coherence (always lit, brighter when coherent)
    ///   ch2 R = heart rate (normalized)   — energy
    ///   ch3 G = HRV                        — calm/variability
    ///   ch4 B = breath phase              — breathing motion
    public static func dmxChannels(for f: BioSampleFrame) -> [UInt8] {
        let hrNorm = clampUnit((f.heartRateBPM - 40) / 160)
        let dimmer = clampUnit(0.3 + 0.7 * f.coherence)
        return [
            byte(dimmer),
            byte(hrNorm),
            byte(clampUnit(f.hrvNormalized)),
            byte(clampUnit(f.breathPhase))
        ]
    }

    /// 16-bit fixture mapping: each of the four parameters becomes a
    /// coarse(MSB)+fine(LSB) channel pair (8 channels total, 65 536 steps each),
    /// the professional standard for click-free dimmer/colour fades.
    /// Channel order: dimmer(hi,lo) · R(hi,lo) · G(hi,lo) · B(hi,lo).
    public static func dmxChannels16(for f: BioSampleFrame) -> [UInt8] {
        let hrNorm = clampUnit((f.heartRateBPM - 40) / 160)
        let dimmer = clampUnit(0.3 + 0.7 * f.coherence)
        return word(dimmer) + word(hrNorm) + word(clampUnit(f.hrvNormalized)) + word(clampUnit(f.breathPhase))
    }

    /// Resolution-dispatched mapping used by the live sender (and sACN).
    public static func dmxChannels(for f: BioSampleFrame, resolution: DMXResolution) -> [UInt8] {
        switch resolution {
        case .eightBit:  return dmxChannels(for: f)
        case .sixteenBit: return dmxChannels16(for: f)
        }
    }

    /// Builds one ArtDMX packet. `channels` is padded to an even length in
    /// [2, 512] as the spec requires.
    public static func artDMXPacket(universe: Int, sequence: UInt8, channels: [UInt8]) -> Data {
        var dmx = channels
        if dmx.count < 2 { dmx += Array(repeating: 0, count: 2 - dmx.count) }
        if dmx.count > 512 { dmx = Array(dmx.prefix(512)) }
        if dmx.count % 2 != 0 { dmx.append(0) }          // length must be even
        let length = dmx.count
        let uni = max(0, universe)

        var data = Data()
        data.append(contentsOf: Array("Art-Net".utf8))   // 7 bytes
        data.append(0)                                    // null terminator → 8
        data.append(contentsOf: [0x00, 0x50])             // OpCode OpOutput/ArtDMX (0x5000), little-endian
        data.append(contentsOf: [0x00, 0x0E])             // ProtVer 14, big-endian
        data.append(sequence)                             // Sequence
        data.append(0x00)                                 // Physical
        data.append(UInt8(uni & 0xFF))                    // SubUni (low byte)
        data.append(UInt8((uni >> 8) & 0x7F))             // Net (high 7 bits)
        data.append(UInt8((length >> 8) & 0xFF))          // LengthHi
        data.append(UInt8(length & 0xFF))                 // LengthLo
        data.append(contentsOf: dmx)                      // DMX data
        return data
    }

    /// The dimmer (luminance) unit value a frame maps to — must match the
    /// `dmxChannels*` builders (0.3 + 0.7·coherence). Exposed for the slew path
    /// and tests.
    static func dimmerUnit(for f: BioSampleFrame) -> Float { clampUnit(0.3 + 0.7 * f.coherence) }

    /// L1 master law, shared by Art-Net and sACN: Blackout wins (dimmer 0,
    /// whatever the master says), otherwise the Grand Master scales the dimmer
    /// linearly. Guards non-finite input; everything clamps to [0…1].
    public static func masteredDimmer(_ dimmer: Float, grandMaster: Float, blackout: Bool) -> Float {
        guard !blackout else { return 0 }
        let gm = clampUnit(grandMaster.isFinite ? grandMaster : 1)
        return clampUnit(dimmer) * gm
    }

    /// Overwrites the dimmer channel(s) of an already-built DMX array with a
    /// (slew-limited) value. ch0 for 8-bit; ch0..1 (coarse/fine) for 16-bit.
    /// Leaves the colour channels (R/G/B) untouched.
    static func applyDimmer(_ channels: inout [UInt8], resolution: DMXResolution, dimmer: Float) {
        switch resolution {
        case .eightBit:
            guard channels.count >= 1 else { return }
            channels[0] = byte(dimmer)
        case .sixteenBit:
            guard channels.count >= 2 else { return }
            let w = word(dimmer)
            channels[0] = w[0]
            channels[1] = w[1]
        }
    }

    /// Overwrites the COLOUR (R/G/B) channels of an already-built DMX array with
    /// slew-RATE-limited values, closing the colour half of the flash gap. The
    /// dimmer alone was slewed before, so at a high dimmer a hard colour jump (e.g.
    /// red→cyan on a chord change, recomputed ~30 Hz) was an un-limited luminance
    /// swing (W3C 2.3.1 / Law 6). Each colour channel rides the SAME cap as the
    /// dimmer, which bounds a FULL swing to ~1.2 Hz (a large strobe is
    /// impossible). Since #372 `maxDelta` is PASSED IN rather than defaulted here:
    /// this function is shared (`SACNSender` calls it), so a cap baked in locally
    /// would be a second, invisible copy of the number the caller's loop interval
    /// determines. The default keeps the two existing test call sites honest at the
    /// shipped interval. Honest caveat (inherited from the shared slew primitive, not
    /// new here): a rate cap bounds ≤3 Hz only for flashes of amplitude ≳0.4 — a
    /// tiny-amplitude (0.1–0.2) reversal every 2–3 ticks could still exceed 3 Hz.
    /// That is unreachable with our sources (bio is sub-Hz; music colour changes
    /// per chord/beat, never at 6–12 Hz), so it is a documented residual, not a
    /// live risk; a hard per-amplitude cap would need a flash-FREQUENCY counter
    /// (Council note, out of scope). `last` is the per-channel anchor (R,G,B in
    /// 0…1, -1 = no history yet — the first tick snaps, then ramps), updated in
    /// place; reset it (to []) on stop so a restart doesn't ramp from a stale hue.
    /// The dimmer channel is left untouched (applyDimmer owns it). Shared by both
    /// ArtNet and sACN so both protocols get the identical flash-safe guarantee.
    static func applySlewedColour(_ channels: inout [UInt8], resolution: DMXResolution,
                                  last: inout [Float],
                                  maxDelta: Double = FlashGuard.senderTickDelta) {
        if last.count != 3 { last = [-1, -1, -1] }
        let channelStride = resolution == .sixteenBit ? 2 : 1
        for c in 0..<3 {
            let idx = channelStride + c * channelStride   // ch0 = dimmer; R/G/B follow
            switch resolution {
            case .eightBit:
                guard idx < channels.count else { return }
                let target = Float(channels[idx]) / 255
                let slewed = FlashGuard.slewedDimmer(from: last[c], to: target, blackout: false,
                                                     maxDelta: maxDelta)
                last[c] = slewed
                channels[idx] = byte(slewed)
            case .sixteenBit:
                guard idx + 1 < channels.count else { return }
                let target = Float(UInt16(channels[idx]) << 8 | UInt16(channels[idx + 1])) / 65535
                let slewed = FlashGuard.slewedDimmer(from: last[c], to: target, blackout: false,
                                                     maxDelta: maxDelta)
                last[c] = slewed
                let w = word(slewed)
                channels[idx] = w[0]; channels[idx + 1] = w[1]
            }
        }
    }

    /// Re-encode a held DMX byte array between the two resolutions, so a
    /// mid-hold resolution change cannot leave `sendIfFresh` reading a stride the
    /// array does not have. Pure and shared by both protocols — `SACNSender` holds
    /// the same kind of array and calls this too.
    ///
    /// 8-bit → 16-bit is EXACT and stays exact: `65535 / 255 == 257`, so a byte `b`
    /// becomes the word `b * 257`, i.e. coarse `b` + fine `b`, and converting back
    /// yields `b` again for all 256 values (verified for every byte, not sampled).
    /// 16-bit → 8-bit is lossy by construction — that IS what choosing 8-bit means.
    static func reencode(_ channels: [UInt8], from old: DMXResolution,
                         to new: DMXResolution) -> [UInt8] {
        guard old != new, !channels.isEmpty else { return channels }
        switch (old, new) {
        case (.sixteenBit, .eightBit):
            var out: [UInt8] = []
            out.reserveCapacity(channels.count / 2)
            var i = 0
            while i + 1 < channels.count {
                let v = UInt16(channels[i]) << 8 | UInt16(channels[i + 1])
                out.append(byte(Float(v) / 65535))
                i += 2
            }
            return out
        case (.eightBit, .sixteenBit):
            var out: [UInt8] = []
            out.reserveCapacity(channels.count * 2)
            for b in channels { out.append(contentsOf: word(Float(b) / 255)) }
            return out
        default:
            return channels
        }
    }

    // NaN-safe: a non-finite bio/music channel (NaN/Inf) would otherwise reach
    // UInt8(_ * 255) / UInt16(_ * 65535) below and TRAP the app. Map non-finite → 0.
    private static func clampUnit(_ x: Float) -> Float { Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1) }
    private static func byte(_ unit: Float) -> UInt8 { UInt8(clampUnit(unit) * 255) }

    /// A unit value as a 16-bit coarse(MSB)+fine(LSB) DMX channel pair.
    private static func word(_ unit: Float) -> [UInt8] {
        let v = UInt16(clampUnit(unit) * 65535)
        return [UInt8(v >> 8), UInt8(v & 0xFF)]
    }
}
#endif
