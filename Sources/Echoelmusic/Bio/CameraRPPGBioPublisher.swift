//
//  CameraRPPGBioPublisher.swift
//  Echoelmusic — Bio
//
//  Wires the dormant camera rPPG path into the live EngineBus: drives
//  CameraCapture → CameraAnalyzer (photoplethysmography) and publishes a
//  BioSampleFrame(source: .cameraPPG) at ~1 Hz when a confident pulse is
//  detected. Opt-in (started explicitly by the UI), never auto-run.
//
//  Concurrency:
//  CameraCapture delivers CVPixelBuffers on its capture queue; we average the
//  center region to 3 Sendable Floats THERE, then hop to the main actor to feed
//  the @MainActor CameraAnalyzer (CVPixelBuffer is non-Sendable, so it never
//  crosses actors). EngineBus.publish(bio:) is nonisolated, so the 1 Hz loop can
//  publish directly.
//
//  RUNTIME NOTE: actual pulse detection needs a real device (camera + a finger
//  or face, ideally the torch). Compile-verified here; behaviour device-checked.
//

#if canImport(AVFoundation) && canImport(Observation)
import Foundation
import AVFoundation
import Observation

/// Lock-protected hand-off for pre-extracted RGB samples from the camera capture
/// queue to the @MainActor analyzer. The OLD path hopped to the main actor with a
/// `Task { @MainActor }` PER FRAME (~30/s at native capture rate, before the
/// analyzer's internal frame-skip). That flood of main-actor task submissions
/// starved the UI executor while biofeedback ran — the dropdown `.menu` Picker
/// stopped responding ("Sobald Biofeedback läuft kann ich nicht mehr auswählen").
/// Now the capture queue just appends samples here (one lock, no actor hop) and the
/// existing 10 Hz publish loop drains them on the main actor — zero per-frame tasks.
private final class RGBSampleQueue: @unchecked Sendable {
    struct Sample { let r: Float; let g: Float; let b: Float; let t: TimeInterval }
    private let lock = NSLock()
    private var samples: [Sample] = []
    /// Cap so a stalled drain can't grow this without bound (~3 s at 30 fps).
    private static let maxBuffered = 90

    func push(r: Float, g: Float, b: Float, t: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if samples.count >= Self.maxBuffered { samples.removeFirst(samples.count - Self.maxBuffered + 1) }
        samples.append(Sample(r: r, g: g, b: b, t: t))
    }

    /// Atomically take and clear everything queued so far (FIFO order preserved).
    func drain() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return [] }
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Honest, glanceable state for a live camera stall — so a mid-session freeze is
/// never silent/confusing (founder-approved: "ehrlicher Hinweis"). Low-frequency:
/// it only changes on a recovery/thermal transition, NOT every 10 Hz tick, so a leaf
/// that reads ONLY this property doesn't churn (per-property @Observable tracking).
public enum RPPGRecoveryState: Equatable, Sendable {
    /// Frames flowing normally — no banner.
    case healthy
    /// A stall was detected; the camera is restarting itself.
    case recovering
    /// The device is thermally throttled (torch dimmed); frames may pause until it cools.
    case cooling
    /// iOS holds the session interrupted (backgrounded/system) — restarts are no-ops
    /// until the OS releases it; be honest instead of silently showing 0 bpm.
    case interrupted

    /// Short user-facing line for the bio strip (nil when nothing to show).
    public var userHint: String? {
        switch self {
        case .healthy:     return nil
        case .recovering:  return "Camera recovering…"
        case .cooling:     return "Device cooling down — pulse holds for a moment"
        case .interrupted: return "Camera paused by iOS — waiting to resume"
        }
    }
}

@MainActor
@Observable
public final class CameraRPPGBioPublisher {

    public private(set) var isRunning = false

    /// Camera access is denied/restricted in Settings (UX-1). Set when a start
    /// attempt fails WITH that authorization status, cleared by a successful
    /// start — low-frequency (start attempts only), safe to read in leaf views.
    /// Without it, a denied camera left `isRunning == false` with NO explanation:
    /// the strip said "Cover camera" forever and the header showed no cue at all.
    public private(set) var permissionDenied = false

    // Live status for the UI so the user can position correctly (rPPG is
    // position-sensitive). Updated ~3×/s while running.
    public private(set) var fingerDetected = false
    public private(set) var signalQuality: Double = 0   // 0...1
    public private(set) var confidence: Double = 0      // 0...1 — pulse-lock progress
    public private(set) var detectedBPM: Double = 0
    /// A CALM BPM for on-screen display (founder 2026-07-02: "ruhige Anzeige"). It updates
    /// only on a CONFIDENT reading and EMA-smooths, HOLDING the last good value through
    /// low-confidence patches — so the glanceable number stops bouncing (e.g. 55↔98 during
    /// a marginal grip). The measurement (`detectedBPM`) and the bus-published HR stay
    /// honest and untouched; this is display-only.
    public private(set) var displayBPM: Double = 0
    /// Only readings at/above this confidence move `displayBPM` (higher than `lockThreshold`
    /// so the noisy 0.35–0.55 band holds instead of wandering).
    /// `nonisolated`: a pure constant, so the pure `pulseTrustworthy` gate and its
    /// Foundation-only unit tests (CameraRPPGTrustTests) can read it without hopping
    /// to the main actor. Runtime-identical; no observation/render effect.
    nonisolated static let displayThreshold = 0.6
    /// Max change of the shown pulse per ~100 ms tick — a physiological slew cap so the
    /// displayed BPM can never jump. 1.0 bpm/tick ≈ 10 bpm/s: calm enough that a resting
    /// readout doesn't visibly twitch, still fast enough to track a genuine rise/fall within
    /// a couple seconds. (Was 2.0 — founder: "bpm springt"; the readout was still too lively.)
    static let maxDisplayStep = 1.0
    /// Live bandpass-filtered pulse waveform (~[-1,1]) for the "Stimmungsbild".
    public private(set) var waveform: [Float] = []
    /// Honest recovery/cooling state for the UI (see RPPGRecoveryState). Changes only on a
    /// stall/recover/thermal transition — read it in a LEAF view (BioStripView) so the low-freq
    /// banner never registers the root body as a 10 Hz observer.
    public private(set) var recoveryState: RPPGRecoveryState = .healthy
    /// Ticks remaining to keep showing "recovering" after a restart is triggered (~10 Hz).
    /// Decays so a brief hiccup's banner doesn't linger once frames return.
    @ObservationIgnored private var recoveringTicks = 0
    /// EMA of the INBOUND camera sample rate (Hz), measured from what the publish loop
    /// actually drains. Device log 1783506447: after a stall recovery the analyzer window
    /// sat at win=0 for 10 s while finger/R stayed live — consistent with the camera
    /// delivering a thermally-throttled trickle (frames arrive, far too few for the pulse
    /// band). This measurement makes that state visible in the diag line and drives the
    /// honest "cooling" banner below ~6 Hz (pulse extraction needs the 0.7–4 Hz band —
    /// at a few fps the measurement is physically impossible, so say so instead of
    /// showing a silent dead readout). Seeded at nominal so startup never false-flags.
    @ObservationIgnored private var inboundRateEMA: Double = 15
    /// Publish-loop ticks since start — grace window so the cooling banner can't fire
    /// during camera warm-up.
    @ObservationIgnored private var loopTicks = 0
    /// Below this sustained inbound rate the pulse band is unmeasurable → honest cooling.
    static let minMeasurableInboundHz = 6.0
    /// Lock threshold — also the bus-publish gate.
    static let lockThreshold = 0.35

