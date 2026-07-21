//
//  MIDIFileImporter.swift
//  Echoelmusic — Sequencer
//
//  Reads a Standard MIDI File (Type 0 or 1) into melodic `Note`s for the piano
//  roll — the inverse of MIDIFileExporter, completing the "bring your DAW MIDI
//  into Echoel" loop. Pure value logic (Foundation only) so it is unit-testable
//  in CI (round-trips against the exporter).
//
//  Note timing is mapped from the file's own PPQ division onto `Note.ticksPerQuarter`
//  (480), so an imported clip sits sample-tight on Echoel's grid regardless of the
//  source resolution. Note-on (status 0x9n, velocity > 0) opens a note; the matching
//  note-off (0x8n, or 0x9n velocity 0) on the same channel+pitch closes it. Running
//  status, meta and SysEx events are handled/skipped. Percussion channel 10 is
//  excluded by default (those are drum hits, not melody).
//

import Foundation

public enum MIDIFileImporter {

    public enum ImportError: Error, Sendable, Equatable {
        case notAMIDIFile
        case truncated
        case unsupportedDivision   // SMPTE timecode division (negative) — not supported
    }

    /// Parse SMF `data` into melodic notes. `includeChannel10` keeps GM percussion
    /// (usually unwanted for the melodic roll). Notes come back sorted by start.
    public static func notes(from data: [UInt8], includeChannel10: Bool = false) throws -> [Note] {
        try channelNotes(from: data)
            .filter { includeChannel10 || $0.channel != 9 }    // ch10 == index 9
            .map(\.note)
            .sorted { $0.startTick != $1.startTick ? $0.startTick < $1.startTick : $0.pitch < $1.pitch }
    }

    /// Parse SMF `data` into (channel, note) pairs — the shared parse used by both
    /// the melodic `notes(...)` and the drum-grid extraction. Channel is the 0-based
    /// MIDI channel (9 == GM percussion / "channel 10").
    public static func channelNotes(from data: [UInt8]) throws -> [(channel: Int, note: Note)] {
        var p = 0
        func need(_ n: Int) throws { if p + n > data.count { throw ImportError.truncated } }
        func u16(_ i: Int) -> Int { (Int(data[i]) << 8) | Int(data[i + 1]) }
        func u32(_ i: Int) -> Int {
            (Int(data[i]) << 24) | (Int(data[i + 1]) << 16) | (Int(data[i + 2]) << 8) | Int(data[i + 3])
        }

        // Header: "MThd" len=6 format ntracks division.
        try need(14)
        guard data[0] == 0x4D, data[1] == 0x54, data[2] == 0x68, data[3] == 0x64 else {
            throw ImportError.notAMIDIFile
        }
        let division = u16(12)
        guard division & 0x8000 == 0, division > 0 else { throw ImportError.unsupportedDivision }
        let filePPQ = division
        p = 8 + u32(4)   // skip to first chunk after the header body

        struct Open { var startTick: Int; var velocity: Float }
        var open: [Int: Open] = [:]        // key = channel*128 + pitch
        var out: [(channel: Int, note: Note)] = []

        @inline(__always) func mapTicks(_ fileTick: Int) -> Int {
            // Scale the file's PPQ to Note.ticksPerQuarter (round to nearest).
            (fileTick * Note.ticksPerQuarter + filePPQ / 2) / filePPQ
        }

        while p + 8 <= data.count {
            let isTrack = data[p] == 0x4D && data[p+1] == 0x54 && data[p+2] == 0x72 && data[p+3] == 0x6B
            let len = u32(p + 4)
            let bodyStart = p + 8
            let bodyEnd = min(data.count, bodyStart + len)
            p = bodyEnd
            guard isTrack else { continue }   // skip unknown chunks

            var i = bodyStart
            var absTick = 0
            var running: UInt8 = 0

            func readVLQ() -> Int {
                var value = 0
                while i < bodyEnd {
                    let b = data[i]; i += 1
                    value = (value << 7) | Int(b & 0x7F)
                    if b & 0x80 == 0 { break }
                }
                return value
            }

            while i < bodyEnd {
                absTick += readVLQ()
                guard i < bodyEnd else { break }
                var status = data[i]
                if status & 0x80 != 0 { i += 1 } else { status = running }   // running status
                if status & 0x80 != 0 { running = status }

                let hi = status & 0xF0
                let chan = Int(status & 0x0F)

                switch hi {
                case 0x80, 0x90:                      // note off / note on
                    guard i + 1 < bodyEnd else { i = bodyEnd; break }
                    let pitch = Int(data[i]); let vel = Int(data[i + 1]); i += 2
                    let key = chan * 128 + pitch
                    let isOn = (hi == 0x90 && vel > 0)
                    if isOn {
                        open[key] = Open(startTick: absTick, velocity: Float(vel) / 127.0)
                    } else if let o = open.removeValue(forKey: key) {
                        let startT = mapTicks(o.startTick)
                        let lenT = max(1, mapTicks(absTick) - startT)
                        out.append((channel: chan,
                                    note: Note(pitch: pitch, startTick: startT,
                                               lengthTicks: lenT, velocity: o.velocity)))
                    }
                case 0xA0, 0xB0, 0xE0:                 // 2-data-byte channel msgs — skip
                    i += 2
                case 0xC0, 0xD0:                       // 1-data-byte channel msgs — skip
                    i += 1
                case 0xF0:                             // meta / sysex
                    if status == 0xFF {                // meta: type + VLQ len + bytes
                        guard i < bodyEnd else { break }
                        i += 1                         // meta type
                        let mlen = readVLQ()
                        i = min(bodyEnd, i + mlen)
                    } else {                           // sysex: VLQ len + bytes
                        let slen = readVLQ()
                        i = min(bodyEnd, i + slen)
                    }
                default:
                    i = bodyEnd                          // unknown — bail this track
                }
            }
        }

        return out
    }

