#if canImport(SwiftUI)
import SwiftUI

// AUv3BrowserView.swift
// Echoel — the installed-plugin browser, first step of AUv3 hosting. Shows the Audio
// Unit instruments and effects on this device (the ones a channel could host). Honest:
// this lists what's installed; loading one into a channel + embedding its UI is the
// next cycle. See Audio/AUv3Host.swift + docs/dev/DMMW_ARCHITECTURE.md.

@MainActor
struct AUv3BrowserView: View {

    @State private var host = AUv3Host()
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
                section("Instruments", host.instruments, icon: "pianokeys")
                section("Effects", host.effects, icon: "dial.medium")
                Text("Found on this device. Hosting a plugin inside an Echoel channel — its sound in your graph, its UI in an Echoel panel — is the next step.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        .onAppear { if !host.didScan { host.scan() } }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [HostedAUInfo], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text("\(items.count)").font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                ForEach(items) { au in
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(au.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                            Text(au.manufacturer).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 40)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
            }
        }
    }
}
#endif
