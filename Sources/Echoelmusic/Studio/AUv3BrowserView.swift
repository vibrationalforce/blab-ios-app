#if canImport(SwiftUI)
import SwiftUI

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

    var body: some View {
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

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if host.didScan && host.total == 0 {
                    Text("No Audio Units found. Install AUv3 instruments or effects from the App Store; they'll appear here.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let err = host.loadError {
                    Text(err).font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if host.loaded != nil { loadedBar }
                section("Instruments", host.instruments, icon: "pianokeys")
                section("Effects", host.effects, icon: "dial.medium")
                Text("Instruments load into the audio graph and play from the keyboard above. Effect insertion and showing a plugin's own interface are the next steps.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        .onAppear { if !host.didScan { host.scan() } }
    }

    // The currently-loaded instrument + a one-octave preview keyboard.
    private var loadedBar: some View {
        @Bindable var host = host
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(EchoelTheme.accent)
                Text(host.loaded?.name ?? "").font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.text).lineLimit(1)
                Spacer(minLength: 0)
                Button("Unload") { host.unload() }
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.danger)
            }
            Toggle(isOn: $host.replaceBuiltInVoice) {
                Text("Use plugin instead of Echoel's voice")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            }
            .tint(EchoelTheme.accent)
            previewKeyboard
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
        let isLoaded = host.loaded == au
        Button {
            if au.isInstrument { Task { await host.load(au) } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13))
                    .foregroundStyle(isLoaded ? EchoelTheme.accent : EchoelTheme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(au.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                    Text(au.manufacturer).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if host.isLoading && host.loaded != au {
                    ProgressView().controlSize(.small)
                } else if isLoaded {
                    Text("Loaded").font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.accent)
                } else if au.isInstrument {
                    Image(systemName: "play.circle").font(.system(size: 15)).foregroundStyle(EchoelTheme.dim)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(isLoaded ? EchoelTheme.accent.opacity(0.12) : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(isLoaded ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!au.isInstrument)
    }
}
#endif
