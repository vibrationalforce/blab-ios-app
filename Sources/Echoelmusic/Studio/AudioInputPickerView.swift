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
// returns nothing while the category is `.playback`, and `.playback` is Echoel's DEFAULT. The
// session is upgraded to `.playAndRecord` on any explicit mic action — monitoring is ONE of
// five call sites (`AudioEngine.setInputMonitoring`, `MicrophoneManager` ×3,
// `MultiTrackRecorder`), plus `AudioConfiguration.configureAudioSession` itself when
// `recordingRouteNeeded`. ⛔ The first version of this paragraph said "only … when the user
// turns monitoring on"; that is the sentence the user-facing empty state is built on, so its
// looseness is not cosmetic.
//
// With `.onAppear` as the only refresh, the door opens against a `.playback` session and shows
// an EMPTY list. ⛔ AND THE FIRST VERSION GOT THE CAUSALITY BACKWARDS: it said the interface is
// "invisible until they close the sheet and open it again". Reopening re-runs `.onAppear`
// against a session that is STILL `.playback` — it changes nothing. Reopening only ever helped
// AFTER the toggle had already upgraded the category, which is exactly the second refresh point
// below. Getting that inverted would send the next reader looking for a presentation bug.
//
// So: refresh on appear (the route may have changed since last time), refresh right after the
// monitoring toggle, and refresh on any route change (a cable moved while the sheet is open).
//
// ⛔ SINCE #299 BOTH TOGGLE DIRECTIONS CHANGE THE CATEGORY. What stood here — "the OFF path does
// NOT downgrade, `setInputMonitoring(false)` only disconnects" — was true when it was written
// and false one commit later: OFF now releases the record route, and when no recorder still
// holds it the session drops back to `.playback`. USER-VISIBLE CONSEQUENCE, so it is written
// down rather than discovered: turning monitoring off while this sheet is open empties the
// input list, because iOS publishes no inputs under `.playback`. That is honest (the empty
// state below says "Turn on live monitoring above to list the available inputs") and it is the
// price of not leaving every other app's Bluetooth headset on the HFP mono codec — but it IS a
// change, and a comment asserting it cannot happen is worse than no comment.
//
// ⚠️ THIS CLEARS THE OBSERVER, NOT THE WHOLE VIEW. The freeze law (CLAUDE.md 10.76.50) bans
// HIGH-FREQUENCY reads in an ancestor body; the `.onReceive` below is an event publisher that
// fires when a cable moves, in a leaf that only exists while the sheet is open — not a poll, no
// violation. Separately and PRE-EXISTING: `monitoringSection` reads
// `audioEngine.feedbackGuardActive`, which is assigned every guard tick (~15 Hz) while
// monitoring runs, so this body already rebuilt at that rate. `AudioEngine` now gates that
// assignment on change; there is no `.menu` Picker in this sheet either way, so it was never a
// freeze here — but do not read the sentence above as a clean bill of health for the view.

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