    /// Minimum AUTOCORRELATION strength ("acf") a reading must carry before it may move the
    /// shown pulse OR latch the tempo. Confidence alone can be inflated by the peak-counter
    /// SELF-AGREEING on a noisy, poorly-placed finger (device log 2026-07-04: R saturated
    /// 0.7–0.8, acf 0.14, conf 0.90 → "settled" at a WRONG 79 bpm while the true resting pulse
    /// was ~54, visible later in the SAME session at acf 0.78). Requiring real periodicity
    /// means a bad reading now HOLDS ("acquiring") instead of showing/seeding a fantasy number
    /// — the pulse must EARN trust. On this device real locks always carry strong acf
    /// (0.57–0.84); junk maxes ~0.29, so 0.4 separates them cleanly. (Camera is the approximate
    /// fallback — a chest strap gives clean beat-to-beat directly and is the preferred source.)
    nonisolated static let trustAutoFloor = 0.4

    /// STRONG autocorrelation that, on its OWN, proves a real pulse regardless of the
    /// confidence metric (device log 1783420026: acf climbed to 0.59–0.72 with a
    /// rock-stable 56 bpm for ~10 s while conf sat at 0.01 — a genuine, strongly
    /// periodic pulse that the display refused to show because it also demanded
    /// confidence). The confidence channel (peak-counter based) and the acf channel
    /// don't always rise together; strong periodicity is the STRONGER evidence, so it
    /// should not have to wait for confidence to catch up. Set well above the junk
    /// ceiling (~0.29, see trustAutoFloor note) so the high-conf/low-acf self-agreeing
    /// junk case can never reach it.
    nonisolated static let strongAutoFloor = 0.6

    /// A reading may move the display / latch the tempo when it is EITHER confident AND
    /// corroborated by real periodicity, OR carries strong periodicity on its own. The
    /// junk case (conf high, acf ~0.14) still fails BOTH clauses. Pure → unit-testable.
    nonisolated static func pulseTrustworthy(confidence: Double, autoStrength: Double) -> Bool {
        (confidence >= displayThreshold && autoStrength >= trustAutoFloor)
            || autoStrength >= strongAutoFloor
    }
    /// THE BUS-PUBLISH GATE — deliberately the SAME bar as the shown number.
    ///
    /// Until 2026-07-27 this path gated on `bpm > 0 && bpmConfidence >= lockThreshold`
    /// alone, i.e. strictly WEAKER than `pulseTrustworthy`, which the display has used
    /// since the acf work. That asymmetry meant the screen was held to more evidence than
    /// the instrument: device log 2469 (build 10.79.352) carries
    /// `bpm=75 conf=0.62 acf=0.30 auto=64` and `bpm=80 conf=0.62 acf=0.32 auto=63` — over
    /// the old publish threshold, under the display's — so the readout correctly held ~48
    /// while the BUS fed 75–80 bpm to the synth, the visual, OSC, ADM-OSC and Art-Net.
    /// The number you SEE and the number you HEAR must clear one bar.
    ///
    /// Note it is `pulseTrustworthy` EXACTLY, not `pulseTrustworthy && confidence >= lockThreshold`.
    /// That AND looks safer and is wrong: it would drop the documented strong-periodicity /
    /// low-confidence case (acf 0.59–0.72 at conf 0.01, a rock-stable real 56 bpm) out of the
    /// SOUND while the display still shows it — the same asymmetry, merely inverted.
    ///
    /// Pure → unit-testable, which the inline `guard` it replaces was not.
    nonisolated static func shouldPublish(bpm: Double, confidence: Double, autoStrength: Double) -> Bool {
        bpm > 0 && pulseTrustworthy(confidence: confidence, autoStrength: autoStrength)
    }

    /// True once a confident pulse is locked.
    public var isLocked: Bool { detectedBPM > 0 && confidence >= Self.lockThreshold }

    /// True once the pulse is confident AND FLAT — display-grade confidence with the calm
    /// displayBPM moving ≤ ~3 bpm over ~3 s. This is the gate for LATCHING the take tempo:
    /// confidence alone fires on the falling tail of the warm-up curve (device log: locked 87
    /// while the pulse was still descending 125→…→69 — "in dem Moment wo bpm locked springt
    /// die bpm nach oben"). Settled = the descent has actually finished.
    public private(set) var isSettled = false
    /// Reference value + start time of the current flat window (tracked in the 10 Hz tick).
    private var settleRef: Double = -1
    private var settleSince: CFAbsoluteTime = 0
    /// Flat-window parameters: ≤3 bpm drift sustained for ≥3 s.
    private static let settleTolerance = 3.0
    private static let settleSeconds = 3.0

    /// BIO-STREAM HOLD across brief signal dropouts (founder 2026-07-09: "das
    /// Flickern im Fullscreen … hängt damit zusammen ob Biofeedback an ist").
    /// A marginal signal (e.g. exposure drifting bright) makes `bpmConfidence`
    /// flap around `lockThreshold`; blanking the bus frame on every dip let the
    /// visual's `freshBio()` go stale and hard-FLIP between bio-mode and idle-mode
    /// — the flicker, visible only while biofeedback runs — and blanked the pulse
    /// readout. We re-emit the last good frame (coherence decaying, never a snap
    /// to 0) for a short grace, so the stream the visual eases over stays
    /// continuous; only a sustained loss lets it fall to idle, as ONE smooth
    /// transition instead of a strobe.
    private var lastGoodBioFrame: BioSampleFrame?
    private var lastGoodPublishTick = Int.min
    private var lastValidCoherence: Float = 0
    /// ~4 s at the 10 Hz tick. Deliberately non-private so a test can pin the
    /// invariant this hold depends on: a held frame carries its ORIGINAL timestamp,
    /// so the hold only works while it is SHORTER than every consumer's freshness
    /// gate. A consumer with a shorter window expires the frame mid-grace and snaps
    /// to its idle defaults — the exact bio↔idle jump this exists to prevent (it
    /// happened: `SpectralDonutView` passed `maxAge: 2`).
    static let bioHoldTicks = 40

    /// Live, specific placement guidance — turns the internal amplitude/exposure
    /// diagnostics into user coaching so the lens reaches a lockable signal, instead
    /// of a flat "Acquiring…". Pure derived state, read on the main actor by the UI.
    public var coachingHint: String { acquisitionCue.fullHint }

    /// The typed coaching state (single source of truth for `coachingHint` and the
    /// compact header amber cue). Derived from the live analyzer signals on the main
    /// actor; the string/label/actionable mapping is the pure, tested `PulseCue`.
    public var acquisitionCue: PulseCue {
        // Denied access wins over EVERYTHING — no placement coaching can help,
        // and "Cover camera" for a permission dead end misleads (UX-1).
        if permissionDenied { return .cameraDenied }
        if isLocked { return .locked }
        if !fingerDetected { return .coverLens }
        // Finger is on the lit lens but no lock yet — say WHY, from the live signal.
        if analyzer.brightness > 0.85 || analyzer.redChannel > 0.92 { return .tooBright }
        // Large swings = the finger moving / changing pressure, not a pulse (the analyzer
        // rejects these windows, so it can't lock). Tell the user the real blocker so a
        // motion-heavy contact gets actionable guidance instead of an endless "finding…".
        if CameraAnalyzer.isMotionAmplitude(analyzer.lastFilteredAmplitude) { return .holdStill }
        if analyzer.lastFilteredAmplitude < 0.0008 { return .pressGently }
        return .finding
    }

    @ObservationIgnored private let capture = CameraCapture()
    @ObservationIgnored private let analyzer = CameraAnalyzer()
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    /// Capture-queue → main-actor sample hand-off (no per-frame Task hop). See
    /// RGBSampleQueue: this is the fix for the menu freeze during biofeedback.
    @ObservationIgnored private let sampleQueue = RGBSampleQueue()
    /// Monotonic token identifying the CURRENT start() call. Bumped by every start() and
    /// by stop(); a start() that resumes from its `await` only proceeds if it is still the
    /// latest generation — so a Start→Stop or Start→Stop→Start interleave during the camera
    /// config window can't resurrect a stopped camera or orphan a second publish loop.
    @ObservationIgnored private var startGeneration = 0

