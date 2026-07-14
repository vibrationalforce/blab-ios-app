#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
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
                if host.didScan && host.total == 0 {
                    Text("No Audio Units found. Install AUv3 instruments or effects from the App Store; they'll appear here.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if host.hasNoThirdPartyUnits {
                    Text("Only Apple's built-in units showed up. Third-party AUv3 sometimes register late — this list keeps refreshing for a few seconds. If yours still don't appear, open each plugin's app once (that registers its AUv3 with iOS), then tap Rescan.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let err = host.loadError {
                    Text(err).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if host.loaded != nil || !host.loadedEffects.isEmpty || !host.loadedMasterEffects.isEmpty { loadedBar }
                section("Instruments", host.instruments, icon: "pianokeys")
                if !host.effects.isEmpty { effectTargetPicker }
                section("Effects", host.effects, icon: "dial.medium")
                Text("Tap an instrument to load it (play it from the keyboard or your song). Effects go to the target you pick: the instrument's own Channel chain (instrument → fx → master) or the Master bus (the whole mix → fx → output). Open any loaded plugin's own interface with “Open”. Each plugin's own settings return when you reload it.")
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

    @ViewBuilder
    private func section(_ title: String, _ items: [HostedAUInfo], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text("\(items.count)").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                ForEach(items) { au in row(au, icon: icon) }
            }
        }
    }

    @ViewBuilder
    private func row(_ au: HostedAUInfo, icon: String) -> some View {
        // Instrument is single-slot (Loaded badge); effects append to the targeted
        // chain, so they stay tappable (you can add more) and highlight when present.
        let highlighted: Bool = {
            if au.isInstrument { return host.loaded == au }
            return effectTarget == .master ? host.loadedMasterEffects.contains(au)
                                            : host.loadedEffects.contains(au)
        }()
        Button {
            Task {
                if !au.isInstrument && effectTarget == .master { await host.loadMasterEffect(au) }
                else { await host.load(au) }
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
        .disabled(host.isLoading)   // one load at a time — matches the host's re-entrancy guard
    }
}
#endif
