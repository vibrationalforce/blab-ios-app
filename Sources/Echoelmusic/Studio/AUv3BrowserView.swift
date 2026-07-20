#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(UIKit)
import UIKit
#endif

// AUv3BrowserView.swift
// Echoel — the AUv3 browser + host. Lists the Audio Unit instruments and effects
// installed on this device, loads a chosen INSTRUMENT into the live audio graph,
// and lets you play it from a small preview keyboard. Honest scope: instruments
// load + play here; effect insertion and embedding the plugin's own UI / state
// save are the next steps. See Audio/AUv3Host.swift + docs/dev/DMMW_ARCHITECTURE.md.

@MainActor
struct AUv3BrowserView: View {

    @Environment(AUv3Host.self) private var host
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    /// When the browser is opened FOR a specific track, a tap on an instrument or
    /// effect assigns it straight to that track (founder 2026-07-20: "eine ganz
    /// einfache Lösung für externe Effekte und Instrumente … direkt auf die Spur")
    /// — no Browse → load → dismiss → "Assign loaded" round-trip. nil = the global
    /// browser, byte-identical to before.
    struct LaneAssignTarget {
        let name: String
        /// Set this track's instrument to the tapped unit.
        let assignInstrument: (HostedAUInfo) -> Void
        /// Append the tapped effect to this track's chain; false if the chain is full.
        let assignEffect: (HostedAUInfo) -> Bool
    }
    var laneTarget: LaneAssignTarget? = nil

    /// Transient confirmation after a lane assignment ("<plugin> → <track>").
    @State private var assignBadge: String?

    /// Which hosted plugin's own UI to present — the instrument, a channel insert
    /// effect, or a master-bus effect (by chain index).
    private struct PluginUIRequest: Identifiable {
        let id = UUID(); let title: String
        enum Target: Equatable { case instrument; case channelEffect(Int); case masterEffect(Int) }
        let target: Target
    }
    @State private var uiRequest: PluginUIRequest?

    /// Where a tapped EFFECT is inserted: the instrument's own channel, or the master bus.
    private enum EffectTarget: String, CaseIterable { case channel = "Channel"; case master = "Master" }
    @State private var effectTarget: EffectTarget = .channel

    /// Momentary "Copied" confirmation for the diagnostic copy button.
    @State private var copiedDiagnostic = false

    /// The technical guidance stays collapsed by default — a professional sheet
    /// never fronts iOS-registry internals. Pros/support can expand it on demand.
    @State private var showTroubleshoot = false