    // Exposure-lock state machine (10 Hz). Lock against the FINGER-covered scene,
    // not the dim finger-less one; re-settle if a lock saturates.
    @ObservationIgnored private var exposureLocked = false
    @ObservationIgnored private var fingerStableTicks = 0
    /// Ticks the CURRENT lock has been held — a lock that dies young is a phantom.
    @ObservationIgnored private var lockAgeTicks = 0
    /// Consecutive locks that quick-failed (finger lost within quickFailWindowTicks).
    @ObservationIgnored private var quickFailLocks = 0
    @ObservationIgnored private var saturatedTicks = 0
    @ObservationIgnored private var fingerLostTicks = 0
    /// Ticks the finger has been CONTINUOUSLY present (regardless of brightness) —
    /// drives the strict→permissive lock-ceiling decay (prefer a dark lock).
    @ObservationIgnored private var fingerPresentTicks = 0
    /// Accumulated full-window weak-periodicity ticks while locked (bright-lock
    /// recovery) and the bounded number of weak re-locks used this placement.
    @ObservationIgnored private var weakAcfTicks = 0
    @ObservationIgnored private var weakRelocksUsed = 0
    /// Counts publish-loop ticks with ZERO drained RGB samples. When the RGB pipe
    /// stalls (analyzer frozen while the capture watchdog stays happy — device log
    /// 2026-07-02), this crosses the threshold and forces a full camera recovery.
    @ObservationIgnored private var stallTicks = 0
    /// Consecutive publisher-forced recoveries WITHOUT any frames returning in between.
    /// Capped so a camera that starts but never yields a usable sample can't be
    /// reconfigured forever (each reconfigure delays frames further — thermal/battery
    /// churn, permanently "acquiring"). Refilled only after SUSTAINED flow (see
    /// healthyTicks) — the brief trickle right after a recovery (exposure re-lock
    /// frames) must NOT reset it, or a recurring stall thrashes at "1/3" forever and
    /// never escalates (device log 1783177538: six recoveries all logged as 1/3,
    /// 45 s of dead pulse).
    @ObservationIgnored private var forcedRecoveries = 0
    /// Consecutive publish ticks WITH samples — the "flow is really healthy again"
    /// counter that refills the recovery budget after ~3 s of sustained samples.
    @ObservationIgnored private var healthyTicks = 0
    /// One-shot final escalation: when in-place recoveries are exhausted, do a FULL
    /// cold stop→start of the capture once (the founder's manual Stop→Start healed
    /// exactly the stall the in-place recovery could not — same log).
    /// Cold-restart escalation state. UNLIMITED with a ~18 s backoff (was a ONE-SHOT
    /// `didColdRestart` flag): device log 1783588109 showed the one cold restart
    /// failing silently, after which "leaving it to the watchdog" left rPPG blind
    /// for ~83 s — the capture watchdog only acted on a RUNNING session, so a dead
    /// session had NO reviver. The founder's manual Stop→Start heals this stall
    /// class (log 1783177700); the machine now keeps doing exactly that until
    /// frames actually flow again.
    @ObservationIgnored private var coldRestarts = 0
    @ObservationIgnored private var coldCooldownTicks = 0
    private static let maxForcedRecoveries = 3
    private static let lockAfterTicks = 12      // ~1.2 s of stable finger before lock
    private static let resettleAfterTicks = 20  // ~2 s of saturation → re-settle
    private static let relockOnLossTicks = 30   // ~3 s without finger → allow re-lock
    // Only lock exposure when the finger scene is dark enough for PPG. A bright
    // finger scene means torch light is flooding the lens; locking there captured a
    // washed frame that never produced a pulse (device log 2026-07-02: locked at
    // bright=0.62, bpm=0 the whole session). Healthy PPG brightness is ~0.1–0.4.
    // `nonisolated` so the `nonisolated static func canLockNow` (and its tests) can
    // read it — the class is @MainActor, which would otherwise isolate this constant
    // and break the nonisolated reference (CLAUDE.md: @MainActor prop from nonisolated).
    nonisolated private static let maxLockBrightness: Float = 0.6

    // MARK: - Pure lock predicates (extracted so the state machine is unit-tested)

    /// A tick may count toward an exposure lock only when the finger is present AND
    /// the scene is dark enough for PPG — never lock a bright/flooded frame.
    nonisolated static func canLockNow(fingerDetected: Bool, brightness: Float) -> Bool {
        fingerDetected && brightness < maxLockBrightness
    }

    // PREFER A DARK LOCK (device log 1783401421 vs 1783370283): a lock at
    // bright=0.19 produced acf 0.8+ and a settled pulse; a lock at bright=0.34
    // (well under the permissive 0.6 cap) froze a too-bright exposure — the
    // window filled but acf never rose above ~0.4, the pulse NEVER settled, and
    // the tempo never body-seeded for the whole take. So the first seconds hold
    // a STRICT ceiling while the AGC pulls the torch-lit scene down; only after
    // that do we fall back to the permissive cap (a late soft lock still beats
    // no lock on unusual skin/devices).
    nonisolated static let strictLockBrightness: Float = 0.28
    nonisolated static let strictLockWindowTicks = 60   // ~6 s at the 10 Hz poll

    /// The brightness ceiling a lock must satisfy, given how long the finger has
    /// been continuously present. Pure → unit-tested.
    nonisolated static func lockBrightnessCeiling(fingerPresentTicks: Int) -> Float {
        fingerPresentTicks < strictLockWindowTicks ? strictLockBrightness : maxLockBrightness
    }

    // PHANTOM-LOCK BACKOFF (device log 2026-07-07, ~890 s onward): with NO finger on
    // the lens, ambient light flicked the finger detector on (R≈0.41) just long enough
    // to lock — the lock itself then DARKENED the scene (R→0.15), the "finger" vanished,
    // the unlock re-brightened it, and the cycle repeated every ~9 s indefinitely (torch
    // hot, exposure churn, UI flicker). Discriminator: a REAL finger survives a lock for
    // many seconds/minutes; these phantom locks die within a few. So a lock that loses
    // its finger inside `quickFailWindowTicks` counts as a quick-fail, and each
    // consecutive quick-fail stretches the NEXT lock's required stable time — the
    // oscillation self-extinguishes while a genuine placement is barely delayed.
    nonisolated static let quickFailWindowTicks = 60   // lock died within ~6 s = phantom

    /// Stable ticks required before the next lock, given how many consecutive locks
    /// quick-failed. 0 fails → base (~1.2 s); each fail adds one base step, capped at
    /// 6× (~7.2 s) — longer than any ambient flicker, easy for a real steady finger.
    nonisolated static func requiredStableTicks(base: Int, quickFails: Int) -> Int {
        base * (1 + min(max(quickFails, 0), 5))
    }

    // BRIGHT-LOCK RECOVERY: a lock that is bright-but-not-washed-out (0.34 << the
    // 0.72 washout line) shows a FULL analysis window with ~zero periodicity —
    // the saturation path never fires, so without this the take sits unsettled
    // forever. Sustained weak acf while unsettled → hand exposure back to auto so
    // the strict dark gate can re-lock. Bounded per placement (never thrashes).
    nonisolated static let weakRelockAcfFloor: Float = 0.2
    nonisolated static let weakRelockAcfStrong: Float = 0.4
    nonisolated static let weakRelockAfterTicks = 120   // ~12 s of accumulated weakness
    nonisolated static let maxWeakRelocks = 2
    // Confidence counts as pulse evidence too (device log 1783410930: the analyzer
    // was reading a real 76–83 bpm at conf 0.6–0.78 while acf sat at ~0 — this
    // device shows periodicity through the peak counter, not always through acf —
    // and relock 2/2 fired anyway, collapsing a WORKING signal to conf 0.03).
    // A lock that is producing confident estimates is not a bad lock.
    nonisolated static let weakRelockConfFloor: Float = 0.35
    nonisolated static let weakRelockConfStrong: Float = 0.6

