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

    /// #601b (review): this door's own copy of the strip's `micMonitorRefused`. Before it,
    /// a denied mic snapped the toggle back with ZERO explanation here, and the empty state
    /// below told the user to switch on the very thing that just refused — an unfulfillable
    /// loop on exactly the founder's "Audio in" path. Rendered gated on the ENGINE as well
    /// (`monitorRefused && !audioEngine.isInputMonitoring`), the #485 pattern: the engine
    /// stays the single source of truth for "is it listening", so a grant through the OTHER
    /// door self-corrects a stale refusal here.
    @State private var monitorRefused = false

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
                    set: { on in
                        if on {
                            // #601: ask for the mic FIRST — the direct call could never
                            // show the permission dialog (undetermined → 0 Hz input
                            // format → silent bail), so this toggle flipped back with
                            // no explanation on a fresh install. The refresh runs AFTER
                            // the engage: turning monitoring on upgrades the session to
                            // `.playAndRecord`, which is the moment `availableInputs`
                            // starts returning anything at all.
                            Task { @MainActor in
                                let engaged = await audioEngine.engageInputMonitoring()
                                monitorRefused = !engaged
                                inputs.refresh()
                            }
                        } else {
                            _ = audioEngine.setInputMonitoring(false)
                            monitorRefused = false
                            inputs.refresh()
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Live monitoring")
            }
            if monitorRefused && !audioEngine.isInputMonitoring {
                Text("Monitoring could not start — check microphone access in Settings.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                // #610: the same Settings door as the mix-board strip — one state, one
                // wording, two doors (the TheMonitorSaysWhyItIsSilentTests discipline).
                // See the studio twin for the full reasoning (iOS asks once; a Settings
                // grant relaunches the app, so no re-check is needed).
                Button { openAppSettings() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash").font(.system(size: 9))
                        Text("Allow microphone")
                    }
                    .font(EchoelTheme.font(11))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(EchoelTheme.warning.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
                    .foregroundStyle(EchoelTheme.warning)
                    // #610b (review): hit area to the 34-pt floor, chip unchanged — see the
                    // studio twin's comment; pinned in TapTargetFloorTests.
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Microphone access is off")
                .accessibilityHint("Opens Settings so you can allow microphone access and hear yourself live")
            }
            if audioEngine.isInputMonitoring {
                // #605 (UX audit #9): the engine-stopped case the refusal line above cannot
                // see — permission was granted, the graph is wired, but the engine is paused
                // (call/Siri/alarm), so the toggle shows ON and nothing sounds. Inside this
                // `isInputMonitoring` block the bare `!isRunning` IS the compound gate the
                // mix-board door spells out. Same sentence as there, on purpose (one state,
                // one wording — pinned by TheMonitorSaysWhyItIsSilentTests). No retry button:
                // see the mix-board comment (AudioDegradedRow owns recovery for `degraded`).
                // ⛔ #605b: `!degraded` — in THIS sheet the false promise would stand ALONE:
                // AudioDegradedRow lives in the studio column underneath, invisible while the
                // sheet is up, so during `degraded` the only visible sentence would promise a
                // recovery that will not come. Gated off, the degraded case shows nothing here
                // and the user meets the row (cause + Retry) on dismiss — recovery one gesture
                // away beats a wrong promise on screen (review of #605).
                if !audioEngine.isRunning && !audioEngine.degraded {
                    Text("Monitoring is on, but audio is paused — it comes back by itself when the call, alarm or Siri ends.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                // VL3 (#599) — the OPTIONAL in-key correction. The toggle is the
                // optionality (default OFF); "Tune" is the character: 1 = the classic
                // hard snap, 0 = gentle drift. Both numeric → EchoelValueField (law);
                // the on/off is a named binary → Toggle, like monitoring above.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tune to key").font(EchoelTheme.font(13, .semibold))
                            .foregroundStyle(EchoelTheme.text)
                        Text("Snaps your monitored voice into the session's key — the instrument knows the Tonart, nothing is guessed from the signal.")
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { audioEngine.voiceTuneEnabled },
                        set: { audioEngine.setVoiceTune($0) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Tune to key")
                }
                if audioEngine.voiceTuneEnabled {
                    EchoelValueField(
                        label: "Amount",
                        value: Binding(get: { audioEngine.voiceTuneStrength },
                                       set: { audioEngine.voiceTuneStrength = $0 }),
                        range: 0...1, decimals: 2)
                    EchoelValueField(
                        label: "Tune",
                        value: Binding(get: { audioEngine.voiceTuneRetune },
                                       set: { audioEngine.voiceTuneRetune = $0 }),
                        range: 0...1, decimals: 2)
                    Text("Tune 1.00 is the classic hard-snap vocal effect; low values drift gently. The pitch stage adds a little latency to the monitor only — the music is untouched.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
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
        // #601b: with the mic refused, "turn on monitoring above" is an unfulfillable loop —
        // the switch just snapped back. Send the user to the actual fix instead.
        if monitorRefused {
            return "The microphone is not available to Echoel. Allow microphone access in Settings, then switch monitoring on."
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
