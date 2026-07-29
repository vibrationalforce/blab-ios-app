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
//    motion       → gain       movement brings it forward — DORMANT in this build
//                              (#215): nothing measures motion, so the BIO arm sends no
//                              /gain at all rather than a constant. The MUSIC arm
//                              (`MusicMediaMap.admMessages`) still drives /gain from the
//                              master level whenever notes sound. See `motionGain`.
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

    /// Dialect for SCENE streaming (ADM-OSC or IEM MultiEncoder). The bio→object
    /// path is always ADM-OSC; this only affects `streamsScene`.
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
    public static func admMessages(for f: BioSampleFrame, object n: Int) -> [(String, Float)] {
        let idx = max(1, n)
        let prefix = "/adm/obj/\(idx)"
        // breath phase [0..1] → azimuth [-180..180]: L↔R sweep with the breath
        let azimuth = clamp((f.breathPhase * 2 - 1) * 180, -180, 180)
        // coherence [0..1] → distance [0..1]: coherent pulls close (small distance)
        let distance = clamp(1 - f.coherence, 0, 1)
        // HRV [0..1] → elevation [-90..90]: calm lifts (use upper hemisphere 0..60)
        let elevation = clamp(f.hrvNormalized * 60, -90, 90)
        // motion [0..1] → gain [0..1]: movement brings the object forward — WHEN
        // something measures motion. Today nothing does, so this arm asserts no gain at
        // all (#215); see `motionGain`.
        var msgs: [(String, Float)] = [
            ("\(prefix)/position/azimuth", azimuth),
            ("\(prefix)/position/elevation", elevation),
            ("\(prefix)/position/distance", distance)
        ]
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
