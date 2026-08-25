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

    /// The character the LIVE values sit on, or nil once a field has been dragged off
    /// every named point. Hoisted out of `monitoringSection` for two reasons: #287 (a
    /// `Binding<Optional>` built inline inside a `Picker` inside a body this size is the
    /// shape that has taken this bundle red on type-check time), and because the caption
    /// below the picker asks the same question — one spelling, not two (#416).
    private var voiceTuneCharacter: VoiceTuneCharacter? {
        VoiceTuneCharacter.matching(strength: Double(audioEngine.voiceTuneStrength),
                                    retuneSpeed: Double(audioEngine.voiceTuneRetune))
    }

    /// Derived selection: reads back from the two fields, writes both on a pick. No stored
    /// selection anywhere — see the note at the picker.
    private var voiceTuneCharacterBinding: Binding<VoiceTuneCharacter?> {
        Binding(
            get: { voiceTuneCharacter },
            set: { choice in
                guard let choice else { return }
                audioEngine.voiceTuneStrength = Float(choice.strength)
                audioEngine.voiceTuneRetune = Float(choice.retuneSpeed)
            })
    }

    // ⚠️ THE ATTRIBUTE BELONGS TO THIS DECLARATION, and #681 briefly gave it away. Two
    // computed members were inserted above `private var monitoringSection`, anchored on
    // that line — which put them BETWEEN the attribute and the declaration it decorates.
    // A doc comment between an attribute and a declaration is trivia, so it still PARSES:
    // `@ViewBuilder` simply bound to the new `voiceTuneCharacter`, and the builder then
    // tried to make a `View` out of `VoiceTuneCharacter?`. It is load-bearing here because
    // the `#if os(iOS)` below leaves an EMPTY body on every other platform, which only a
    // result builder tolerates. Anchor an insertion on the declaration and you can still
    // land above its attribute — check what sits above the anchor, not only the anchor.
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
                // #613: copy branches on the engine's ONE denial definition — see the
                // studio twin's comment. Settings advice only when Settings is the fix.
                if audioEngine.micPermissionDenied {
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
                } else {
                    // #613: granted mic, non-permission failure — no Settings costume.
                    // #613b: deliberately NO `!degraded` gate here, ASYMMETRIC to the
                    // studio twin. AudioDegradedRow lives in the studio column and is
                    // INVISIBLE under this sheet — gating would leave the refusal block
                    // empty: a snapped-back toggle with no explanation, the exact defect
                    // class this chain fights. And unlike the #605b silence line (whose
                    // "comes back by itself" promise is FALSE when degraded), "try
                    // again" stays honest there — retry is what the row itself offers.
                    Text("Monitoring could not start — try again.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !audioEngine.isInputMonitoring {
                // #828 — the codec verdict, no longer hidden behind monitoring. The
                // route is SYSTEM-SHARED: another app holding `.playAndRecord` with
                // HFP, or a call in progress, degrades the music while Echoel sits
                // in `.playback` — and since #827 Echoel itself never requests HFP,
                // so external causes are the ONLY ones left. Gated on !monitoring
                // because while monitoring runs, `MonitorLatencyRow` below renders
                // the same verdict — one sentence on screen, never two (#416).
                // Renders nothing for a healthy route.
                RouteCodecRow()
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
                    // #681 — the founder's "Autotune (Charakter Einstellungen)". A character is
                    // a choice with NAMES, so it is a Picker and not a fifth number (CLAUDE.md,
                    // "READ THE WORD NUMERIC"). It sits ABOVE the two fields it writes, the
                    // preset-over-parameters shape `presetRow` already uses in the sound panel.
                    //
                    // ⭐ THE SELECTION IS DERIVED FROM THE LIVE VALUES, never stored. There is no
                    // `@State` character here on purpose: a stored selection would keep claiming
                    // "Tight" after a finger moved Amount, and a control that lies about what is
                    // active is worse than none (the `DiatonicHarmonyFollower` ownership lesson).
                    // `matching` returns nil once the values sit off every named point — then no
                    // segment is highlighted and the caption below says why. That is also why
                    // there is no "Custom" segment: choosing it could only be a no-op, which is
                    // exactly the inert control this shape exists to avoid.
                    Text("Character")
                        .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Picker("Character", selection: voiceTuneCharacterBinding) {
                        ForEach(VoiceTuneCharacter.allCases) { character in
                            Text(character.label).tag(VoiceTuneCharacter?.some(character))
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Autotune character")
                    if voiceTuneCharacter == nil {
                        Text("Custom — your own Amount and Tune. Pick a character to return to a named setting.")
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                // #663 — THE NUMBER, next to the warning that motivates it. The founder asked
                // for "alle Latenzen und Kombinationen optimiert für Sessions"; #653–#657 made
                // that measurable but only inside `echoel_diag.log`, which answers after an
                // export. This answers while he is choosing the route.
                // ⚠️ Its OWN leaf, and that is the 10.76.41/50 freeze law, not tidiness: this
                // view hosts Pickers, and a value read in THIS body would register the whole
                // body as an observer of whatever the leaf watches.
                MonitorLatencyRow()
                if inputs.outputIsHighLatency {
                    Text("Output is on \(inputs.outputRouteName.isEmpty ? "Bluetooth" : inputs.outputRouteName) (~150–250 ms). The iPhone mic stays low-latency, but you'll hear your own voice slightly delayed through Bluetooth — fine for the beat, less tight for vocals. Plug in wired/USB headphones for delay-free self-monitoring.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // ⛔ #827 — the #824 "Bluetooth headset mic" toggle STOOD HERE for one
                // cycle and was struck by the founder the same day ("Keine
                // Telefonqualität zulassen, das mag niemand"). Echoel never requests
                // HFP: the headset's own mic is simply never used — mic from
                // iPhone/wired/USB, output stays full-quality A2DP stereo. Do not
                // re-add a door to call quality; the ban lives in
                // `AudioConfiguration.recordOptions`, guarded by
                // `TheRecordRouteDoesNotDefaultToHFPTests`.
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
        // #613: but ONLY when Settings really is the fix — for a granted mic whose engage
        // failed transiently, "turn on monitoring above" is again the right instruction,
        // so the non-denied case deliberately falls through to the default line below.
        if monitorRefused && audioEngine.micPermissionDenied {
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
/// The measured monitor latency, as a number the founder can read without exporting a log.
///
/// #663. Same gathering and same sum as the `latency:` breadcrumb — `AudioConfiguration`
/// owns both, so the screen and the file cannot disagree (#416).
///
/// ⚠️ A LEAF ON PURPOSE. `AudioInputPickerView` hosts Pickers, and 10.76.41/50 cost several
/// device builds to learn that a value read in a Picker-hosting body tears down an open
/// popover whenever it changes. Nothing here is polled: `AVAudioSession` latency changes only
/// when the route changes, so the read happens on appear and on `routeChangeNotification`.
/// There is no timer, and adding one would be the freeze bug.
private struct MonitorLatencyRow: View {
    @State private var readout: AudioConfiguration.LatencyReadout?
    /// `nil` until the first read, and `nil` again if anything sets a buffer size outside the
    /// three named tiers — the segmented control then shows no selection, which is the honest
    /// rendering of "this size has no name" (see `currentLatencyMode`).
    @State private var mode: AudioConfiguration.LatencyMode?

    var body: some View {
        Group {
            if let readout {
                // Two siblings, not one: the readout carries
                // `.accessibilityElement(children: .combine)` so VoiceOver reads the number as
                // one item, and folding the control into that would make it unreachable. An
                // explicit outer stack so the spacing between them is a decision, not whatever
                // the mounting context happens to impose.
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Monitor latency").font(EchoelTheme.font(11))
                                .foregroundStyle(EchoelTheme.dim)
                            Spacer(minLength: 8)
                            Text(readout.floorText)
                                .font(EchoelTheme.font(13, .semibold))
                                .foregroundStyle(EchoelTheme.text)
                                .monospacedDigit()
                        }
                        Text(readout.breakdownText + "\n" + Self.caveat)
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        // #670 — the BANDWIDTH fact, which no latency number can express. The two
                        // Bluetooth warnings in the parent are both about DELAY; this one is about
                        // the route collapsing to the mono call codec once the mic is claimed, and
                        // it takes the music down with it. `danger`, and only when there is
                        // something to say: `note` is `nil` for a healthy route, so a good cable
                        // renders no line at all rather than a reassurance nobody asked for.
                        // ⚠️ This copy of the verdict appears only while monitoring runs,
                        // because the row it lives in does. ⛔ Until #828 that was the ONLY
                        // copy, and the gap was real: the route is SYSTEM-SHARED — another
                        // app holding `.playAndRecord` with HFP, or a call, degrades the
                        // music while Echoel sits in `.playback`, and the warning was
                        // hidden. #828 closed it with `RouteCodecRow` in the parent, gated
                        // on !monitoring so exactly ONE copy of the sentence is on screen
                        // at any time (#416). Do not remove either copy without the other's
                        // gate in the same commit.
                        if let note = readout.codec.note {
                            Text(note)
                                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    bufferPicker
                }
            }
        }
        .onAppear {
            readout = AudioConfiguration.latencySnapshot()
            mode = AudioConfiguration.currentLatencyMode
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
                // `.receive(on:)` is not decoration and it is not copied for symmetry:
                // AVAudioSession posts this from its OWN thread, and this closure writes
                // `@State` on a `@MainActor` view. The sibling refresh at the top of this
                // file carries the same hop for the same reason.
                readout = AudioConfiguration.latencySnapshot()
                // `mode` too: `.onAppear` set both, this handler set only the readout, and two
                // `@State` fields in one leaf with different staleness rules is a bug waiting
                // for its first writer.
                mode = AudioConfiguration.currentLatencyMode
            }
        #endif
    }

    /// #674 — the door for a policy that had no producer. A `Picker`, NOT an `EchoelValueField`,
    /// and that is the rule rather than an exception to it: the UI law says every adjustable
    /// NUMERIC parameter is a value field, and it says in the same breath that a parameter whose
    /// values have NAMES is a picker. "Ultra / Low / Normal" are three named tiers of one enum,
    /// not a continuum — offering 128–512 as a typed number would invite sizes the audio graph
    /// never agreed to.
    ///
    /// It sits INSIDE this leaf on purpose. The number it changes is rendered two lines above
    /// it, so the refresh stays local: a control in the parent would have to reach down, and a
    /// read in the parent is the 10.76.41/50 freeze.
    @ViewBuilder
    private var bufferPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Buffer", selection: Binding(
                get: { mode },
                set: { newValue in
                    guard let newValue, newValue != mode else { return }
                    // ⛔ `try?` stood here and it swallowed the ONE failure this whole family
                    // (#653–#674) exists to surface. `setLatencyMode` can throw; on a throw the
                    // buffer is unchanged, so the segment must snap BACK rather than sit lit
                    // over a size the session refused. Both branches end by re-deriving the
                    // mode from the buffer, which is the only value that can be trusted.
                    do {
                        try AudioConfiguration.setLatencyMode(newValue)
                    } catch {
                        log.audio("Buffer request refused: \(error.localizedDescription)")
                    }
                    // The THIRD `latencySnapshot()` read in this file, added deliberately and
                    // named: a buffer change is not a route change, so without it the floor
                    // above would keep showing the previous size and the control would look
                    // like it did nothing. The sibling guard's count moves with it (#364/#664).
                    mode = AudioConfiguration.currentLatencyMode
                    readout = AudioConfiguration.latencySnapshot()
                })) {
                ForEach(AudioConfiguration.LatencyMode.allCases) { option in
                    Text(option.shortName).tag(Optional(option))
                }
            }
            .pickerStyle(.segmented)
            Text(Self.bufferCaveat)
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ⚠️ THE COST IS IN THE COPY BECAUSE IT IS REAL AND ALREADY HAPPENED. 256 frames was the
    /// shipped default until dense polyphonic chords missed the render deadline and it was
    /// heard on the device as crackle (10.76.49). Offering the smaller buffer without saying
    /// that would hand the player a switch whose failure mode is a mystery.
    static let bufferCaveat = "Smaller buffer = less delay, tighter deadline. "
                            + "Dense chords have crackled at Low before — Normal is the safe default. "
                            + "This is a request: the system may grant less, and it resets on relaunch."

    /// The one sentence the numbers cannot carry themselves.
    ///
    /// "floor", never "total": hardware in + out + ONE buffer period is a LOWER BOUND on what
    /// the ear hears, not the round trip. Saying so beats letting the reader assume the
    /// stronger claim — the same retraction `latencyLine` carries for the log.
    static let caveat = "Lower bound — hardware plus one buffer. Effects add on top."
}

/// #828 — the codec verdict, visible whenever the Input sheet is open and monitoring is
/// OFF (while monitoring runs, `MonitorLatencyRow` carries the same sentence — one copy
/// on screen, never two, #416). Since #827 Echoel never requests HFP itself, so what
/// this row names is the cause we cannot prevent: another app or a call putting the
/// SHARED route on the mono call codec while Echoel plays. Renders NOTHING for a
/// healthy route (`note` is `nil` — no reassurance line nobody asked for).
///
/// ⚠️ A LEAF on purpose (10.76.41/50): the codec is read in THIS body only, never in
/// the Picker-hosting parent. Event-driven refresh — appear + `routeChangeNotification`,
/// no timer; adding one would be the freeze bug.
private struct RouteCodecRow: View {
    @State private var codec: AudioConfiguration.RouteCodec?

    var body: some View {
        Group {
            if let note = codec?.note {
                Text(note)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { codec = AudioConfiguration.latencySnapshot().codec }
        #if os(iOS)
        .onReceive(NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
                // AVAudioSession posts from its own thread; this writes `@State` on a
                // `@MainActor` view — same hop as every sibling handler in this file.
                codec = AudioConfiguration.latencySnapshot().codec
            }
        #endif
    }
}

#endif