    public static func notes(from data: Data, includeChannel10: Bool = false) throws -> [Note] {
        try notes(from: [UInt8](data), includeChannel10: includeChannel10)
    }

    // MARK: - Drum grid (GM channel 10 → BeatPlayer's 8-track / 16-step grid)

    /// Echoel drum-track index for a General-MIDI percussion note, or nil if it has
    /// no slot (it folds into "Perc"). Tracks: 0 Kick · 1 Snare · 2 ClosedHat ·
    /// 3 OpenHat · 4 Clap · 5 Perc · (6 Bass / 7 LeadFX are not GM drums).
    public static func drumTrack(forGM note: Int) -> Int {
        switch note {
        case 35, 36:            return 0   // bass drums → Kick
        case 38, 40, 37:        return 1   // snares + side stick → Snare
        case 42, 44:            return 2   // closed / pedal hat → ClosedHat
        case 46:                return 3   // open hat → OpenHat
        case 39:                return 4   // hand clap → Clap
        default:                return 5   // toms / cymbals / aux perc → Perc
        }
    }

    /// Build BeatPlayer's (steps, accents) grid from a SMF's channel-10 notes,
    /// folded onto the first 16-step bar. `trackCount`/`stepCount` size the grid.
    /// Accents mark hard hits (velocity ≥ 0.85). Empty (no ch10 hits) → all-false.
    public static func drumGrid(from data: [UInt8], trackCount: Int = 8, stepCount: Int = 16)
        throws -> (steps: [[Bool]], accents: [[Bool]]) {
        var steps = [[Bool]](repeating: [Bool](repeating: false, count: stepCount), count: trackCount)
        var accents = [[Bool]](repeating: [Bool](repeating: false, count: stepCount), count: trackCount)
        for (channel, note) in try channelNotes(from: data) where channel == 9 {
            let step = note.startStep
            guard step >= 0, step < stepCount else { continue }   // first bar only
            let track = drumTrack(forGM: note.pitch)
            guard track >= 0, track < trackCount else { continue }
            steps[track][step] = true
            if note.velocity >= 0.85 { accents[track][step] = true }
        }
        return (steps, accents)
    }

    public static func drumGrid(from data: Data, trackCount: Int = 8, stepCount: Int = 16)
        throws -> (steps: [[Bool]], accents: [[Bool]]) {
        try drumGrid(from: [UInt8](data), trackCount: trackCount, stepCount: stepCount)
    }
}
