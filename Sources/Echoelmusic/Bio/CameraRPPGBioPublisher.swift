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
    /// Cap so a stalled drain can't grow this without bound (~6 s at the 15 fps the
    /// session is pinned to — `activeVideoMaxFrameDuration`. The "~3 s at 30 fps" here
    /// was wrong about the rate and therefore about the headroom it claims).
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
    /// Lock threshold. It is NO LONGER the bus-publish gate (that is `shouldPublish`, which
    /// uses `pulseTrustworthy` — see 2026-07-27) and no longer the `isLocked` gate either.
    /// What still reads it: the `displayThreshold` doc above, and the test that pins the
    /// low-confidence/high-acf case as sitting below it.
    /// `nonisolated` for the same SE-0434 reason as its three neighbours below: Xcode's
    /// toolchain isolates a `static let` on a `@MainActor` class even when immutable, while
    /// SwiftPM may not — so a nonisolated test reading it compiles on one toolchain and not
    /// the other. Runtime-identical.
    nonisolated static let lockThreshold = 0.35

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
    /// alone, while the display has used `pulseTrustworthy` since the acf work.
    ///
    /// The two gates were INCOMPARABLE, not merely one weaker than the other — the first
    /// version of this comment claimed "strictly WEAKER" and that was wrong in a way worth
    /// spelling out, because it hides half the behaviour change:
    ///   · old-passes / new-rejects: conf 0.62, acf 0.30 — the device-log case below. The
    ///     bus followed a reading the screen refused. This is what the fix removes.
    ///   · old-rejects / new-passes: conf < 0.35 with acf ≥ 0.6 — also real and also
    ///     device-observed (log 1783420026, acf 0.59–0.72 at conf 0.01, a stable 56 bpm).
    ///     The bus used to block a pulse the screen already trusted. The fix OPENS this.
    /// So device verification runs in both directions: watch for more idle, AND watch that
    /// the newly-admitted low-confidence/high-acf band carries sane numbers outward to the
    /// synth, OSC, ADM-OSC and Art-Net.
    ///
    /// The asymmetry meant the screen was held to more evidence than the instrument:
    /// device log 2469 (build 10.79.352) carries
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
    /// SCOPE — this unifies the BAR, not the VALUE. What gets published is the raw
    /// `analyzer.estimatedBPM`; what gets shown is `displayBPM`, which is slew-capped at
    /// `maxDisplayStep` (explicitly display-only). So after a hold the bus jumps to the new
    /// value immediately while the readout walks there over seconds. Same defect class,
    /// smaller and transient — not closed by this function.
    ///
    /// ⛔ This paragraph used to say `displayBPM` was "octave-folded and slew-capped", and
    /// that a raw estimate "the fold would halve is published un-halved". Both halves died
    /// with #185 (2026-07-28): the display-side fold is gone, because it folded against its
    /// own output and could latch the shown pulse at half the real rate forever. Corrected
    /// rather than deleted, because a session reading the old text would go looking for a
    /// second fold that no longer exists.
    ///
    /// Pure → unit-testable, which the inline `guard` it replaces was not. Note what that
    /// does NOT buy: no test asserts that the publish loop actually CALLS this. Reverting
    /// the call site to the old inline guard keeps every test in `CameraRPPGTrustTests`
    /// green. The predicate is pinned; the wiring is not.
    nonisolated static func shouldPublish(bpm: Double, confidence: Double, autoStrength: Double) -> Bool {
        bpm > 0 && pulseTrustworthy(confidence: confidence, autoStrength: autoStrength)
    }

    /// True once a confident pulse is locked — the SAME bar as the display and the bus.
    ///
    /// This used to be `detectedBPM > 0 && confidence >= lockThreshold`, i.e. byte-for-byte
    /// the old publish guard, so "locked" implied "the instrument is being fed". Unifying
    /// only the publish gate broke that implication and left `isLocked` true across the
    /// newly-rejected band (conf 0.62 / acf 0.30 — both device-log-2469 readings): the
    /// header light would go green, `PulseCue.locked` would say "Locked", the confidence bar
    /// would pin to full and the coaching would fall silent (`.locked` is not actionable) —
    /// while nothing reached the bus. That is the same lying control this change set out to
    /// remove, moved one surface over. All three now clear one bar; the band falls through
    /// `acquisitionCue` to `.finding`, which is the honest message.
    public var isLocked: Bool {
        Self.shouldPublish(bpm: detectedBPM,
                           confidence: confidence,
                           autoStrength: analyzer.lastAutoStrength)
    }

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

    /// ENGAGE-side hysteresis on the bus-publish decision (#566, C2). Stepped once per publish
    /// tick — i.e. at 1 Hz, since the publish block sits behind `tick % 10 == 0` — with the
    /// instantaneous `shouldPublish` verdict. The latch is TIME-based, not tick-based, so the
    /// rate it is stepped at does not change the seconds it waits.
    ///
    /// ⚠️ ENGAGE ONLY, DELIBERATELY. The release side stays with `bioHoldTicks` (4 s), and the
    /// reason is a measurement rather than caution: `usableBio()` expires a camera frame at
    /// `freshnessWindow` = 6 s against the frame's OWN timestamp, and the hold below re-emits
    /// the last good frame WITHOUT re-stamping it (the law written at that call site). So the
    /// longest a body reading can survive a dropout is six seconds no matter what any latch
    /// decides, and moving the hold from 4 s to 5 s would buy one second of an already-bounded
    /// window while changing the visual's bio↔idle behaviour, which no test here can verify.
    /// The engage side is the half that is missing outright: without it a SINGLE trustworthy
    /// tick inside a bad stretch opens the bus and produces a 0→1→0 blip.
    private var bioTrust = BioTrustLatch()

    /// #567 (C3) breadcrumb bookkeeping — diagnostics only, nothing reads them to decide.
    /// `lastBreathGateOpen` starts `false` so the FIRST time the gate opens is a transition and
    /// gets logged to the second; `lastBreathLogTick` starts at `Int.min` so the first closed
    /// tick also logs rather than waiting 5 s for a periodic slot. (`tick - Int.min` would
    /// overflow — the comparison below is `>= 50` on a `Int.min` subtraction, so the sentinel is
    /// deliberately the *value* `Int.min / 2`: far enough in the past to fire immediately,
    /// close enough that the subtraction cannot trap.)
    private var lastBreathGateOpen = false
    private var lastBreathLogTick = Int.min / 2
    private var lastValidCoherence: Float = 0

    /// WALL-CLOCK start of the current uninterrupted `.finding` stretch — set when a take
    /// starts and reset forward on every tick whose `placementCue` is NOT `.finding` (and on
    /// every tick the capture session is interrupted). `0` means no take is running.
    ///
    /// ⛔ THE FIRST VERSION OF THIS LINE SAID "reset forward on every TRUSTWORTHY READING",
    /// and the line below said "moves on every trustworthy tick". Both are false, in the
    /// direction that HIDES the feature's main cost: the resetting cases are dominated by
    /// the UNtrustworthy ones (`.coverLens`, `.tooBright`, `.holdStill`, `.pressGently`).
    /// The comment at the reset site had it right, so the file disagreed with itself — the
    /// #416 shape, in prose, inside the commit whose banner is ONE DEFINITION.
    ///
    /// ⚠️ AND THE COST THE WRONG WORDING HID: any momentary blip above the motion-amplitude
    /// line or below the 0.0008 amplitude floor restarts the FULL window. A struggling
    /// contact that flickers `.finding` ↔ `.holdStill` can burn five minutes and never see
    /// the message — in exactly the population `.stalled` was written for. Whether device
    /// log 2490's 97 s were CONTINUOUSLY `.finding` is therefore a load-bearing premise for
    /// the feature firing at all on the take that motivated it, and it is not established.
    ///
    /// ⚠️ ONE field, not a `takeStartedAt` plus a `lastTrustworthyAt`, and the reason is that
    /// two fields would have to agree about which of them wins at the start of a take, when
    /// there has never been a trustworthy reading. "When did the current unlocked stretch
    /// begin" answers both questions with one value and cannot disagree with itself.
    ///
    /// ⚠️ WALL CLOCK, not `frame.timestamp` — #434 paid for this exact confusion one file
    /// over. A frame stamp stands still in precisely the situation a duration is needed
    /// (the pulse-hold republish re-emits `held.timestamp`), so a duration measured on it
    /// reads zero for as long as the thing it is measuring lasts.
    ///
    /// Advanced during a LOCK as well, so losing a lock at t = 200 s starts a fresh 45 s
    /// rather than reading stalled immediately.
    ///
    /// ⚠️ `@ObservationIgnored` ON PURPOSE, and it is not an oversight even though
    /// `acquisitionCue` reads it: this field moves on most ticks, so tracking it would add a
    /// 10 Hz invalidation source to a publisher the freeze law (10.76.41/50) is already
    /// careful about. It does not need to notify — the cue is re-derived from
    /// `confidence`/`detectedBPM`/`fingerDetected`, which ARE tracked and DO churn at 10 Hz,
    /// so every reader re-evaluates on its own. The cost is bounded and named: nothing
    /// invalidates at the instant the 45 s elapses; the message appears on the next tick,
    /// i.e. within ~100 ms.
    @ObservationIgnored private var acquisitionSince: CFAbsoluteTime = 0

    /// WHICH stall it is, LATCHED at the instant the window first elapses. `nil` = the
    /// window has not elapsed (or was reset), which is also what `acquisitionCue` guards on.
    ///
    /// ⭐ A LATCH AND NOT A COMPUTED SPLIT, and this is the correction the #484 review
    /// forced. The first version re-evaluated `conf`/`acf` on EVERY read of
    /// `acquisitionCue`, i.e. ~10 Hz on a leaf that re-renders at that rate. Both inputs sit
    /// right at their thresholds in this band — `CameraAnalyzer.isUncorroboratedRipple`
    /// actively bleeds `bpmConfidence *= 0.9` per peak pass THROUGH the 0.6 line — so a
    /// stuck take flipped the header between two labels and the card between two OPPOSITE
    /// instructions several times a second. Every other classifier in this file uses a
    /// counter or a window (`settleSince`, `saturatedTicks`, `weakAcfTicks`,
    /// `fingerLostTicks`); this one had none.
    ///
    /// ⚠️ Deciding it in the TICK rather than in the cue also keeps it ONE definition: the
    /// split is written once, here, and `acquisitionCue` only reads the answer. A computed
    /// property that re-derived it would be a second copy of a threshold pair the trust gate
    /// already owns (#416).
    @ObservationIgnored private var stallWasRhythmless: Bool?

    /// Time hysteresis over "the contact is washed out" (#569). Reuses `BioTrustLatch` (#566)
    /// rather than a private counter — this file already carries four ad-hoc ones
    /// (`saturatedTicks`, `weakAcfTicks`, `fingerLostTicks`, `settleSince`) and a fifth spelling
    /// of the same idea is how thresholds drift apart.
    ///
    /// ASYMMETRIC ON PURPOSE. 4 s to engage: `placementCue` derives `.tooBright` from
    /// `analyzer.brightness`/`redChannel`, which move per FRAME, so anything shorter puts a
    /// WRAPPING sentence into a reserved slot at the publisher's own rate — the #382 shove with
    /// a faster clock, and the exact reason `warrantsFullHintOnScreen` excluded `.tooBright`.
    /// 3 s to release: the sentence must not blink out the instant a fingertip shifts, and a
    /// user who has just been told to press lighter needs the line to survive long enough to
    /// be read. Together they bound the slot to at most one resize per ~3 s.
    @ObservationIgnored private var brightHintLatch = BioTrustLatch(engageSeconds: 4, releaseSeconds: 3)

    /// Whether the washed-out coaching has been true long enough to spend a wrapping line on.
    ///
    /// ⚠️ TRACKED (no `@ObservationIgnored`) AND WRITTEN ONLY ON A TRANSITION — both halves are
    /// load-bearing. Tracked, because the banner has to appear when this flips and nothing else
    /// in that view is guaranteed to invalidate at that moment. Written only on a change,
    /// because the `@Observable` macro calls `withMutation` on EVERY set regardless of
    /// equality: an unconditional assignment in the 10 Hz tick would add a 10 Hz invalidation
    /// source to a publisher the freeze law (10.76.41/50) already handles carefully — i.e. it
    /// would re-create the menu-freeze this file has been fixed for twice.
    public private(set) var brightHintLatched = false

    /// ⭐ ONE respiration estimator for the whole take (#343). It used to be rebuilt from
    /// scratch on EVERY publish and fed only the newest 10 s analysis window — and that is
    /// not a settling-time nuisance, it is a structural blind spot exactly where this app
    /// aims: at 6 breaths/min (the HRV-resonance rate `BioScienceInfo` cites and
    /// `BreathPacer` paces toward) one window spans ONE breath cycle, so it can contain at
    /// most one upward zero-crossing — and a PERIOD needs two. Simulated over the shipped
    /// constants across all 360 whole-degree starting phases, 10 s of RR reaches the true
    /// 6/min at NO phase (345 read exactly 0; the other 15 read a spurious 7.4, which is
    /// worse than silence), while `confidence` lands at 0.46–0.63 — ABOVE the 0.4 gate
    /// below at every one of them. The publisher therefore reported "breath measured" and
    /// a wrong or zero rate, for the one breathing rate the product is built around.
    ///
    /// ⛔ An earlier version of this comment said "rate 0 at four phases, 0.46–0.50". Both
    /// halves were narrower than the truth and the first one is FALSE as a general claim —
    /// the estimator seeds `smooth`/`prevSmooth` at zero, so a window that starts on a
    /// rising edge manufactures a crossing that is not a breath. Four hand-picked phases
    /// missed that entirely. Accumulate instead and it is measured: 60 s reads 5.7–6.2
    /// across the same sweep at full confidence. (30 s reads 5.2–6.6 — usable, but the
    /// spread is why the guard uses 60 s.)
    ///
    /// Fed incrementally from `analyzer.beatTimes`, which is why that property exists:
    /// windows overlap ~90 % and interval values carry no identity, so "newer than the last
    /// beat I consumed" is the only way to ingest a beat AT MOST once. (Not "exactly once":
    /// the analyzer's peak threshold is window-relative, so a marginal peak can be accepted
    /// at a slightly different sample in a later window and re-enter as a new beat. Rare, and
    /// it costs one extra sample in a filter that already smooths — but the stronger claim
    /// would be false.)
    ///
    /// ⚠️ Making this long-lived is what forced `RespirationEstimator`'s freshness term. Its
    /// `crossingCount` is monotonic, so a per-take estimator would otherwise keep certifying
    /// the last measured rate forever. Read that comment before shortening either lifetime.
    @ObservationIgnored private var respiration = RespirationEstimator()
    /// Absolute time of the newest beat already considered for `respiration`. 0 = none yet.
    @ObservationIgnored private var lastRespirationBeatTime: Double = 0
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
    ///
    /// TWO LAYERS since #484: `placementCue` answers "what is wrong with the contact RIGHT
    /// NOW" from the instantaneous signals, and this property adds the one thing an
    /// instantaneous read cannot know — HOW LONG the answer has been "nothing is wrong and
    /// nothing is locking". Only `.finding` is upgraded, because every other case already
    /// names a correctable blocker and replacing that with a duration message would trade a
    /// specific instruction for a vaguer one.
    public var acquisitionCue: PulseCue {
        let base = placementCue
        // `stallWasRhythmless == nil` means the publish tick has not latched a stall — which
        // covers "no take is running" (both anchors are cleared together in `stop()`) and
        // "the window has not elapsed yet". A cue read from an idle publisher can therefore
        // never claim a stall that no clock was measuring.
        guard base == .finding, let rhythmless = stallWasRhythmless else { return base }
        return .stalled(hasRhythmlessSignal: rhythmless)
    }

    /// Whether a surface with a reserved single-line slot should spend it on `fullHint` rather
    /// than `shortLabel` — the publisher's answer, which is the enum's answer PLUS the one
    /// thing an enum cannot know: how long the case has held (#569).
    ///
    /// `PulseCue.warrantsFullHintOnScreen` stays exactly as it is and keeps owning `.stalled`;
    /// it is a fact about the STRINGS and belongs beside them (#416). What is added here is a
    /// fact about TIME, which is this object's business — the same split `acquisitionCue`
    /// already makes over `placementCue`.
    ///
    /// ⚠️ THE `== .tooBright` TEST IS NOT REDUNDANT. The consumer renders
    /// `acquisitionCue.fullHint`, so the latch and the cue must agree about WHICH sentence is
    /// being spent on a wrapping line. Without it, a latch left standing during the 3 s release
    /// window would authorise a full-height banner for whatever the cue had become — including
    /// `.locked`, whose "Locked" needs no line at all.
    public var cueWarrantsFullHintOnScreen: Bool {
        let cue = acquisitionCue
        if cue.warrantsFullHintOnScreen { return true }
        return brightHintLatched && cue == .tooBright
    }

    /// Clear the washout latch and its published flag together — the pair is only ever reset
    /// as a pair, which is why this is a method and not two lines copied to each site.
    private func resetBrightHint() {
        brightHintLatch.reset()
        if brightHintLatched { brightHintLatched = false }
    }

    /// The instantaneous placement classification — everything `acquisitionCue` knew before
    /// #484 added a clock. Kept separate (and non-public) so the stall clock in the publish
    /// tick can ask "is the contact currently clean" without restating any of these tests:
    /// one definition, and the tick and the UI can never disagree about what `.finding` is.
    private var placementCue: PulseCue {
        // Denied access wins over EVERYTHING — no placement coaching can help,
        // and "Cover camera" for a permission dead end misleads (UX-1).
        if permissionDenied { return .cameraDenied }
        if isLocked { return .locked }
        if !fingerDetected { return .coverLens }
        // Finger is on the lit lens but no lock yet — say WHY, from the live signal.
        //
        // ⭐ THE WASHOUT LINE HAS ONE OWNER, and it is the state machine. This line used to
        // carry its own copy — `brightness > 0.85 || redChannel > 0.92`. The red halves were
        // equal; the brightness halves were not, and the difference ran the wrong way: the
        // COACHING number (0.85) sat ABOVE the line at which this same file calls the frame
        // washed out (0.72) and hands exposure back to auto. Across 0.72…0.85 the machine was
        // re-settling BECAUSE it judged the scene flooded, while the screen said nothing about
        // light at all.
        //
        // ⛔ FOUR THINGS THE FIRST VERSION OF THIS COMMENT CLAIMED THAT ARE NOT TRUE. It is
        // kept as a correction because each one would mislead the next reader in a different
        // direction, and the second is the one that matters for the product.
        //
        // 1. It said this establishes "ONE definition of too bright". It does not. This file
        //    holds THREE brightness lines that each mean "flooded" in their own comment's
        //    words: `strictLockBrightness` 0.28, `maxLockBrightness` 0.6, and `isWashedOut`
        //    0.72. The cue now adopts the LOOSEST. So the contradiction moved rather than
        //    closed: at brightness 0.65 `canLockNow` refuses to lock — the machine has decided
        //    the scene is flooded — and the screen still shows no light cue. That residual band
        //    contains 0.62, the exact device-log value this file cites TWICE as its canonical
        //    failure ("locked at bright=0.62 → no pulse all session"). One definition OF
        //    WASHOUT, of three brightness lines.
        // 2. It said the old messages told the user to "press HARDER". None of the three does.
        //    They are "Hold still — keep your finger steady", "Press gently and hold still" and
        //    "Hold still — finding your pulse…" — the middle one literally asks for LIGHTER
        //    pressure. And the omission was load-bearing: `.holdStill` was left off that list,
        //    yet by this file's own attribution ("finger lightening / re-grip") and the
        //    analyzer's ("hard-press / re-grip"), a re-grip is the most likely cause in the
        //    newly-claimed band — so `.holdStill` was arguably the RIGHT message there and is
        //    now preempted. Whether "Press a little lighter" should own that transient is a
        //    device/wording call, recorded with #304/#410, deliberately not decided here.
        // 3. It said the cue's pair was "written before `isWashedOut` existed". Unprovable:
        //    this clone is shallow (`.git/shallow`), and `git log -S` on either predicate
        //    returns only the graft and this commit. The present state is checkable, the
        //    ordering is not.
        // 4. It said the failed session's bright≈0.30 was "far below BOTH thresholds". That
        //    counted two of the three above — 0.30 is ABOVE `strictLockBrightness` (0.28), the
        //    one line this file says decides whether the take works at all. Still true that
        //    this change does nothing at 0.30; not true that 0.30 is comfortably clear.
        //
        // What survives all four: the coaching must not keep a private copy of a threshold the
        // state machine owns. That is why the call is here.
        if Self.isWashedOut(brightness: analyzer.brightness, red: analyzer.redChannel) {
            return .tooBright
        }
        // Large swings = the finger moving / changing pressure, not a pulse (the analyzer
        // rejects these windows, so it can't lock). Tell the user the real blocker so a
        // motion-heavy contact gets actionable guidance instead of an endless "finding…".
        if CameraAnalyzer.isMotionAmplitude(analyzer.lastFilteredAmplitude) { return .holdStill }
        if analyzer.lastFilteredAmplitude < 0.0008 { return .pressGently }
        return .finding
    }

    /// The analyzer's current window of beat-to-beat intervals, in MILLISECONDS and RAW —
    /// no plausibility band, no ectopic rejection. Read by `AnalysisPoincareView` (#347
    /// Slice 3b), which runs it through `RRIntervalHygiene` itself.
    ///
    /// RAW ON PURPOSE, and it is the one thing to get right about this property: hygiene is
    /// only honest if the consumer can also see how much it REMOVED
    /// (`RRIntervalHygiene.acceptedFraction`), and a pre-filtered array makes that
    /// unknowable. Filtering here would hand every caller a clean-looking series with no way
    /// to tell a perfect contact from a broken one.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS PROPERTY SAID EXACTLY THAT WHILE RETURNING
    /// `analyzer.rrIntervals`, WHICH IS FILTERED TWICE. That array's producing loop `continue`s
    /// past every peak difference outside 0.3…1.5 s and then IQR-rejects the survivors, both
    /// into fresh compacted arrays. So the beats either side of a removal arrived already
    /// adjacent, `RRIntervalHygiene` could not see the gap, and the plot drew a transition that
    /// never happened — the very defect the commit one before this one existed to remove,
    /// reintroduced one layer upstream by a doc comment that asserted the opposite.
    /// `RRIntervalHygiene`'s own header had flagged this file since July ("Do NOT read the
    /// camera path as the good example … Its own slice"). Mechanism plausible, justification
    /// false — this repo's named failure mode, in the sentence that told the next reader not to
    /// worry about it. It now returns `rawIntervalsMs`, which is what the paragraph claims.
    ///
    /// ⚠️ HIGH-FREQUENCY READ — the freeze law (10.76.50). `CameraAnalyzer.rrIntervals` is
    /// observable and changes on every accepted beat, so this must only ever be read inside a
    /// LEAF view. Reading it in `EchoelStudioView`/`WorkspaceView` — both of which already
    /// hold this publisher in `@Environment` — would register the whole surface as an
    /// observer and tear down any open `.menu` Picker on every heartbeat.
    ///
    /// (The strap has no equivalent yet: `PolarH10BioPublisher.rrIntervals` is
    /// `@ObservationIgnored` and appended per beat, so exposing it the same way would notify
    /// nothing. See `AnalysisPoincareView`'s header for why that is a slice and not a
    /// one-liner.)
    public var rrWindowMs: [Double] { analyzer.rawIntervalsMs }

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
    /// contract every other `resetForRecovery()` call site relies on. (This said "the two
    /// existing" call sites; with this one there are three, and the count is written out at
    /// the `respiration.reset()` comment. Left as a relative statement so it cannot go stale
    /// a second time.)
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
    ///
    /// TWO CONSUMERS SINCE #416, and the second one is user-facing: `acquisitionCue` asks
    /// this the same question to decide `PulseCue.tooBright`. That is deliberate — one
    /// definition of WASHOUT for the recovery and for the sentence on screen, so they cannot
    /// say opposite things again (they did: this line is 0.72, the cue carried its own 0.85).
    /// ⛔ The first version of this sentence had that backwards — "0.85 here vs 0.72 there" —
    /// on the doc comment whose one job is to say which number lives where.
    ///
    /// NOT the only brightness line in this file: `strictLockBrightness` (0.28) and
    /// `maxLockBrightness` (0.6) also decide "flooded", and the cue adopts the loosest of the
    /// three. Do not read this as the single source of that judgement — read the ⛔ block at
    /// `acquisitionCue` for the band that still has no cue.
    ///
    /// The cost of the second consumer: moving these numbers now moves what the player is
    /// TOLD, not only what the exposure does. `Tests/CISmoke/OneDefinitionOfTooBrightTests.swift`
    /// pins both halves.
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
        // Arm the stall clock (#484) synchronously with `isRunning`, so it can never be
        // zero — i.e. "no take" — while a take is running. Its VALUE here barely matters:
        // the publish tick resets it on every tick whose cue is not `.finding`, and before
        // the first frame arrives the cue is `.coverLens`. What matters is that it is
        // non-zero, because that is what `acquisitionCue` guards on.
        acquisitionSince = CFAbsoluteTimeGetCurrent()
        self.bus = bus

        let sampleQueue = self.sampleQueue
        capture.setOnFrame { pixelBuffer in
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
        capture.setOnSessionReset { [weak self] in
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
                // Undo the stall clock armed above, in the SAME branch that undoes
                // `isRunning` — otherwise an idle publisher carries a non-zero anchor, and
                // `acquisitionSince`'s own doc says 0 means "no take is running". The latch
                // goes with it: the two are only ever cleared as a pair (#454's law, one
                // field over — a per-take anchor a failed start forgets is a previous take's
                // number, and here it would be a take that never began).
                acquisitionSince = 0
                stallWasRhythmless = nil
                resetBrightHint()
                capture.setOnFrame(nil)
                capture.setOnSessionReset(nil)
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
                    let bpm = self.detectedBPM
                    // ⛔ A SECOND octave-fold used to sit here, folding against `displayBPM`.
                    // Deleted 2026-07-28 (#185) because it could not release once it engaged.
                    //
                    // It read: if bpm > displayBPM * 1.6 { bpm /= 2 } else if < 0.6 { bpm *= 2 }
                    // — and `displayBPM` is not an independent reference, it is the value the
                    // very next lines move TOWARD the folded number. So the recurrence is
                    // D ← D + slew(EMA(D, fold(R, D)) − D), whose fixed point for a genuine
                    // rate R is D = R/2: at D = R/2 the trigger asks whether R > 1.6·(R/2),
                    // i.e. whether R > 0.8·R, which is TRUE FOR EVERY R. The fold therefore
                    // re-arms itself on every tick and the shown pulse stays halved forever.
                    // A real 105 bpm settles at 52.5 and never comes back — and because
                    // `displayBPM` feeds the settle gate below, the latched take tempo is
                    // halved with it.
                    //
                    // Nothing is lost by removing it: the harmonic fold the founder actually
                    // asked for ("springt ständig auf 196 bpm") already happened upstream in
                    // `CameraAnalyzer.stabilisedBPM`, against the RUNNING ESTIMATE rather than
                    // the display, with plausibility bounds (fold only if the result stays in
                    // 40…200) and an autocorrelation octave anchor — none of which this copy
                    // had. And a 2× glitch that slips through is already handled below: the
                    // EMA plus the `maxDisplayStep` slew cap eases through it instead of
                    // yanking. Do not reintroduce a fold that reads its own output.
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
                // THE STALL CLOCK (#484) measures uninterrupted time in `.finding` — a
                // placed, dark-enough, steady, firm-enough contact that is producing
                // nothing. Anything else resets it, which is stated ONCE, here, by asking
                // the same classification the screen shows rather than re-testing brightness
                // / motion / amplitude / lock. Consequences that fall out for free:
                //   · a lock advances it (`.locked` ≠ `.finding`), so losing a lock starts a
                //     fresh window instead of reading stalled the same second;
                //   · the permission dialog and the pre-contact wait do not count, because
                //     the cue is `.cameraDenied` / `.coverLens` there — a user who took a
                //     minute to answer the dialog does not meet "still no pulse" on contact;
                //   · a user who spends a minute fighting `.tooBright` and finally achieves
                //     a clean contact starts their 45 s from THAT moment, which is the only
                //     honest reading of "a good contact has produced nothing for 45 s".
                //
                // ⛔ `capture.isInterrupted` IS THE ONE CASE THAT DID NOT FALL OUT FOR FREE,
                // and the first version of this line missed it. Nothing stops this publisher
                // on `scenePhase`; when iOS holds the session the stall branch deliberately
                // does nothing (breadcrumb only, no analyzer reset), and `isFingerDetected`
                // only changes when frames are PROCESSED — so every input to `placementCue`
                // freezes at its last value. A take frozen in `.finding` while the user
                // takes a call or opens Control Centre accrued the ENTIRE interruption into
                // the window, and came back reading "still nothing to read — try another
                // finger" for a gap iOS caused. That is the same "blame the body for a
                // system fact" this case exists to remove, one layer down. The suppressing
                // information is computed in this same tick, ~100 lines above.
                if self.placementCue != .finding || self.capture.isInterrupted {
                    self.acquisitionSince = nowT
                    self.stallWasRhythmless = nil
                } else if self.stallWasRhythmless == nil, self.acquisitionSince > 0,
                          nowT - self.acquisitionSince >= PulseCue.stalledAfterSeconds {
                    // LATCHED ONCE, here — see `stallWasRhythmless`. At least one channel
                    // carrying something means "the lens has a signal and it is the wrong
                    // shape" (re-place the finger); neither carrying anything means the
                    // reading is absent, not misshapen (another finger / warm the hand).
                    // Asked from the SAME two constants the trust gate uses, so a retune of
                    // either cannot leave this classification behind (#416).
                    //
                    // ⛔ `||`, NOT `&&`. The first version tested `conf >= display && acf <
                    // trust`, making the FALSE branch a catch-all that swept up conf 0.5 /
                    // acf 0.5 — genuine corroborated periodicity that merely had not cleared
                    // the strong-only clause, i.e. exactly what `strongAutoFloor` exists
                    // for — and told those users to warm their hands.
                    self.stallWasRhythmless = self.confidence >= Self.displayThreshold
                        || self.analyzer.lastAutoStrength >= Self.trustAutoFloor
                }

                // THE WASHOUT LATCH (#569), driven from the SAME `placementCue` the stall
                // clock above asks and the screen shows — one classification, three readers,
                // so a retune of `isWashedOut` cannot leave this behind (#416). `nowT` rather
                // than a fresh clock read for the same reason.
                let brightNow = self.brightHintLatch.step(trustworthy: self.placementCue == .tooBright,
                                                          now: nowT)
                // Only on a CHANGE — see `brightHintLatched`. An unconditional set here is a
                // 10 Hz invalidation of every observer of this publisher.
                if brightNow != self.brightHintLatched { self.brightHintLatched = brightNow }

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
                    // `cue` = the label the SCREEN is showing right now (#484). Without it a
                    // device log cannot answer "was this take continuously `.finding`, and
                    // did `.stalled` ever fire" — the exact question log 2490 left open and
                    // that `stalledAfterSeconds`' own doc had to answer by INFERENCE from
                    // amp/bright/finger. One argument; it makes the next log decisive.
                    EchoelCrashLog.breadcrumb(String(format:
                        "rPPG: finger=%@ R=%.2f bright=%.2f q=%.2f amp=%.4f pk=%d acf=%.2f auto=%.0f rate=%.1f in=%.1f win=%d bpm=%.0f conf=%.2f cue=%@",
                        self.fingerDetected ? "yes" : "no",
                        self.analyzer.redChannel, self.analyzer.brightness, self.signalQuality,
                        self.analyzer.lastFilteredAmplitude, self.analyzer.lastPeakCount,
                        self.analyzer.lastAutoStrength, self.analyzer.lastAutoBPM,
                        self.analyzer.lastActualRate, self.inboundRateEMA,
                        self.analyzer.lastWindowSize, self.detectedBPM, self.confidence,
                        self.acquisitionCue.shortLabel))
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
                // All three evidence values read HERE, not reused from the display block
                // above: `manageExposure()` runs in between and can call
                // `analyzer.resetForRecovery()`, which zeroes estimatedBPM, bpmConfidence
                // AND lastAutoStrength together. Reusing the earlier `autoStrength` local
                // would compare a stale-high periodicity against a fresh-zero confidence.
                // Harmless today only because the same flush zeroes `bpm` and the `bpm > 0`
                // conjunct short-circuits — a stale `acf >= strongAutoFloor` satisfies
                // `pulseTrustworthy` on its own, so anyone who later relaxes `bpm > 0` or
                // makes the flush preserve the last estimate would silently reopen it.
                // #566 (C2): the instantaneous verdict, then the ENGAGE-side latch. Both must
                // hold to publish a LIVE frame — `trustNow` because a dip must still fall
                // through to the hold branch, and `trusted` because a single good tick inside
                // a bad stretch is exactly the 0→1→0 blip this cycle removes. The latch can
                // only ever make this gate MORE conservative: it never publishes something
                // `shouldPublish` rejected.
                let trustNow = Self.shouldPublish(bpm: bpm,
                                                  confidence: self.analyzer.bpmConfidence,
                                                  autoStrength: self.analyzer.lastAutoStrength)
                let trusted = self.bioTrust.step(trustworthy: trustNow,
                                                 now: CFAbsoluteTimeGetCurrent())
                guard trustNow, trusted else {
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
                // ONE estimator per take, fed each beat exactly once (#343 — see the
                // `respiration` property for why replaying a single 10 s window could not
                // measure resonance breathing at all). Reported only when the respiratory
                // oscillation is clear AND a period was actually measured — see the two-part
                // gate below, which this line described as "the confidence gate" for one
                // commit after it stopped being one — so breathRate > 0 signals "measured
                // breath available" to the UI.
                //
                // The count check is not defensive noise: these two arrays are produced
                // together and are 1:1 by construction, and indexing on that assumption is
                // exactly the kind of thing a later edit on one side breaks silently. If
                // they ever diverge, skipping the ingest keeps the LAST good estimate
                // rather than crashing or feeding garbage into long-lived state.
                let beatTimes = self.analyzer.beatTimes
                if beatTimes.count == rrMs.count {
                    for (i, t) in beatTimes.enumerated() where t > self.lastRespirationBeatTime {
                        // Cursor advances on CONSIDERATION, not on acceptance. Otherwise a
                        // beat rejected below is re-examined on every later publish forever.
                        self.lastRespirationBeatTime = t
                        let ms = rrMs[i]
                        // Belt-and-braces only: `CameraAnalyzer` already accepts just
                        // 300…1500 ms, so this cannot fire today. It stays as the boundary
                        // this long-lived filter is willing to be fed, independent of an
                        // upstream band that is free to widen.
                        guard ms > 250, ms < 2000 else { continue }
                        self.respiration.ingest(heartRate: 60_000.0 / ms, at: t)
                    }
                }
                // Age BEFORE reading. The estimator's staleness terms only run inside
                // `ingest`, so without this a take whose beat supply dries up — `CameraAnalyzer`
                // returns early on fewer than three peaks while `fallbackBPM` keeps the pulse
                // alive, so this loop still publishes — would freeze `confidence` at whatever
                // it last earned. Same clock as the beats (`systemUptime`, see the frame sink).
                self.respiration.age(to: ProcessInfo.processInfo.systemUptime)
                let resp = self.respiration
                // BOTH halves, and the second one is not redundant. `confidence` bounds the
                // claim about the SWING; it says nothing about whether a period was ever
                // measured. With zero crossings and a healthy envelope the expression is
                // `0.5 * envConf`, which clears 0.4 — the original #343 symptom, "breath
                // measured: yes, rate: zero". `breathRate` was harmless there (0 either way),
                // but `breathPhase` published `resp.amplitude`: a real number carrying no
                // measured period, straight into `BreathArp.direction` and `BioComposer`'s
                // inhale bias. A rate of zero is not a measurement, so it is not published.
                let measuredBreath = resp.confidence >= 0.4 && resp.ratePerMinute > 0
                // #567 (C3): INSTRUMENT, DO NOT TUNE. The 2026-08-12 device log shows this gate
                // never opening while signal quality was nominally high, and the founder's C3
                // note says plainly why nothing is being changed here yet: "changing a threshold
                // blind is how the 2026-08-12 confusion happened". This line is the evidence
                // that lets C3b pick ONE of its three candidates instead of guessing.
                //
                // `envConf` is the discriminator and the reason `RespirationEstimator` grew a
                // diagnostic mirror: `confidence` is envelope × count-with-envelope-veto, so a
                // low value means either "no respiratory swing reached the sensor" (exposure
                // drift / contact — candidates a and b) or "the swing is there, no period
                // measured yet" (candidate c, the 0.4 gate itself). One number cannot say which.
                //
                // ⚠️ AND THE BLIND SPOT IS PART OF THE INSTRUMENT, so it is written down rather
                // than discovered later: this line sits INSIDE the publish path, past
                // `guard trustNow, trusted`. During a pulse dropout there is no breath line at
                // all — the ABSENCE of a line means the pulse gate was closed, not that breath
                // was fine. It is not hoisted above the gate because the values it prints are
                // only final after `respiration.age(to:)` two dozen lines up, and calling that
                // earlier would age the estimator more often: a behaviour change, which this
                // cycle is explicitly not allowed to make.
                //
                // RATE: one line per 5 s, plus one immediately on every gate transition. At the
                // 1 Hz publish tick a per-tick line would be ~180 entries per 3-minute session
                // in a file the founder also reads for launch and crash triage; a transition is
                // the event worth catching to the second, and between transitions 0,2 Hz still
                // gives ~10 samples per breath cycle at the 6/min the founder will be breathing.
                if measuredBreath != self.lastBreathGateOpen || tick - self.lastBreathLogTick >= 50 {
                    self.lastBreathGateOpen = measuredBreath
                    self.lastBreathLogTick = tick
                    // Hoisted and pre-typed, not a multi-term expression inside the literal:
                    // #287 turned the blocking gate red with exactly that shape, and this file
                    // is on the 100 ms loop where a slow type-check is worst.
                    let rateText = String(format: "%.1f", resp.ratePerMinute)
                    let ampText = String(format: "%.3f", resp.amplitude)
                    let envText = String(format: "%.3f", resp.lastEnvConf)
                    let confText = String(format: "%.3f", resp.confidence)
                    let gateText = measuredBreath ? "open" : "closed"
                    EchoelCrashLog.breadcrumb(
                        "breath: rate=\(rateText) amp=\(ampText) envConf=\(envText) "
                        + "conf=\(confText) gate=\(gateText)")
                }
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
                    // SDNN pools FLAT. "A spread has no adjacency requirement" is true and is
                    // NOT the load-bearing reason — it explains why segmenting buys nothing,
                    // not why segmenting would cost. The cost is that `sdnn(segments:)` also
                    // carries the ISOLATED-beat exclusion (the compensatory-pause case), and on
                    // an rPPG take with bad contact almost every run is length 1: measured on
                    // the guard's fixture, `sdnn(rrMs:)` reads 50.0 ms where `sdnn(segments:)`
                    // reads 0.0. Publishing 0 for a take that HAS real intervals is worse than
                    // the artifact it would remove, and whether the strap's exclusion suits the
                    // camera's gap structure is unmeasured. #268's lesson: do not copy a
                    // judgment across because the call sites look symmetric.
                    //
                    // ⚠️ THE PRICE, named rather than left for the next reader to discover:
                    // `PolarH10BioPublisher` publishes `sdnn(segments:)` into the SAME field and
                    // the SAME OSC address (`/echoelmusic/bio/heart/sdnn`). Since #425 made
                    // RMSSD and pNN50 agree across the two sources, SDNN is the ONLY remaining
                    // definitional split, so an integrator switching camera→strap sees a step in
                    // it that no body produced. Registered, not fixed here — closing it is a
                    // measurement (does the exclusion suit rPPG gaps?), not an edit.
                    //
                    // ⚠️ AND #459 MADE THIS LINE'S INPUT DIVERGE FROM ITS NEIGHBOUR'S, which is
                    // worth naming because the divergence is now invisible. SDNN reads the LOCAL
                    // `rrMs` snapshot; pNN50 one field down reads `analyzer.rrSegments`. They are
                    // the same beats today only because `rrMs` IS `analyzer.rrIntervals` and the
                    // runs were derived from it in the same tick. Change `rrMs` to anything else
                    // — `rawIntervalsMs`, a hygiene pass — and SDNN silently describes a
                    // different set of beats than pNN50 and RMSSD, in the same frame. That is the
                    // exact class #459 removed one layer up, re-entering through the back door.
                    // `testSDNNDeliberatelyStaysFlat` pins the FORM (`sdnn(rrMs:`), not the
                    // argument, so nothing goes red if it happens.
                    hrvSDNNms: Float(HRVMetrics.sdnn(rrMs: rrMs)),
                    // pNN50 DOES read consecutive pairs, so it gets the same treatment as
                    // RMSSD one layer up: pooled only within runs of genuinely adjacent
                    // beats. `rrIntervals` is twice-compacted (see `RRAdjacency`), so a flat
                    // walk counts a difference across a dropped beat — and a cross-gap
                    // difference is exactly the kind that clears the 50 ms threshold, which is
                    // why the relative error here is larger than on RMSSD.
                    //
                    // ⭐ READ, NOT RE-DERIVED (#459). This used to call
                    // `RRAdjacency.segments(intervalsMs: rrMs, endTimesSeconds: beatTimes)`
                    // itself, next to the analyzer doing the identical call for RMSSD — the
                    // same decision written out twice, from the same two arrays, with the
                    // argument pair copied by hand. The cost was never the arithmetic (O(30),
                    // ~1 Hz); it was that an edit to either copy would have left RMSSD and
                    // pNN50 disagreeing about which beats are adjacent, in the same frame,
                    // and making those two agree is the whole point of #425.
                    hrvPNN50: Float(HRVMetrics.pnn50(segments: self.analyzer.rrSegments))
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
        capture.setOnSessionReset(nil)
        // Detach the frame sink BEFORE tearing the session down, so the analyzer stops
        // being fed the moment we decide to stop rather than whenever `stop()`'s async
        // teardown happens to land. NOTE what this ordering is and is not: it is hygiene,
        // NOT the safety guarantee. `CameraCapture.stop()` returns immediately (the work
        // is on `sessionQueue`), so frames can still be in flight either way — what makes
        // that safe is `LockedBox` (#213), not this line. Reading the order as the fix is
        // exactly the mistake the first draft of that fix made.
        capture.setOnFrame(nil)
        capture.setTorch(false)
        capture.unlockExposure()       // leave the device back in auto for next time
        capture.stop()
        sampleQueue.clear()            // drop any frames buffered but not yet drained
        analyzer.stopPulseDetection()
        // A new take gets a new estimator: the last take's baseline, envelope and cycle
        // count say nothing about this one.
        //
        // ⛔ The first version of this comment justified it with a stale CURSOR ("the clock
        // behind `beatTimes` does not necessarily continue across a camera teardown"). That
        // is false and the reviewer was right to call it: the clock is
        // `ProcessInfo.processInfo.systemUptime` (see the frame sink above), monotonic since
        // boot and entirely indifferent to an `AVCaptureSession` teardown. The named failure
        // mode cannot happen. The reset is still correct — the reason was not. Resetting the
        // cursor alongside is then hygiene, not a fix: it must never be NEWER than the
        // estimator's state, or the first beats of the next take would be skipped.
        //
        // Deliberately NOT reset on any of the THREE `analyzer.resetForRecovery()` sites —
        // two in `manageExposure()`, guarded by `deadWindowNeedsFlush` and by
        // `fingerLostTicks >= relockOnLossTicks`, plus the stall recovery in
        // `handleCameraSessionReset()`.
        //
        // ⛔ FOURTH ATTEMPT AT THIS ONE SENTENCE, and the failure mode is worth more than the
        // fact. Round 1 named only the third site. Round 2 described the other two in prose
        // ("a weak-signal re-lock and a finger-off/re-placement flush"). Round 3 replaced the
        // prose with guard NAMES, on the theory that an identifier cannot drift — and named
        // `weakLockNeedsResettle`, which is not a reset site at all: its branch unlocks the
        // exposure and returns without touching the analyzer. The SEMANTICS were right every
        // time (the second flush really is the finger-off/re-placement one); only the label
        // was wrong, which is the hardest version to notice, because the sentence around it
        // reads true. An identifier is only more reliable than prose if someone checks that it
        // is the identifier on the guard — `grep -n "resetForRecovery" ` shows the three call
        // sites and the `if` directly above each one settles it in ten seconds.
        //
        // Naming them matters because the second one is where the obvious justification does
        // NOT hold: at a re-placement the finger may have been off the lens entirely, so "the
        // person is still breathing" is an assumption about the body, not about the signal.
        // (Not the full set of beat-supply interruptions either: `CameraAnalyzer` clears both
        // arrays on a true lock loss without going through `resetForRecovery`.)
        //
        // The reason it is still right is not that assumption but the estimator's own ageing:
        // timestamps only move forward, and its freshness term plus the envelope veto let
        // `confidence` fall through the publisher gate below when the gap produced no real
        // cycle — whether the trace went flat or merely noisy. Resetting instead would
        // re-create #343 once per recovery, and #303 measured those 12–13 s apart on a bad
        // contact. What does NOT cover the gap is the estimator's `dt >= 5` guard: it skips
        // one filter step and ages nothing.
        respiration.reset()
        lastRespirationBeatTime = 0
        // THE HOLD ANCHORS ARE PER-TAKE TOO, and these three were missing here — the same
        // omission the re-lock block further down already records for four other fields
        // (device log 2465). `tick` is a LOCAL of `publishTask`, so a new take restarts it
        // at 0 while `lastGoodPublishTick` still carried the previous take's count: `tick -
        // lastGoodPublishTick` was hugely NEGATIVE, hence `<= bioHoldTicks`, hence the hold
        // branch re-published the PREVIOUS take's frame for the whole re-acquisition window
        // (#415 measured ~19 s). This method clears twenty-five OTHER per-take fields; these
        // three were simply left out.
        //
        // ⚠️ NOT "from the first tick", which is what the first version of this block wrote.
        // The publish path sits behind `tick % 10 == 0` AND behind the inbound-rate truth
        // gate (`inboundRateEMA >= minMeasurableInboundHz`), so the earliest republish is
        // `tick == 10`, about 1 s in — and a frameless first second decays the re-seeded EMA
        // to 15·0.9^10 ≈ 5.2, under the 6.0 threshold, skipping even that one.
        //
        // ⭐ THE HALF NOTHING DOWNSTREAM CAN MASK is `lastValidCoherence` on the SUCCESS
        // path. ⛔ The first version of this block said the field "is not on the hold path at
        // all" — false, and twenty lines above the code that disproves it: the hold branch
        // both decays it (`lastValidCoherence *= 0.9`) and publishes it. What is not on the
        // hold path is the SUCCESS-path fallback `coherence.valid ? … : lastValidCoherence *
        // 0.9`, whose write-back runs ONLY when valid — so while coherence is invalid every
        // genuinely live frame, with a genuinely new timestamp, carries a number from the
        // PREVIOUS take. No freshness gate and no timestamp dedupe can catch that; the frame
        // really is fresh, only that one field belongs elsewhere. The comment above that line
        // states the intent it violates — "hold coherence across TRANSIENT invalidity" — and
        // a stop/start is not transient.
        //
        // ⛔ AND "scaled once" WAS WRONG BY ~8×, because the two halves are not independent:
        // `lastValidCoherence > 0` requires a valid success publish, and that same path also
        // sets `lastGoodBioFrame`, so half 1's hold branch fires on every publish tick of the
        // new take and decays the field by 0.9 each time. At the ~19 s this block itself
        // cites that is `0.9^19 ≈ 0.135`, then scaled once more on the first live frame —
        // ≈12 % of the old value, not 90 %. What survives of the original wording is the part
        // that matters: once the hold stops firing nothing decays it further, so it is a
        // stale CONSTANT rather than a decay.
        //
        // ⛔ AND IT IS FAR LESS REACHABLE THAN THE FIRST VERSION CLAIMED, which said "at the
        // start of a take there is not yet enough RR". `HRVCoherence.minIntervals` is 16 and
        // the camera does not ACCUMULATE its RR series — `CameraAnalyzer` rebuilds it whole
        // from a fixed 10 s peak window, so 16 intervals needs ≥17 clean peaks in 10 s, i.e.
        // a sustained ≳102 bpm. `OSCSender`'s header already records this ("on the CAMERA it
        // may never be reached"). So: at any resting pulse `lastValidCoherence` stays 0 for
        // the whole process and this half is VACUOUS — and when an exertion take does write
        // it, the defect lasts the WHOLE next take rather than an acquisition window, because
        // the field never becomes valid again at rest. Both directions were wrong at once.
        //
        // ⚠️ THE TWO ANCHORS MUST BE CLEARED TOGETHER, and that is not tidiness. `Int.min`
        // is a sentinel inside a SUBTRACTION: `tick - Int.min` traps on overflow. The only
        // thing that has ever prevented it is the `if let held` short-circuit in front of
        // it — cold start pairs `nil` with `Int.min`, so the subtraction is unreachable.
        // Restoring exactly that pair is why this is two lines and not one.
        lastGoodBioFrame = nil
        lastGoodPublishTick = Int.min
        // #566: the trust latch is a per-take anchor too, and carrying it across a session
        // boundary is the same defect as carrying the held frame — an engaged latch would
        // assert trust in a body the instrument has stopped looking at, and the next take's
        // first trustworthy tick would publish immediately instead of earning its three
        // seconds. Cleared with its two neighbours, for their reason.
        bioTrust.reset()
        lastValidCoherence = 0
        // #454's law, applied to the field #484 adds: a per-take anchor that stop() forgets
        // is a previous take's number read as this one's. Zero — not "now" — because zero is
        // this field's "no take is running" sentinel, and `acquisitionCue` guards on it; a
        // wall-clock value here would let an IDLE publisher accumulate a 45 s stall and then
        // report one the moment the next take places a finger.
        acquisitionSince = 0
        stallWasRhythmless = nil
        // Same law, one field further (#454): a latch that `stop()` forgets is a PREVIOUS
        // take's washout, and it would authorise a wrapping banner the moment the next take's
        // cue happened to be `.tooBright` — before this take had measured anything.
        resetBrightHint()
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
