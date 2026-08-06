//
//  EchoelNumberPad.swift
//  Echoelmusic — Studio
//
//  The ONE numeric keypad, used by every `EchoelValueField` (so entry is identical
//  app-wide — "alles angleichen"). The iOS system decimal pad can't carry a sign key,
//  so we present our own: a clean grid with − and + at the BOTTOM-LEFT, where − makes the
//  value negative and + makes it positive (the logical way to enter e.g. Transpose −5).
//  Fields with a non-negative range (Hz, BPM, dimensionless) show − disabled.
//
//  Design: Website-CI tokens, ≥44 pt keys, ≤8 px radius, no glow/scale. Pure UI.
//

import Foundation

/// The keypad's one entry rule, kept pure (and outside the SwiftUI guard) so the blocking
/// bundle can measure it — same shape as `ScrubPrecision` next door.
///
/// THE DEFECT IT CLOSES (#431). `commit()` snaps to the field's `10^-decimals` grid, and
/// nothing stopped the buffer from growing past it. On a two-place row a player typed
/// `0.375`, READ `0.375` in the 30 pt readout, tapped OK and got `0.38`. The readout was not
/// a preview of the commit; it was a promise the commit did not keep. Reach, paren-matched over
/// `Sources/` with whole-line comments EXCLUDED: **62 construction sites — 40 pass `decimals: 2`,
/// 11 pass `0`, 10 take the 4-place default, and 1 forwards** (`EchoelFXView.field`, itself
/// `decimals: Int = 2`). Three of those 62 render many rows each — `field` here, `param` and
/// `knob` in `EchoelStudioView` (both already inside the 10 defaults). The `decimals: 0` rows
/// were never exposed: their separator key is disabled by `allowsDecimal`, so no `.` can enter
/// those buffers and the fraction cap never applies.
///
/// ⛔ THE FIRST VERSION SAID "64 sites", AND 64 IS THE RAW `git grep -c` LINE COUNT — from
/// BEFORE this comment added a third prose hit to it. That is the third edition of this repo to
/// quote the line count as the site count, in a tree where `Core/EchoelDecimalText.swift` spends
/// five lines saying the command counts LINES and that a doc quoting it must name WHICH comment
/// hits it subtracts. Two further tells were in the same sentence and I missed both: the
/// breakdown summed to 61, one short of its own total, and "plus the two forwarding helpers"
/// double-counted rows already inside the 40/11/10 split. **Lesson, distinct from the usual
/// stale-number one: the METHOD named in a doc is a claim too. Mine said "paren-matched" while
/// the matcher swept comment lines in, so the sentence described a procedure that yields 62 and
/// reported 64 — re-running it is what falsified it, not re-reading it.**
///
/// ⭐ WHY THE REFUSAL STOPS AT THE FRACTION AND DOES **NOT** EXTEND TO THE RANGE. `clamped`
/// can also move a committed number away from the readout (type `999` on a `0…1` row, get
/// `1.0`), and treating that the same way would be wrong, not merely bigger. A fraction digit
/// past the grid can never be rescued by another keystroke — no continuation of `0.375` is
/// representable at two places. An out-of-range PREFIX is the normal middle of typing a valid
/// number: `8` is outside `20…18000` on the way to `800`. So the pad refuses what is already
/// unreachable and keeps accepting what is merely incomplete. The clamp stays, deliberately.
///
/// ⚠️ THE TRADE THIS MAKES, stated because it changes a shipped number. Refusing the keystroke
/// TRUNCATES where the snap used to ROUND, and the cost is bigger than the worked example above
/// suggests: `0.375` is the TIE, where truncating and rounding both lose 0.005. The honest worst
/// case is `0.379` — it used to commit `0.38` (error 0.001) and now commits `0.37` (error 0.009).
/// **Maximum quantisation error therefore DOUBLES, from half a grid unit to just under a whole
/// one.** Accepted on the repo's standing rule that a control may not show one number and store
/// a different one (#135, #416, #427): the old error was smaller and INVISIBLE, the new one is
/// on screen and one keystroke from being fixed. Quoting only `0.375` would have been the
/// flattering half of the measurement.
enum NumberPadEntry {

