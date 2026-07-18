//
//  FaceExpressionBioPublisher.swift
//  Echoelmusic — Bio capture (A5 BodyVibe camera modulator)
//
//  Publishes front-camera facial-EXPRESSION as bio control channels: ARKit
//  ARFaceTrackingConfiguration → blendShapes → smile/brow/jaw ∈ [0..1] on the
//  EngineBus, at ~10 Hz, source `.faceCam`.
//
//  IMPORTANT — framing (EU AI Act): these are EXPRESSION / MOVEMENT used as a
//  CONTROL signal for the instrument, NEVER an inferred "emotion" or affective
//  state. A smile MOVES a parameter; it is not read as a feeling. The image never
//  leaves the device — only the abstracted [0..1] channels (see BioEgressPolicy).
//
//  Camera exclusivity: ARFaceTrackingConfiguration owns the front TrueDepth camera
//  and cannot run alongside the rPPG AVCaptureSession — so this is ONE more
//  mutually-exclusive `BioSource`, selected deliberately (the single-active-source
//  model already enforces the exclusion). It carries NO pulse; whether the pulse
//  source should COEXIST (e.g. a BLE strap for HR + face for expression) is a
//  product decision deferred to the selection-wiring slice — this file just
//  honestly publishes face channels + neutral bio under `.faceCam`.
//
//  WIRING STATE: this cycle the type compiles but NOTHING instantiates it (behind
//  `FeatureFlags.cameraExpression`, default OFF). Runtime is bit-identical until the
//  selection wiring lands. Concurrency follows the rPPG discipline: the ARKit
//  delegate (which may fire off the main actor) never hops to @MainActor per frame —
//  it stores the latest blendShapes under a lock; the 10 Hz @MainActor loop drains.
//

import Foundation
import Observation
#if canImport(ARKit)
import ARKit
#endif

/// Thread-safe holder for the latest blendShape bag. Mirrors the rPPG
/// `RGBSampleQueue` rule: the high-rate producer writes here with ZERO actor hop;
/// the low-rate main-actor loop reads it.
private final class LatestFaceSample: @unchecked Sendable {
    private let lock = NSLock()
    private var coefficients: [String: Float] = [:]
    private var hasFace = false

    func store(_ c: [String: Float]) {
        lock.lock(); coefficients = c; hasFace = true; lock.unlock()
    }
    /// The latest bag, or `nil` while no face has been seen yet.
    func read() -> [String: Float]? {
        lock.lock(); defer { lock.unlock() }
        return hasFace ? coefficients : nil
    }
    func clear() {
        lock.lock(); coefficients = [:]; hasFace = false; lock.unlock()
    }
}

@MainActor
@Observable
public final class FaceExpressionBioPublisher {

    /// True while the ARKit session is running and the publish loop is live.
    public private(set) var isPublishing = false

    /// Whether this device can track the face at all (front TrueDepth / ARKit).
    /// `false` on any platform without ARKit or without face-tracking hardware —
    /// callers gate the "Face" bio source on this.
    public static var isSupported: Bool {
        #if canImport(ARKit)
        return ARFaceTrackingConfiguration.isSupported
        #else
        return false
        #endif
    }

    @ObservationIgnored private var mapping = FaceExpressionMapping()
    @ObservationIgnored private let latest = LatestFaceSample()
    @ObservationIgnored private var lastPublish: CFAbsoluteTime = 0

    #if canImport(ARKit)
    @ObservationIgnored private let arSession = ARSession()
    @ObservationIgnored private var delegateProxy: FaceDelegateProxy?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    #endif

    public init() {}

    /// Start front-camera expression tracking and publish `.faceCam` frames to `bus`.
    /// No-op when unsupported or already running. The camera-permission dialog (the
    /// same `NSCameraUsageDescription` rPPG uses) is raised by `arSession.run`.
    public func start(publishing bus: EngineBus) {
        guard !isPublishing, Self.isSupported else { return }
        #if canImport(ARKit)
        let proxy = FaceDelegateProxy(latest: latest)
        delegateProxy = proxy
        arSession.delegate = proxy
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isPublishing = true
        startPublishLoop(bus: bus)
        #endif
    }

    /// Stop tracking and publishing. Idempotent. Resets the smoothed state so a
    /// restart begins from neutral (a lost face reads as "no expression").
    public func stop() {
        #if canImport(ARKit)
        publishTask?.cancel()
        publishTask = nil
        arSession.pause()
        arSession.delegate = nil
        delegateProxy = nil
        #endif
        latest.clear()
        mapping = FaceExpressionMapping()
        isPublishing = false
    }

    #if canImport(ARKit)
    private func startPublishLoop(bus: EngineBus) {
        lastPublish = CFAbsoluteTimeGetCurrent()
        publishTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)   // 10 Hz
                guard let self else { return }
                self.tick(bus: bus)
            }
        }
    }

    /// One 10 Hz drain: latest bag → channels → rate-based EMA → `.faceCam` frame.
    /// Skips while no face is present (never publishes a stale/spiked value).
    private func tick(bus: EngineBus) {
        guard let bag = latest.read() else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let dt = Swift.max(0, now - lastPublish)
        lastPublish = now
        let raw = FaceExpressionMapping.rawChannels(from: bag)
        mapping = mapping.updated(rawSmile: raw.smile,
                                  rawBrowRaise: raw.browRaise,
                                  rawJawOpen: raw.jawOpen,
                                  dt: dt)
        bus.publish(bio: BioSampleFrame(
            timestamp: now,
            heartRateBPM: 0,          // faceCam carries NO pulse (coexistence deferred)
            hrvNormalized: 0,
            breathRate: 0,
            breathPhase: 0,
            coherence: 0,
            motionEnergy: 0,
            source: .faceCam,
            faceSmile: mapping.smile,
            faceBrowRaise: mapping.browRaise,
            faceJawOpen: mapping.jawOpen
        ))
    }
    #endif
}

#if canImport(ARKit)
/// Nonisolated ARKit delegate: extracts blendShape coefficients into the lock-
/// protected holder. Never touches the @MainActor publisher directly, so ARKit's
/// delegate queue is irrelevant — no per-frame actor hop (the rPPG lesson).
private final class FaceDelegateProxy: NSObject, ARSessionDelegate {
    private let latest: LatestFaceSample
    init(latest: LatestFaceSample) { self.latest = latest }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let face = anchor as? ARFaceAnchor else { continue }
            var bag: [String: Float] = [:]
            bag.reserveCapacity(face.blendShapes.count)
            for (key, value) in face.blendShapes {
                bag[key.rawValue] = value.floatValue
            }
            latest.store(bag)
        }
    }
}
#endif
