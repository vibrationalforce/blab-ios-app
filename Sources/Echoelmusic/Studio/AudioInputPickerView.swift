#if canImport(SwiftUI)
import SwiftUI

// AudioInputPickerView.swift
// Echoel — choose the recording input (built-in mic, wired headset, USB/Lightning
// interface, Bluetooth) with an honest latency note per route, so the performer
// knows before a take whether the route can monitor in real time.

@MainActor
struct AudioInputPickerView: View {

    @Environment(AudioInputManager.self) private var inputs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if inputs.available.isEmpty {
                        emptyState
                    } else {
                        ForEach(inputs.available) { input in row(input) }
                    }
                    footer
                }
                .padding(16)
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Input")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { inputs.refresh() }
        }
    }

    // MARK: - Rows

    private func row(_ input: AudioInputInfo) -> some View {
        let selected = input.id == inputs.selectedID
        return Button { inputs.select(input.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: input.kind))
                    .foregroundStyle(EchoelTheme.dim).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.name)
                        .font(EchoelTheme.font(14, .medium)).foregroundStyle(EchoelTheme.text)
                    Text(input.latency.advice)
                        .font(EchoelTheme.font(11)).foregroundStyle(color(for: input.latency))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(EchoelTheme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(selected ? EchoelTheme.accent.opacity(0.6) : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(input.name). \(input.latency.advice)\(selected ? ". Selected" : "")")
        .accessibilityHint("Use this input for recording")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.slash").font(.title2).foregroundStyle(EchoelTheme.dim)
            Text("Input is managed by the system here.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private var footer: some View {
        Text("Bluetooth records fine but adds ~150–250 ms — for live monitoring of your own voice, use a wired or USB input.")
            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Presentation helpers

    private func icon(for kind: AudioInputKind) -> String {
        switch kind {
        case .builtIn:   return "iphone"
        case .wired:     return "cable.connector"
        case .usb:       return "cable.connector.horizontal"
        case .bluetooth: return "wave.3.right"
        case .carPlay:   return "car"
        case .virtual:   return "dot.radiowaves.left.and.right"
        case .other:     return "mic"
        }
    }

    private func color(for latency: MonitoringLatency) -> Color {
        switch latency {
        case .low:    return EchoelTheme.accent
        case .medium: return EchoelTheme.dim
        case .high:   return EchoelTheme.danger
        }
    }
}
#endif
