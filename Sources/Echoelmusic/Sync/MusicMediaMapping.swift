//
//  MusicMediaMapping.swift
//  Echoelmusic — EchoelSync
//
//  The runtime of the Signal Router's music→media converters: maps a MusicalFrame
//  to LIGHT (DMX RGB via SpectralColor) and to SPATIAL (ADM-OSC object position via
//  pitch→azimuth/elevation). This is "shape light & space by musical parameters"
//  made real — the DMMW differentiator. Pure value-in/value-out (no socket), so it
//  unit-tests like the senders' bio kernels. The Art-Net / sACN / ADM-OSC senders
//  call these when music is sounding and fall back to their bio kernels otherwise
//  (bio stays the co-modulator, never bolted on). See docs/dev/DMMW_ARCHITECTURE.md.
//

#if canImport(Network)
import Foundation

public enum MusicMediaMap {

    // MARK: Music → Light (DMX)

    /// The dimmer (luminance) unit value for a musical frame — brighter when the
    /// music is louder. Matches the structure of `ArtNetSender.dimmerUnit(for:)`.
    public static func dimmerUnit(forMusic f: MusicalFrame) -> Float {
        clampUnit(0.3 + 0.7 * Float(f.masterLevel))
    }

    /// Maps a musical frame to a 4-param fixture (dimmer + R + G + B), colour from the
    /// sounding CHORD via `SpectralColor.physicalColor(forChord:)` — octave-transposed
    /// into the visible band, CIE 1931, mixed amplitude-weighted in OKLab (anti-white) —
    /// so the pitch/chord you play IS the colour, and the lamp agrees with the note grid.
    /// 8-bit = 4 channels; 16-bit = 8 (coarse/fine pairs), matching
    /// `ArtNetSender.dmxChannels(for:resolution:)`.
    ///
    /// (This doc said "OKLab hue circle" until 2026-07-28. That was this call site's
    /// ORIGINAL mapper, left behind when the call switched to the physical one on
    /// 2026-07-27; the hue circle has since been deleted entirely.)
    public static func dmxChannels(forMusic f: MusicalFrame,
                                   resolution: ArtNetSender.DMXResolution) -> [UInt8] {
        let rgb = SpectralColor.physicalColor(forChord: f.notes.map { (hz: $0.frequencyHz, amplitude: $0.amplitude) })
        let dim = dimmerUnit(forMusic: f)
        let r = Float(rgb.r), g = Float(rgb.g), b = Float(rgb.b)
        switch resolution {
        case .eightBit:  return [byte(dim), byte(r), byte(g), byte(b)]
        case .sixteenBit: return word(dim) + word(r) + word(g) + word(b)
        }
    }

    // MARK: Music → Spatial (ADM-OSC)

    /// Maps a musical frame to ADM-OSC (address, value) pairs for object `n`:
    ///   loudest note's pitch-class → azimuth (where it sits around you)
    ///   loudest note's height      → elevation (higher pitch lifts it)
    ///   master level               → distance (louder pulls it close) + gain
    /// Pure; clamped to ADM-OSC v1.0 ranges. Mirrors `ADMOSCSender.admMessages(for:object:)`.
    public static func admMessages(forMusic f: MusicalFrame, object n: Int) -> [(String, Float)] {
        let idx = Swift.max(1, n)
        let prefix = "/adm/obj/\(idx)"
        let loudest = f.notes.max(by: { $0.amplitude < $1.amplitude })
        let hz = loudest?.frequencyHz ?? 0
        // pitch-class [0..12) → azimuth [-180..180]
        let pc = SpectralColor.pitchClass(ofFrequency: hz)            // 0..<12
        let azimuth = clamp(Float(pc / 12.0 * 360.0 - 180.0), -180, 180)
        // pitch height (~A1…A7) → elevation [0..60] (upper hemisphere)
        let height = hz > 0 ? clampUnit(Float(log2(hz / 55.0) / 6.0)) : 0.5
        let elevation = clamp(height * 60, -90, 90)
        let master = Float(f.masterLevel)
        let distance = clamp(1 - master, 0, 1)
        let gain = clamp(0.3 + master * 0.7, 0, 1)
        return [
            ("\(prefix)/position/azimuth", azimuth),
            ("\(prefix)/position/elevation", elevation),
            ("\(prefix)/position/distance", distance),
            ("\(prefix)/gain", gain)
        ]
    }

    // MARK: Helpers (match ArtNetSender's byte/word encoding)

    // NaN-safe (mirrors ArtNetSender): a non-finite channel would trap byte()/word()
    // in the UInt8/UInt16 conversion below. Map non-finite → 0.
    private static func clampUnit(_ x: Float) -> Float { Swift.min(Swift.max(x.isFinite ? x : 0, 0), 1) }
    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(v, lo), hi) }
    private static func byte(_ unit: Float) -> UInt8 { UInt8(clampUnit(unit) * 255) }
    private static func word(_ unit: Float) -> [UInt8] {
        let v = UInt16(clampUnit(unit) * 65535)
        return [UInt8(v >> 8), UInt8(v & 0xFF)]
    }
}
#endif
