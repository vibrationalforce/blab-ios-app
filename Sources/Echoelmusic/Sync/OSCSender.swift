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
//    /echoelmusic/bio/heart/hrv     float [0..1]     — pulse AND its own sentinel (both halves
//        are required and neither is redundant — see the block at `bioMessages`)
//    /echoelmusic/bio/heart/rmssd   float ms         — pulse AND its own sentinel
//    /echoelmusic/bio/heart/pnn50   float [0..1]     — rides the RMSSD gate (same RR record)
//    /echoelmusic/bio/heart/sdnn    float ms         — pulse AND its own sentinel
//    /echoelmusic/bio/breath/rate   float [3..40]    — on the plausibility band (3…40/min)
//    /echoelmusic/bio/breath/phase  float [0..1]     — with the RATE, never gated on itself:
//        the phase has no unknown sentinel (0 = EXHALE start, 0.5 = inhale start), so a value
//        gate would drop real data once per breath cycle
//    /echoelmusic/bio/coherence     float [0..1]     — pulse AND its own sentinel, like hrv.
//        ⚠️ This one is the most likely to stay SILENT for a whole session: coherence needs
//        `HRVCoherence.minIntervals` = 16 accepted RR intervals, and the camera's RR series
//        comes from a fixed 10 s peak window (`CameraAnalyzer.detectPeaks`) — about 10
//        intervals at a resting heart rate. On the BLE strap it arrives after ~16 beats.
//    /echoelmusic/bio/synthetic     float 0|1        — 1 = the DEMO generator, 0 = a real body
//        (#639). Gated on THE BATCH, not on itself: it is prepended to every frame that sends
//        at least one measured value, and omitted entirely from a frame that sends nothing —
//        so #245's silence law is intact and a receiver never gets a bare flag. A receiver that
//        never sees the address while values are arriving is talking to a build older than
//        #639; that is the honest reading, and it is why the address is ADDITIVE rather than an
//        extra argument on the existing ones (appending to `/heart/bpm` would break every
//        integrator on the old contract in the name of honesty).
//        ⚠️ TREAT IT AS STATE, NOT AS A PREFIX. These are separate UDP datagrams and UDP does
//        not guarantee order, so it may arrive after the values of its own tick. It is re-sent
//        with every frame (~1 Hz) and only changes when the player switches source, so latching
//        the last value is correct and a one-tick inversion self-corrects.
//        ⚠️ It answers "is this a body", not "which sensor". A richer per-source address may be
//        added later as its OWN address; do not repurpose this one's meaning, which is the one
//        thing a wire contract cannot survive.
//    /echoelmusic/bio/motion        float [0..1]  — NOT SENT in this build (#215):
//        nothing measures motion, so the address would carry a constant 0 that a
//        receiver cannot tell apart from a motionless performer. It returns the day a
//        CoreMotion producer does; see `bioMessages` and `ModSource.hasProducer`.
//
//  Discrete BioEventGraph events (kind → address, args [confidence, aux]).
//  ⭐ #785: these carry provenance too, but on a DIFFERENT cadence from the batch above —
//  `/echoelmusic/bio/synthetic` is emitted immediately before the event it describes and again
//  only when the origin CHANGES, latched across drains. Reason: events CLUSTER (per-RR beats,
//  paired breath onsets), so re-stating it per event would multiply traffic on the path shaped
//  by latency. A receiver joining mid-session learns the state from the ~1 Hz batch, which is
//  what "treat it as state" above already asks of it. Arity is UNCHANGED — provenance is an
//  additive address, never a third float. See `eventMessages(for:lastAnnounced:)`.
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

    /// The provenance value most recently announced on the EVENT path, latched across drains
    /// so the flag is sent once per change rather than once per event (#785).
    ///
    /// ⚠️ SEPARATE FROM THE BATCH PATH'S LATCH ON PURPOSE — there isn't one. `bioMessages`
    /// re-states the flag on every non-empty batch, which is correct there: a batch is ~1 Hz
    /// and already carries several messages, so one more is free and a receiver that joined
    /// late gets the state on its next frame. Events are bursty (breath onsets cluster), so
    /// re-stating per event would multiply the traffic on the one path that is latency-shaped.
    /// A receiver that joins mid-session therefore learns the state from the BATCH, which is
    /// exactly what CLAUDE.md's "als ZUSTAND latchen" asks of it.
    private var lastAnnouncedEventSynthetic: Bool?

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
        var accepted: [BioEvent] = []
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
            accepted.append(event)
            sentAny = true
        }
        // #785 — the flag and the events go out through ONE pure builder, so the ordering
        // question the #639 register left open ("a separate edit with a separate ordering
        // question") is answered in a testable place rather than inline. Collecting first
        // costs one array on the egress poll — not the audio thread, and this function
        // already allocated a `[Float]` per event.
        let built = Self.eventMessages(for: accepted, lastAnnounced: lastAnnouncedEventSynthetic)
        for message in built.messages { send(address: message.address, floats: message.floats) }
        lastAnnouncedEventSynthetic = built.announced
        if sentAny { lastSentTimestamp = CFAbsoluteTimeGetCurrent() }
    }

    /// Messages for a drained burst of ALREADY-GATED events, with the provenance flag placed
    /// immediately before the first event it describes and again only when it CHANGES (#785).
    ///
    /// Pure and `static` for the reason `BioEgressPolicy` records one screen up: the first cut
    /// of the egress gate was inlined here and the test re-implemented it, so the test passed
    /// with the production guard deleted. One symbol, called by both.
    ///
    /// ⛔ THE THREE SHAPES THAT WERE REJECTED, same list as #639 one level down:
    ///   · Append the flag to `/bio/event/*` — breaks every integrator reading `[confidence,
    ///     aux]` on the old contract. The addresses keep their arity.
    ///   · Send it unconditionally — an empty drain would emit a flag describing nothing,
    ///     the #245 defect this family exists to remove ("not sending is the only form the
    ///     protocol has for I-do-not-know").
    ///   · Re-state it per event — correct but noisy on the burstiest path; see the latch above.
    ///
    /// `events` must already have passed `BioEgressPolicy.allowsEgress`, which is fail-closed
    /// on `source == nil`; the `?? false` below is therefore unreachable in production and is
    /// a total-function default, not a policy decision.
    nonisolated static func eventMessages(
        for events: [BioEvent], lastAnnounced: Bool?
    ) -> (messages: [(address: String, floats: [Float])], announced: Bool?) {
        var messages: [(address: String, floats: [Float])] = []
        var announced = lastAnnounced
        for event in events {
            let synthetic = event.source?.isSynthetic ?? false
            if announced != synthetic {
                messages.append(("/echoelmusic/bio/synthetic", [synthetic ? 1 : 0]))
                announced = synthetic
            }
            messages.append((Self.address(for: event.kind), [event.confidence, event.aux]))
        }
        return (messages, announced)
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
    /// value (>0) **and on a measured pulse**, so consumers never read a synthesized
    /// number — and, crucially, so a source that provides SDNN but no beat-to-beat RR
    /// (HealthKit's native SDNN) still emits its SDNN even though it has no RMSSD/pNN50
    /// (those are RR-derived). "No beat-to-beat RR" means no INTERVAL series, not no
    /// heartbeat — hence the pulse half applies to SDNN too.
    nonisolated static func bioMessages(for frame: BioSampleFrame) -> [(address: String, floats: [Float])] {
        var msgs: [(address: String, floats: [Float])] = []
        // ⛔ #245: THESE USED TO BE UNCONDITIONAL, and that was the same defect #215 fixed
        // for `/bio/motion` further down this very function. On the wire a 0 is a VALUE: a VJ
        // binding a scale to `/bio/heart/bpm` gets a hard collapse to zero, a lighting desk
        // slews its Grand Master to black, and neither has any way to tell that apart from a
        // measured stop. Not sending is the only form the protocol has for "I do not know" —
        // the receiver holds its last value, which is what a performer expects when the camera
        // blinks.
        //
        // ⚠️ THREE EARLIER VERSIONS OF THIS COMMENT NAMED TRIGGERS THAT DO NOT EXIST. Neither
        // "before a publisher locks" nor "after a finger lifts" produces such a frame:
        // `CameraRPPGBioPublisher.shouldPublish` requires `bpm > 0`, and `PolarH10BioPublisher`
        // requires a plausible BPM. Nor is the "log 2476: ONE frame in 110 s" figure reproducible
        // from anything in this repo. And the third attempt — `FaceExpressionBioPublisher`, "the
        // REAL zero-pulse producer" — is wrong too: that type has ZERO instantiations in
        // `Sources/` and sits behind `FeatureFlags.cameraExpression` (default off, its front-
        // camera permission string founder-gated), so no `.faceCam` frame exists in a shipped
        // build. This gate is therefore DEFENSIVE, with no producer today; keep it, because a
        // zero-pulse frame from a future publisher must not put an invented BPM on a lighting
        // desk, and stop trying to name a trigger for it until one actually exists. What IS
        // reachable on shipping hardware is the sentinel half below: a strap publishes no
        // respiration at all, and coherence stays 0 for most of a camera take.
        if frame.hasMeasuredHeartRate {
            msgs.append(("/echoelmusic/bio/heart/bpm", [frame.heartRateBPM]))
        }
        // ⛔ HRV AND COHERENCE NEED **BOTH** HALVES, and this repo has now got it wrong in each
        // direction once, on the same two addresses, in consecutive commits:
        //
        //   · PULSE ONLY (105d6ab) let the warm-up through. Both are derived from the beat
        //     SERIES, not from a single beat, so a locked BPM sits next to a 0 for either of
        //     them — exactly the collapse-to-zero this slice exists to stop.
        //     ⚠️ THE "~55 s" THIS COMMENT USED TO CLAIM WAS BORROWED FROM A 64-BEAT COMMENT IN
        //     `PolarH10BioPublisher` AND IS WRONG FOR BOTH FIELDS. HRV clears in about three
        //     beats (`CameraAnalyzer` computes RMSSD at `rrIntervals.count >= 3`, and
        //     `RRIntervalHygiene.canStateHRV` is a fraction test with no minimum count).
        //     COHERENCE is the one that sits at 0, and its real threshold is a COUNT:
        //     `HRVCoherence.minIntervals` = 16 accepted RR intervals. On the strap that is
        //     ~16 beats; on the CAMERA it may never be reached, because the RR series comes
        //     from a fixed 10 s peak window (`CameraAnalyzer.detectPeaks`) — about 10 intervals
        //     at a resting heart rate. So on a camera session `/coherence` can stay silent for
        //     the whole take, which makes the sentinel half load-bearing permanently, not for
        //     a warm-up. That is a stronger argument than the one this comment used to make.
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
        // #639 — PROVENANCE, PREPENDED, AND GATED ON THE BATCH RATHER THAN ON ITSELF.
        //
        // WHY IT EXISTS. `BioEgressPolicy` lets the DEMO generator (`.fallback`) stream out, and
        // that is correct — it is Echoel's own synthesis, not Health-store data (5.1.3). But it
        // meant a lighting desk, an immersive renderer or a fellow performer received
        // `/bio/heart/bpm 74` from a simulator with no way at all to tell. Every in-app surface
        // has said "Demo" since #627…#637; THIS wire said nothing, and it is the half aimed at
        // integrators who cannot see the screen.
        //
        // ⛔ NOT "the wire said nothing" FLAT — #629 already put provenance on a real network
        // wire (`ColabPayload.BioPeek.synthetic`, the peer rows in a Live-Colabo session). The
        // difference is the contract, and it is worth naming: that one is OUR OWN encoding
        // between two copies of this app, so it could be widened at will and is deliberately
        // TRI-STATE (`Bool?` — "old peer" is a third answer). OSC is a PUBLISHED contract with
        // receivers we do not control, which is why this is an additive address and why it is
        // binary: an OSC float has no "unknown", so "old build" had to be expressed as the
        // ABSENCE of the address rather than as a third value.
        //
        // ⚠️ AND IT IS A DISCLOSURE, in the direction nobody asked about. The flag says nothing
        // about WHICH sensor and opens no HealthKit path (claim 7 pins that 5.1.3 is untouched).
        // What it does remove is plausible deniability: a receiver on the LAN can now tell that
        // a real body is in the room rather than a simulator. That is the point — an integrator
        // has to be able to trust the number — but it is a new fact on the network and belongs
        // in writing, not in the gap between two honest sentences.
        //
        // ⛔ THE FIRST CUT APPENDED IT UNCONDITIONALLY AT THE TOP OF THIS FUNCTION AND BROKE
        // #245 — the law this very function exists to enforce: a frame with NOTHING measured
        // must be SILENT, so a receiver reads absence as absence. An always-present flag turns
        // every dead frame into traffic. `OSCAbsenceTests.testAFrameWithNothingMeasuredSends
        // NothingAtAll` went red, on correct-looking code, for the right reason.
        //
        // ⭐ THE THIRD KIND OF GATE, named because this file already has two and a reader will
        // otherwise mis-file it. #245 gates each address on ITS OWN measurement. #215 drops an
        // address that has no producer at all. This one is gated on THE BATCH: it ships only
        // alongside data it describes, never alone. A receiver therefore never gets a bare flag,
        // a silent frame stays perfectly silent, and every value that does arrive is
        // accompanied by its origin.
        //
        // ⚠️ 0 IS A FACT HERE, not a missing measurement — "a real body" — which is why the
        // no-structural-zeros rule above does not reach this line. And a receiver that never
        // sees the address is talking to a build older than #639; that is the honest reading,
        // and it is why this is an ADDITIVE address rather than an extra argument on the
        // existing ones (appending to `/heart/bpm` would break every integrator on the old
        // contract in the name of honesty).
        //
        // ⚠️ FIRST in the list is a courtesy, not a guarantee: separate datagrams, and UDP does
        // not promise order. The header tells the receiver to latch it as state; at ~1 Hz and
        // changing only when the player switches source, a one-tick inversion self-corrects.
        if !msgs.isEmpty {
            msgs.insert(("/echoelmusic/bio/synthetic", [frame.source.isSynthetic ? 1 : 0]), at: 0)
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
