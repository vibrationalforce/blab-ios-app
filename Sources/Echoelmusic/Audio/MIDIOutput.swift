//
//  MIDIOutput.swift
//  Echoelmusic — live MIDI / MPE OUT (the DAW handoff)
//
//  The counterpart to MIDIInput: Echoel publishes its body-generated performance
//  as a CoreMIDI VIRTUAL SOURCE named "Echoelmusic". Any host on the device or
//  network (Logic, Ableton via a Mac network session, AUM, Drambo, hardware via
//  a class-compliant interface) can subscribe to it and record/route the exact
//  notes you hear — the melody the body composes plays your DAW in real time.
//
//  Two modes:
//   • Standard MIDI 1.0 — every note on channel 1. Universal, record-anywhere.
//   • MPE — notes are spread across member channels 2…16 (lower zone, master
//     channel 1) so a receiver can treat each note independently. On enable we
//     emit the MPE Configuration RPN so the host auto-configures its zone. This
//     is the open-standard, "multidimensional" output path (per-note expression
//     streaming — pitch bend / CC74 from the live body — is the documented
//     follow-up; the channel structure here is already valid MPE).
//
//  NOT audio-thread code. Every call originates on the MainActor (the one
//  PatternEngine clock → PianoRollModel.trigger), so CoreMIDI send is safe here.
//  Compiles everywhere: the CoreMIDI implementation is guarded; on platforms
//  without it the API is a no-op so callers need no platform branches.
//

import Foundation
#if canImport(Observation)
import Observation
#endif
#if canImport(CoreMIDI)
import CoreMIDI
#endif

@MainActor
@Observable
public final class MIDIOutput {

