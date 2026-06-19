//
//  MIDIFileExporter.swift
//  Echoelmusic — Sequencer
//
//  Exports an 8×16 drum pattern to a Standard MIDI File (SMF Type 0).
//  Pure value logic — Foundation only, deterministic, no Apple-UI frameworks —
//  so it is unit-testable in CI. Completes the EchoelSeq roadmap item
//  "take your beat to any DAW": PatternEngine grid → .mid.
//
//  Format: SMF Type 0 (single track), 96 ticks/quarter (24 ticks per 16th).
//  The 8 sequencer tracks map to General MIDI percussion notes on channel 10.
//

import Foundation

public enum MIDIFileExporter {

    /// GM percussion notes (channel 10) for the 8 sequencer tracks:
    /// kick · snare · closed-hat · open-hat · clap · tom · rim · crash.
    public static let drumNotes: [UInt8] = [36, 38, 42, 46, 39, 45, 37, 49]

    /// Pulses Per Quarter note. 96 / 4 = 24 ticks per 16th-note step.
    public static let ticksPerQuarter: UInt16 = 96
    private static var ticksPerStep: Int { Int(ticksPerQuarter) / 4 }

    /// Build a Type-0 Standard MIDI File for the grid + tempo.
    /// - Parameters:
    ///   - steps: `steps[track][step] == true` triggers a note.
    ///   - tempo: BPM (clamped to 1...1000).
    ///   - velocity: note-on velocity, 1...127.
    public static func export(steps: [[Bool]], tempo: Double, velocity: UInt8 = 100,
                              humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        var track = Data()

        // Tempo meta event: FF 51 03 <µs per quarter, 3 bytes big-endian>.
        let clampedTempo = Swift.min(Swift.max(tempo, 1), 1000)
        let usPerQuarter = UInt32(60_000_000.0 / clampedTempo)
        track.append(contentsOf: [0x00, 0xFF, 0x51, 0x03])
        track.append(UInt8((usPerQuarter >> 16) & 0xFF))
        track.append(UInt8((usPerQuarter >> 8) & 0xFF))
        track.append(UInt8(usPerQuarter & 0xFF))

        // Gather note-on/off events (channel 10 → status 0x99 / 0x89).
        struct Ev { let tick: Int; let on: Bool; let note: UInt8; let vel: UInt8 }
        var events: [Ev] = []
        let gate = ticksPerStep / 2  // each hit lasts half a step
        var hitIndex = 0
        for (t, row) in steps.enumerated() {
            let note = drumNotes[t % drumNotes.count]
            for (s, active) in row.enumerated() where active {
                let (tickDelta, velScale) = humanize.jitter(index: hitIndex, seed: seed)
                hitIndex += 1
                let onTick = Swift.max(0, s * ticksPerStep + tickDelta)
                let vel = UInt8(Swift.min(127, Swift.max(1, Int(Float(velocity) * velScale))))
                events.append(Ev(tick: onTick, on: true, note: note, vel: vel))
                events.append(Ev(tick: onTick + gate, on: false, note: note, vel: 0))
            }
        }
        // Order by tick; note-off before note-on at the same tick (off=false sorts first).
        events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : (!$0.on && $1.on) }

        var lastTick = 0
        for ev in events {
            track.append(contentsOf: vlq(ev.tick - lastTick))
            lastTick = ev.tick
            track.append(ev.on ? 0x99 : 0x89)
            track.append(ev.note)
            track.append(ev.on ? ev.vel : 0)
        }

