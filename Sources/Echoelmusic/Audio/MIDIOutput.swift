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
        guard enabled, isReady, (0...127).contains(pitch) else { return }
        let ch = allocateChannel(for: pitch)
        let vel = UInt8(max(1, min(127, Int(velocity * 127))))   // 1…127 (0 = note off)
        send([0x90 | UInt8(ch), UInt8(pitch), vel])
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
        let status = UInt32(bytes[0])
        let data1 = UInt32(bytes[1])
        let data2 = bytes.count > 2 ? UInt32(bytes[2]) : 0
        var word = (UInt32(0x2) << 28) | (status << 16) | (data1 << 8) | data2

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