    /// Master switch — off by default (most users record nothing; opt in from Sync).
    public var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            // Un-routing MIDI out must also stop the clock (#300), and it must send Stop
            // (0xFC) while the port is still alive — otherwise a receiver keeps running on
            // a clock that will never pulse again and has no way to learn that it ended.
            if enabled { startIfNeeded() } else { stopClock(); allNotesOff() }
        }
    }

    /// Spread notes across MPE member channels instead of all on channel 1.
    public var mpeEnabled = false {
        didSet {
            guard mpeEnabled != oldValue else { return }
            allNotesOff()                 // never strand a note when the layout changes
            if enabled && mpeEnabled { sendMPEConfiguration() }
        }
    }

    /// Stream the body's live 5D expression per note (Glide/Slide/Press) alongside
    /// each note-on — the ROLI-Seaboard-style multidimensional take, out to any MPE
    /// rig/DAW. Opt-in, off by default, and only meaningful with `mpeEnabled` (each
    /// note needs its own member channel for per-note bend/pressure/CC74). With it
    /// off, output is byte-for-byte the previous note-on/off stream.
    public var expressionEnabled = false

    /// Number of MPE member channels (lower zone): MIDI channels 2…16.
    public static let mpeMemberChannels = 15

    /// Read the two persisted MIDI-out preferences into the live flags — the ONE owner of
    /// that transfer (#713).
    ///
    /// Both the port-open path (`startIfNeeded`) and the Routing switches call THIS, the shape
    /// `MIDIInput.applyNetworkSessionPreference()` established: a switch and the live engine
    /// cannot disagree if only one piece of code moves the value. The alternative — the view
    /// assigning `mpeEnabled` directly — would make the surface a second lifecycle owner,
    /// which is the mistake BLE-3 had to undo when the patchbay was starting and stopping a
    /// heart-rate strap behind the player's back.
    ///
    /// ⛔ "THE LAUNCH PATH" IS WHAT #713 CALLED IT, AND THAT NAMES A HOOK THAT DOES NOT EXIST
    /// (#714). `startIfNeeded()` runs from `enabled`'s didSet, and `enabled` is only ever set
    /// by `applyRouting()` from the persisted `midi.out` route. With that route OFF at launch
    /// the didSet short-circuits and this method never runs — so it is the PORT-OPEN path, not
    /// the launch path. Harmless today (nothing can be sent while the route is off), but a
    /// name that describes a mechanism the code does not take is how the next session plans
    /// from a hook it cannot find (#374).
    ///
    /// ⚠️ It reads `UserDefaults` rather than taking arguments so that a caller cannot pass a
    /// value the persisted key does not hold. `StudioDefault`'s own default is the fallback,
    /// so an install that has never seen the switches behaves exactly as before this slice.
    /// One MIDI-out STATE CHANGE, written to BOTH sinks — the #650 shape, one subsystem over.
    ///
    /// ⭐ WHY (#715). Every one of this file's nine log lines went to `log.log`, which reaches
    /// `os_log` and an in-memory ring `ProfessionalLogger`'s own doc calls "write-only today".
    /// The file the founder exports — `echoel_diag.log` — is written by
    /// `EchoelCrashLog.breadcrumb` and by nothing else. So #713 shipped two switches whose
    /// entire evidence trail was unreadable from a device: if he turns MPE on and something
    /// misbehaves, the log he sends says nothing about MIDI out at all. #650 found exactly this
    /// hole in the monitoring path after five slices of instrumentation had gone somewhere
    /// nobody could read; this is the same hole, found the same way, before it cost a round trip.
    ///
    /// ⚠️ STATE CHANGES ONLY, never per event. `breadcrumb` does `Date()` plus a `write(2)`, so
    /// a call on the note path would be file I/O at note rate — and `send` is reached from the
    /// clock timer. Every call site here is port lifecycle or a preference edge, all on the main
    /// actor, which is where the `log.log` lines it joins already sat.
    ///
    /// ⚠️ ONE MESSAGE, TWO SINKS (#416). The prefixes differ because the sinks do: `os_log`
    /// carries a category, the breadcrumb file is flat and needs a greppable stem.
    private func logOutcome(_ message: String, level: LogLevel = .info) {
        log.log(level, category: .system, "MIDI OUT: \(message)")
        EchoelCrashLog.breadcrumb("midiout: \(message)")
    }

    public func applyOutputPreferences() {
        let store = UserDefaults.standard
        let mpe = store.object(forKey: StudioDefaultKeys.midiOutMPE.key) as? Bool
            ?? StudioDefaultKeys.midiOutMPE.value
        let expression = store.object(forKey: StudioDefaultKeys.midiOutExpression.key) as? Bool
            ?? StudioDefaultKeys.midiOutExpression.value
        let moved = (mpeEnabled != mpe) || (expressionEnabled != expression)
        if mpeEnabled != mpe { mpeEnabled = mpe }
        if expressionEnabled != expression { expressionEnabled = expression }
        // Only an actual edge, so a no-op re-apply on every enable leaves no line.
        if moved { logOutcome("prefs mpe=\(mpe) expression=\(expression)") }
    }

    public private(set) var isReady = false

    #if canImport(CoreMIDI)
    @ObservationIgnored private var client: MIDIClientRef = 0
    @ObservationIgnored private var outputPort: MIDIPortRef = 0
    @ObservationIgnored private var virtualSource: MIDIEndpointRef = 0
    #endif

    /// Active pitch → MIDI channel (0-based), so each note's off goes out on the
    /// same channel it started on (essential for MPE). A pitch can be held more
    /// than once (voice-leading) → keep a small stack per pitch.
    @ObservationIgnored private var channelForPitch: [Int: [Int]] = [:]
    /// Round-robin cursor over member channels for MPE allocation.
    @ObservationIgnored private var nextMember = 0

    public init() {}

    // MARK: - Lifecycle

    private func startIfNeeded() {
        // #713/#714: read the two persisted quality preferences FIRST, on EVERY enable edge.
        // Placement is exact, not incidental. On the first call `isReady` is still false, so
        // `mpeEnabled`'s `didSet` calls `sendMPEConfiguration()` into its own `guard isReady`
        // and the zone RPN is announced by the line after `isReady = true` instead.
        applyOutputPreferences()

        // ⛔ #713 WROTE `guard !isReady else { return }` HERE AND THAT WAS A SILENT DEFECT.
        // `isReady` is never reset — un-routing `midi.out` sets `enabled = false` and leaves
        // the port open — so a player who turned the route OFF, switched MPE ON in Routing,
        // and turned the route back on got member-channel notes with the zone RPN never
        // announced at all: the didSet's `enabled && mpeEnabled` was false at toggle time, and
        // this early return skipped the announce at re-enable. A receiving rig then reads
        // ordinary multi-channel MIDI. #713 CREATED that state, because before it `mpeEnabled`
        // could not move at runtime.
        //
        // ⚠️ THE GUARANTEE IS "ANNOUNCED BEFORE ANY NOTE CAN FLOW", NOT "EXACTLY ONCE", and
        // that is a deliberate downgrade of #713's wording. Re-enabling after a preference
        // change sends the RPN twice — once from the didSet, once here. It is a state-setting
        // RPN and receivers apply it idempotently, whereas suppressing the duplicate would
        // mean remembering what was announced, which would also suppress the re-announce a
        // rig that disappeared and came back actually needs.
        if isReady {
            if mpeEnabled { sendMPEConfiguration() }
            logOutcome("re-enabled on an open port"
                       + (mpeEnabled ? " · MPE zone re-announced" : " · channel 1"))
            return
        }
        #if canImport(CoreMIDI)
        let clientStatus = MIDIClientCreateWithBlock("Echoelmusic Output" as CFString, &client, nil)
        guard clientStatus == noErr else {
            logOutcome("client create failed (\(clientStatus))", level: .warning)
            return
        }
        let portStatus = MIDIOutputPortCreate(client, "Echoelmusic Out" as CFString, &outputPort)
        guard portStatus == noErr else {
            logOutcome("output port create failed (\(portStatus))", level: .warning)
            return
        }
        // The virtual source: this is what hosts see as "Echoelmusic" to record from.
        // MIDI 1.0 protocol → we send classic MIDIPacketList bytes via MIDIReceived.
        // (MIDISourceCreate is deprecated since iOS 14; the protocol variant is the
        // supported call and avoids a -warnings-as-errors build failure.)
        let srcStatus = MIDISourceCreateWithProtocol(client, "Echoelmusic" as CFString, ._1_0, &virtualSource)
        guard srcStatus == noErr else {
            logOutcome("virtual source create failed (\(srcStatus))", level: .warning)
            return
        }
        // Persist a stable unique ID so the host re-binds to the same source across
        // launches instead of treating each run as a new device.
        _ = MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, 0x4543_484F) // "ECHO"
        isReady = true
        if mpeEnabled { sendMPEConfiguration() }
        logOutcome("ready (virtual source 'Echoelmusic'"
                   + (mpeEnabled ? " · MPE zone announced" : " · channel 1")
                   + (expressionEnabled ? " · expression" : "") + ")")
        #else
        logOutcome("CoreMIDI unavailable on this platform — no-op")
        #endif
    }

    // MARK: - Note events (mirror exactly what the synth plays)

    public func noteOn(pitch: Int, velocity: Float) {
        noteOn(pitch: pitch, velocity: velocity, expression: nil)
    }

    /// Note-on that can carry the body's live 5D expression. When `expression` is
    /// supplied AND `expressionEnabled && mpeEnabled`, the per-note Glide (pitch
    /// bend), Slide (CC74) and Press (channel pressure) are emitted on the SAME
    /// member channel the note was allocated to — so a receiving MPE rig hears the
    /// note as a fully expressive, body-driven voice. Otherwise identical to the
    /// plain note-on (expression is simply ignored).
    public func noteOn(pitch: Int, velocity: Float, expression: MPEExpression?) {
        guard enabled, isReady, (0...127).contains(pitch) else { return }
        let ch = allocateChannel(for: pitch)
        let vel = UInt8(max(1, min(127, Int(velocity * 127))))   // 1…127 (0 = note off)
        send([0x90 | UInt8(ch), UInt8(pitch), vel])
        // While 5D is armed, EVERY note-on states its dimensions — an expression-
        // less note resets its member channel to neutral instead of inheriting
        // whatever bend/CC74/pressure the previous note left there (audible as a
        // detuned neighbour on external MPE rigs once per-note overrides exist;
        // MPE-spec practice is to initialise per-note dimensions at note-on).
        if mpeEnabled, expressionEnabled {
            sendExpression(expression ?? .neutral, channel: ch)
        }
    }

    /// Emit the three continuous MPE per-note dimensions on member channel `ch`:
    /// Glide (14-bit pitch bend), Slide (CC74) and Press (channel pressure, 0xD0).
    private func sendExpression(_ expr: MPEExpression, channel ch: Int) {
        let pb = MPEExpression.pitchBend14(expr.bend)
        send([0xE0 | UInt8(ch), pb.lsb, pb.msb])                       // Glide
        send([0xB0 | UInt8(ch), MPEExpression.slideCCIndex, expr.slideCC74])  // Slide (CC74)
        send([0xD0 | UInt8(ch), expr.pressure])                       // Press (channel pressure)
    }

    public func noteOff(pitch: Int) {
        guard enabled, isReady, (0...127).contains(pitch) else { return }
        guard let ch = releaseChannel(for: pitch) else { return }
        send([0x80 | UInt8(ch), UInt8(pitch), 0])
    }

    public func allNotesOff() {
        guard isReady else { channelForPitch.removeAll(); return }
        // Explicit per-note offs for everything we believe is sounding, plus an
        // All-Notes-Off CC (123) on every channel as a belt-and-braces flush.
        for (pitch, channels) in channelForPitch {
            for ch in channels { send([0x80 | UInt8(ch), UInt8(pitch), 0]) }
        }
        channelForPitch.removeAll()
        nextMember = 0
        for ch in 0..<16 { send([0xB0 | UInt8(ch), 123, 0]) }
    }

    // MARK: - Channel allocation

    private func allocateChannel(for pitch: Int) -> Int {
        let ch: Int
        if mpeEnabled {
            // Member channels are MIDI 2…16 → 0-based indices 1…15.
            ch = 1 + (nextMember % Self.mpeMemberChannels)
            nextMember += 1
        } else {
            ch = 0   // channel 1
        }
        channelForPitch[pitch, default: []].append(ch)
        return ch
    }

    private func releaseChannel(for pitch: Int) -> Int? {
        guard var stack = channelForPitch[pitch], !stack.isEmpty else { return nil }
        let ch = stack.removeLast()
        if stack.isEmpty { channelForPitch[pitch] = nil } else { channelForPitch[pitch] = stack }
        return ch
    }

    // MARK: - MPE configuration

    /// Emit the MPE Configuration Message (RPN 0x06) on the master channel (1) to
    /// claim a lower zone of `mpeMemberChannels` member channels, so a host
    /// auto-configures its MPE input. CC101=0, CC100=6, CC6=<count>.
    private func sendMPEConfiguration() {
        guard isReady else { return }
        send([0xB0, 101, 0])
        send([0xB0, 100, 6])
        send([0xB0, 6, UInt8(Self.mpeMemberChannels)])
    }

    // MARK: - Clock out (#300) — Echoel as the master clock

    /// True while MIDI Clock is being emitted. Read-only; driven by the transport.
    public private(set) var isSendingClock = false

    /// The clock pulse timer. Main-queue `DispatchSourceTimer`, like `PatternEngine`'s step
    /// timer and `AudioEngine`'s meter poll — but `repeating:`, where `PatternEngine`'s is
    /// one-shot and re-schedules itself from `.now()` inside each `advance()`. That is a
    /// real difference, not a detail: a self-rescheduling timer accumulates main-queue
    /// latency as drift, a repeating one does not. So Echoel's own step grid and the clock
    /// it exports drift apart over a long take, and nothing re-syncs them (no Song Position
    /// Pointer, no re-Start). A tight rig should slave Echoel to hardware, not the reverse.
    ///
    /// ⚠️ ITS OWN TIMER, NOT A DIVISION OF THE STEP TICK. Two reasons hold unconditionally:
    /// the step tick is 4 PPQ and 24 PPQN needs 6 sub-pulses per step regardless, and the
    /// step gap is variable by design (`swingGap`, and the tempo glide moves it every tick).
    ///
    /// ⭐ AND THE THIRD REASON IS LIVE AGAIN SINCE #327: deriving pulses from the step tick
    /// would export SWING as a TEMPO WOBBLE to every slaved device. `PatternEngine.swingGap`
    /// lengthens the gap after an even step and shortens the next; a receiver counting 24 PPQN
    /// off that gap reads it as the tempo speeding up and slowing down twice per beat.
    ///
    /// ⛔ THE HISTORY IS KEPT BECAUSE IT IS THE REPO'S NAMED FAILURE MODE, TWICE OVER. The
    /// FIRST version of this comment called the wobble "the whole musical argument of the
    /// slice" — an overstatement, since the two reasons above hold on their own. The SECOND
    /// version then demoted it with a fact that was true when written and is now false: that
    /// `swing` is 0 in every shipping path, because the one production caller of `setSwing`
    /// passed a hardwired `0` (#278). #327 replaced that literal with `style.swing`, so six of
    /// the sixteen offered genres now swing (deepHouse 0.16 down to minimalTechno 0.04 —
    /// re-derive against `MusicStyle.offered`, do not quote). The demotion note itself said
    /// this would "break silently the day swing returns". That day was #327. Re-promoted.
    @ObservationIgnored nonisolated(unsafe) private var clockTimer: DispatchSourceTimer?

    /// Uptime of the last pulse that actually went out, so a tempo change can re-arm the
    /// timer ON ITS EXISTING PHASE instead of restarting the interval from `.now()`.
    /// See `setClockTempo` for why that distinction decides whether the headline feature
    /// (a body-driven tempo) reaches the receiver as the tempo Echoel is playing.
    @ObservationIgnored private var lastPulseAt: DispatchTime?

    /// The absolute deadline the timer is currently armed for.
    ///
    /// ⛔ THIS EXISTS BECAUSE THE FIRST VERSION OF THIS NACHLESE RE-BROKE ITS OWN FIX, and
    /// the shape is worth remembering: `setClockTempo` re-armed from `lastPulseAt`, which is
    /// nil until the FIRST pulse has gone out — and its `else` branch fell back to one
    /// `interval`. But the pre-first-pulse deadline is not an interval, it is the DOWNBEAT
    /// (`startClock`'s `startingIn`, a whole step). A tempo change landing in that window
    /// silently pulled Start forward from ~125 ms to ~21 ms and reintroduced the very offset
    /// the slice removes. Keeping the absolute deadline makes the re-arm phase-preserving in
    /// BOTH windows.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS FIX NAMED THE WRONG TRIGGER — "reachable,
    /// `PatternEngine.advance` relays at step rate". `advance()` CANNOT land in this window,
    /// and the ordering that proves it is two lines of `PatternEngine.play()`: it calls
    /// `transport?.play()` FIRST (which arms this clock at `now_a + step`) and arms its own
    /// first tick only afterwards, at `now_b + step` with `now_b > now_a`. Same delay, later
    /// capture ⇒ the first pulse always precedes the first `advance()`, so `lastPulseAt` is
    /// non-nil by then. The window is genuinely reachable, just by DIRECT tempo writes inside
    /// the first 16th — tap tempo, a preset load, the lock field. Same fix, honest trigger:
    /// a justification that a future session can disprove is a fix it will delete.
    @ObservationIgnored private var nextPulseAt: DispatchTime?

    /// Start (0xFA) is owed but not yet sent — it goes out from the FIRST pulse, not from
    /// the play edge. See `startClock(bpm:startingIn:)`.
    @ObservationIgnored private var pendingStart = false

    /// Begin clock output at `bpm`: Start (0xFA) once, then Clock (0xF8) at 24 PPQN.
    /// No-op when MIDI out is not routed, or when a non-usable tempo is passed.
    ///
    /// ⭐ `startingIn` IS WHAT MAKES THE FEATURE WORTH HAVING, AND THE FIRST VERSION OF THIS
    /// SLICE DID NOT HAVE IT. `Transport.play()` fans out to its play subscribers
    /// immediately, but `PatternEngine.play()` schedules its first `advance()` one whole
    /// step later — so Echoel's own bar 1 SOUNDS one 16th after the play edge, deliberately
    /// (`Transport.play()`'s comment explains why). A receiver puts its beat 1 on Start and
    /// advances on clocks, so emitting Start at the play edge left every slaved DAW up to
    /// 125 ms (at 120 bpm) AHEAD of Echoel, permanently, from the first bar — a sync feature
    /// that was out of sync. ("Up to": a full 16th if the receiver begins on the Start byte,
    /// one 16th minus one pulse ≈ 104 ms if it begins on the first Clock AFTER Start, which
    /// is what the spec says. The fix is right under either reading; only the number moves.)
    /// Start is therefore deferred to the first pulse and the first pulse is armed for
    /// `startingIn` seconds from now: pass `Transport.stepDuration(atTempo:)`.
    public func startClock(bpm: Double, startingIn delay: TimeInterval = 0) {
        guard enabled else { return }
        guard let interval = UMPEncoder.clockInterval(bpm: bpm) else {
            log.log(.warning, category: .system, "MIDI CLOCK: refused to start at bpm \(bpm)")
            return
        }
        startIfNeeded()
        // `startIfNeeded` can fail (port/source creation error) and `sendRealTime` guards on
        // `isReady`, so claiming "on" before checking would make BOTH the published flag and
        // the log line lie about a clock that emits nothing.
        guard isReady else {
            log.log(.warning, category: .system, "MIDI CLOCK: port not ready, not started")
            return
        }
        stopClockTimer()                       // idempotent re-arm, no double timer
        if !isSendingClock {
            pendingStart = true                // Start ONLY on a true start, not on a re-arm
            isSendingClock = true
        }
        lastPulseAt = nil                      // fresh phase; the first pulse anchors it
        nextPulseAt = nil                      // …and no stale deadline survives the re-arm
        armClockTimer(interval: interval, firstAfter: Swift.max(0, delay))
        log.log(.info, category: .system, "MIDI CLOCK: on (\(bpm) bpm, 24 ppqn)")
    }

    /// Stop clock output and send Stop (0xFC). Safe to call when already stopped.
    ///
    /// ⚠️ NO STOP WITHOUT A START. Deferring Start to the first pulse opened an asymmetry
    /// that did not exist while Start rode the play edge: press play and stop again inside
    /// the first step (or un-route MIDI out there) and the owed Start never went out, while
    /// this method still sent a bare 0xFC. Spec-legal and ignored by most gear — but a
    /// receiver already running under ANOTHER master is stopped by it, which is the one
    /// case where a clock master must be silent rather than polite.
    public func stopClock() {
        stopClockTimer()
        let startWasOwed = pendingStart
        pendingStart = false
        lastPulseAt = nil
        nextPulseAt = nil
        guard isSendingClock else { return }
        isSendingClock = false
        if !startWasOwed { sendRealTime(.stop) }
        log.log(.info, category: .system, "MIDI CLOCK: off")
    }

    /// Re-arm the pulse interval for a new tempo WITHOUT emitting Start again — the body
    /// moves the tempo continuously (the glide in `PatternEngine.advance`), so a Start per
    /// tempo change would reset every receiver's song position several times a second.
    ///
    /// ⭐ THE RE-ARM PRESERVES PHASE, AND THAT IS THE WHOLE CORRECTNESS OF THIS METHOD.
    /// `PatternEngine.advance()` relays `transport?.setTempo(tempo)` on EVERY tick while a
    /// glide is in flight (~2 s, i.e. every 125 ms at 120 bpm), and `Transport.setTempo`
    /// fires its subscribers on every real move — so this runs many times per second exactly
    /// when the body is driving the tempo, which is the case the slice exists for. A re-arm
    /// from `.now()` discards however much of the current interval had already elapsed, so
    /// pulses go MISSING at every tempo relay and the receiver reads a tempo lower than the
    /// one Echoel is playing, for the whole glide. Anchoring the next deadline to the last
    /// pulse that actually went out keeps the pulse train continuous across the change.
    /// ⚠️ THERE ARE TWO PHASES TO PRESERVE, NOT ONE, and missing the second is how the first
    /// version of this Nachlese undid its own headline fix. Before the first pulse
    /// (`lastPulseAt == nil`) the pending deadline is not "one interval from the last pulse"
    /// — it is the DOWNBEAT that `startClock(startingIn:)` scheduled. Falling back to
    /// `interval` there pulls Start forward by nearly a whole step. So the deadline itself is
    /// remembered (`nextPulseAt`) and honoured in that window.
    public func setClockTempo(_ bpm: Double) {
        guard isSendingClock, let interval = UMPEncoder.clockInterval(bpm: bpm) else { return }
        stopClockTimer()
        // Distance to the next pulse. If that moment has already passed (a big slow-down, or
        // a stall), fire immediately rather than scheduling into the past — compared with
        // `>` rather than subtracted, because `uptimeNanoseconds` is unsigned and a past
        // deadline would wrap to ~584 years (2^64 ns).
        //
        // Precise about WHERE that matters, since the first version implied it rescued the
        // running branch: in the `lastPulseAt` branch the old `&-` was already harmless —
        // `Swift.max(0, interval - elapsed)` clamped the wrapped result to 0, i.e. "fire now",
        // which is the right answer anyway. The branch that genuinely needs the guard is the
        // NEW pre-first-pulse one below: it has no `max(0, …)`, so an already-passed downbeat
        // would otherwise be scheduled 584 years out.
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let next: TimeInterval
        if let last = lastPulseAt {
            // Running: hold the existing pulse phase, only the spacing changes.
            let elapsed = nowNs > last.uptimeNanoseconds
                ? Double(nowNs - last.uptimeNanoseconds) / 1e9
                : 0
            next = Swift.max(0, interval - elapsed)
        } else if let pending = nextPulseAt {
            // Pre-first-pulse: the downbeat is a fixed moment in time. A tempo change must
            // not move it, only the spacing of what follows it.
            next = pending.uptimeNanoseconds > nowNs
                ? Double(pending.uptimeNanoseconds - nowNs) / 1e9
                : 0
        } else {
            // Unreachable in production — `isSendingClock` is true, so either a pulse has
            // fired (branch 1) or a deadline is armed (branch 2). Kept as the correct safe
            // default, and said out loud so nobody "simplifies" three branches back to two.
            next = interval
        }
        armClockTimer(interval: interval, firstAfter: next)
    }

    private func armClockTimer(interval: Double, firstAfter: Double) {
        #if canImport(CoreMIDI)
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Leeway 0: the clock IS the timing product here. The meter poll can drift a
        // millisecond and nobody hears it; a clock pulse that drifts is the jitter a
        // drummer feels. This is still a MAIN-QUEUE timer, not a sample-accurate one: at
        // 120 bpm it wakes 48×/s and at `Transport.maxTempo` 120×/s, each fire doing
        // CoreMIDI destination lookups on the actor that hosts every SwiftUI menu. That
        // load is compile-verified only — it needs a device run with a Picker open.
        let deadline = DispatchTime.now() + firstAfter
        nextPulseAt = deadline
        t.schedule(deadline: deadline, repeating: interval, leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.emitPulse() }
        }
        clockTimer = t
        t.resume()
        #endif
    }

    /// One clock pulse — and the owed Start, if this is the first pulse of a run, so Start
    /// lands on the downbeat rather than one step early.
    private func emitPulse() {
        if pendingStart {
            pendingStart = false
            sendRealTime(.start)
        }
        sendRealTime(.clock)
        lastPulseAt = DispatchTime.now()
        // The armed deadline has been consumed; from here `lastPulseAt` is the phase anchor.
        // Clearing it keeps `setClockTempo`'s two branches mutually exclusive by CONSTRUCTION
        // rather than by the reader trusting that the first branch always wins.
        nextPulseAt = nil
    }

    /// Thread-safe cancel. Not `nonisolated`: every caller (`startClock`, `stopClock`,
    /// `setClockTempo`) is already on the main actor, and `deinit` reaches the timer by the
    /// direct property access below rather than through here. Keeping it isolated preserves
    /// the property `PatternEngine`'s identical `nonisolated(unsafe)` storage relies on —
    /// *written only on the main actor* — so the escape hatch stays a read-side one.
    /// (⛔ The first version made this `nonisolated`, which compiles fine but silently voided
    /// that argument while a comment three lines away still cited it.)
    private func stopClockTimer() {
        clockTimer?.cancel()
        clockTimer = nil
    }

    deinit {
        // Same shape as `PatternEngine.deinit` (`PatternEngine.swift`, which this slice
        // copied the timer from): a plain `deinit` on a `@MainActor` class is already
        // nonisolated, and `DispatchSourceTimer.cancel()` is thread-safe. Written as the
        // direct property access rather than a call to `stopClockTimer()` because that
        // method is main-actor isolated and a `deinit` is not.
        //
        // An ACTIVE `DispatchSourceTimer` is retained by the dispatch runtime, so dropping
        // the last reference does NOT stop it: `[weak self]` makes the handler a no-op and
        // the source fires forever, unreachable.
        //
        // ⛔ The first version justified this with "earns its keep in tests and previews".
        // There are no such consumers: `EchoelmusicApp.swift` holds the ONE `MIDIOutput` in
        // the app and it never deallocates, and no test constructs one with a running clock.
        // The honest justification is the ordinary one — an owner that outlives the process
        // is a fact of today's wiring, not a property of the class, and a leaked repeating
        // main-queue timer is exactly the kind of thing that stops being free the moment
        // that wiring changes.
        clockTimer?.cancel()
    }

    private func sendRealTime(_ message: UMPEncoder.RealTime) {
        #if canImport(CoreMIDI)
        guard isReady else { return }
        var word = UMPEncoder.systemRealTime(status: message.rawValue)
        var eventList = MIDIEventList()
        let packet = MIDIEventListInit(&eventList, ._1_0)
        _ = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        _ = MIDIReceivedEventList(virtualSource, &eventList)
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            _ = MIDISendEventList(outputPort, MIDIGetDestination(i), &eventList)
        }
        #endif
    }

    // MARK: - CoreMIDI send

    /// Send one short MIDI 1.0 channel-voice message (status + ≤2 data bytes) over
    /// the Universal MIDI Packet (UMP) path, matching the protocol-created source
    /// and MIDIInput's event-list usage. A MIDI 1.0 message packs into one 32-bit
    /// UMP word: [type 0x2 | group 0 | status | data1 | data2].
    private func send(_ bytes: [UInt8]) {
        #if canImport(CoreMIDI)
        guard isReady, (2...3).contains(bytes.count) else { return }
        // Build the MIDI 1.0 UMP word via the pure, unit-tested encoder (group 0),
        // so the live wire format is centralised and verified by UMPEncoderTests.
        var word = UMPEncoder.midi1ChannelVoice(status: bytes[0], data1: bytes[1],
                                                data2: bytes.count > 2 ? bytes[2] : 0)

        var eventList = MIDIEventList()
        let packet = MIDIEventListInit(&eventList, ._1_0)
        _ = MIDIEventListAdd(&eventList, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        // To the virtual source (hosts recording "Echoelmusic")…
        _ = MIDIReceivedEventList(virtualSource, &eventList)
        // …and to every connected destination (hardware / other apps' inputs).
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            _ = MIDISendEventList(outputPort, MIDIGetDestination(i), &eventList)
        }
        #endif
    }
}