    /// The overflow cap that was already here — a fat-fingered run must not overflow the field.
    /// Named so the guard and its test cannot drift apart.
    ///
    /// ⚠️ It is enforced in `acceptsDigit` ONLY, so `appendDecimal` and `setSign` can still push
    /// the buffer to 11 characters (`-` + 9 digits + `.`). That hole predates #431 — the old
    /// `guard buffer.count < 9` lived in `append` too — and it cannot affect the grid, which
    /// `acceptsDigit` measures from the separator rather than from the total length.
    static let maxLength = 9

    /// Whether one more digit may join `buffer` on a field that displays `decimals` places.
    ///
    /// Digits BEFORE the separator are unrestricted (bounded only by `maxLength`): `decimals`
    /// says how fine the grid is, never how large the number may be. Only the fraction is
    /// capped, because only the fraction is what the commit would silently round away.
    ///
    /// ⛔ The first version took `maxLength` as a defaulted parameter. No caller and no test ever
    /// passed a second value, so it was speculative generality — and it was also the one
    /// construct in this slice with no precedent in `Sources/` (every `= OwnType.staticMember`
    /// here is a property initialiser, never a default argument). Both reasons point the same
    /// way: read the static.
    static func acceptsDigit(after buffer: String, decimals: Int) -> Bool {
        guard buffer.count < maxLength else { return false }
        guard let separator = buffer.firstIndex(of: ".") else { return true }
        let typed = buffer.distance(from: buffer.index(after: separator), to: buffer.endIndex)
        // `max(0,)` and not a precondition: a negative `decimals` is nonsense a caller could
        // still pass, and the safe reading of it is "no fraction at all", not a crash.
        return typed < Swift.max(0, decimals)
    }
}

#if canImport(SwiftUI)
import SwiftUI

struct EchoelNumberPad: View {
    let title: String
    let initial: Double
    let decimals: Int
    let unit: String
    let range: ClosedRange<Double>
    /// Called with the committed, range-clamped value when the user taps OK.
    let onCommit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The literal typed string. Empty → the current value shows as a dimmed preview and
    /// the first keystroke starts a fresh number.
    @State private var buffer = ""

    private var allowsNegative: Bool { range.lowerBound < 0 }
    private var allowsDecimal: Bool { decimals > 0 }

    /// What the field will become if committed now (buffer if it parses, else the initial).
    ///
    /// ⛔ THIS COMMENT CLAIMED THE PARSE "GOT WIDER" AND CONTRADICTED THE ONE 50 LINES BELOW.
    /// It said the old hand-rolled `","→"."` swap "silently dropped on the floor" a separator
    /// that is neither "." nor ",". Nothing was ever dropped: the buffer is ASCII throughout
    /// (see `displayString`), so the old comma branch was already unreachable and the new
    /// U+066B branch is equally unreachable. `EchoelDecimalText.ascii` is a better-documented
    /// guard for a FUTURE caller, not a widening of live behaviour — and both statements
    /// could not be true at once, which is how the contradiction was found.
    private var pendingValue: Double {
        let cleaned = EchoelDecimalText.ascii(buffer)
        if cleaned.isEmpty || cleaned == "-" || cleaned == "." || cleaned == "-." {
            return initial
        }
        return Double(cleaned) ?? initial
    }

