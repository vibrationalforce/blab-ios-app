#if canImport(SwiftUI)
import SwiftUI

// BroadcastView.swift
// Echoel — configure + control the phone-native broadcast (RTMP/SRT). Pairs with
// BroadcastPublisher (the rtmp.out/srt.out router sink). Honest about engine state:
// if the streaming engine isn't in this build, it says so instead of faking "live".

@MainActor
struct BroadcastView: View {

    @Environment(BroadcastPublisher.self) private var broadcast
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Broadcast")
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
        @Bindable var broadcast = broadcast
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Destination setup for live streaming (RTMP/SRT).")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                if !broadcast.engineAvailable {
                    Text("Streaming engine not installed in this build. Destination settings are saved and will work once it ships.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Protocol
                Picker("Protocol", selection: $broadcast.transport) {
                    ForEach(BroadcastPublisher.Transport.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                field("Ingest URL", text: $broadcast.url,
                      placeholder: "rtmp://a.rtmp.youtube.com/live2")
                secureField("Stream key", text: $broadcast.streamKey)

                if !broadcast.statusMessage.isEmpty {
                    Text(broadcast.statusMessage)
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The loudness of the mix before going live. ⛔ THE LABEL SAID "Output
                // loudness" until #316 — the meter sits at the master chain's INPUT, so on a
                // page about what leaves the device that word was the most misleading one
                // available. The grid itself now names its measurement point.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loudness").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    MasterLoudnessGrid()
                    // ⛔ Was "Most platforms target ≈ −14 LUFS integrated, true peak ≤ −1
                    // dBTP." — on the one page about what leaves the device, printed under a
                    // meter that measures the chain's input. #316 removed the machine's
                    // verdict; leaving this would have asked the reader to make the same one
                    // by eye. Doorless today (HaishinKit unlinked), fixed anyway so it does
                    // not wake up wrong.
                    Text("These numbers are the mix before the master chain, not the delivered stream.")
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    broadcast.isLive ? broadcast.stop() : broadcast.start()
                } label: {
                    Text(broadcast.isLive ? "Stop" : "Go Live")
                        .font(EchoelTheme.font(15, .semibold))
                        .foregroundStyle(broadcast.isLive ? EchoelTheme.onPrimary : .black)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(broadcast.isLive ? EchoelTheme.danger : EchoelTheme.text))
                }
                .buttonStyle(.plain)
                .disabled(!broadcast.isConfigured)

                // ⛔ A "turn broadcast on from the patchbay" tip stood here and was FALSE
                // (brand audit 2026-08-28): the patchbay is a pure dataflow surface —
                // `hasEnabledRoute(fromSource:)` has no production caller (BLE-3 lesson,
                // SignalRouter.swift), so connecting a route starts nothing.
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            TextField(placeholder, text: text)
                .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            SecureField("•••••••••••", text: text)
                .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }
}
#endif
