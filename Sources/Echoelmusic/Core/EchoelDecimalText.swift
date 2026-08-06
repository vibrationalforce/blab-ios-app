//
//  EchoelDecimalText.swift
//  Echoelmusic — Core
//
//  Every adjustable number in this app is read and typed through ONE control
//  (`EchoelValueField` + `EchoelNumberPad`, the app-wide law in CLAUDE.md).
//
//  `git grep -c "EchoelValueField(" -- Sources` → 65 matching LINES, but **THREE of them are
//  comments** — this one, `EchoelValueField.swift`'s own `stacksLabel` doc (added by #353e), and
//  `EchoelNumberPad.swift`'s `NumberPadEntry` doc (added by #431). It was 64 / TWO until #431,
//  which is exactly the drift this paragraph predicts: the count moves whenever anyone WRITES
//  about it, and #431's own edition then quoted the stale 64 as its site count.
//  ⛔ THE PARENTHETICAL THAT STOOD HERE SAID "the only comment-line hit in the tree", and #353e
//  falsified it the moment it landed: a doc that quotes the command has to say WHICH hits it
//  subtracts, and "the only" is a claim about the whole tree that any future comment can break.
//  Count the comment hits, do not assume there is one. So: **62** call sites, of which
//  **57** are reachable — the 5 in `PianoRollView`, doorless per CLAUDE.md, are the only
//  unreachable ones. ⛔ Two editions in a row quoted the raw grep output as the call-site
//  count and were off by exactly one, because the line that documents the number is itself
//  matched by the command it documents. `git grep -c` counts lines, not call sites.
//  ⛔ This line first said "58", which was neither number and had no command beside it — in
//  a repo whose CLAUDE.md spends a paragraph on exactly that failure. The command is here so
//  the next reader re-runs it instead of quoting me. It then said "62" and went stale anyway.
//  The RAW LINE COUNT went 64 (at #281) → 66 → 63 → 64, the drop because #132 Slice 6 deleted
//  `PatchEditorView.swift` and its 4 fields, the rise because #353e added a second comment hit:
//  a count can FALL as well as rise, AND it can rise without a single new call site, so "it only
//  ever grows" and "it grew, so someone added a field" are both wrong.
//  Re-run the command, subtract every comment line, and do
//  not quote any of those numbers. Nothing asserts it, so it drifts silently — the count is
//  context for the law, not the law itself.
//
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
//  WHY A HELPER AND NOT A SYSTEM FORMATTER — and ⛔ THE FIRST VERSION OF THIS PARAGRAPH
//  ARGUED AGAINST A STRAWMAN. It said "`NumberFormatter` groups by DEFAULT, so 1234.5 would
//  print 1.234,50". That is false: a fresh `NumberFormatter()` has `numberStyle == .none`,
//  for which `usesGroupingSeparator` is already `false`. Grouping arrives only if you opt
//  into `.decimal`, and one property call turns it off. The reason that DOES survive is the
//  lifecycle one: `NumberFormatter` is not `Sendable` and is expensive per instantiation, so
//  a correct use needs a cached isolated instance, where a `printf` plus one separator swap
//  needs neither and is deterministic.
//
//  The comparison the first version never made, and the one an informed reader will reach
//  for, is `FloatingPointFormatStyle`:
//      value.formatted(.number.precision(.fractionLength(n)).grouping(.never).locale(loc))
//  It is a `Sendable` value type (no lifecycle problem), cannot group when told not to, and
//  additionally localizes the DIGITS (see the next paragraph). It is a genuinely better
//  answer for a fully-localized app and this file does not foreclose it — swapping the two
//  functions below for it is a contained change. It was not taken here because it would
//  change ar_EG output on the same commit that has no way to verify it, which is a Council
//  question, not a slice detail.
//
//  ⚠️ WHAT THIS DOES NOT LOCALIZE — DIGITS. `localized` swaps only the separator, so ar_EG
//  gets "1٫5": Western digits with an Arabic separator, which nobody writes. The keypad
//  compounds it — the decimal key shows U+066B while the digit keys show ASCII. So do not
//  read the U+066B handling below as "Arabic is supported"; it is a separator swap, not a
//  numbering system. Arabic is not a shipping market and this is stated rather than fixed.
//
//  WHAT IT DELIBERATELY DOES NOT DO: it does not localize the MINUS sign for OUTPUT.
//  Several locales print U+2212; the keypad's sign key writes ASCII "-" and `Double()`
//  parses only ASCII "-". A prettier minus that fails to parse is exactly the class of bug
//  this file exists to prevent, so the sign stays ASCII on the way out — and, since the
//  reviewer pointed out the asymmetry, U+2212 IS normalized on the way IN, so the argument
//  above is true in both directions instead of only the one it was written about.
//

import Foundation

