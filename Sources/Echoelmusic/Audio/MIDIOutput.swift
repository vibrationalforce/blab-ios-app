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
            if enabled { startIfNeeded() } else { allNotesOff() }
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
        guard !isReady else { return }
        #if canImport(CoreMIDI)
        let clientStatus = MIDIClientCreateWithBlock("Echoelmusic Output" as CFString, &client, nil)
        guard clientStatus == noErr else {
            log.log(.warning, category: .system, "MIDI OUT: client create failed (\(clientStatus))")
            return
        }
        let portStatus = MIDIOutputPortCreate(client, "Echoelmusic Out" as CFString, &outputPort)
        guard portStatus == noErr else {
            log.log(.warning, category: .system, "MIDI OUT: output port create failed (\(portStatus))")
            return
        }
        // The virtual source: this is what hosts see as "Echoelmusic" to record from.
        // MIDI 1.0 protocol → we send classic MIDIPacketList bytes via MIDIReceived.
        // (MIDISourceCreate is deprecated since iOS 14; the protocol variant is the
        // supported call and avoids a -warnings-as-errors build failure.)
        let srcStatus = MIDISourceCreateWithProtocol(client, "Echoelmusic" as CFString, ._1_0, &virtualSource)
        guard srcStatus == noErr else {
            log.log(.warning, category: .system, "MIDI OUT: virtual source create failed (\(srcStatus))")
            return
        }
        // Persist a stable unique ID so the host re-binds to the same source across
        // launches instead of treating each run as a new device.
        _ = MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, 0x4543_484F) // "ECHO"
        isReady = true
        if mpeEnabled { sendMPEConfiguration() }
        log.log(.info, category: .system, "MIDI OUT: ready (virtual source 'Echoelmusic'\(mpeEnabled ? " · MPE" : ""))")
        #else
        log.log(.info, category: .system, "MIDI OUT: CoreMIDI unavailable on this platform — no-op")
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
