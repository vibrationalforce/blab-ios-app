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

    /// Convert a `Note` PPQ tick (480 PPQ) into this exporter's PPQ. On-grid notes
    /// map identically; sub-step (unquantized) positions survive the export.
    private static func exportTicks(noteTicks: Int) -> Int {
        noteTicks * Int(ticksPerQuarter) / Note.ticksPerQuarter
    }

    /// Build a Type-0 Standard MIDI File for the grid + tempo.
    /// - Parameters:
    ///   - steps: `steps[track][step] == true` triggers a note.
    ///   - tempo: BPM (clamped to 1...1000).
    ///   - velocity: note-on velocity, 1...127.
    public static func export(steps: [[Bool]], tempo: Double, velocity: UInt8 = 100,
                              humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        var track = Data()

        // Tempo meta event: FF 51 03 <µs per quarter, 3 bytes big-endian>.
        // One source of truth (tempoMeta) — it clamps the 3-byte field.
        track.append(contentsOf: tempoMeta(tempo))

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

        track.append(contentsOf: tempoMeta(tempo))

        struct Ev { let tick: Int; let on: Bool; let note: UInt8; let vel: UInt8 }
        var events: [Ev] = []
        for (i, n) in notes.enumerated() {
            let (tickDelta, velScale) = humanize.jitter(index: i, seed: seed)
            let onTick = Swift.max(0, exportTicks(noteTicks: n.startTick) + tickDelta)
            // Preserve duration: shift the note-off with the note-on.
            let offTick = onTick + Swift.max(1, exportTicks(noteTicks: n.lengthTicks))
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

    /// Build a Type-1 SMF carrying the WHOLE take: a conductor track (tempo + time-
    /// signature + key-signature + name), a melody track (channel 1, real durations +
    /// velocity), and a drum track (channel 10, GM percussion) — so the complete
    /// arrangement opens together in any DAW instead of melody and beat as separate files.
    ///
    /// DAW-usable loop (founder: "8/16-Takt-Loop … in der DAW weiterarbeiten"):
    /// - `bars` sets the exported REGION length; every track's End-of-Track is anchored to
    ///   exactly `bars × 4` quarter notes, so the clip spans N whole bars and loops
    ///   seamlessly on the grid (no truncated tail at the loop point).
    /// - `keyRootPitchClass` (0=C…11=B, <0 = unknown/omit) + `keyIsMinor` write a real key-
    ///   signature meta so the DAW shows the Tonart.
    /// - `accents` (parallel to `steps`) map accented drum cells to a louder velocity.
    public static func exportCombined(notes: [Note], steps: [[Bool]],
                                      accents: [[Bool]] = [],
                                      tempo: Double, bars: Int = 1,
                                      keyRootPitchClass: Int = -1, keyIsMinor: Bool = false,
                                      velocity: UInt8 = 100,
                                      humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        let barCount = Swift.max(1, bars)
        // The region spans exactly N bars of 4/4 → N×4 quarters worth of ticks.
        let regionEndTick = barCount * 4 * Int(ticksPerQuarter)

        // Conductor track: tempo + 4/4 time-signature + key-signature + a name.
        var conductorMeta = tempoMeta(tempo)
        conductorMeta += timeSignatureMeta()
        conductorMeta += keySignatureMeta(rootPitchClass: keyRootPitchClass, minor: keyIsMinor)
        conductorMeta += trackNameMeta("Echoelmusic")
        let conductor = serializeTrack([], leadingMeta: conductorMeta, endTick: regionEndTick)
        let melody = serializeTrack(melodyEvents(notes, humanize: humanize, seed: seed),
                                    leadingMeta: trackNameMeta("Melody"), endTick: regionEndTick)
        let drums = serializeTrack(drumEvents(steps, accents: accents, velocity: velocity,
                                              humanize: humanize, seed: seed),
                                   leadingMeta: trackNameMeta("Drums"), endTick: regionEndTick)

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

    /// Export ONE launchable `Clip` as a Type-1 Standard MIDI File — the founder's
    /// "MIDI Clip Save": a saved drum pattern and/or melody → a DAW-openable `.mid`.
    /// Maps straight onto the tested `exportCombined` engine (conductor + melody +
    /// drums tracks), so a melody-only clip emits channel-1 note-ons, a drum-only clip
    /// emits channel-10 percussion, and a combined clip emits both.
    ///
    /// The exported REGION length is DERIVED from the clip's own content — the melody's
    /// last note-end and the drum grid width — each rounded UP to whole bars, so the
    /// clip spans N whole bars and loops on the grid. `Clip` stays READ-ONLY (this only
    /// reads it). MIDI is the only kind with an inline pattern; a media-carrier clip
    /// (audio/video/visual) has no notes/grid, so it yields a well-formed 1-bar region
    /// with no note events (honest, never a crash).
    public static func export(clip: Clip, tempo: Double,
                              keyRootPitchClass: Int = -1, keyIsMinor: Bool = false,
                              velocity: UInt8 = 100,
                              humanize: Humanizer = .tight, seed: UInt64 = 0) -> Data {
        let notes = clip.melody?.notes ?? []
        let steps = clip.drums?.steps ?? []
        let accents = clip.drums?.accents ?? []

        // Region length = whichever content reaches furthest, rounded UP to whole bars.
        // Melody notes are clip-absolute Note-PPQ ticks (same space as ticksPerBar=1920);
        // the drum grid is 16 steps per bar. Empty content → 0 bars → the max(1,…) floor.
        let melodyEndTick = notes.map { $0.startTick + $0.lengthTicks }.max() ?? 0
        let melodyBars = (Swift.max(0, melodyEndTick) + TimelineTime.ticksPerBar - 1) / TimelineTime.ticksPerBar
        let gridWidth = steps.map { $0.count }.max() ?? 0
        let drumBars = (gridWidth + 15) / 16
        let bars = Swift.max(1, Swift.max(melodyBars, drumBars))

        return exportCombined(notes: notes, steps: steps, accents: accents,
                              tempo: tempo, bars: bars,
                              keyRootPitchClass: keyRootPitchClass, keyIsMinor: keyIsMinor,
                              velocity: velocity, humanize: humanize, seed: seed)
    }

    // MARK: - Meta-event builders (each begins with a 0x00 delta-time)

    static func tempoMeta(_ tempo: Double) -> [UInt8] {
        let clampedTempo = Swift.min(Swift.max(tempo, 1), 1000)
        // The SMF tempo meta is a fixed 3-byte field → max 0xFFFFFF µs/quarter
        // (~3.576 BPM). Clamp the ENCODED value so a very slow tempo saturates at
        // the format floor instead of silently overflowing (dropping the top byte,
        // which read back ~6× too fast). No-op for any tempo ≥ ~3.576 BPM, so every
        // realistic export is byte-identical.
        let usPerQuarter = Swift.min(UInt32(60_000_000.0 / clampedTempo), 0xFF_FFFF)
        return [0x00, 0xFF, 0x51, 0x03,
                UInt8((usPerQuarter >> 16) & 0xFF),
                UInt8((usPerQuarter >> 8) & 0xFF),
                UInt8(usPerQuarter & 0xFF)]
    }

    /// 4/4, 24 MIDI clocks per metronome click, 8 32nds per quarter — the standard anchor
    /// so a DAW places the clip on bar/beat lines instead of guessing.
    private static func timeSignatureMeta() -> [UInt8] {
        [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]   // numerator 4, denom 2^2=4
    }

    /// FF 59 02 <sf> <mi>. `sf` = signed sharps(+)/flats(−) on the circle of fifths,
    /// `mi` = 0 major / 1 minor. Omitted (empty) when the root is unknown (<0).
    private static func keySignatureMeta(rootPitchClass pc: Int, minor: Bool) -> [UInt8] {
        guard pc >= 0 else { return [] }
        // Sharps/flats for each MAJOR key by pitch class (enharmonic pick ≤6 accidentals).
        let majorSf: [Int] = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]
        // A minor key uses its relative major's signature (relative major = root + 3 semitones).
        let refPc = minor ? ((pc % 12) + 3) % 12 : (pc % 12)
        let sf = majorSf[(refPc % 12 + 12) % 12]
        let sfByte = UInt8(bitPattern: Int8(sf))
        return [0x00, 0xFF, 0x59, 0x02, sfByte, minor ? 0x01 : 0x00]
    }

    /// FF 03 <len> <ascii> — a track name the DAW shows on the imported track.
    private static func trackNameMeta(_ name: String) -> [UInt8] {
        let bytes = Array(name.utf8.prefix(127))
        return [0x00, 0xFF, 0x03, UInt8(bytes.count)] + bytes
    }

    // MARK: - Event building (shared by the combined exporter)

    /// One absolute-tick MIDI channel event; `status` already encodes the channel
    /// (e.g. 0x90 melody note-on, 0x99 drum note-on, 0x80/0x89 note-off).
    private struct MIDIEvent { let tick: Int; let on: Bool; let status: UInt8; let note: UInt8; let vel: UInt8 }

    private static func melodyEvents(_ notes: [Note], humanize: Humanizer, seed: UInt64) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        for (i, n) in notes.enumerated() {
            let (tickDelta, velScale) = humanize.jitter(index: i, seed: seed)
            let onTick = Swift.max(0, exportTicks(noteTicks: n.startTick) + tickDelta)
            let offTick = onTick + Swift.max(1, exportTicks(noteTicks: n.lengthTicks))
            let note = UInt8(Swift.min(127, Swift.max(0, n.pitch)))
            let vel = UInt8(Swift.min(127, Swift.max(1, Int(n.velocity * 127 * velScale))))
            events.append(MIDIEvent(tick: onTick, on: true, status: 0x90, note: note, vel: vel))
            events.append(MIDIEvent(tick: offTick, on: false, status: 0x80, note: note, vel: 0))
        }
        return events
    }

    private static func drumEvents(_ steps: [[Bool]], accents: [[Bool]] = [], velocity: UInt8,
                                   humanize: Humanizer, seed: UInt64) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        let gate = ticksPerStep / 2
        var hitIndex = 0
        // Accented cells hit harder; non-accented sit back — so the beat's dynamics survive
        // the export instead of every hit landing at one flat velocity.
        let accentVel = UInt8(Swift.min(127, Int(velocity) + 20))
        let normalVel = UInt8(Swift.max(1, Int(velocity) - 20))
        for (t, row) in steps.enumerated() {
            let note = drumNotes[t % drumNotes.count]
            let accentRow = (t < accents.count) ? accents[t] : []
            for (s, active) in row.enumerated() where active {
                let (tickDelta, velScale) = humanize.jitter(index: hitIndex, seed: seed)
                hitIndex += 1
                let onTick = Swift.max(0, s * ticksPerStep + tickDelta)
                let isAccent = s < accentRow.count && accentRow[s]
                let base = isAccent ? accentVel : normalVel
                let vel = UInt8(Swift.min(127, Swift.max(1, Int(Float(base) * velScale))))
                events.append(MIDIEvent(tick: onTick, on: true, status: 0x99, note: note, vel: vel))
                events.append(MIDIEvent(tick: onTick + gate, on: false, status: 0x89, note: note, vel: 0))
            }
        }
        return events
    }

    /// Serialize absolute-tick events (+ optional leading meta) into an MTrk chunk
    /// with a trailing End-of-Track. Note-off sorts before note-on at the same tick.
    /// `endTick` anchors the End-of-Track to the region end (N bars), so the imported clip
    /// spans exactly N bars and loops seamlessly — even when the last note ends before the
    /// bar line. 0 = end right after the last event (legacy behaviour).
    private static func serializeTrack(_ events: [MIDIEvent], leadingMeta: [UInt8] = [],
                                       endTick: Int = 0) -> Data {
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
        // End-of-Track: delay it to the region end so the clip length == N bars.
        track.append(contentsOf: vlq(Swift.max(0, endTick - lastTick)))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])
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