    private var clamped: Double {
        Swift.min(Swift.max(pendingValue, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            grid
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EchoelTheme.bg)
    }

    // MARK: - Header (label + live value + range)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(EchoelTheme.font(13))
                .foregroundStyle(EchoelTheme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayString)
                    .font(EchoelTheme.font(30, .semibold).monospacedDigit())
                    .foregroundStyle(buffer.isEmpty ? EchoelTheme.dim : EchoelTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty {
                    Text(unit)
                        .font(EchoelTheme.font(15))
                        .foregroundStyle(EchoelTheme.dim)
                }
                Spacer(minLength: 0)
            }
            Text("Range \(fmt(range.lowerBound))–\(fmt(range.upperBound))\(unit.isEmpty ? "" : " " + unit)")
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The big readout: the typed buffer if any, otherwise the current value (dimmed).
    ///
    /// The buffer is mapped to the locale's separator for DISPLAY ONLY. It is stored in
    /// ASCII throughout (see `appendDecimal`), which is what keeps `Double(cleaned)`,
    /// `buffer.contains(".")` and `deleteLast()` literally correct — a buffer holding a
    /// multi-scalar separator would let `removeLast()` strand half a character.
    private var displayString: String {
        buffer.isEmpty ? fmt(initial) : EchoelDecimalText.localized(buffer)
    }

    // MARK: - Keypad grid

    private var grid: some View {
        // 7 8 9 / 4 5 6 / 1 2 3 / − 0 ⌫ / + . OK
        // − and + sit in the bottom-LEFT column (founder ask), OK is prominent.
        VStack(spacing: 10) {
            HStack(spacing: 10) { digit("7"); digit("8"); digit("9") }
            HStack(spacing: 10) { digit("4"); digit("5"); digit("6") }
            HStack(spacing: 10) { digit("1"); digit("2"); digit("3") }
            HStack(spacing: 10) {
                signKey(negative: true)
                digit("0")
                deleteKey
            }
            HStack(spacing: 10) {
                signKey(negative: false)
                decimalKey
                okKey
            }
        }
    }

    private func digit(_ d: String) -> some View {
        keyButton(action: { append(d) }) {
            Text(d).font(EchoelTheme.font(22)).foregroundStyle(EchoelTheme.text)
        }
    }

    /// − (negative) / + (positive): set the sign of the value being entered. − is disabled
    /// where the range can't go below zero. This is the founder's "Vorzeichen unten links".
    private func signKey(negative: Bool) -> some View {
        let enabled = negative ? allowsNegative : true
        return keyButton(action: { setSign(negative: negative) }, enabled: enabled) {
            Image(systemName: negative ? "minus" : "plus")
                .font(EchoelTheme.font(20, .semibold))
                .foregroundStyle(enabled ? EchoelTheme.text : EchoelTheme.dim.opacity(0.4))
        }
    }

    /// The key is LABELLED in the reader's locale ("," in German) while what it appends
    /// stays ASCII ".". Label and buffer diverging is deliberate and is the whole trick: a
    /// German player must not have to press a key marked "." to type the number they read
    /// as "0,50", and the parser must not have to guess.
    private var decimalKey: some View {
        keyButton(action: { appendDecimal() }, enabled: allowsDecimal) {
            Text(EchoelDecimalText.separator()).font(EchoelTheme.font(22))
                .foregroundStyle(allowsDecimal ? EchoelTheme.text : EchoelTheme.dim.opacity(0.4))
        }
        // A bare separator glyph is announced by VoiceOver as its punctuation name, or —
        // for U+066B — often not at all. Name the key by what it does.
        //
        // ⚠️ AND IT IS IN `Localizable.xcstrings` (de: "Dezimaltrennzeichen"), which the first
        // version was not. A string LITERAL binds to the `LocalizedStringKey` overload, so an
        // uncatalogued literal ships as English — meaning this "fix" would have replaced a
        // German user's own voice saying "Komma" with the English words "Decimal separator",
        // on the comma locales that are this whole slice's audience. An i18n commit that adds
        // an untranslated string is a regression wearing the right label.
        .accessibilityLabel("Decimal separator")
    }

    private var deleteKey: some View {
        keyButton(action: { deleteLast() }) {
            Image(systemName: "delete.left").font(EchoelTheme.font(20))
                .foregroundStyle(EchoelTheme.text)
        }
        .accessibilityLabel("Delete")
    }

    /// The one PRIMARY button on this keypad — and it fills with `EchoelTheme.text`
    /// (off-white) over a black label, not with the bio-green `accent` (#364).
    ///
    /// ⛔ IT WAS GREEN, AND THAT IS THE ONE THING `EchoelTheme` FORBIDS BY NAME: "in-app
    /// PRIMARY buttons fill with `.text`, NOT `.accent`. The bio-green `accent` is reserved
    /// for the body's live signal … never as page chrome." A keypad confirm key is chrome —
    /// it means "commit this number", which is true of a filter cutoff, a tempo and a pan
    /// alike, and has nothing to do with the body. This keypad opens from EVERY
    /// `EchoelValueField` in the app, so it was also the single most-seen green surface,
    /// which is exactly how a reserved signal colour stops signalling anything.
    ///
    /// It reads MORE prominently now, not less: off-white on the 6 %-grey key field is a far
    /// larger step than green was, and the label goes from 11.59:1 on green to 15.89:1 on
    /// off-white. Both cleared the 4.5:1 floor, so this is a coherence fix, not an
    /// accessibility one — saying otherwise would be the more flattering sentence and the
    /// less true one.
    private var okKey: some View {
        keyButton(action: { commit() }, tint: EchoelTheme.text) {
            Text("OK").font(EchoelTheme.font(18, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
        }
        .accessibilityLabel("Confirm \(title)")
    }

    /// One key cell: tall, solid fill, 8 px radius, no glow. Disabled keys read dimmed.
    private func keyButton<Content: View>(action: @escaping () -> Void,
                                          enabled: Bool = true,
                                          tint: Color? = nil,
                                          @ViewBuilder _ label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(tint ?? EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.borderStrong, lineWidth: tint == nil ? 1 : 0))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Editing

    private func append(_ d: String) {
        // The length cap AND the fraction cap both live in `NumberPadEntry.acceptsDigit` —
        // see its doc for why the refusal stops at the fraction and never at the range.
        guard NumberPadEntry.acceptsDigit(after: buffer, decimals: decimals) else { return }
        buffer += d
    }

    private func appendDecimal() {
        guard allowsDecimal, !buffer.contains(".") else { return }
        buffer += buffer.isEmpty || buffer == "-" ? "0." : "."
    }

    /// − prepends a leading minus (works on an in-progress number or, if empty, seeds it so
    /// the next digit lands negative); + strips the leading minus. Sign-only, never a digit.
    private func setSign(negative: Bool) {
        let body = buffer.hasPrefix("-") ? String(buffer.dropFirst()) : buffer
        buffer = negative ? "-" + body : body
    }

    private func deleteLast() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
    }

    private func commit() {
        onCommit(snapped(clamped))
        dismiss()
    }

    /// Snap to the field's decimal grid so the committed number is exact.
    ///
    /// ⛔ THE #431 REVIEW FOUND THIS DOC ASSERTING TWO THINGS, AND BOTH WERE WRONG. It claimed
    /// the line is still load-bearing, and that it "makes tapping OK without typing commit the
    /// number the header was showing".
    ///
    /// **On today's only caller it is REDUNDANT.** `EchoelNumberPad` is constructed in exactly
    /// one place (`EchoelValueField`'s `.sheet`), whose `onCommit` runs `apply`, and `apply`
    /// calls `ScrubPrecision.snapped` — the same clamp-then-`(v·10^d).rounded()/10^d` in the same
    /// order. Removing this line would change nothing today. It stays as defence-in-depth for a
    /// future direct caller of the pad, which is a weaker and truer claim than the one it
    /// replaced. (A "do not delete" note with a false reason is worse than none: the next session
    /// cannot refute it.)
    ///
    /// **The header could also disagree with the commit, at exact ties — CLOSED BY #432.** `fmt`
    /// → `EchoelDecimalText.string` → `String(format: "%.Nf", …)` is C `printf` and rounds
    /// HALF-TO-EVEN on the exact binary value, while this rounds HALF-AWAY-FROM-ZERO. They parted
    /// company wherever the value was an exact dyadic tie whose lower neighbour is even — `0.125`
    /// at two places read "0.12" and committed `0.13`. Reachable, because `initial` is the live
    /// value and a derived binding (`EchoelStudioView.visualEnergy`) lands off-grid by
    /// construction. `fmt` now grids before it formats, and this function no longer keeps its own
    /// copy of the arithmetic: there is ONE definition of the grid, `ScrubPrecision.gridded`.
    private func snapped(_ v: Double) -> Double {
        ScrubPrecision.gridded(v, decimals: decimals)
    }

    /// The pad's own readout and its "Range …–…" line. Same helper as `EchoelValueField`, so
    /// the number cannot read one way in the field and another way in the pad that edits it —
    /// and, since #432, gridded by the same rule the commit uses, so it cannot read one way and
    /// commit another either.
    ///
    /// ⚠️ IT ALSO FORMATS THE TWO BOUNDS, and a bound is not a value a touch will keep — gridding
    /// one can only misstate it, outward (a lower bound of `0.5` on a whole-number row would read
    /// "Range 1–…" while `0.5` is still legal). Latent, not live: every range bound in `Sources/`
    /// was checked against its own row's `decimals` and none is an exact dyadic tie there. Written
    /// down because the next bound somebody adds is the one that makes it live.
    private func fmt(_ v: Double) -> String {
        EchoelDecimalText.string(ScrubPrecision.gridded(v, decimals: decimals), decimals: decimals)
    }
}
#endif