        // End of track.
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        // Assemble: header chunk + track chunk.
        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(contentsOf: be32(6))
        data.append(contentsOf: be16(0))                 // format 0
        data.append(contentsOf: be16(1))                 // 1 track
        data.append(contentsOf: be16(ticksPerQuarter))   // division
        data.append(contentsOf: Array("MTrk".utf8))
        data.append(contentsOf: be32(UInt32(track.count)))
        data.append(track)
        return data
    }

    /// Build a Type-0 SMF for a piano-roll melody (channel 1). Each note uses
    /// its real start, length (→ duration) and velocity.
    public static func export(notes: [Note], tempo: Double,
                              humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        var track = Data()

        let clampedTempo = Swift.min(Swift.max(tempo, 1), 1000)
        let usPerQuarter = UInt32(60_000_000.0 / clampedTempo)
        track.append(contentsOf: [0x00, 0xFF, 0x51, 0x03])
        track.append(UInt8((usPerQuarter >> 16) & 0xFF))
        track.append(UInt8((usPerQuarter >> 8) & 0xFF))
        track.append(UInt8(usPerQuarter & 0xFF))

        struct Ev { let tick: Int; let on: Bool; let note: UInt8; let vel: UInt8 }
        var events: [Ev] = []
        for (i, n) in notes.enumerated() {
            let (tickDelta, velScale) = humanize.jitter(index: i, seed: seed)
            let onTick = Swift.max(0, n.startStep * ticksPerStep + tickDelta)
            // Preserve duration: shift the note-off with the note-on.
            let offTick = onTick + n.lengthSteps * ticksPerStep
            let note = UInt8(Swift.min(127, Swift.max(0, n.pitch)))
            let vel = UInt8(Swift.min(127, Swift.max(1, Int(n.velocity * 127 * velScale))))
            events.append(Ev(tick: onTick, on: true, note: note, vel: vel))
            events.append(Ev(tick: offTick, on: false, note: note, vel: 0))
        }
        events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : (!$0.on && $1.on) }

        var lastTick = 0
        for ev in events {
            track.append(contentsOf: vlq(ev.tick - lastTick))
            lastTick = ev.tick
            track.append(ev.on ? 0x90 : 0x80) // channel 1
            track.append(ev.note)
            track.append(ev.on ? ev.vel : 0)
        }

        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(contentsOf: be32(6))
        data.append(contentsOf: be16(0))
        data.append(contentsOf: be16(1))
        data.append(contentsOf: be16(ticksPerQuarter))
        data.append(contentsOf: Array("MTrk".utf8))
        data.append(contentsOf: be32(UInt32(track.count)))
        data.append(track)
        return data
    }

    /// Build a Type-1 SMF carrying the WHOLE take: a conductor track (tempo),
    /// a melody track (channel 1, real durations + velocity), and a drum track
    /// (channel 10, GM percussion) — so the complete arrangement opens together
    /// in any DAW instead of melody and beat as separate files.
    public static func exportCombined(notes: [Note], steps: [[Bool]], tempo: Double,
                                      velocity: UInt8 = 100,
                                      humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        // Conductor track: just the tempo map.
        let clampedTempo = Swift.min(Swift.max(tempo, 1), 1000)
        let usPerQuarter = UInt32(60_000_000.0 / clampedTempo)
        let tempoMeta: [UInt8] = [0x00, 0xFF, 0x51, 0x03,
                                  UInt8((usPerQuarter >> 16) & 0xFF),
                                  UInt8((usPerQuarter >> 8) & 0xFF),
                                  UInt8(usPerQuarter & 0xFF)]
        let conductor = serializeTrack([], leadingMeta: tempoMeta)
        let melody = serializeTrack(melodyEvents(notes, humanize: humanize, seed: seed))
        let drums = serializeTrack(drumEvents(steps, velocity: velocity, humanize: humanize, seed: seed))

        var data = Data()
        data.append(contentsOf: Array("MThd".utf8))
        data.append(contentsOf: be32(6))
        data.append(contentsOf: be16(1))                 // format 1 (multi-track)
        data.append(contentsOf: be16(3))                 // conductor + melody + drums
        data.append(contentsOf: be16(ticksPerQuarter))   // division
        data.append(conductor)
        data.append(melody)
        data.append(drums)
        return data
    }

    // MARK: - Event building (shared by the combined exporter)

    /// One absolute-tick MIDI channel event; `status` already encodes the channel
    /// (e.g. 0x90 melody note-on, 0x99 drum note-on, 0x80/0x89 note-off).
    private struct MIDIEvent { let tick: Int; let on: Bool; let status: UInt8; let note: UInt8; let vel: UInt8 }

    private static func melodyEvents(_ notes: [Note], humanize: Humanizer, seed: UInt64) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        for (i, n) in notes.enumerated() {
            let (tickDelta, velScale) = humanize.jitter(index: i, seed: seed)
            let onTick = Swift.max(0, n.startStep * ticksPerStep + tickDelta)
            let offTick = onTick + n.lengthSteps * ticksPerStep
            let note = UInt8(Swift.min(127, Swift.max(0, n.pitch)))
            let vel = UInt8(Swift.min(127, Swift.max(1, Int(n.velocity * 127 * velScale))))
            events.append(MIDIEvent(tick: onTick, on: true, status: 0x90, note: note, vel: vel))
            events.append(MIDIEvent(tick: offTick, on: false, status: 0x80, note: note, vel: 0))
        }
        return events
    }

    private static func drumEvents(_ steps: [[Bool]], velocity: UInt8, humanize: Humanizer, seed: UInt64) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        let gate = ticksPerStep / 2
        var hitIndex = 0
        for (t, row) in steps.enumerated() {
            let note = drumNotes[t % drumNotes.count]
            for (s, active) in row.enumerated() where active {
                let (tickDelta, velScale) = humanize.jitter(index: hitIndex, seed: seed)
                hitIndex += 1
                let onTick = Swift.max(0, s * ticksPerStep + tickDelta)
                let vel = UInt8(Swift.min(127, Swift.max(1, Int(Float(velocity) * velScale))))
                events.append(MIDIEvent(tick: onTick, on: true, status: 0x99, note: note, vel: vel))
                events.append(MIDIEvent(tick: onTick + gate, on: false, status: 0x89, note: note, vel: 0))
            }
        }
        return events
    }

    /// Serialize absolute-tick events (+ optional leading meta) into an MTrk chunk
    /// with a trailing End-of-Track. Note-off sorts before note-on at the same tick.
    private static func serializeTrack(_ events: [MIDIEvent], leadingMeta: [UInt8] = []) -> Data {
        var track = Data()
        track.append(contentsOf: leadingMeta)
        let sorted = events.sorted { $0.tick != $1.tick ? $0.tick < $1.tick : (!$0.on && $1.on) }
        var lastTick = 0
        for ev in sorted {
            track.append(contentsOf: vlq(ev.tick - lastTick))
            lastTick = ev.tick
            track.append(ev.status)
            track.append(ev.note)
            track.append(ev.vel)
        }
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        var chunk = Data()
        chunk.append(contentsOf: Array("MTrk".utf8))
        chunk.append(contentsOf: be32(UInt32(track.count)))
        chunk.append(track)
        return chunk
    }

    // MARK: - Byte helpers (internal → reachable via @testable)

    /// MIDI variable-length quantity (7 bits/byte, high bit = continuation).
    static func vlq(_ value: Int) -> [UInt8] {
        var v = UInt32(Swift.max(0, value))
        var out = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            out.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return out
    }

    static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}
