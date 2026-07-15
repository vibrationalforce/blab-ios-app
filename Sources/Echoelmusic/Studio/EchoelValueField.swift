//
//  EchoelValueField.swift
//  Echoelmusic — Studio
//
//  The one control: a NUMERIC VALUE, no permanent slider/knob (saves space, reads
//  science-first). Interaction:
//   • Press the value and drag in ANY direction — UP or RIGHT increases, DOWN or
//     LEFT decreases (founder 2026-07-12: "nicht nur hoch und runter sondern auch
//     links und rechts"). A transparent vertical slider appears to the left as a
//     position reference. Full range crosses in ~one short drag, so it's fast,
//     not stiff. (The old pull-sideways FINE mode is gone — horizontal now ADJUSTS;
//     precision lives in tap-to-type.)
//   • TAP the value to open the EchoelNumberPad — our own keypad with − / + at the
//     bottom-left (the iOS decimal pad can't carry a sign key). Same pad everywhere.
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
    /// Optional fixed box width for COMPACT contexts (e.g. the transport bar's BPM),
    /// where the default 150 is far wider than a short value needs. When nil the box
    /// keeps the Dynamic-Type-scaled default. The one control still — just narrower.
    var boxWidth: CGFloat? = nil

    /// Presents the shared numeric keypad (tap-to-type path).
    @State private var showPad = false

    // Drag state (incremental deltas, so the value never jumps mid-gesture).
    @State private var scrubbing = false
    @State private var lastY: CGFloat = 0
    @State private var lastX: CGFloat = 0

    /// Drag distance (points) that covers the FULL range at normal speed — small, so
    /// the fader feels fast/direct (the old velocity-scrub felt stiff).
    private let fullRangePoints: Double = 200

    var body: some View {
        // With a label, the caption sits left and the box trails (aligned columns).
        // With an EMPTY label (compact strips — e.g. the timeline lane gain) render
        // JUST the box: the leading Text + expanding Spacer would otherwise reserve
        // ~30 pt of dead width and blow the box past its host column. One caller uses
        // label:"" today (the lane mix strip); this keeps that field as small as its box.
        Group {
            if label.isEmpty {
                valueBox
            } else {
                HStack(spacing: 12) {
                    Text(label)
                        .font(EchoelTheme.font(14, .medium))
                        .foregroundStyle(EchoelTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    valueBox
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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
        // radius; bio-green while scrubbing or while the pad is open.
        let active = scrubbing || showPad
        return ZStack {
            HStack(spacing: 5) {
                Text(numberString)
                    .font(EchoelTheme.font(17).monospacedDigit())
                    .foregroundStyle(active ? EchoelTheme.accent : EchoelTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(EchoelTheme.font(13, .medium))
                        .foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }

            // A transparent layer turns the value into a vertical fader: drag = adjust,
            // tap = open the keypad.
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(scrubGesture)
                .onTapGesture { showPad = true }
        }
        .frame(width: boxWidth ?? valueWidth)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(active ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        // The transparent orientation slider floats just left of the box while dragging.
        .overlay(alignment: .leading) {
            if scrubbing { faderOverlay.offset(x: -22) }
        }
        .animation(.easeOut(duration: 0.12), value: scrubbing)
        .sheet(isPresented: $showPad) {
            EchoelNumberPad(title: label, initial: Double(value), decimals: decimals,
                            unit: unit, range: Double(range.lowerBound)...Double(range.upperBound)) { newVal in
                apply(newVal)
                onChange()
                onCommit()
            }
            .presentationDetents([.height(440), .large])
            .presentationDragIndicator(.visible)
        }
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
        // 8 pt slop so a TAP (which always carries ~1–3 pt of jitter) reliably opens the
        // keypad instead of being claimed as a near-zero scrub. Deliberate drags still
        // adjust. (The old 1 pt threshold made tap-to-type flaky.)
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if !scrubbing {
                    scrubbing = true
                    lastY = g.translation.height   // anchor; no jump on the first move
                    lastX = g.translation.width
                    return
                }
                let span = Double(range.upperBound - range.lowerBound)
                // BOTH axes adjust (founder 2026-07-12): up = increase, right = increase.
                // The deltas ADD, so a diagonal drag is simply faster — never a fight.
                let dyStep = Double(lastY - g.translation.height)
                let dxStep = Double(g.translation.width - lastX)
                lastY = g.translation.height
                lastX = g.translation.width
                let delta = ((dyStep + dxStep) / fullRangePoints) * span
                if delta != 0 {
                    apply(Double(value) + delta)
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
}
#endif