    /// Copy the full AUv3 scan diagnostic to the clipboard so the founder can paste
    /// the deciding fact (which makers iOS returned to this app) in one tap.
    private func copyDiagnostic(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copiedDiagnostic = true
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Plugins (AUv3)")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                        }
                }
            }
        }
        .sheet(item: $uiRequest) { req in pluginUISheet(req) }
    }

    @ViewBuilder
    private func pluginUISheet(_ req: PluginUIRequest) -> some View {
        NavigationStack {
            Group {
                #if canImport(UIKit) && canImport(AVFoundation)
                if let au = resolveAudioUnit(req.target) {
                    AUv3PluginUIView(audioUnit: au).ignoresSafeArea()
                } else {
                    Text("Plugin unavailable.").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                }
                #else
                Text("Plugin interfaces need iOS.").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                #endif
            }
            .navigationTitle(req.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { uiRequest = nil } }
            }
        }
    }

    #if canImport(AVFoundation)
    /// Resolve the AUAudioUnit for a UI request (instrument / channel fx / master fx).
    private func resolveAudioUnit(_ target: PluginUIRequest.Target) -> AUAudioUnit? {
        switch target {
        case .instrument:            return host.instrumentAudioUnit()
        case .channelEffect(let i):  return host.effectAudioUnit(at: i)
        case .masterEffect(let i):   return host.masterEffectAudioUnit(at: i)
        }
    }
    #endif

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Rescan header: opening the browser always refreshes (below), and this
                // button re-scans on demand so a plugin you just installed shows up
                // without relaunching (was scan-once → stale).
                HStack(spacing: 8) {
                    Text("\(host.total) installed")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    Spacer(minLength: 0)
                    Button { host.scan() } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Re-scans for Audio Units you've installed since opening the app")
                }
                // Lane-assign mode: make it obvious a tap lands on THIS track, and
                // echo each assignment (founder: direct-to-track, no round-trip).
                if let target = laneTarget {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 12))
                            .foregroundStyle(EchoelTheme.accent)
                        Text(assignBadge ?? "Tap an instrument or effect to add it to “\(target.name)”.")
                            .font(EchoelTheme.font(12)).foregroundStyle(assignBadge == nil ? EchoelTheme.dim : EchoelTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.accent.opacity(0.4), lineWidth: 1))
                }
                // Calm, human states only — no iOS-registry internals, no error
                // codes, no "quit the app / open GarageBand" walls on the main sheet
                // (founder 2026-07-20: "solche workarounds nerven — unprofessionell").
                // Any genuine "your plugins aren't here yet" case gets ONE quiet line
                // plus an OPTIONAL, collapsed troubleshooting disclosure below.
                if host.didScan && host.total == 0 {
                    quietNote("Install AUv3 instruments or effects from the App Store — they appear here automatically.")
                    troubleshootDisclosure
                } else if host.registryColdForProcess || host.hasNoThirdPartyUnits {
                    quietNote("Only the built-in Apple Audio Units are here right now. Instruments and effects you install appear automatically.")
                    troubleshootDisclosure
                }
                if let err = host.loadError {
                    Text(err).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // AU-2: restore state stays visible — a failed restore is the one
                // clue why a plugin "vanished" after relaunch (loadError above is
                // cleared on every appear; this notice is dismissed explicitly).
                if host.isRestoringChains {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Restoring last session…")
                            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    }
                }
                if let notice = host.restoreNotice {
                    HStack(alignment: .top, spacing: 8) {
                        Text(notice).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("OK") { host.clearRestoreNotice() }
                            .font(EchoelTheme.font(12, .semibold))
                            .foregroundStyle(EchoelTheme.text)
                            .buttonStyle(.plain)
                    }
                }
                // The global host preview (loaded instrument + preview keyboard) is
                // about the shared audition chain — hide it in lane-assign mode, where
                // the point is to write onto the track, not audition globally.
                if laneTarget == nil,
                   host.loaded != nil || !host.loadedEffects.isEmpty || !host.loadedMasterEffects.isEmpty { loadedBar }
                // Sorted into the three families a production/performance workflow
                // reaches for (founder 2026-07-20): MIDI plugins · instruments · audio
                // effects. Each family lays out in an ADAPTIVE grid — one column on a
                // phone, more as the window widens (iPad / landscape / Stage Manager).
                categorySection("MIDI Plugins", host.midiPlugins, icon: "pianokeys.inverse", kind: .midiPlugin)
                categorySection("Instruments", host.instruments, icon: "pianokeys", kind: .instrument)
                // Channel/Master picker only matters for the global host chain.
                if laneTarget == nil, !host.effects.isEmpty { effectTargetPicker }
                categorySection("Audio Effects", host.effects, icon: "dial.medium", kind: .audioEffect)
                Text(laneTarget == nil
                     ? "Tap an instrument to load it; tap an effect to add it to the Channel or Master chain you've selected. Open a loaded plugin's own controls with “Open”."
                     : "Tap an instrument to set this track's sound; tap an effect to add it to the track's chain.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        // Always refresh on open so newly-installed AUv3 appear (was scan-once → stale),
        // and clear any stale load error from a previous visit (QA #5).
        .onAppear { host.clearLoadError(); host.scan() }
    }

    /// A single, calm status line — muted, no icon-shout, no error code. The
    /// professional replacement for the old troubleshooting walls.
    private func quietNote(_ text: String) -> some View {
        Text(text)
            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Optional, COLLAPSED-by-default help. A curious user or support can open it;
    /// everyone else never sees registry jargon. Gentle human steps + a discreet
    /// "copy details" for a bug report (the technical string lives here, not on the
    /// main sheet).
    @ViewBuilder private var troubleshootDisclosure: some View {
        DisclosureGroup(isExpanded: $showTroubleshoot) {
            VStack(alignment: .leading, spacing: 8) {
                // The genuinely effective cold-registry sequence (device log
                // 2026-07-20: many plugins installed, iOS still served this app only
                // Apple units). Opening another AU host once re-scans the shared
                // registry; a restart is what actually registers newly-installed
                // plugins system-wide.
                helpStep("Open GarageBand (or another Audio Unit host) once and view its plugin list — that wakes up iOS's shared plugin registry — then return here and tap Rescan.")
                helpStep("Still not showing? Restart your iPhone, reopen Echoelmusic, and tap Rescan. iOS often only registers newly-installed plugins after a restart.")
                if let diag = host.diagnostic {
                    Button { copyDiagnostic(diag.report) } label: {
                        Label(copiedDiagnostic ? "Copied" : "Copy details for support",
                              systemImage: copiedDiagnostic ? "checkmark" : "doc.on.doc")
                            .font(EchoelTheme.font(11, .semibold))
                            .foregroundStyle(EchoelTheme.dim)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Not seeing a plugin you installed?")
                .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.dim)
        }
        .tint(EchoelTheme.dim)
        .padding(.top, 2)
    }

    private func helpStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(EchoelTheme.dim).frame(width: 3, height: 3).padding(.top, 7)
            Text(text).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Where tapped effects land — the instrument channel or the master bus.
    private var effectTargetPicker: some View {
        Picker("Effect target", selection: $effectTarget) {
            ForEach(EffectTarget.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
        }
        .pickerStyle(.segmented)
    }

    // The hosted channel: instrument (+ insert effect) + a one-octave preview keyboard.
    private var loadedBar: some View {
        @Bindable var host = host
        return VStack(alignment: .leading, spacing: 8) {
            if let inst = host.loaded {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(EchoelTheme.accent)
                    Text(inst.name).font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(EchoelTheme.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Open") { uiRequest = .init(title: inst.name, target: .instrument) }
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.accent)
                    Button("Unload") { host.unload() }
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.danger)
                }
            }
            // Insert-effect chain, in signal order.
            ForEach(Array(host.loadedEffects.enumerated()), id: \.element.id) { index, fx in
                HStack(spacing: 8) {
                    Image(systemName: "dial.medium").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                    Text("→ \(fx.name)").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Open") { uiRequest = .init(title: fx.name, target: .channelEffect(index)) }
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.accent)
                    Button("Remove") { host.unloadEffect(at: index) }
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                }
            }
            if host.loaded == nil && !host.loadedEffects.isEmpty {
                Text("Load an instrument to feed these effects.")
                    .font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim)
            }
            // Master-bus FX chain (processes the whole mix → output).
            if !host.loadedMasterEffects.isEmpty {
                Text("Master bus").font(EchoelTheme.font(10, .semibold)).foregroundStyle(EchoelTheme.dim)
                ForEach(Array(host.loadedMasterEffects.enumerated()), id: \.element.id) { index, fx in
                    HStack(spacing: 8) {
                        Image(systemName: "dial.medium").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                        Text("Mix → \(fx.name)").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Open") { uiRequest = .init(title: fx.name, target: .masterEffect(index)) }
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.accent)
                        Button("Remove") { host.unloadMasterEffect(at: index) }
                            .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                    }
                }
            }
            if host.loaded != nil {
                Toggle(isOn: $host.replaceBuiltInVoice) {
                    Text("Use plugin instead of Echoelmusic's voice")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                }
                .tint(EchoelTheme.accent)
                previewKeyboard
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        // AU-2 review residual: an Unload/Remove DURING the restore window would
        // run but its persist is suppressed — the plugin would resurrect next
        // launch. Disable the whole bar for the few-second restore, like the
        // load rows.
        .disabled(host.isRestoringChains)
    }

    // 12 keys from middle C — tap to hear the loaded instrument.
    private var previewKeyboard: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { semitone in
                let pitch = UInt8(60 + semitone)
                Button {
                    host.noteOn(pitch)
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        host.noteOff(pitch)
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isBlack(semitone) ? EchoelTheme.text.opacity(0.18) : EchoelTheme.fill)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(EchoelTheme.border, lineWidth: 1))
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isBlack(_ semitone: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(semitone % 12)
    }

    /// One plugin family, laid out in an adaptive grid. On a phone this is a single
    /// column; the grid grows to 2–3 columns as width allows so a big installed
    /// library stays scannable in a production/performance session. MIDI plugins are
    /// display-only for now (routing lands in an update); instruments + effects load.
    @ViewBuilder
    private func categorySection(_ title: String, _ items: [HostedAUInfo], icon: String,
                                 kind: HostedAUInfo.Category) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text("\(items.count)").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(items) { au in row(au, icon: icon, kind: kind) }
                }
                if kind == .midiPlugin {
                    Text("Detected on this device. Instruments and audio effects load and play now; MIDI-plugin routing arrives in an update.")
                        .font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ au: HostedAUInfo, icon: String, kind: HostedAUInfo.Category) -> some View {
        if kind == .midiPlugin {
            midiRow(au, icon: icon)
        } else {
            loadableRow(au, icon: icon)
        }
    }

    /// A MIDI-processor plugin: shown so the library is complete, but NOT tappable —
    /// MIDI routing isn't wired yet, so a load affordance would be a dead tap. Honest,
    /// calm, professional (no fake action).
    private func midiRow(_ au: HostedAUInfo, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
            VStack(alignment: .leading, spacing: 1) {
                Text(au.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                Text(au.manufacturer).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("MIDI").font(EchoelTheme.font(9, .semibold)).foregroundStyle(EchoelTheme.dim)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(EchoelTheme.fill))
        }
        .frame(height: 40)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func loadableRow(_ au: HostedAUInfo, icon: String) -> some View {
        // Instrument is single-slot (Loaded badge); effects append to the targeted
        // chain, so they stay tappable (you can add more) and highlight when present.
        // In lane-assign mode the highlight (global-host state) doesn't apply.
        let highlighted: Bool = {
            if laneTarget != nil { return false }
            if au.isInstrument { return host.loaded == au }
            return effectTarget == .master ? host.loadedMasterEffects.contains(au)
                                            : host.loadedEffects.contains(au)
        }()
        Button {
            if let target = laneTarget {
                // Direct-to-track: write the assignment, echo it, no global load.
                if au.isInstrument {
                    target.assignInstrument(au)
                    assignBadge = "“\(au.name)” → \(target.name)"
                } else {
                    assignBadge = target.assignEffect(au)
                        ? "“\(au.name)” → \(target.name)"
                        : "\(target.name)'s effect chain is full."
                }
            } else {
                Task {
                    if !au.isInstrument && effectTarget == .master { await host.loadMasterEffect(au) }
                    else { await host.load(au) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13))
                    .foregroundStyle(highlighted ? EchoelTheme.accent : EchoelTheme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(au.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                    Text(au.manufacturer).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if host.isLoading {
                    ProgressView().controlSize(.small)
                } else if au.isInstrument && highlighted {
                    Text("Loaded").font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.accent)
                } else {
                    Image(systemName: au.isInstrument ? "play.circle" : "plus.circle")
                        .font(.system(size: 15)).foregroundStyle(EchoelTheme.dim)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(highlighted ? EchoelTheme.accent.opacity(0.12) : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(highlighted ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // One load at a time (host re-entrancy guard) — AND the whole restore
        // window (AU-2 review: a tap in the gap between two restore loads would
        // be guard-dropped with no feedback while the row looked enabled).
        .disabled(host.isLoading || host.isRestoringChains)
    }
}
#endif
