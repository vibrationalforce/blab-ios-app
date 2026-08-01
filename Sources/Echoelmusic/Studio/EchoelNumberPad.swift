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
        // Cap length so a fat-fingered run can't overflow the field.
        guard buffer.count < 9 else { return }
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
    private func snapped(_ v: Double) -> Double {
        let f = pow(10.0, Double(decimals))
        return (v * f).rounded() / f
    }

    /// The pad's own readout and its "Range …–…" line. Same helper as `EchoelValueField`, so
    /// the number cannot read one way in the field and another way in the pad that edits it.
    private func fmt(_ v: Double) -> String {
        EchoelDecimalText.string(v, decimals: decimals)
    }
}
#endif
