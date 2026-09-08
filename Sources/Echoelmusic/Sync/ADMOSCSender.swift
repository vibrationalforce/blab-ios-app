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
//  Default bio → object mapping (all four are existing BioSampleFrame fields). EVERY ONE
//  of them is sent only while its own channel is actually measured (#260) — see
//  `admMessages` for why, and note that two of these structural zeros are extremes, not
//  neutral positions:
//    breath phase → azimuth    sound sweeps L↔R with the breath — needs `hasMeasuredBreath`
//    coherence    → distance   coherent = pulled close; scattered = far — needs a pulse
//                              AND a non-zero coherence, which a camera take may never
//                              reach (16 RR intervals)
//    HRV          → elevation  calm lifts the object — needs a pulse AND a non-zero HRV
//    motion       → gain       movement brings it forward — DORMANT in this build
//                              (#215): nothing measures motion, so the BIO arm sends no
//                              /gain at all rather than a constant. The MUSIC arm
//                              (`MusicMediaMap.admMessages`) still drives /gain from the
//                              master level whenever notes sound. See `motionGain`.
//  Silence on an address means "not measured", never "measured as zero"; the renderer
//  holds its last value, which is what a slipped finger should look like.
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
    public var host: String {
        didSet { Self.persistTarget(host, port); reconnectIfActive() }
    }

    /// Renderer OSC port. ADM-OSC renderers typically listen on a port distinct
    /// from TouchOSC's 8000 — default 9000, user-configurable.
    public var port: UInt16 {
        didSet { Self.persistTarget(host, port); reconnectIfActive() }
    }

    /// 1-based ADM object index this bio source drives.
    public var objectIndex: Int

    /// S3 — Immersive-Stage scene streaming. When true, each tick streams the ATTACHED
    /// scene (every placed track as `/adm/obj/1…N`) INSTEAD of the bio→object mapping.
    /// Mutual exclusion is the whole point: streaming the track scene suppresses the
    /// bio object so object 1 never collides. Off by default ⇒ the bio path is
    /// untouched and Release is bit-identical. Toggling it re-arms a fresh send.
    public var streamsScene = false {
        didSet { if streamsScene != oldValue { lastSentScene = nil } }
    }

    /// Dialect for SCENE streaming. The bio→object path is always ADM-OSC polar;
    /// this only affects the `streamsScene` branch.
    ///
    /// ⛔ NOTHING IN `Sources/` WRITES THIS (#745). Measured with comments
    /// stripped: the name occurs TWICE in code, both in this file — this
    /// declaration and the read in `sendIfFresh`. `ImmersiveStageView`, the one
    /// surface that touches this sender's stream controls, names it ZERO times;
    /// its `Toggle` binds `streamsScene` and nothing else. So all three cases of
    /// `SpatialOSCDialect` are built and golden-file tested, and exactly one of
    /// them can ever reach the wire.
    ///
    /// ⚠️ THIS IS SECOND-ORDER DOORLESS, and that distinction decides what to do
    /// about it. `AutoMixChain.preset` (#736) was a live multi-way choice on a
    /// REACHABLE surface, so it earned a door. Here the branch that reads this
    /// property sits behind `streamsScene`, whose only writer lives in a view with
    /// zero construction sites — deliberately parked, like `BroadcastView`. Adding
    /// a picker here would build a control nobody can open. **Register it, do not
    /// door it**; the door belongs in the same commit that re-mounts the stage.
    ///
    /// ⭐ The user-facing copy is already honest about this by accident: the stage
    /// toggle reads "Stream to renderer (ADM-OSC)" — it names the one dialect that
    /// can actually happen. Whoever adds the picker must widen that label in the
    /// same commit, or the label starts lying the moment the choice becomes real.
    ///
    /// NOT A DEFECT TO DELETE. `admCartesianMessages` and `iemMessages` are the
    /// difference between "speaks the open standard" and "speaks our corner of it"
    /// — Cartesian-only consoles and the IEM suite are exactly the rigs the
    /// identity line's immersive pillar is aimed at.
    public var sceneDialect: SpatialOSCDialect = .admOSC

    /// Object count in the most recent streamed scene — drives a UI activity readout
    /// without a timer (like `lastSentTimestamp`).
    public private(set) var lastSceneObjectCount = 0

    public private(set) var isActive = false

    /// CFAbsoluteTime of the last datagram sent — lets the UI render an activity
    /// dot without a timer (mirrors OSCSender).
    public private(set) var lastSentTimestamp: TimeInterval = 0

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private weak var sceneStore: SpatialSceneStore?
    @ObservationIgnored private var lastSentScene: SpatialScene?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private let loop = PollingLoop()
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1

    public init(host: String = "127.0.0.1", port: UInt16 = 9000, objectIndex: Int = 1) {
        let d = UserDefaults.standard
        self.host = d.string(forKey: Self.hostKey) ?? host
        let p = d.integer(forKey: Self.portKey)
        self.port = (p > 0 && p <= 65_535) ? UInt16(p) : port
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
        lastSentScene = nil
        lastSceneObjectCount = 0
    }

    /// Attach the live Immersive-Stage scene (weak — the store lives at app level).
    /// Streaming only actually happens while `streamsScene` is true AND a route has
    /// opened the socket.
    public func attachScene(_ store: SpatialSceneStore?) {
        sceneStore = store
    }

    // MARK: - Target persistence + live reconnect

    private static let hostKey = "net.adm.host"
    private static let portKey = "net.adm.port"
    private static func persistTarget(_ host: String, _ port: UInt16) {
        let d = UserDefaults.standard
        d.set(host, forKey: hostKey)
        d.set(Int(port), forKey: portKey)
    }
    /// A host/port edit takes effect immediately while streaming (connect() otherwise
    /// only runs in start()): drop the old socket, reconnect. Idle ⇒ no-op.
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
        // S3 — SCENE STREAMING takes over the socket when armed: every placed track is
        // an object (/adm/obj/1…N via the golden-tested formatter), and the bio→object
        // path below is suppressed entirely so object 1 never collides. Static
        // positions send once (dedup on scene equality); a puck move / recorded
        // automation restreams. Streaming but nothing placed yet ⇒ send nothing (never
        // fall back to bio — that would reintroduce the collision).
        if streamsScene {
            guard let scene = sceneStore?.scene, !scene.objects.isEmpty else {
                if lastSceneObjectCount != 0 { lastSceneObjectCount = 0 }
                return
            }
            // Guard the observed write so a static scene doesn't fire an @Observable
            // notification every 20 Hz tick (that would churn the Immersive Stage's
            // puck body — the readout is a low-frequency status, not a live meter).
            if lastSceneObjectCount != scene.objects.count { lastSceneObjectCount = scene.objects.count }
            guard scene != lastSentScene else { return }
            lastSentScene = scene
            send(scene: scene, dialect: sceneDialect)   // sets lastSentTimestamp
            return
        }
        // Music drives the object POSITION when sounding (pitch→azimuth/elevation,
        // level→distance/gain), bio otherwise — bio stays the co-modulator. Dedup on
        // the chosen source's timestamp so a music-only change still moves the object.
        let music = bus.freshMusical(maxAge: 1.5)
        let sourceTimestamp: TimeInterval
        let messages: [(String, Float)]
        if let m = music, m.isSounding {
            sourceTimestamp = m.timestamp
            messages = MusicMediaMap.admMessages(forMusic: m, object: objectIndex)
        } else if let frame = bus.latestBio, BioEgressPolicy.allowsEgress(frame.source) {
            // 5.1.3: the bio→object co-modulation path sends breath/coherence/HRV-
            // derived positions — only Echoel-measured sources may leave the device.
            sourceTimestamp = frame.timestamp
            messages = Self.admMessages(for: frame, object: objectIndex)
        } else {
            return
        }
        guard sourceTimestamp != lastFrameTimestamp else { return }
        lastFrameTimestamp = sourceTimestamp
        // A frame whose channels are all still unmeasured produces NO addresses (#260), so
        // return before the stamp: `lastSentTimestamp` documents itself as "the last
        // datagram sent" and would otherwise record a tick on which nothing left the
        // device. Matches `OSCSender`'s `if sentAny`.
        //
        // ⚠️ This does NOT fix an indicator, and an earlier draft of this comment claimed it
        // did. `lastSentTimestamp` has no reader anywhere in `Sources/`; the Patchbay dot
        // (`PatchbayView`, `outputRow("ADM-OSC", active:)`) reads `isActive`, deliberately,
        // because a low-frequency flag is freeze-safe. The honest statement of what remains:
        // on a strap-only rig this arm can now send nothing for a whole session while that
        // dot still reads "sending". That is a separate defect, not one this line closes.
        guard !messages.isEmpty else { return }
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

    // MARK: - Scene-driven send (S3 — driven by the tick while `streamsScene` is armed)

    /// Pushes an entire SpatialScene through the open socket in the given
    /// dialect (ADM-OSC or IEM). Formatting is the pure
    /// `SpatialSceneOSCFormatter` (golden-file tested); this method only
    /// moves bytes. Called by `sendIfFresh` when `streamsScene` is on (mutual
    /// exclusion with the bio→object path); still safe to call directly.
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
    ///
    /// ⛔ EVERY ADDRESS RIDES THE MEASUREMENT OF ITS OWN CHANNEL (#260), the same rule
    /// `OSCSender.bioMessages` follows since #245 — and here the stakes are higher than
    /// on the OSC feed, because two of the three structural zeros are not neutral, they
    /// are EXTREMES:
    ///   · unmeasured breath ⇒ `breathPhase` 0 ⇒ azimuth **−180**, the object slammed
    ///     hard left;
    ///   · unmeasured coherence ⇒ `1 - 0` ⇒ distance **1**, the object pushed to the far
    ///     end of the room.
    /// A renderer cannot tell either apart from a performer who really is hard left and far
    /// away.
    ///
    /// ⛔ AND BOTH OCCURRED ON SHIPPING HARDWARE, which is what makes this a defect rather
    /// than a hypothetical. `PolarH10BioPublisher` publishes `breathRate: 0, breathPhase: 0`
    /// on EVERY frame — the strap derives no respiration — and `.ble` is egress-allowed, so
    /// a chest-strap session pinned `/position/azimuth` at exactly −180 for its whole
    /// duration, every time. The camera is the same story one axis over: `coherence` stays 0
    /// until 16 accepted RR intervals, and `CameraAnalyzer`'s RR series comes from a fixed
    /// 10 s peak window (≈10 intervals at a resting rate), so `distance` sat at 1 for entire
    /// takes. (An earlier draft of this comment blamed `FaceExpressionBioPublisher`'s
    /// all-zero frame instead. That was WRONG and worth recording: the type has zero
    /// instantiations in `Sources/` and sits behind `FeatureFlags.cameraExpression`, so no
    /// `.faceCam` frame exists in a shipped build. The real path is stronger, not weaker.)
    ///
    /// ⚠️ Consequence to know before mapping: on a bio-only rig an address that is never
    /// measured never arrives, so the object keeps its initial position rather than being
    /// driven to a default. `distance` is the one most likely to stay absent for a whole
    /// take — see `HRVCoherence.minIntervals` and the note in `OSCSender`.
    public nonisolated static func admMessages(for f: BioSampleFrame,
                                               object n: Int) -> [(String, Float)] {
        let idx = max(1, n)
        let prefix = "/adm/obj/\(idx)"
        var msgs: [(String, Float)] = []

        // breath phase [0..1] → azimuth [-180..180]: L↔R sweep with the breath.
        // Gated on `breathRate`, not on the phase: `breathPhase` has no unknown sentinel
        // (0 is a real position, exhale start), so it cannot answer for itself.
        // `isFinite` too, because this is the ONE axis whose gate a corrupt value can pass:
        // the other two compare `> 0`, which is false for NaN, while `3...40` can hold a
        // real rate beside a corrupt phase. `clamp` here is not NaN-safe, so without this a
        // NaN would go out as an azimuth — and even the NaN-safe form would land on −180,
        // the very position this gate exists to stop asserting. `isFinite` also refuses
        // ±infinity, deliberately: an infinite phase would clamp to a legal-looking ±180
        // that is nonetheless not a reading, and this arm's whole rule is that it asserts
        // only what was measured.
        // ⭐ #1140 — `hasMeasuredBreathWaveform`, NOT `hasMeasuredBreath`, and this arm is the
        // one that argued hardest for the distinction before it existed. `HealthKitBioPublisher`
        // reads a real respiratory RATE while `breathPhase` stays frozen at 0.5, so the old gate
        // opened and this line sent `(0.5·2−1)·180` = **azimuth 0°** — the object asserted dead
        // centre front, permanently, as a measurement. That is precisely "an invented number in
        // someone's rig", which the sentence above forbids in so many words. The rate gate was
        // never wrong about the rate; it was answering a different question.
        if f.hasMeasuredBreathWaveform, f.breathPhase.isFinite {
            msgs.append(("\(prefix)/position/azimuth",
                         clamp((f.breathPhase * 2 - 1) * 180, -180, 180)))
        }
        // HRV [0..1] → elevation [-90..90]: calm lifts (upper hemisphere 0..60).
        // Both halves, as on the OSC path: an HRV beside a pulse of 0 is a publisher bug,
        // not a reading, and this arm must not put an invented number in someone's rig.
        if f.hasMeasuredHeartRate, f.hrvNormalized > 0 {
            msgs.append(("\(prefix)/position/elevation", clamp(f.hrvNormalized * 60, -90, 90)))
        }
        // coherence [0..1] → distance [0..1]: coherent pulls close (small distance).
        if f.hasMeasuredHeartRate, f.coherence > 0 {
            msgs.append(("\(prefix)/position/distance", clamp(1 - f.coherence, 0, 1)))
        }
        // motion [0..1] → gain [0..1]: movement brings the object forward — WHEN
        // something measures motion. Today nothing does, so this arm asserts no gain at
        // all (#215); see `motionGain`.
        if let gain = motionGain(motion: f.motionEnergy,
                                 hasProducer: ModSource.motion.hasProducer) {
            msgs.append(("\(prefix)/gain", gain))
        }
        return msgs
    }

    /// The bio arm's object gain, or `nil` when nothing measures motion — in which case
    /// this sender asserts no gain at all and the renderer keeps whatever it has.
    ///
    /// WHY NIL RATHER THAN A NUMBER, and this is the part a first attempt got wrong.
    /// `sendIfFresh` has TWO gain arms for the same object index, alternating at 20 Hz:
    /// `MusicMediaMap.admMessages` while `MusicalFrame.isSounding`, this one otherwise.
    /// `isSounding` is `!notes.isEmpty && masterLevel > 0`, so the arms swap at every rest
    /// and every phrase boundary, and ADM-OSC carries no slew. So the old constant `0.3`
    /// here was NOT "the only level this object could ever have" — it was the level at
    /// musical rest, and it happened to equal the music arm's own floor, i.e. a clean duck.
    /// Substituting unity would have inverted that into a JUMP of up to +8 dB above where
    /// the music arm left off, on every rest, snapping back at the next note onset — a
    /// boost of whatever tail, bleed or room sits on that object, exactly when the music
    /// stops. Sending nothing produces no step at all, and in a bio-only rig it leaves
    /// `/adm/obj/{n}/gain` unasserted, which is the honest statement: Echoel is not
    /// driving this parameter today. It also matches how the sibling defect was fixed on
    /// the OSC side (`/echoelmusic/bio/motion` is omitted, not zeroed).
    ///
    /// Parameterised on the predicate instead of reading it, so BOTH answers are reachable
    /// from a test. Branching on `ModSource.motion.hasProducer` INSIDE the tests would
    /// leave the live arm permanently dead — prose in `if` clothing — and would silently
    /// switch off the regression assertions on the day a producer lands.
    nonisolated static func motionGain(motion: Float, hasProducer: Bool) -> Float? {
        guard hasProducer else { return nil }
        // Bit-identical to the expression this replaced (`0.3 + motion * 0.7`), because
        // `1 - Float(0.3)` and `Float(0.7)` are the same binary32 value. The live mapping
        // is not being retuned; only its dormant case is being answered differently.
        return clamp(motionRestingGain + motion * (1 - motionRestingGain), 0, 1)
    }

    /// Object gain with a MEASURED motion modulator at rest. Named rather than inlined so
    /// the "what does an unmoving body sound like" decision has one place to be argued
    /// with. Unused while `hasProducer` is false — kept because it is the right resting
    /// point for a live motion channel, not because anything reads it today.
    ///
    /// `nonisolated` deliberately: this class is `@MainActor`, and CLAUDE.md records that
    /// Xcode's toolchain isolates an immutable `static let` on such a class even where
    /// SwiftPM accepts it. Both call sites are on the main actor anyway, so this
    /// pre-empts the toolchain disagreement rather than being load-bearing.
    nonisolated static let motionRestingGain: Float = 0.3

    nonisolated private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(v, lo), hi)
    }
}
#endif
