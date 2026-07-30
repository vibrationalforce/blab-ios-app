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
//  OSC address space follows master prompt §2. ⛔ EVERY BIO ADDRESS IS GATED ON ITS OWN
//  MEASUREMENT (#245): silence means "not measured", never "measured as zero". A receiver
//  holds its last value, which is what a performer expects when the camera blinks — sending
//  a structural 0 instead collapsed a bound scale or slewed a lighting desk to black with no
//  way to tell that apart from a real stop.
//    /echoelmusic/bio/heart/bpm     float [40..200]  — only with a measured pulse
//    /echoelmusic/bio/heart/hrv     float [0..1]     — on its OWN sentinel, NOT the pulse:
//        both live sensors publish a locked BPM with hrv 0 for the first ~55 s, until the
//        RR record is long enough for a spectrum
//    /echoelmusic/bio/breath/rate   float [4..30]    — on the plausibility band (3…40/min)
//    /echoelmusic/bio/breath/phase  float [0..1]     — with the RATE, never gated on itself:
//        the phase has no unknown sentinel (0 = EXHALE start, 0.5 = inhale start), so a value
//        gate would drop real data once per breath cycle
//    /echoelmusic/bio/coherence     float [0..1]     — on its own sentinel, same as hrv
//    /echoelmusic/bio/motion        float [0..1]  — NOT SENT in this build (#215):
//        nothing measures motion, so the address would carry a constant 0 that a
//        receiver cannot tell apart from a motionless performer. It returns the day a
//        CoreMotion producer does; see `bioMessages` and `ModSource.hasProducer`.
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
        // Discard the backlog accrued while this route was OFF (#155 review). The
        // producer (`bioEvents.start(on:)`) runs from app start, this consumer only
        // once the patchbay routes `osc.out` — so the 64-slot queue is typically FULL
        // of events from earlier in the session by the time anyone switches OSC on.
        // Before #155 that mattered less: drop-oldest kept the newest ~6 s. Now the
        // producer refuses on overflow, so the queue holds the OLDEST 63 events — and
        // `drainAndSendEvents` would blast hours-old heartbeats down the wire on the
        // first tick. `BioEgressPolicy` gates on source and privacy, NOT on age
        // (`sendIfFresh` covers frames only), so nothing downstream would catch it.
        // Enabling a route mid-performance is exactly when this happens.
        while bus.bioEvents.dequeue() != nil {}
        // Governed: 10 Hz nominal, but a thermally stressed or nearly empty device
        // drops this to 5 Hz (minimal tier). Bio egress is a stream of smoothed
        // scalars, not events with a deadline — halving its rate costs a receiving
        // patch nothing but a coarser interpolation. `drainAndSendEvents` still
        // drains the FULL queue on each tick, so no discrete event is lost.
        loop.start(interval: .milliseconds(100), governedByBioCeiling: true) { [weak self] in
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
        // 5.1.3: HealthKit-store data never leaves the device — only Echoel's own
        // measurements (camera / BLE strap / demo) stream out (BioEgressPolicy).
        // The timestamp is still recorded above so a blocked frame is not retried.
        guard BioEgressPolicy.allowsEgress(frame.source) else { return }
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
            // 5.1.3, same rule as the frame path above (#186). This gate was MISSING:
            // `sendIfFresh` refuses a HealthKit/Watch frame, while this loop sent breath
            // onsets derived from that very frame — `BioEventPublisher` reads
            // `bus.latestBio` whatever its source. A rule half the code follows is not a
            // rule, and the app's own privacy text names the ways out.
            //
            // ⚠️ Scope, corrected by review: this is DEFENCE-IN-DEPTH, not an active-leak
            // plug. On a HealthKit frame the channels the graph is actually fed are a
            // constant 0.5 and a hardcoded 0, so today's detectors cannot fire from that
            // source at all — except once, via the shared detector state that is not reset
            // when the source changes. `BioEgressPolicy`'s header has the full derivation.
            // Do not "simplify this away as dead code": the day a publisher feeds real
            // Health-derived channels into the graph, this is what covers it.
            //
            // The predicate lives in `BioEgressPolicy` so the test cannot re-implement it
            // and drift (it did, in the first cut of this fix). Dequeue stays above the
            // guard — a blocked event must still be consumed or it wedges the queue.
            guard BioEgressPolicy.allowsEgress(event) else { continue }
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
    public nonisolated static func address(for kind: BioEvent.Kind) -> String {
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
        for m in Self.bioMessages(for: frame) {
            send(address: m.address, floats: m.floats)
        }
    }

    /// The bio-frame → OSC message list. Pure + `nonisolated` so the gating is
    /// unit-testable (like `ADMOSCSender.admMessages`) and shares one source of truth
    /// with `send(frame:)`. Each un-normalized HRV metric is gated on ITS OWN source
    /// value (>0) so consumers never read a synthesized number — and, crucially, so a
    /// source that provides SDNN but no beat-to-beat RR (HealthKit's native SDNN) still
    /// emits its SDNN even though it has no RMSSD/pNN50 (those are RR-derived).
    nonisolated static func bioMessages(for frame: BioSampleFrame) -> [(address: String, floats: [Float])] {
        var msgs: [(address: String, floats: [Float])] = []
        // ⛔ #245: THESE TWO USED TO BE UNCONDITIONAL, and that was the same defect #215 fixed
        // for `/bio/motion` one address further down — restated here because the fix and the
        // defect lived eighteen lines apart in one function. Before a publisher locks, or after
        // a finger lifts, `heartRateBPM` is a structural 0. On the wire a 0 is a VALUE: a VJ
        // binding a scale to `/bio/heart/bpm` gets a hard collapse to zero, a lighting desk
        // slews its Grand Master to black, and neither has any way to tell that apart from a
        // measured stop. Not sending is the only form the protocol has for "I do not know" —
        // the receiver holds its last value, which is what a performer expects when the camera
        // blinks. And it is not hypothetical: log 2476 published ONE frame in 110 s of a locked
        // pulse (#235), so the un-measured state is the COMMON one today, not the edge case.
        if frame.hasMeasuredHeartRate {
            msgs.append(("/echoelmusic/bio/heart/bpm", [frame.heartRateBPM]))
        }
        // ⛔ HRV AND COHERENCE NEED **BOTH** HALVES, and this repo has now got it wrong in each
        // direction once, on the same two addresses, in consecutive commits:
        //
        //   · PULSE ONLY (105d6ab) let the warm-up through. Both are derived from the beat
        //     SERIES, not from a single beat: Polar and the camera publish a locked BPM with
        //     `hrvNormalized: 0` / `coherence: 0` until enough RR has accumulated for a
        //     spectrum — roughly the first 55 s of every session, and again whenever the RR
        //     record is untrustworthy. Exactly the collapse-to-zero this slice exists to stop.
        //   · SENTINEL ONLY (33876a0) let a MALFORMED frame through: a frame with no pulse
        //     cannot carry HRV or coherence at all, so a non-zero value beside `bpm == 0` is
        //     not a reading to forward — it is a bug at the publisher, and forwarding it puts
        //     an invented number on someone else's lighting desk. CI caught this one.
        //
        // So: the pulse must be real AND the field's own sentinel must be non-zero. Both docs
        // already say what their zero means ("0 means NOT MEASURED, not minimum variability";
        // "treat 0 as 'not available', not as 'incoherent'"), and `ModSource.isMeasured` answers
        // the sentinel half per channel — this is that answer plus the physiological precondition.
        if frame.hasMeasuredHeartRate, frame.hrvNormalized > 0 {
            msgs.append(("/echoelmusic/bio/heart/hrv", [frame.hrvNormalized]))
        }
        // Beat-to-beat (RR-derived) time-domain metrics — only from a real RR source
        // (camera/Polar). Instrument-grade values for TouchDesigner / Resolume / Max.
        // Same conjunction as `/hrv`: these three are the MOST beat-derived quantities in the
        // frame (RMSSD and pNN50 are statistics OVER successive NN intervals, SDNN over the NN
        // series), so a non-zero value beside `bpm == 0` is a publisher bug in exactly the way
        // the block above describes. They were left on a bare sentinel when `/hrv` and
        // `/coherence` gained the precondition; three of five heart addresses obeying a
        // different rule than the other two is how the next reader concludes the rule is
        // arbitrary and "tidies" it back out.
        if frame.hasMeasuredHeartRate, frame.hrvRMSSDms > 0 {
            msgs.append(("/echoelmusic/bio/heart/rmssd", [frame.hrvRMSSDms]))
            msgs.append(("/echoelmusic/bio/heart/pnn50", [frame.hrvPNN50]))
        }
        // SDNN needs no beat-to-beat RR, so it rides its OWN sentinel rather than the RMSSD
        // one that used to hide it: an egress-allowed source supplying SDNN without RR
        // now emits it. (HealthKit IS such a source but its frames are network-blocked
        // upstream by BioEgressPolicy per App Store 5.1.3, so today the split only
        // matters for a future SDNN-only egress-allowed source — it is the honest
        // per-metric gating regardless.) It still needs a pulse: "no beat-to-beat RR"
        // means no INTERVAL series, not no heartbeat.
        if frame.hasMeasuredHeartRate, frame.hrvSDNNms > 0 {
            msgs.append(("/echoelmusic/bio/heart/sdnn", [frame.hrvSDNNms]))
        }
        // Breath rides its OWN gate — `BioSampleFrame.hasMeasuredBreath`, which is the
        // PLAUSIBILITY BAND (3…40/min) and not a bare `> 0`: you cannot breathe half a time a
        // minute, so a value outside the band is an absence. (The first cut of this slice
        // declared a second `hasMeasuredBreath` as `breathRate > 0` right next to the existing
        // one — a redeclaration that did not compile, and would have admitted 0.5/min if it had.)
        //
        // ⚠️ A SEPARATE GATE, BUT NOT FOR THE REASON FIRST WRITTEN HERE. That said the two
        // signals are "independently produced". They are not, on the only egress-allowed source
        // that carries breath: `CameraRPPGBioPublisher` derives respiration from the RR series
        // via RSA, so no pulse means no breath. HealthKit IS an independent respiration source
        // and is network-blocked upstream (5.1.3). The separate gate is still correct — it is
        // defensive against the day an independent producer arrives, and it costs nothing — but
        // it buys no live case today, and saying otherwise overstated the slice.
        //
        // ⚠️ `breathPhase` is gated on the RATE and never on itself: the phase has NO unknown
        // sentinel — 0 is a meaningful position (EXHALE start; 0.5 is inhale start, per the
        // field's own doc) — so it cannot answer this question about itself. A `> 0` test there
        // would drop real data once per breath cycle.
        if frame.hasMeasuredBreath {
            msgs.append(("/echoelmusic/bio/breath/rate", [frame.breathRate]))
            msgs.append(("/echoelmusic/bio/breath/phase", [frame.breathPhase]))
        }
        // Same conjunction as `/hrv` above, and for the same two reasons.
        if frame.hasMeasuredHeartRate, frame.coherence > 0 {
            msgs.append(("/echoelmusic/bio/coherence", [frame.coherence]))
        }
        // Motion rides a STRUCTURAL gate rather than a value one (#215). Every
        // `BioSampleFrame` construction site in `Sources/` hardcodes `motionEnergy: 0`
        // and the last CoreMotion provider went in the 2026-06-19 cleanup, so this
        // address carried a constant 0 to every receiver — and at the receiving end a
        // constant 0 is indistinguishable from a performer standing perfectly still.
        // A VJ binds a visual to it, sees nothing move, and has no way to learn FROM THE
        // WIRE that the channel is dead — `docs/dev/VJ_BRIDGE.md` had to carry the
        // warning in prose because the protocol could not. Not sending it makes the
        // absence visible in any OSC monitor instead.
        //
        // What a bound receiver sees is unchanged: it was receiving a constant 0 and now
        // holds its last value, which is 0. The one real difference is a receiver that
        // CREATES channels on first receipt (TouchDesigner's OSC In CHOP) — after an app
        // restart the channel never appears, so a downstream expression errors instead of
        // reading 0. That is a doc note, and VJ_BRIDGE.md carries it.
        //
        // Why `hasProducer` and not `motionEnergy > 0`: 0 is a REAL reading for motion
        // (perfectly still) with no sentinel — a value gate would drop a motionless
        // performer's channel mid-show. `ModulationMatrix` already argues this at
        // length and owns the predicate; this is the same question asked at egress.
        if ModSource.motion.hasProducer {
            msgs.append(("/echoelmusic/bio/motion", [frame.motionEnergy]))
        }
        return msgs
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
    public nonisolated static func encode(address: String, floats: [Float]) -> Data {
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
    private nonisolated static func paddedOSCString(_ s: String) -> Data {
        var bytes = Array(s.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return Data(bytes)
    }
}
#endif
