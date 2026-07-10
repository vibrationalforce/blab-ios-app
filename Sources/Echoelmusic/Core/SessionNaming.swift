// SessionNaming.swift
// Echoel — the compact, automatic name stamped on every session and export file:
// artist · date · key (Tonart) · tempo · concert pitch (Kammerton). So a take
// that lands in Ableton / FL Studio already says who made it, when, in what key,
// at what BPM and tuning — no manual renaming.
//
//   Echoel_2026-06-12_Cm_124bpm_A440
//   Echoel_2026-06-12_Cm_124bpm_A440_Melody-4bar.mid
//
// Pure value logic (Foundation only) so it is fully unit-tested and reused by the
// session store and the MIDI exporter alike.

import Foundation

/// Builds the short, filesystem-safe session/export name from the musical
/// context. All formatting (date, trimmed tempo, integer-or-decimal Kammerton)
/// is centralised here so the session label and the export filename never drift.
public enum SessionNaming {

    /// The descriptive stem, e.g. `Echoel_2026-06-12_Cm_124bpm_A440` — or, with a
    /// place token (E2, opt-in on-device location), `Echoel_2026-07-10_Hamburg_Am_72bpm_A440`.
    /// - artist:  free-text username (sanitised to a filename-safe token).
    /// - key:     short Tonart tag (`MusicalKey.shortName`), e.g. "Cm".
    /// - bpm:     tempo; whole numbers print clean ("124"), else up to 2 dp.
    /// - a4Hz:    Kammerton; whole numbers print as "A440", else "A442.5".
    /// - place:   optional locality token after the date ("Hamburg"). Sanitised;
    ///            empty or unsanitisable → omitted entirely (no fallback token).
    public static func stem(
        artist: String,
        date: Date,
        key: String,
        bpm: Double,
        a4Hz: Double,
        calendar: Calendar = .current,
        place: String = ""
    ) -> String {
        let artistToken = sanitize(artist, fallback: "Echoel")
        let keyToken = sanitize(key, fallback: "Key")
        let placeToken = sanitize(place, fallback: "")
        var parts = [artistToken, dateStamp(date, calendar: calendar)]
        if !placeToken.isEmpty { parts.append(placeToken) }
        parts.append(contentsOf: [keyToken, "\(trimmed(bpm))bpm", "A\(trimmed(a4Hz))"])
        return parts.joined(separator: "_")
    }

    /// A full export filename: the stem, an optional part label ("Drums",
    /// "Melody-4bar") and an extension. e.g.
    /// `Echoel_2026-06-12_Cm_124bpm_A440_Drums.mid`.
    public static func fileName(
        artist: String,
        date: Date,
        key: String,
        bpm: Double,
        a4Hz: Double,
        part: String,
        ext: String,
        calendar: Calendar = .current,
        place: String = ""
    ) -> String {
        let base = stem(artist: artist, date: date, key: key, bpm: bpm, a4Hz: a4Hz,
                        calendar: calendar, place: place)
        let partToken = sanitize(part, fallback: "")
        let cleanExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        let withPart = partToken.isEmpty ? base : base + "_" + partToken
        return cleanExt.isEmpty ? withPart : withPart + "." + cleanExt
    }

    // MARK: - Formatting helpers

    /// `yyyy-MM-dd` — sortable and unambiguous worldwide.
    static func dateStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, d = c.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// A number with up to 2 decimals, trailing zeros (and a trailing dot)
    /// trimmed: 124.0 → "124", 123.50 → "123.5", 442.42 → "442.42".
    static func trimmed(_ value: Double) -> String {
        var s = String(format: "%.2f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// Reduce free text to a filename-safe token: keep letters/digits, collapse
    /// everything else to nothing, cap length. Empty result → `fallback`.
    static func sanitize(_ raw: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = raw.unicodeScalars.filter { allowed.contains($0) }
        let token = String(String.UnicodeScalarView(scalars)).prefix(24)
        return token.isEmpty ? fallback : String(token)
    }
}
