#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import AVFoundation
import Combine   // NotificationCenter.publisher for AVAudioSession route changes
#endif

// AudioInputPickerView.swift
// Echoel — choose the recording input (built-in mic, wired headset, USB/Lightning
// interface, Bluetooth) with an honest latency note per route, so the performer
// knows before a take whether the route can monitor in real time.
//
// ⭐ WHY THIS VIEW REFRESHES THREE TIMES AND NOT ONCE (#298). `AVAudioSession.availableInputs`
// returns nothing while the category is `.playback`, and `.playback` is Echoel's DEFAULT — the
// session is only upgraded to `.playAndRecord` the moment the user turns monitoring on
// (`AudioConfiguration.upgradeToPlayAndRecord`, called from `AudioEngine.setInputMonitoring`).
// With `.onAppear` as the only refresh, the sequence a performer actually walks —
// open the door, see the list — hits the session in `.playback` and shows an EMPTY list. The
// interface they just plugged in is invisible until they close the sheet and open it again.
// So: refresh on appear (route may have changed since last time), refresh right AFTER the
// monitoring toggle (the category just changed underneath us), and refresh on any route change
// (an interface plugged in while the sheet is open).
//
// ⚠️ THE ROUTE-CHANGE OBSERVER IS SAFE HERE AND WOULD NOT BE ONE LEVEL UP. The freeze law
// (CLAUDE.md 10.76.50) bans HIGH-FREQUENCY reads in an ancestor body — this is an event
// publisher that fires when a cable moves, a handful of times per session, and it lives in a
// leaf that only exists while the sheet is open. It is not a poll.

@MainActor
struct AudioInputPickerView: View {

    @Environment(AudioInputManager.self) private var inputs
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    monitoringSection
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
            #if os(iOS)
            .onReceive(NotificationCenter.default
                .publisher(for: AVAudioSession.routeChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in
                    // An interface/headset was plugged in or pulled while this sheet is open.
                    // `.receive(on:)` is not decoration: AVAudioSession posts this from its own
                    // thread, and `refresh()` is `@MainActor`.
                    inputs.refresh()
                }
            #endif
        }
    }

    // MARK: - Live monitoring + feedback guard

    @ViewBuilder
    private var monitoringSection: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "headphones").foregroundStyle(EchoelTheme.dim).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live monitoring").font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text("Hear your mic through the output, in time with the beat")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { audioEngine.isInputMonitoring },
                    set: {
                        _ = audioEngine.setInputMonitoring($0)
                        // Turning monitoring ON upgrades the session to `.playAndRecord`, which
                        // is the moment `availableInputs` starts returning anything at all.
                        // Without this the list stays empty until the sheet is reopened.
                        inputs.refresh()
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Live monitoring")
            }
            if audioEngine.isInputMonitoring {
                EchoelValueField(
                    label: "Monitor level",
                    value: Binding(get: { audioEngine.inputMonitorGain },
                                   set: { audioEngine.inputMonitorGain = $0 }),
                    range: 0...1, decimals: 2)
                HStack(spacing: 8) {
                    Circle()
                        .fill(audioEngine.feedbackGuardActive ? Color.orange : EchoelTheme.accent)
                        .frame(width: 8, height: 8)
                    Text(audioEngine.feedbackGuardActive ? "Feedback guard — ducking runaway" : "Feedback guard armed")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                .accessibilityElement(children: .combine)
                if inputs.outputIsHighLatency {
                    Text("Output is on \(inputs.outputRouteName.isEmpty ? "Bluetooth" : inputs.outputRouteName) (~150–250 ms). The iPhone mic stays low-latency, but you'll hear your own voice slightly delayed through Bluetooth — fine for the beat, less tight for vocals. Plug in wired/USB headphones for delay-free self-monitoring.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Use headphones or an interface to avoid acoustic feedback. On the speaker, the guard automatically ducks any howl that builds up.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        #endif
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
            Text(emptyStateText)
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .padding(.horizontal, 12)
    }

    /// ⛔ THIS STRING USED TO BE THE macOS SENTENCE ON EVERY PLATFORM: "Input is managed by the
    /// system here." On iOS that is simply false — the app manages the input, via
    /// `setPreferredInput`. It read as a dead end ("nothing to do here") in the one situation
    /// where the user has something very specific to do: switch monitoring on so iOS starts
    /// publishing the input list. An empty state that misdescribes WHY it is empty sends the
    /// person away from the fix.
    /// ⛔ ONE LITERAL PER BRANCH, NOT A `+` CHAIN. A long message assembled with `+` inside a
    /// ternary is the ledgered type-checker hazard that turned the blocking gate red on
    /// `3379bb3`. Keep each branch a single literal.
    private var emptyStateText: String {
        #if os(iOS)
        if audioEngine.isInputMonitoring {
            return "No input is available on the current route."
        }
        return "Turn on live monitoring above to list the available inputs. iOS only publishes them while the mic is in use."
        #else
        return "Input is managed by the system here."
        #endif
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