    /// One 10 Hz step of the weak-periodicity counter. Not diagnostic until the
    /// window is FULL; a settled pulse is never disturbed; weakness means NO pulse
    /// evidence at all (acf AND confidence both low) — genuinely strong evidence on
    /// either channel pays the counter back down twice as fast. Pure → unit-tested.
    nonisolated static func weakTicksStep(current: Int, windowFull: Bool,
                                          acf: Float, confidence: Float, settled: Bool) -> Int {
        guard windowFull, !settled else { return 0 }
        if acf >= weakRelockAcfStrong || confidence >= weakRelockConfStrong {
            return max(0, current - 2)
        }
        if acf < weakRelockAcfFloor && confidence < weakRelockConfFloor { return current + 1 }
        return current
    }

    /// Whether a locked-but-weak exposure should be handed back to auto. Pure.
    nonisolated static func weakLockNeedsResettle(weakTicks: Int, relocksUsed: Int) -> Bool {
        weakTicks >= weakRelockAfterTicks && relocksUsed < maxWeakRelocks
    }

    /// LAST-RESORT RECOVERY once the re-settle budget is EXHAUSTED.
    ///
    /// Device log 2465 (v10.79.349, founder ~10 min session): the budget was spent at
    /// relock 1/2 (t≈145 s) and 2/2 (t≈162 s), and because the finger never left the
    /// lens neither reset path — a new placement (`relockOnLossTicks`, ~3 s off) nor a
    /// fresh capture session — ever fired. The remaining four minutes read `conf=0.00`
    /// with `amp` swollen to 0.15–0.54, `pk=0` and `acf`→0 while `bright`/`R` drifted
    /// upward: a rolling window full of drift, with NO recovery mechanism left at all.
    /// `bio=0` in the visual line for nearly the whole take is that same fact from the
    /// other end — the instrument's premise (the body drives the sound) was dead while
    /// the user held perfectly still.
    ///
    /// The fix deliberately does NOT hand out more exposure re-settles. A re-settle is
    /// expensive and gambles the lock (`unlockExposure` + `setTorch` reconfigure, and it
    /// injects the exposure brightness STEP into the window — this file's history is a
    /// list of regressions from exactly that churn: the phantom-lock oscillation above,
    /// and relock 2/2 collapsing a WORKING signal to conf 0.03). Instead it flushes the
    /// ANALYZER window, which is what the symptom actually points at, costs nothing but
    /// the refill, and cannot destabilise the exposure state machine because it never
    /// touches it. `displayBPM` is held by the publish loop across the refill (it never
    /// advances on bpm=0), so the SHOWN pulse holds instead of snapping to 0 — the same
    /// contract the two existing `resetForRecovery()` call sites rely on.
    ///
    /// 30 s of CONTINUED weakness *after* the budget ran out, self-rate-limited: the
    /// flush zeroes the counter and empties the window, so `weakTicksStep`'s
    /// `windowFull` guard holds it at 0 for the whole refill. At most one flush per
    /// ~30 s + refill while dead, and none at all while the signal is usable.
    nonisolated static let deadWindowFlushAfterTicks = 300   // ~30 s at 10 Hz

    /// Whether an exhausted-budget lock has been dead long enough to flush the analyzer
    /// window. Mutually exclusive with `weakLockNeedsResettle` BY CONSTRUCTION — that one
    /// requires `relocksUsed < maxWeakRelocks`, this one requires the opposite — so the
    /// two recoveries can never fire in the same tick or compete for the counter. Pure.
    nonisolated static func deadWindowNeedsFlush(weakTicks: Int, relocksUsed: Int) -> Bool {
        relocksUsed >= maxWeakRelocks && weakTicks >= deadWindowFlushAfterTicks
    }

    /// A locked scene is washed out (AC pulse swamped) once it drifts too bright or
    /// the red channel clips — trigger a re-settle so it recovers instead of sitting dead.
    nonisolated static func isWashedOut(brightness: Float, red: Float) -> Bool {
        brightness > 0.72 || red > 0.92
    }

    public init() {}

