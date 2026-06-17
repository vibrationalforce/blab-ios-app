//
//  EchoelValueField.swift
//  Echoelmusic — Studio
//
//  The one control: a NUMERIC VALUE, no permanent slider/knob (saves space, reads
//  science-first). Interaction is a direct VERTICAL FADER:
//   • Press the value and drag UP/DOWN — a transparent vertical slider appears to the
//     left as a position reference (touch-sensitive, musical for filter sweeps). Full
//     range crosses in ~one short drag, so it's fast, not stiff.
//   • Pull sideways while dragging for FINE mode (precise to the decimal grid).
//   • Tap the value to type an exact number (decimal pad; accepts comma or dot).
//   • VoiceOver: adjustable by swipe, speaks the real value + unit.
//
//  Everything scales with Dynamic Type / the app zoom (EchoelTheme.font relativeTo +
//  the studio pinch-zoom). Website CI tokens only. Pure UI — no audio-thread work.
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

struct EchoelValueField<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var unit: String = ""
    /// Decimals shown and the snap grid (default 4 → exact to 0.0001).
    var decimals: Int = 4
    var onChange: () -> Void = {}
    var onCommit: () -> Void = {}

    // The value box + label grow with Dynamic Type / app zoom. Wide enough for a
    // 4-decimal value with a large integer part plus its unit ("18000.0000 Hz").
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 150

    @State private var text = ""
    @FocusState private var focused: Bool

    // Vertical-fader drag state (incremental, so toggling fine mode never jumps).
    @State private var scrubbing = false
    @State private var lastY: CGFloat = 0

    /// Drag distance (points) that covers the FULL range at normal speed — small, so
    /// the fader feels fast/direct (the old velocity-scrub felt stiff).
    private let fullRangePoints: Double = 200

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(EchoelTheme.font(14, .medium))
                .foregroundStyle(EchoelTheme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            valueBox
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onAppear { syncText() }
        .onChange(of: value) { _, _ in if !focused { syncText() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibleValue)
        .accessibilityHint("Swipe up or down to adjust, or double-tap to type")
        .accessibilityAdjustableAction { dir in
            let span = Double(range.upperBound - range.lowerBound)
            let step = span / 50
            switch dir {
            case .increment: apply(Double(value) + step)
            case .decrement: apply(Double(value) - step)
            @unknown default: break
            }
            onCommit()
        }
    }

    private var valueBox: some View {
        // Number + unit read as ONE cohesive field ("440.0000  Hz"), trailing-aligned
        // so values line up in a column. Website CI: solid fill, 1px muted border, 8px
        // radius; bio-green only while editing/scrubbing.
        ZStack {
            HStack(spacing: 5) {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .font(EchoelTheme.font(17).monospacedDigit())
                    .foregroundStyle(focused || scrubbing ? EchoelTheme.accent : EchoelTheme.text)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .toolbar {
                        // Gate on `focused` so only the active field contributes one Done
                        // to the shared keyboard accessory (avoids the stacked-Done bug).
                        if focused {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer(); Button("Done") { focused = false }
                            }
                        }
                    }
                    #endif
                    .onSubmit(commitText)
                    .onChange(of: focused) { _, f in if !f { commitText() } }

                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(EchoelTheme.font(13, .medium))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }

            // While not editing, a transparent layer turns the value into a vertical
            // fader: drag = adjust, tap = type. Removed when focused so the TextField
            // receives touches for editing.
            if !focused {
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(scrubGesture)
                    .onTapGesture { focused = true }
            }
        }
        .frame(width: valueWidth)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(focused || scrubbing ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        // The transparent orientation slider floats just left of the box while dragging.
        .overlay(alignment: .leading) {
            if scrubbing { faderOverlay.offset(x: -22) }
        }
        .animation(.easeOut(duration: 0.12), value: scrubbing)
    }

    /// The transient vertical slider shown on press — a position reference to orient by.
    private var faderOverlay: some View {
        let h: CGFloat = 180
        let thumb: CGFloat = 13
        return ZStack(alignment: .bottom) {
            Capsule().fill(EchoelTheme.fill.opacity(0.85))
                .overlay(Capsule().strokeBorder(EchoelTheme.border, lineWidth: 1))
                .frame(width: 6, height: h)
            Capsule().fill(EchoelTheme.accent.opacity(0.35))
                .frame(width: 6, height: max(thumb, h * frac))
            Circle().fill(EchoelTheme.accent)
                .frame(width: thumb, height: thumb)
                .offset(y: -(h - thumb) * frac)
        }
        .frame(width: thumb, height: h)
        .allowsHitTesting(false)
    }

    /// Current value as a 0…1 fraction of the range (for the fader fill/thumb).
    private var frac: CGFloat {
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        guard hi > lo else { return 0 }
        return CGFloat(Swift.min(Swift.max((Double(value) - lo) / (hi - lo), 0), 1))
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if !scrubbing {
                    scrubbing = true
                    lastY = g.translation.height   // anchor; no jump on the first move
                    return
                }
                let span = Double(range.upperBound - range.lowerBound)
                let dyStep = Double(lastY - g.translation.height)        // up = increase
                lastY = g.translation.height
                // Pull sideways (>80 pt) for FINE mode — precise without losing speed.
                let fine = abs(g.translation.width) > 80 ? 0.22 : 1.0
                let delta = (dyStep / fullRangePoints) * span * fine
                if delta != 0 {
                    apply(Double(value) + delta)
                    if !focused { syncText() }
                    onChange()
                }
            }
            .onEnded { _ in scrubbing = false; onCommit() }
    }

    private func apply(_ raw: Double) {
        let clamped = Swift.min(Swift.max(raw, Double(range.lowerBound)), Double(range.upperBound))
        // Snap to the decimal grid so the displayed number is exact.
        let f = pow(10.0, Double(decimals))
        value = V((clamped * f).rounded() / f)
    }

    private var accessibleValue: String {
        let n = numberString
        switch unit {
        case "Hz":  return "\(n) hertz"
        case "s":   return "\(n) seconds"
        case "BPM": return "\(n) beats per minute"
        case "":    return n
        default:    return "\(n) \(unit)"
        }
    }

    /// The unit suffix shown after the value (Hz, s, BPM, …). Empty for dimensionless
    /// values, whose meaning is carried by the label.
    private var unitLabel: String { unit }

    private var numberString: String { String(format: "%.\(decimals)f", Double(value)) }

    private func syncText() { text = numberString }

    private func commitText() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let d = Double(cleaned) { apply(d) }
        syncText()
        onCommit()
    }
}
#endif