//  WHAT STILL PRINTS A POINT — and this paragraph is now a RECORD, not a to-do list. It was
//  a to-do list for exactly one commit; #267 finished the sweep, and leaving it in the
//  imperative would have handed the next reader work that is already done.
//
//  ⛔ AND THE GREP IT WAS BUILT ON WAS THE WRONG GREP. `String(format: "%\.[0-9]*f'` only
//  matches a LITERAL format string, so it could not see `String(format: cond ? "%.1f" :
//  "%.0f", x)` — which is precisely how `BioStripView`'s RMSSD line survived a sweep that
//  converted the line directly below it, and how five more display sites survived
//  (`LiveColaboView`'s visible coherence three lines under its converted VoiceOver label,
//  two in `MeditationView`, one in `BreathGuideView`, and `EchoelFXView.signed`). **Use
//  `git grep -n 'String(format:' -- Sources/` — the narrow pattern is not sufficient.**
//
//  As of #267 no user-visible readout formats its own decimals. What deliberately still
//  uses `printf` and must keep an ASCII point:
//  · logs / diagnostics / breadcrumbs — `EchoelCrashLog`, `CameraCapture`, `CameraAnalyzer`,
//    `VideoRecorder`, `AudioConfiguration`, `SingleExport`, `RenderGapDetector`,
//    `ExternalDisplayScene`, the `EchoelStudioView` generate-breadcrumb.
//  · FILENAMES — `SessionNaming`. A comma there is corruption, not a nicer number, and
//    `Tests/CISmoke/FilenameNumbersStayASCIITests` pins it against this file.
//  · `%d` forms (bar.beat.sixteenth, mm:ss) — integers carry no decimal separator.
//  · `Precision.two` (`DSP/TuningReference.swift`) and `HRVCoherence.headline` — the first
//    is test-only, the second has zero consumers. Both are documented where they live.
//

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
        localized(String(format: "%.\(Swift.max(0, decimals))f", value), locale)
    }

    /// ⛔ THE OVERLOAD THAT WAS MISSING, AND ITS ABSENCE BROKE BOTH BLOCKING GATES.
    ///
    /// `String(format: "%.1f", x)` accepts a `Float` — C varargs promote it silently — so the
    /// 23 readouts this replaced compiled for years while typed `Float`. Swift does NOT widen
    /// `Float` to `Double` at a call site, so the first sweep produced 12 compile errors in
    /// one commit. This repo's bio bus is `Float` end to end (`BioSampleFrame.heartRateBPM`,
    /// `.hrvNormalized`, `.breathRate`, `.coherence`), as are the meters and
    /// `BioSessionSummary`, so the next call site would have hit it again.
    ///
    /// WHY AN OVERLOAD AND NOT `Double(x)` AT EACH CALL: wrapping per site is a rule a human
    /// has to remember, and the failure is a red gate every time they don't. Here it is the
    /// type system's job. The concrete `Double` overload above still wins for literals and
    /// for `.nan`/`.infinity`, so nothing becomes ambiguous.
    ///
    /// `Double(x)` from a `Float` is exact (widening), and it is the same promotion `printf`
    /// performed — so every converted readout renders byte-identically in an ASCII locale.
    public static func string<T: BinaryFloatingPoint>(_ value: T, decimals: Int,
                                                      locale: Locale = .current) -> String {
        string(Double(value), decimals: decimals, locale: locale)
    }

    /// Swap an ASCII-point string into the locale's reading. For display only.
    ///
    /// The keypad keeps its typed buffer in ASCII and maps it through here at draw time, so
    /// `Double(buffer)` and `buffer.contains(".")` stay literally true.
    ///
    /// ⛔ The first version of this line also claimed `deleteLast()` "can never strand half of
    /// a multi-scalar separator". Wrong mechanism, right conclusion: `String.removeLast()`
    /// removes one extended grapheme CLUSTER, so a multi-scalar separator would be deleted
    /// whole anyway. The real hazards of a localized buffer are `buffer.contains(".")`
    /// silently returning false and the 9-character cap counting the wrong units.
    public static func localized(_ asciiPoint: String, _ locale: Locale = .current) -> String {
        let sep = separator(locale)
        guard sep != "." else { return asciiPoint }
        return asciiPoint.replacingOccurrences(of: ".", with: sep)
    }

    /// Normalize a typed number into an ASCII-point string that `Double.init` accepts.
    ///
    /// ⛔ THE FIRST DOCSTRING HERE OVERSOLD THIS TWICE. Both halves are corrected in place,
    /// because a `public` helper's comment is what the NEXT call site will trust.
    ///
    /// 1. It said a value "can arrive from a hardware keyboard, a paste, or a file written on
    ///    a differently-configured device". None of those paths exist: the app has no numeric
    ///    `TextField` anywhere, and this function's ONLY production caller is
    ///    `EchoelNumberPad.pendingValue`, whose argument is a buffer the pad itself keeps in
    ///    ASCII. So every branch below is a no-op on every input that exists today —
    ///    including the U+066B branch, which the commit that added it wrongly advertised as
    ///    having "widened" the parse. These are guards for a future caller, not live
    ///    behaviour, and the previous hand-rolled `","→"."` swap was equally dead.
    ///
    /// 2. It said "'.' is never ambiguous here because grouping never happens" — true of ".",
    ///    and aimed at the wrong character. **"," IS ambiguous**: `ascii("1,234", en_US)`
    ///    yields "1.234" → 1.234, where en_US wrote 1,234 meaning ONE THOUSAND. That cannot
    ///    happen from the keypad, but it is precisely what a future paste-into-field would
    ///    hand this function — silently, and off by 1000×. **Anyone wiring a paste or a
    ///    preset-import path to this helper must strip grouping first; this function will not
    ///    do it and cannot detect it.**
    public static func ascii(_ typed: String, _ locale: Locale = .current) -> String {
        var s = typed
        let sep = separator(locale)
        if sep != "." && sep != "," { s = s.replacingOccurrences(of: sep, with: ".") }
        // U+2212 MINUS SIGN. The header argues at length that a non-ASCII minus renders fine
        // and then fails to parse; defending only the OUTPUT side left that argument half
        // made. `Double.init` rejects "−12.5", and `pendingValue` would silently fall back to
        // the initial value — a committed edit that looks accepted and changes nothing.
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        return s.replacingOccurrences(of: ",", with: ".")
    }
}
