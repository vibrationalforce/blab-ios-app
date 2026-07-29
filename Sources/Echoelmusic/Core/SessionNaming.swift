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
        calendar: Calendar = SessionNaming.fileCalendar,
        place: String = ""
    ) -> String {
        let artistToken = sanitize(artist, fallback: "E~")
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
        calendar: Calendar = SessionNaming.fileCalendar,
        place: String = ""
    ) -> String {
        let base = stem(artist: artist, date: date, key: key, bpm: bpm, a4Hz: a4Hz,
                        calendar: calendar, place: place)
        let partToken = sanitize(part, fallback: "")
        let cleanExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        let withPart = partToken.isEmpty ? base : base + "_" + partToken
        return cleanExt.isEmpty ? withPart : withPart + "." + cleanExt
    }

    /// The place that actually stamps the name: the user's MANUAL override when they
    /// typed one (trimmed), else the auto-resolved GPS locality. Founder 2026-07-14:
    /// "Man kann natürlich auch manuell den Ortsnamen eingeben wenn man Lust hat oder
    /// der Standort nicht funktioniert." Works regardless of the location toggle; the
    /// result is still sanitised downstream by `stem`/`fileName`, so freeform input is
    /// filename-safe.
    public static func effectivePlace(manual: String, resolved: String) -> String {
        let trimmed = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? resolved : trimmed
    }

    // MARK: - Formatting helpers

    /// The calendar every filename is stamped with. **Gregorian on purpose, and this is the
    /// one place the choice is made.**
    ///
    /// ⛔ IT USED TO BE `.current`, and that was a real defect rather than a style point:
    /// `Calendar.current` is the user's PREFERRED calendar, not the world's shared one. In
    /// Thailand the default is Buddhist and in Saudi Arabia it is Islamic Umm al-Qurā, so the
    /// same take exported at the same moment came out as
    ///
    ///     Echoel_2026-07-29_Am_72bpm_A440.mid   (a German performer)
    ///     Echoel_2569-07-29_Am_72bpm_A440.mid   (a Thai performer — Buddhist, year +543)
    ///     Echoel_14XX-XX-XX_Am_72bpm_A440.mid   (a Saudi performer — Umm al-Qurā: a 15th-
    ///                                            century Hijri year, and a different month
    ///                                            and day, since the months are lunar)
    ///
    /// (The Hijri date is deliberately not spelled out. A first draft of this comment quoted a
    /// specific one taken from an audit report; the year was wrong — 1 Muḥarram 1448 falls in
    /// mid-June 2026, so this instant is 1448, not 1447. A fabricated example in a comment that
    /// exists to explain a correctness bug is the same class of defect as the bug. The test
    /// asserts only the century, which is what can be checked without a lunar table.)
    ///
    /// No production caller ever passed the argument, so every shipped filename took the
    /// default. The file header promises a take that "already says … when" when it lands in
    /// Ableton, and `dateStamp`'s own doc promised "sortable and unambiguous worldwide" — that
    /// was the single claim in this file that was false, and false for exactly the users the
    /// naming scheme exists to serve: collaborators comparing files across borders.
    ///
    /// `Calendar(identifier:)` keeps `TimeZone.current`, so the stamped day is still the
    /// performer's LOCAL day — a take at 23:00 in Hamburg is not filed as tomorrow. Localised
    /// dates belong in the UI, where `DateFormatter` already handles them
    /// (`VideoLibraryPanel.title(for:)`); a filename is an interchange token, and interchange
    /// tokens are Gregorian.
    /// ⚠️ `public`, and not by preference: it is the default argument of the PUBLIC `stem` and
    /// `fileName`, and Swift will not let a public signature name an internal declaration
    /// ("static property 'fileCalendar' is internal and cannot be referenced from a default
    /// argument value"). Shipped internal first and the Xcode gate caught it within minutes —
    /// the access-level mismatch CLAUDE.md already lists as a known hard-error pattern, walked
    /// straight into anyway. Keeping the note so the next person moving a constant into a
    /// default argument checks the signature's visibility first.
    public static let fileCalendar = Calendar(identifier: .gregorian)

    /// `yyyy-MM-dd` in the Gregorian calendar — sortable and unambiguous worldwide, which is
    /// only true because of `fileCalendar`; read its note before changing the default.
    static func dateStamp(_ date: Date,
                          calendar: Calendar = SessionNaming.fileCalendar) -> String {
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

    /// Reduce free text to a filename-safe token: keep letters/digits (plus "~",
    /// so the brand mark "E~" survives — founder 2026-07-12: "Es soll am Anfang
    /// ein E~"; "~" is filesystem-safe on APFS and every export target), collapse
    /// everything else to nothing, cap length. Empty result → `fallback`.
    static func sanitize(_ raw: String, fallback: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "~")
        let scalars = raw.unicodeScalars.filter { allowed.contains($0) }
        let token = String(String.UnicodeScalarView(scalars)).prefix(24)
        return token.isEmpty ? fallback : String(token)
    }
}
