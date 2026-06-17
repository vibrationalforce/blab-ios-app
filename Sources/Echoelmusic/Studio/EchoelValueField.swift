//
//  EchoelValueField.swift
//  Echoelmusic — Studio
//
//  The one control: a NUMERIC VALUE, no slider, no knob. It saves space (a value is
//  smaller than a dial) and reads science-first (the number is the truth). Interaction:
//   • Drag the value left/right to scrub — **velocity-sensitive granularity**: a fast
//     flick jumps in big leaps, a slow drag steps exactly on the 0.01 grid (precise to
//     the second decimal). One control covers both coarse and fine.
//   • Tap the value to type an exact number (decimal pad; accepts comma or dot).
//   • VoiceOver: adjustable by swipe, speaks the real value + unit.
//
//  Everything scales with Dynamic Type / the app zoom (see EchoelTheme.font's
//  relativeTo and the studio's pinch-to-zoom), so it stays legible for every pair of
//  eyes. Pure UI — no audio-thread involvement.
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

struct EchoelValueField<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var unit: String = ""
    /// Decimal places shown and the fine-scrub grid (default 4 → exact to 0.0001).
    /// A finer grid also means smoother parameter sweeps while scrubbing.
    var decimals: Int = 4
    var onChange: () -> Void = {}
    var onCommit: () -> Void = {}

    // The value box and label grow with Dynamic Type / app zoom. Wide enough for a
    // 4-decimal value with a large integer part (e.g. "18000.0000").
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 116

    @State private var text = ""
    @FocusState private var focused: Bool

    // Scrub state — fractional accumulator so slow drags land on the 0.01 grid.
    @State private var scrubbing = false
    @State private var lastX: CGFloat = 0
    @State private var lastTime = Date()
    @State private var accumulator: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(EchoelTheme.font(13, .medium))
                .foregroundStyle(EchoelTheme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            valueBox
            // The value TYPE, always shown after the number (Hz, s, BPM, …). Physical
            // units read clearly; dimensionless 0–1 values carry their meaning in the
            // label. Fixed width so values line up in a column.
            Text(unitLabel)
                .font(EchoelTheme.font(12, .medium))
                .foregroundStyle(EchoelTheme.dim)
                .lineLimit(1)
                .frame(width: 34, alignment: .leading)
                .accessibilityHidden(true)
        }
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
        ZStack {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .font(EchoelTheme.font(15).monospacedDigit())
                .foregroundStyle(focused ? EchoelTheme.accent : EchoelTheme.text)
                .textFieldStyle(.plain)
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

            // While not editing, a transparent layer turns the value into a scrubber:
            // drag = velocity-sensitive adjust, tap = start typing. Removed when
            // focused so the TextField receives touches for editing.
            if !focused {
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(scrubGesture)
                    .onTapGesture { focused = true }
            }
        }
        .frame(width: valueWidth)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(focused ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                let now = Date()
                if !scrubbing {
                    scrubbing = true; lastX = g.translation.width; lastTime = now; accumulator = 0
                    return
                }
                let dx = Double(g.translation.width - lastX)          // points since last event
                let dt = Swift.max(now.timeIntervalSince(lastTime), 1.0 / 240.0)
                lastX = g.translation.width; lastTime = now
                let speed = abs(dx) / dt                              // points / second

                let fine = pow(10.0, -Double(decimals))              // 0.01 → precise
                let span = Double(range.upperBound - range.lowerBound)
                let coarse = Swift.max(span / 260.0, fine)           // fast → cross range in ~260 pt
                // Blend fine↔coarse by drag speed (≈80 pt/s = fine, ≈1300 pt/s = coarse).
                let t = smoothstep(80, 1300, speed)
                let perPoint = fine + (coarse - fine) * t

                accumulator += dx * perPoint
                // Emit whole `fine`-sized increments so a slow drag lands on the grid.
                let steps = (accumulator / fine).rounded(.towardZero)
                if steps != 0 {
                    accumulator -= steps * fine
                    apply(Double(value) + steps * fine)
                    if !focused { syncText() }
                    onChange()
                }
            }
            .onEnded { _ in scrubbing = false; onCommit() }
    }

    /// Smooth 0→1 ramp between edges (Hermite); clamps outside.
    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = Swift.min(Swift.max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
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

    /// The unit suffix shown after the value (Hz, s, BPM, …). Empty for
    /// dimensionless values, whose meaning is carried by the label.
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
