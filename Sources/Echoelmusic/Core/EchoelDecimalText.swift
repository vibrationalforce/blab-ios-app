//
//  EchoelDecimalText.swift
//  Echoelmusic — Core
//
//  Every adjustable number in this app is read and typed through ONE control
//  (`EchoelValueField` + `EchoelNumberPad`, 58 call sites, the app-wide law in CLAUDE.md).
//  Both of them printed `String(format: "%.Nf", …)`, which is C's `printf` and therefore
//  hard-wired to a decimal POINT regardless of who is holding the phone. A German,
//  French, Spanish, Italian, Brazilian, Russian or Turkish player — most of continental
//  Europe and most of South America — reads "0.50" where their entire life writes "0,50".
//
//  ⚠️ THIS WAS NEVER A FUNCTIONAL BUG, and saying otherwise would overstate the slice.
//  The keypad's own decimal key emitted "." and `Double("0.50")` accepts ".", so the two
//  halves agreed and entry always worked. What was broken is READING, which is the whole
//  point of a science-first numeric display: a number you have to mentally transliterate
//  is a number you can misread on stage.
//
//  WHY A HELPER AND NOT `NumberFormatter`:
//  · Grouping. `NumberFormatter` groups by default, so 1234.5 would print "1.234,50" in
//    German — inside a field you can type into, whose buffer is ungrouped. The readout and
//    the buffer would disagree mid-edit and the parse would reject the grouped form. Every
//    range here is small (Hz, BPM, ms, dB, semitones); grouping buys nothing and costs a
//    parse hazard. This helper cannot group, by construction.
//  · Lifecycle. `NumberFormatter` is not `Sendable` and is expensive per instantiation, so
//    a correct use needs a cached, isolated instance. A `printf` plus one separator swap
//    needs neither and is deterministic.
//
//  WHAT IT DELIBERATELY DOES NOT DO: it does not localize the MINUS sign. Several locales
//  print U+2212; the keypad's sign key writes ASCII "-" and `Double()` parses only ASCII
//  "-". A prettier minus that fails to parse is exactly the class of bug this file exists
//  to prevent, so the sign stays ASCII and that is a decision, not an oversight.
//

import Foundation

/// Locale-aware fixed-point number text for the one parameter control.
///
/// Formatting and parsing are deliberately inverse: `string(_:decimals:)` produces what the
/// player reads, `ascii(_:)` turns what they typed back into something `Double.init` accepts.
public enum EchoelDecimalText {

    /// The separator this locale reads a decimal fraction with ("." · "," · "٫" · …).
    ///
    /// Falls back to "." rather than trapping: `Locale.decimalSeparator` is optional, and a
    /// missing separator must degrade to the previous behaviour, never to a crash on stage.
    public static func separator(_ locale: Locale = .current) -> String {
        locale.decimalSeparator ?? "."
    }

    /// Fixed-point, `decimals` places, no grouping, locale separator.
    ///
    /// Non-finite input is passed through as whatever `printf` makes of it ("nan", "inf"):
    /// that is the behaviour every call site had before this file existed, it carries no
    /// separator to swap, and inventing a nicer rendering here would hide a NaN that the
    /// caller should be guarding at its own boundary (`FloatingPointClamp`).
    public static func string(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        localized(String(format: "%.\(max(0, decimals))f", value), locale)
    }

    /// Swap an ASCII-point string into the locale's reading. For display only.
    ///
    /// The keypad keeps its typed buffer in ASCII and maps it through here at draw time, so
    /// `Double(buffer)` and `buffer.contains(".")` stay literally true and `deleteLast()`
    /// can never strand half of a multi-scalar separator.
    public static func localized(_ asciiPoint: String, _ locale: Locale = .current) -> String {
        let sep = separator(locale)
        guard sep != "." else { return asciiPoint }
        return asciiPoint.replacingOccurrences(of: ".", with: sep)
    }

    /// Normalize anything a human could have typed or pasted into an ASCII-point string.
    ///
    /// Accepts the locale separator AND "," AND "." unconditionally, on purpose: a value can
    /// arrive from a hardware keyboard, a paste, or a file written on a differently-configured
    /// device, and none of those are obliged to match `Locale.current`. Being permissive on
    /// the way in costs nothing — "." is never ambiguous here because grouping never happens.
    public static func ascii(_ typed: String, _ locale: Locale = .current) -> String {
        var s = typed
        let sep = separator(locale)
        if sep != "." && sep != "," { s = s.replacingOccurrences(of: sep, with: ".") }
        return s.replacingOccurrences(of: ",", with: ".")
    }
}
