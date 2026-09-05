//
//  DMXFixtureFan.swift
//  Echoelmusic — Core
//
//  ONE pure kernel: take the single fixture block both light senders already build, and
//  repeat it across a rig.
//
//  ⭐ WHY THIS EXISTS. Echoel's positioning names Installation · Event · Cinema · Theater,
//  and the light output wrote ONE 4-channel block starting at DMX slot 1 (8 channels in
//  16-bit). Everything past that block was somebody else's problem — and the two protocols
//  failed differently, which is why nobody had noticed:
//
//    · Art-Net sends a SHORT packet, so other fixtures simply hold their last values. The
//      rig looks stuck rather than wrong.
//    · sACN pads to a full 512 slots by specification, so Echoel actively drives every
//      other fixture to ZERO. They go dark and stay dark for as long as it streams.
//
//  The artist's only workaround was re-patching every lamp in the venue onto address 1.
//
//  ⚠️ WHAT THIS IS NOT. It is ADDRESSING, not spatial differentiation. N fixtures receive N
//  IDENTICAL colours, because both DMX arms produce exactly one global colour — the whole
//  rig breathes together. Per-fixture variation needs a producer that exists nowhere in this
//  repo today, and selling this as "the body moves through the room" would be the kind of
//  over-claim `CLAUDE.md` keeps having to retract. The UI copy says "identical".
//
//  ⚠️ IT MUST RUN AFTER THE SLEW, NEVER BEFORE. Both senders rate-limit the dimmer and the
//  colour channels (`FlashGuard`) on the ONE block, and that is what makes the 3 Hz flash
//  ceiling a guarantee rather than a hope. Fanning first would hand the guard N separate
//  histories to smooth — same maths, N times the state, and a bug away from a rig that
//  strobes on every fixture but the first. Fanning last copies an already-safe block.
//
//  Pure value work: no allocation policy, no I/O, no actor. Unit-testable without a socket.
//

import Foundation

public enum DMXFixtureFan {

    /// A DMX universe is 512 slots. Nothing here may produce more, whatever the caller asks.
    public static let universeSlots = 512

    /// Upper bound on the fixture count offered in the UI. Not a protocol limit — 32 blocks
    /// of 8 channels already fills half a universe, and a number field that can ask for 500
    /// invites a value nobody can verify on stage.
    public static let maxFixtures = 32

    /// Repeat `block` `count` times, `spacing` slots apart, clipped to one universe.
    ///
    /// - Parameters:
    ///   - block: the already-slewed channels for ONE fixture. Returned unchanged when
    ///     `count <= 1`, which is the shipped default and makes this a no-op until a player
    ///     says otherwise — the output is byte-identical to before this file existed.
    ///   - count: how many fixtures to address. Clamped to `1...maxFixtures`.
    ///   - spacing: DMX slots between consecutive fixture START addresses. `0` means
    ///     back-to-back — the block's own width — which is how a rig is patched by default.
    ///     A larger value leaves the gap fixtures with a wider footprint occupy; the slots
    ///     in between stay zero, which is the honest thing to send when Echoel does not know
    ///     what lives there.
    /// - Returns: the fanned universe fragment, at most `universeSlots` bytes.
    public static func fanned(_ block: [UInt8], count: Int, spacing: Int) -> [UInt8] {
        guard !block.isEmpty else { return block }
        let fixtures = Swift.min(Swift.max(count, 1), maxFixtures)
        guard fixtures > 1 else { return block }
        // A negative or zero spacing means back-to-back; anything narrower than the block
        // would make fixtures overlap and write each other's channels, so the block width is
        // also the FLOOR rather than merely the default.
        let stride = Swift.max(spacing, block.count)
        let needed = (fixtures - 1) * stride + block.count
        let size = Swift.min(needed, universeSlots)
        var out = [UInt8](repeating: 0, count: size)
        for index in 0..<fixtures {
            let start = index * stride
            guard start < size else { break }
            // The LAST fixture may be clipped by the universe edge rather than dropped: a
            // half-addressed fixture is visible on stage and sends the artist to this
            // setting, whereas a silently missing one reads as a broken lamp.
            let end = Swift.min(start + block.count, size)
            for offset in 0..<(end - start) { out[start + offset] = block[offset] }
        }
        return out
    }
}