    /// Start the camera, drive the analyzer from captured frames, and publish
    /// confident pulse estimates to the bus. No-op if already running.
    public func start(publishing bus: EngineBus) async {
        guard !isRunning else { return }
        // Claim the running state + a fresh generation token SYNCHRONOUSLY, before the
        // first `await` below. Camera permission + session config is a suspension window of
        // seconds on first run; without this a Start→Stop (or Start→Stop→Start) during that
        // window would let this task resume past the await and re-arm torch/analyzer/
        // publishTask AFTER stop() — resurrecting a stopped camera (stuck torch, bio still
        // publishing) or orphaning a second 10 Hz loop. The generation check after the await
        // makes only the LATEST start() the authoritative owner.
        startGeneration += 1
        let gen = startGeneration
        isRunning = true
        self.bus = bus

        let sampleQueue = self.sampleQueue
        capture.onFrame = { pixelBuffer in
            // Average the center region on the capture queue → 3 Sendable Floats.
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let regionX = width / 4, regionY = height / 4
            let regionW = width / 2, regionH = height / 2
            var totalR: Float = 0, totalG: Float = 0, totalB: Float = 0, count: Float = 0
            for y in stride(from: regionY, to: regionY + regionH, by: 8) {
                let rowPtr = base.advanced(by: y * bytesPerRow)
                for x in stride(from: regionX, to: regionX + regionW, by: 8) {
                    let pixel = rowPtr.advanced(by: x * 4)
                    totalB += Float(pixel.load(fromByteOffset: 0, as: UInt8.self))
                    totalG += Float(pixel.load(fromByteOffset: 1, as: UInt8.self))
                    totalR += Float(pixel.load(fromByteOffset: 2, as: UInt8.self))
                    count += 1
                }
            }
            guard count > 0 else { return }
            let avgR = totalR / count / 255.0
            let avgG = totalG / count / 255.0
            let avgB = totalB / count / 255.0
            // No per-frame actor hop — just enqueue. The 10 Hz publish loop drains
            // and feeds the analyzer on the main actor (timestamp preserves the rate
            // calc). This is what keeps the UI / dropdown menus responsive while bio runs.
            sampleQueue.push(r: avgR, g: avgG, b: avgB, t: ProcessInfo.processInfo.systemUptime)
        }

        // If the camera self-recovers (watchdog restart, full reconfigure, or an
        // interruption ending), drop our lock AND force the device back to auto —
        // an interruption resume keeps the same session, so a stale locked exposure
        // survives it (handleCameraSessionReset does both). The torch is re-armed
        // by CameraCapture itself. Fires on a background queue → hop.
        capture.onSessionReset = { [weak self] in
            Task { @MainActor [weak self] in self?.handleCameraSessionReset() }
        }

        do {
            try await capture.start()
        } catch {
            log.log(.warning, category: .biofeedback, "Camera rPPG failed to start: \(error.localizedDescription)")
            // Only undo state if WE are still the latest start (a newer start/stop that
            // superseded us during the await owns the state now — don't clobber it).
            if gen == startGeneration {
                isRunning = false
                capture.onFrame = nil
                capture.onSessionReset = nil
                // Denied/restricted access is a SYSTEM fact, read fresh (not inferred
                // from the error) — the UI must say "enable it in Settings" instead of
                // coaching finger placement that can never work (UX-1).
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                permissionDenied = (status == .denied || status == .restricted)
            }
            return
        }

        // A stop() or a newer start() ran DURING the await above. stop() and every start()
        // bump `startGeneration`, so if ours is stale we are no longer the owner: the latest
        // start() (or stop's teardown) is authoritative — do not touch the shared
        // torch/analyzer/publishTask. This closes both "stop undone" and the orphan-loop leak.
        guard gen == startGeneration else {
            // One thing a stale task MUST still clean up: its own `capture.start()` above
            // already brought the AVCaptureSession up, and it did so AFTER whatever
            // superseded us. `stop()` cannot have torn that down — it ran while we were
            // parked in `requestAccess`, which is not cancellation-aware — so a bare return
            // leaves the session running forever: privacy indicator lit, watchdog live,
            // battery burning, with nobody consuming frames.
            //
            // `isRunning` decides WHICH kind of supersession this was, and it is the right
            // discriminator because it is claimed synchronously on the main actor before any
            // await: false ⇒ a stop() won, so tear the session down; true ⇒ a NEWER start()
            // won and is the rightful owner, so leave its session alone. Tearing down in that
            // second case is the bug this guard exists to prevent — a cancelled predecessor
            // killing a live successor. (`sessionQueue` is FIFO, so a `stop()` enqueued after
            // a main-actor read of `isRunning == false` can never overtake a later start's
            // `startRunning()`.)
            if !isRunning { capture.stop() }
            return
        }

        // Finger-on-lens PPG needs the back-camera torch to illuminate the
        // fingertip — without it there is no red-channel pulse signal. Driven on
        // the session's own running device for reliability.
        // The camera started — access is provably granted (also covers the
        // first-run flow where the user just tapped Allow on the system prompt).
        permissionDenied = false

        capture.setTorch(true)
        analyzer.startPulseDetection()
        stallTicks = 0
        forcedRecoveries = 0
        healthyTicks = 0
        coldRestarts = 0
        coldCooldownTicks = 0
        recoveringTicks = 0
        recoveryState = .healthy
        EchoelCrashLog.breadcrumb("rPPG: started, torch requested")

        // Exposure is now locked from the publish loop ONLY once the finger is
        // stably covering the lit lens (see the loop below) — NOT on a blind timer.
        // Continuous auto-exposure stays on until then so the AGC adapts to the
        // bright finger-covered scene first; locking against the dim finger-less
        // scene was the device-log root cause of "bpm=0 forever" (R saturated 0.82).

        publishTask = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))   // ~10 Hz: live feel
                guard let self, self.isRunning else { break }
                // Drain the frames the capture queue buffered since the last tick and
                // feed them to the analyzer IN ORDER, on the main actor, with their
                // capture timestamps (so the rate maths stays correct). Replaces the old
                // per-frame `Task { @MainActor }` flood that froze the menus while bio ran.
                let drained = self.sampleQueue.drain()
                for s in drained {
                    self.analyzer.processExtractedRGB(avgR: s.r, avgG: s.g, avgB: s.b, timestamp: s.t)
                }
                // Measured inbound rate (drained-per-100ms-tick × 10 = Hz), EMA-smoothed.
                self.loopTicks += 1
                self.inboundRateEMA = self.inboundRateEMA * 0.9 + Double(drained.count) * 10.0 * 0.1
                // Sample-pipe stall guard (device log 2026-07-02: analyzer output frozen
                // byte-identical for ~13 s — no NEW RGB reached it — while the capture-layer
                // watchdog saw frames and stayed happy). If NO samples arrive for ~6 s while
                // we're running, the RGB path (not just the raw session) has stalled: force a
                // full camera recovery. Cooldown lives in CameraCapture.recoverFromStall().
                if drained.isEmpty {
                    self.healthyTicks = 0
                    self.stallTicks += 1
                    if self.coldCooldownTicks > 0 { self.coldCooldownTicks -= 1 }
                    if self.stallTicks >= 60 {          // ~6 s at 10 Hz
                        self.stallTicks = 0
                        // While iOS HOLDS the session interrupted, both ladders are
                        // futile no-ops that only burn the recovery budget, battery and
                        // heat (device log 1783749556: reason-1 interruption re-fired on
                        // EVERY fresh start — 3 forced recoveries + 8 cold restarts, 0
                        // frames, ~3 min). Wait instead; CameraCapture resumes on
                        // InterruptionEnded or app-became-active, and the banner below
                        // says so honestly. Budget stays intact for REAL stalls.
                        if self.capture.isInterrupted {
                            // No `continue`: fall through to the banner logic below so
                            // the strip honestly shows the interrupted state each tick.
                            EchoelCrashLog.breadcrumb("rPPG: no frames ~6 s but iOS holds the camera (interrupted) — waiting, not restarting")
                        } else if self.forcedRecoveries < Self.maxForcedRecoveries {
                            self.recoveringTicks = 40   // ~4 s banner: "Kamera erholt sich…"
                            self.forcedRecoveries += 1
                            EchoelCrashLog.breadcrumb("rPPG: no new frames ~6 s — forcing camera recovery (\(self.forcedRecoveries)/\(Self.maxForcedRecoveries))")
                            self.capture.recoverFromStall()
                        } else if self.coldCooldownTicks == 0 {
                            // ESCALATION — now UNLIMITED with ~18 s backoff (was one-shot,
                            // then "leaving it to the watchdog"; device log 1783588109:
                            // the single cold restart failed SILENTLY and rPPG stayed
                            // blind ~83 s — the watchdog can't revive a session that never
                            // came back up). The founder's manual Stop→Start heals this
                            // stall class; keep doing the machine version — full stop →
                            // fresh session build (inputs, outputs, torch, exposure) —
                            // until frames actually flow again. Backoff prevents thrash.
                            self.recoveringTicks = 40      // same honest banner as branch A
                            self.coldRestarts += 1
                            self.coldCooldownTicks = 180   // ~18 s between cold restarts
                            EchoelCrashLog.breadcrumb("rPPG: recoveries exhausted — cold camera restart #\(self.coldRestarts)")
                            self.capture.stop()
                            try? await Task.sleep(for: .milliseconds(800))
                            guard self.isRunning, !Task.isCancelled else { break }
                            do {
                                try await self.capture.start()
                            } catch {
                                // Visible, never swallowed: a failed cold START was exactly
                                // the invisible terminal state of the old ladder.
                                EchoelCrashLog.breadcrumb("rPPG: cold restart #\(self.coldRestarts) start failed: \(error.localizedDescription)")
                            }
                            self.capture.setTorch(true)
                            self.handleCameraSessionReset()   // drop stale exposure lock → re-lock on finger
                        }
                    }
                } else {
                    self.stallTicks = 0
                    self.healthyTicks += 1
                    // Refill the recovery budget only after ~3 s of SUSTAINED flow — not on
                    // the first post-recovery trickle (that reset was the "stuck at 1/3" bug).
                    if self.healthyTicks >= 30 {
                        self.forcedRecoveries = 0
                        self.coldRestarts = 0
                        self.coldCooldownTicks = 0
                    }
                }
                // Honest recovery/cooling banner state (low-freq): a fresh restart shows
                // "recovering" for a few seconds; a thermally-throttled device shows "cooling"
                // (the same heat that dims the torch can pause frames). Only assign on CHANGE so
                // the @Observable doesn't notify unless the banner actually flips.
                if self.recoveringTicks > 0 { self.recoveringTicks -= 1 }
                let newRecovery: RPPGRecoveryState
                if self.capture.isInterrupted {
                    // The OS holds the camera — highest-priority truth: no restart
                    // banner theater, tell the user why the pulse is paused.
                    newRecovery = .interrupted
                } else if self.recoveringTicks > 0 {
                    newRecovery = .recovering
                } else if self.loopTicks > 50,
                          self.inboundRateEMA < Self.minMeasurableInboundHz {
                    // Camera delivers a trickle (thermal throttle): frames arrive, but far
                    // too few for the 0.7–4 Hz pulse band — be honest instead of silent.
                    newRecovery = .cooling
                } else {
                    switch ProcessInfo.processInfo.thermalState {
                    case .serious, .critical: newRecovery = .cooling
                    default:                  newRecovery = .healthy
                    }
                }
                if newRecovery != self.recoveryState { self.recoveryState = newRecovery }

                // Live status + waveform every tick so positioning is immediate.
                self.fingerDetected = self.analyzer.isFingerDetected
                self.signalQuality = min(max(self.analyzer.signalQuality, 0), 1)
                self.confidence = min(max(self.analyzer.bpmConfidence, 0), 1)
                self.detectedBPM = self.analyzer.estimatedBPM
                // Autocorrelation strength of the latest window — the corroboration signal that
                // separates a real pulse (strong periodicity) from a peak-counter self-agreeing
                // on a noisy finger. Gate both the display and the settle on it (see trustAutoFloor).
                let autoStrength = self.analyzer.lastAutoStrength
                // Calm display value: advance only on a TRUSTWORTHY reading (confident AND
                // corroborated by real periodicity), else hold — so a poorly-placed finger
                // shows "acquiring" instead of a fantasy number.
                if self.detectedBPM > 0 && Self.pulseTrustworthy(confidence: self.confidence, autoStrength: autoStrength) {
                    var bpm = self.detectedBPM
                    // OCTAVE-FOLD toward the established rate: rPPG often reports 2× (or ½) the
                    // true pulse (founder: "springt ständig auf 196 bpm"). Once a stable value
                    // exists, fold a doubled/halved estimate back so the SHOWN number doesn't
                    // yank between 98 and 196 — physiological continuity, display-only.
                    if self.displayBPM > 0 {
                        if bpm > self.displayBPM * 1.6 { bpm /= 2 }
                        else if bpm < self.displayBPM * 0.6 { bpm *= 2 }
                    }
                    if self.displayBPM == 0 {
                        self.displayBPM = bpm                       // first confident reading: adopt as-is
                    } else {
                        // EMA micro-smoothing, THEN a physiological SLEW cap so the shown pulse
                        // can never JUMP unrealistically (founder: "gemessener Puls … ohne
                        // unrealistische Sprünge"). A real heart rate changes a few bpm/s at most;
                        // anything faster is an rPPG glitch. ≤maxDisplayStep per ~100 ms tick glides
                        // through genuine changes and rejects teleports — a 70→133 octave/glitch
                        // eases over ~seconds instead of snapping.
                        let smoothed = self.displayBPM * 0.6 + bpm * 0.4
                        let step = Swift.max(-Self.maxDisplayStep,
                                             Swift.min(Self.maxDisplayStep, smoothed - self.displayBPM))
                        self.displayBPM += step
                    }
                }
                // SETTLED tracking: the tempo-latch gate. Confident + the calm displayBPM flat
                // (≤settleTolerance) for settleSeconds → the warm-up descent is over. Any move
                // beyond tolerance or a confidence drop restarts the window (and un-settles).
                let nowT = CFAbsoluteTimeGetCurrent()
                if self.displayBPM > 0 && Self.pulseTrustworthy(confidence: self.confidence, autoStrength: autoStrength) {
                    if self.settleRef < 0 || abs(self.displayBPM - self.settleRef) > Self.settleTolerance {
                        self.settleRef = self.displayBPM
                        self.settleSince = nowT
                        self.isSettled = false
                    } else if nowT - self.settleSince >= Self.settleSeconds {
                        self.isSettled = true
                    }
                } else {
                    self.settleRef = -1
                    self.isSettled = false
                }
                self.waveform = self.analyzer.recentWaveform

                // EXPOSURE: lock once the finger has covered the lens for ~1.2 s (so
                // the AGC settled on the bright fingertip), and RE-SETTLE if the lock
                // ever leaves the sensor saturated (DC swamps the pulsatile AC).
                self.manageExposure()
                // Publish a confident pulse to the bus at ~1 Hz (every 10th tick).
                tick += 1
                // Diagnostics into the breadcrumb stream (~every 2 s) so a device
                // log reveals WHY there is no signal: finger off → torch/position;
                // finger on but bpm 0 → exposure/signal; conf < 0.35 → still locking.
                if tick % 20 == 0 {
                    // R/bright disambiguate finger placement; amp/pk/acf disambiguate
                    // WHY a placed finger won't lock: amp≈0 → no pulsatile AC (press
                    // lighter / torch); pk<3 with acf high → rounded waveform (the
                    // autocorrelation seed now covers it); acf low → weak/aperiodic
                    // perfusion. This is the one line that pinpoints the failing stage.
                    // `auto` = the independent autocorrelation BPM. If bpm ≈ auto/2 with a
                    // decent acf, the peak-count rate is HALVED (octave error); if they
                    // agree, the rate is genuine. Diagnoses the halving without a reference.
                    EchoelCrashLog.breadcrumb(String(format:
                        "rPPG: finger=%@ R=%.2f bright=%.2f q=%.2f amp=%.4f pk=%d acf=%.2f auto=%.0f rate=%.1f in=%.1f win=%d bpm=%.0f conf=%.2f",
                        self.fingerDetected ? "yes" : "no",
                        self.analyzer.redChannel, self.analyzer.brightness, self.signalQuality,
                        self.analyzer.lastFilteredAmplitude, self.analyzer.lastPeakCount,
                        self.analyzer.lastAutoStrength, self.analyzer.lastAutoBPM,
                        self.analyzer.lastActualRate, self.inboundRateEMA,
                        self.analyzer.lastWindowSize, self.detectedBPM, self.confidence))
                }
                // TRUTH GATE (2026-07-25). The stall ladder above detects a dead RGB pipe
                // and drives recovery, but it did NOT stop this publish path — and the
                // analyzer keeps returning its LAST estimate when nothing new is fed. So a
                // stalled camera published a FROZEN pulse with a FRESH timestamp on every
                // tick, which defeats `freshBio`/`usableBio` by construction: the music and
                // the visual ran off a dead body for the whole 6 s detect window plus the
                // recovery ladder (up to an 18 s cold-restart backoff), while the UI said
                // "recovering". Publishing nothing is the honest state — consumers then
                // expire the last real frame after `maxAge` and ease to idle ONCE.
                // Gated on the smoothed inbound rate, not on a single empty drain: at the
                // 15 fps capture cap (`CameraCapture.swift:137`) a 100 ms tick carries only
                // ~1.5 samples, so a single empty tick is normal jitter. From a healthy
                // ~15 Hz the EMA needs ln(0.4)/ln(0.9) ≈ 8.7 ticks ≈ 0.9 s to fall through
                // this threshold — that lag IS the intended hysteresis.
                // Startup is safe: `inboundRateEMA` is seeded at 15 (≥ the threshold), so
                // the first ticks publish normally and a frameless warm-up self-clears.
                guard self.inboundRateEMA >= Self.minMeasurableInboundHz else { continue }
                guard tick % 10 == 0, let bus = self.bus else { continue }
                let bpm = self.analyzer.estimatedBPM
                guard Self.shouldPublish(bpm: bpm,
                                         confidence: self.analyzer.bpmConfidence,
                                         autoStrength: autoStrength) else {
                    // Brief dropout: keep the visual + pulse warm by re-emitting the
                    // last good frame (coherence gently decaying — never a snap to 0)
                    // until the grace window expires, so a marginal signal can't
                    // strobe the fullscreen visual bio↔idle. Past the grace the signal
                    // is genuinely gone → stop; the visual then eases to idle ONCE.
                    if let held = self.lastGoodBioFrame,
                       tick - self.lastGoodPublishTick <= Self.bioHoldTicks {
                        self.lastValidCoherence *= 0.9
                        bus.publish(bio: BioSampleFrame(
                            // Carry the last good frame's OWN timestamp — do not re-stamp.
                            // (To be precise: that is the time the good frame was PUBLISHED,
                            // not the RGB capture instant — the sample's capture `t` is
                            // consumed inside the analyzer and never reaches here. Still the
                            // right value: it is the age of the newest real measurement.)
                            // Re-stamping made a held frame indistinguishable from a live
                            // one, so no consumer could apply its own staleness policy.
                            // Carrying it is safe for the warm-visual intent because the
                            // hold window (`bioHoldTicks`, ~4 s) is SHORTER than `freshBio`'s
                            // default 5 s maxAge: the frame stays "fresh" for the whole grace
                            // period and expires by itself the moment the grace ends.
                            // ⚠ Consumers that dedupe on `timestamp` now treat a held
                            // republish as a no-op, so the decaying `lastValidCoherence`
                            // below no longer reaches them. That is deliberate: holding the
                            // last REAL value beats following a synthesized decay.
                            timestamp: held.timestamp,
                            heartRateBPM: held.heartRateBPM,
                            hrvNormalized: held.hrvNormalized,
                            breathRate: 0,
                            breathPhase: held.breathPhase,
                            coherence: self.lastValidCoherence,
                            motionEnergy: 0,
                            source: .cameraPPG,
                            hrvRMSSDms: held.hrvRMSSDms,
                            hrvSDNNms: held.hrvSDNNms,
                            hrvPNN50: held.hrvPNN50))
                    }
                    continue
                }
                let rmssdMs = Float(self.analyzer.rmssd)
                // ONE shared normalization ceiling across all bio sources (was ÷200 here,
                // the outlier — BLE + HealthKit already use the house 100 ms ceiling).
                let hrv = Float(HRVNormalization.normalize(self.analyzer.rmssd))
                // analyzer.rrIntervals are already in milliseconds.
                let rrMs = self.analyzer.rrIntervals
                // Real frequency-domain coherence from the camera RR series — the
                // SAME metric as the BLE path (HRVCoherence), not the signal-quality
                // value this used to mislabel as "coherence". rPPG RR is lower-trust
                // than a chest strap (BioSource.providesTrustedHRV is false for
                // .cameraPPG), so consumers still gate on the source; the field is now
                // at least semantically correct. 0 until enough beats/power.
                let coherence = HRVCoherence.compute(rrMs: rrMs, blend: 1.0)
                // Hold coherence across TRANSIENT invalidity rather than publishing 0
                // (line was `coherence.valid ? … : 0`): a single invalid window
                // otherwise flapped coherence real↔0 at the publish rate, which the
                // visual renders as a brightness shimmer while bio runs. A valid read
                // refreshes the held value; an invalid one decays it gently.
                let cohValue: Float = coherence.valid ? coherence.coherence : self.lastValidCoherence * 0.9
                if coherence.valid { self.lastValidCoherence = coherence.coherence }

                // Respiration from the RR series via RSA (breathing modulates HR).
                // Replay the current RR window through a fresh estimator → the current
                // breath amplitude (drives the ball) + rate. Pure + cheap. Reported
                // only when the respiratory oscillation is clear (confidence gate), so
                // breathRate > 0 signals "measured breath available" to the UI.
                var resp = RespirationEstimator()
                var tAcc = 0.0
                for ms in rrMs where ms > 250 && ms < 2000 {
                    tAcc += ms / 1000.0
                    resp.ingest(heartRate: 60_000.0 / ms, at: tAcc)
                }
                let measuredBreath = resp.confidence >= 0.4
                let frame = BioSampleFrame(
                    timestamp: CFAbsoluteTimeGetCurrent(),
                    heartRateBPM: Float(bpm),
                    hrvNormalized: hrv,
                    breathRate: measuredBreath ? Float(resp.ratePerMinute) : 0,
                    breathPhase: measuredBreath ? Float(resp.amplitude) : 0,
                    coherence: cohValue,
                    motionEnergy: 0,
                    source: .cameraPPG,
                    hrvRMSSDms: rmssdMs,
                    hrvSDNNms: Float(HRVMetrics.sdnn(rrMs: rrMs)),
                    hrvPNN50: Float(HRVMetrics.pnn50(rrMs: rrMs))
                )
                bus.publish(bio: frame)
                // Anchor the hold to this good frame (see lastGoodBioFrame docs).
                self.lastGoodBioFrame = frame
                self.lastGoodPublishTick = tick
            }
        }
    }

    /// 10 Hz exposure state machine. Locks exposure only after the finger has
    /// stably covered the torch-lit lens (so the AGC has adapted to that bright
    /// scene), and re-settles if a lock leaves the sensor saturated — the fix for
    /// the device-log "R=0.82, bpm=0 forever" (exposure was frozen too early,
    /// against the dim finger-less scene, then saturated when the finger arrived).
    private func manageExposure() {
        // While iOS holds the session interrupted, no frames flow — the analyzer
        // values below are FROZEN. Every branch of this machine then acts on a
        // dead stream: device log 1783864199 locked exposure twice and burned the
        // ENTIRE weak-relock budget (1/2 + 2/2) during a held interruption, and
        // one of those blind locks left the resumed camera saturated (R=1.00) for
        // 35 s. Freeze the state machine until frames actually flow again;
        // handleCameraSessionReset() re-arms it cleanly on resume.
        guard !capture.isInterrupted else { return }
        let bright = self.analyzer.brightness
        let red = self.analyzer.redChannel
        // Washout detection (threshold 0.72, was 0.85): a locked scene that drifts to
        // bright 0.6–0.8 (finger lightening / re-grip) is already washed out — the AC
        // pulse is swamped — so recover instead of sitting dead (device log 2026-07-02:
        // stayed "locked" at bright 0.80 with bpm=0). Healthy PPG bright is ~0.1–0.4,
        // well under 0.72, so a good lock is never disturbed.
        let saturating = Self.isWashedOut(brightness: bright, red: red)

        if !exposureLocked {
            // Wait for a stable finger AND a dark-enough scene, THEN lock. The
            // brightness gate stops a lock from capturing a washed/flooded frame
            // (device log 2026-07-02: locked at bright=0.62 → no pulse all session).
            // If the finger is present but the scene is too bright, keep auto-exposure
            // running so the AGC pulls the exposure down before we freeze it.
            // The ceiling is STRICT for the first ~6 s of finger presence (prefer the
            // dark, high-AC lock the good sessions live in), then falls back to the
            // permissive cap so unusual skin/devices still lock eventually.
            fingerPresentTicks = fingerDetected ? (fingerPresentTicks + 1) : 0
            let ceiling = Self.lockBrightnessCeiling(fingerPresentTicks: fingerPresentTicks)
            fingerStableTicks = (Self.canLockNow(fingerDetected: fingerDetected, brightness: bright)
                                 && bright < ceiling)
                ? (fingerStableTicks + 1) : 0
            // Phantom-lock backoff: consecutive quick-failed locks stretch the stable
            // time the next lock must earn (see requiredStableTicks) — so ambient
            // flicker can't re-arm the lock↔unlock oscillation.
            if fingerStableTicks >= Self.requiredStableTicks(base: Self.lockAfterTicks,
                                                             quickFails: quickFailLocks) {
                capture.lockExposure()
                capture.setTorch(true)              // exposure reconfig can drop torch
                exposureLocked = true
                saturatedTicks = 0
                fingerLostTicks = 0
                weakAcfTicks = 0
                lockAgeTicks = 0
                EchoelCrashLog.breadcrumb(String(format:
                    "rPPG: exposure locked on finger (bright=%.2f R=%.2f)", bright, red))
            }
            return
        }
        lockAgeTicks += 1
        // A lock that survives past the phantom window proves a real placement —
        // clear the backoff so a later genuine re-grip locks at the fast base time.
        if lockAgeTicks == Self.quickFailWindowTicks { quickFailLocks = 0 }

        // Locked. If it saturates for a sustained spell, the AC pulse is swamped →
        // hand exposure back to auto so it re-settles, then the loop re-locks.
        if saturating {
            saturatedTicks += 1
            if saturatedTicks >= Self.resettleAfterTicks {
                capture.unlockExposure()
                exposureLocked = false
                lockAgeTicks = 0
                fingerStableTicks = 0
                saturatedTicks = 0
                EchoelCrashLog.breadcrumb(String(format:
                    "rPPG: re-settling exposure — saturated (bright=%.2f R=%.2f)", bright, red))
            }
        } else {
            saturatedTicks = max(0, saturatedTicks - 1)
        }

        // BRIGHT-LOCK RECOVERY (device log 1783401421: locked at bright=0.34 —
        // legal under the old 0.6 cap, far from the 0.72 washout line — and the
        // full window then read acf ≈ 0–0.4 for the entire take; the pulse never
        // settled, so the tempo never body-seeded). Sustained ~zero periodicity
        // on a FULL window while unsettled → hand exposure back to auto so the
        // strict dark gate above re-locks properly. Bounded per placement.
        weakAcfTicks = Self.weakTicksStep(current: weakAcfTicks,
                                          windowFull: analyzer.lastWindowSize >= 140,
                                          acf: Float(analyzer.lastAutoStrength),
                                          confidence: Float(confidence),
                                          settled: isSettled)

        // Budget EXHAUSTED and still dead → flush the analyzer window instead of asking
        // for an exposure re-settle nobody is allowed to have (device log 2465: four
        // minutes of conf=0.00 with the finger on the lens and no recovery left). See the
        // doc block on deadWindowFlushAfterTicks for why this is a window problem, not an
        // exposure problem. Checked BEFORE the re-settle branch purely for readability —
        // the two conditions are mutually exclusive on relocksUsed, so order is moot.
        if Self.deadWindowNeedsFlush(weakTicks: weakAcfTicks, relocksUsed: weakRelocksUsed) {
            // Breadcrumb the state we are flushing BECAUSE of, not the zeroes the flush
            // leaves behind — resetForRecovery() clears lastAutoStrength and the analyzer
            // confidence, so reading them afterwards would log "acf=0.00 conf=0.00" every
            // time and the log could never show WHICH dead state triggered it.
            let note = String(format:
                "rPPG: flushing a dead analysis window — budget spent, still no pulse (bright=%.2f acf=%.2f conf=%.2f)",
                bright, Float(analyzer.lastAutoStrength), Float(confidence))
            weakAcfTicks = 0
            analyzer.resetForRecovery()
            EchoelCrashLog.breadcrumb(note)
        }

        if Self.weakLockNeedsResettle(weakTicks: weakAcfTicks, relocksUsed: weakRelocksUsed) {
            weakRelocksUsed += 1
            capture.unlockExposure()
            exposureLocked = false
            lockAgeTicks = 0
            fingerStableTicks = 0
            fingerPresentTicks = 0   // restart the strict dark window — the point of the re-lock
            saturatedTicks = 0
            weakAcfTicks = 0
            EchoelCrashLog.breadcrumb(String(format:
                "rPPG: re-settling exposure — weak periodicity on a bright lock (bright=%.2f acf=%.2f conf=%.2f, relock %d/%d)",
                bright, Float(analyzer.lastAutoStrength), Float(confidence), weakRelocksUsed, Self.maxWeakRelocks))
            return
        }

        // Finger gone for a while → drop the lock so the next placement re-locks
        // against the new (possibly different) finger pressure/position.
        fingerLostTicks = fingerDetected ? 0 : (fingerLostTicks + 1)
        if fingerLostTicks >= Self.relockOnLossTicks {
            // A lock that died young (finger lost within the phantom window) was almost
            // certainly ambient flicker, not a hand — count it toward the backoff. Note
            // the age includes the ~3 s loss wait, so the window comfortably covers it.
            if lockAgeTicks < Self.quickFailWindowTicks {
                quickFailLocks += 1
            } else {
                quickFailLocks = 0
            }
            capture.unlockExposure()
            exposureLocked = false
            lockAgeTicks = 0
            fingerStableTicks = 0
            saturatedTicks = 0
            fingerLostTicks = 0
            fingerPresentTicks = 0
            weakAcfTicks = 0
            weakRelocksUsed = 0   // a NEW placement earns a fresh re-lock budget
            // Flush the analyzer's rolling window too — the SAME clean-slate the camera
            // session-reset path takes (see handleCameraSessionReset). Dropping the lock
            // without this left the pre-loss SATURATED samples + the exposure-unlock
            // brightness STEP in the window, so the next finger placement re-acquired
            // against poisoned data: amp froze and conf stayed 0.00 for the whole window
            // (device log 1784100xxx: first placement locked to conf 0.90, then after a
            // brief finger-off the pulse never re-locked for ~50 s — amp frozen at 0.2546).
            // With the flush a fresh placement re-acquires from clean, exactly like startup.
            // displayBPM is held by the publish loop (never advances on bpm=0), so the SHOWN
            // pulse holds through re-acquire instead of snapping to 0.
            analyzer.resetForRecovery()
        }
    }

    /// The camera restarted the session under us (stall recovery). The device is
    /// freshly configured with exposure back to auto, so reset our exposure state
    /// machine to re-lock cleanly. Also breadcrumbed so the recovery is visible in a
    /// device log (previously a stall just looked like frozen values).
    private func handleCameraSessionReset() {
        // Actively hand the DEVICE back to continuous auto-exposure — do not
        // assume the reset left it there. An interruption RESUME keeps the same
        // configured session, so a custom/locked exposure survives it; device
        // log 1783864199: a (blind) lock taken during the interruption came back
        // saturated after resume — R=1.00/bright=1.00 for 35 s — and because our
        // model said "not locked", the saturation re-settle branch never ran.
        // Unlocking here is idempotent and costs nothing when already auto.
        capture.unlockExposure()
        exposureLocked = false
        fingerStableTicks = 0
        saturatedTicks = 0
        fingerLostTicks = 0
        fingerPresentTicks = 0
        weakAcfTicks = 0
        weakRelocksUsed = 0   // fresh capture session = fresh re-lock budget
        lockAgeTicks = 0
        quickFailLocks = 0    // fresh session = fresh phantom-backoff state
        stallTicks = 0
        // Flush the analyzer's rolling window so the pulse RE-ACQUIRES from clean, exactly
        // like startup (which locked to conf 0.90 in ~20 s). Without this the post-stall
        // window kept the pre-stall samples + the brightness STEP the exposure re-lock
        // injects, freezing amp=0.3618 / conf=0.00 for the whole window; with the camera
        // re-stalling every few seconds it never flushed and the pulse never came back
        // (device log 1783442844). displayBPM is held by the publish loop (it never advances
        // on bpm=0), so the SHOWN pulse holds through re-acquire instead of dropping to 0.
        analyzer.resetForRecovery()
        // Do NOT reset forcedRecoveries here: every forced recovery fires this very
        // callback ~20 ms later, so zeroing the budget here made each recovery erase
        // its own count — "(1/3)" forever, cold restart unreachable (device log
        // 1783201461: four recoveries all logged 1/3 while the analyzer stayed
        // frozen). The budget refills ONLY on ~3 s of sustained frame flow
        // (healthyTicks in the publish loop) or a full stop().
        EchoelCrashLog.breadcrumb("rPPG: camera session recovered after stall — re-locking exposure")
    }

    public func stop() {
        // Bump the generation so any start() still suspended in its camera-config `await`
        // bails on resume instead of resurrecting the camera we're tearing down here.
        startGeneration += 1
        publishTask?.cancel()
        publishTask = nil
        capture.onSessionReset = nil
        capture.setTorch(false)
        capture.unlockExposure()       // leave the device back in auto for next time
        capture.stop()
        capture.onFrame = nil
        sampleQueue.clear()            // drop any frames buffered but not yet drained
        analyzer.stopPulseDetection()
        isRunning = false
        fingerDetected = false
        signalQuality = 0
        confidence = 0
        detectedBPM = 0
        displayBPM = 0
        isSettled = false          // next take must re-prove a flat pulse before tempo latches
        settleRef = -1
        waveform = []
        exposureLocked = false
        fingerStableTicks = 0
        saturatedTicks = 0
        fingerLostTicks = 0
        // A NEW TAKE EARNS A FRESH RE-LOCK BUDGET. These four were missing here, and that
        // is what closed the founder's own escape hatch in device log 2465: after the two
        // re-settles were spent, tapping stop and starting again came back with the budget
        // still at 2/2 and the weakness counter still loaded, so the fresh take had no
        // recovery either. `start()` resets none of them, and the "fresh capture session"
        // path (handleCameraSessionReset) only runs on a STALL — never on a user stop.
        fingerPresentTicks = 0
        weakAcfTicks = 0
        weakRelocksUsed = 0
        lockAgeTicks = 0
        quickFailLocks = 0
        stallTicks = 0
        forcedRecoveries = 0
        inboundRateEMA = 15      // re-seed at nominal so the next start never false-flags
        loopTicks = 0
        recoveringTicks = 0
        recoveryState = .healthy
    }

}
#endif
