// LiveColaboView.swift
// Echoel — Live Colabo (nearby). The DMMW "Live Collaboration" surface: go live,
// discover nearby Echoel devices, connect, and share your current session both
// ways. Built on MultipeerSession (Apple MultipeerConnectivity, no external dep).
// Real-time tempo/phase lock (Ableton Link) is a separate device-verified step.
//
// Uncodixfy: solid fills, ≤8px radius, 1px borders, colour/opacity feedback only.

#if canImport(SwiftUI) && canImport(MultipeerConnectivity)
import SwiftUI

@MainActor
struct LiveColaboView: View {

    @Environment(MultipeerSession.self) private var colab
    @Environment(ProjectStore.self) private var projects
    @Environment(\.dismiss) private var dismiss

    /// Snapshot of the live session to send (provided by the host view).
    let currentSession: () -> Project
    /// Load a received session into the live instrument.
    let onLoadShared: (Project) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    goLiveRow
                    Text(colab.status)
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)

                    if let inc = colab.incoming, let project = inc.project {
                        incomingCard(inc.senderName, project)
                    }

                    if colab.isLive {
                        shareButton
                        if !colab.connectedPeerNames.isEmpty { connectedSection }
                        discoveredSection
                    } else {
                        Text("Two Echoelmusic devices on the same Wi-Fi find each other here. Go live, connect, and share your session both ways — a starting point to jam from together.")
                            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Live Colabo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onDisappear { colab.stop() }
        }
    }

    // MARK: - Pieces

    private var goLiveRow: some View {
        Button { colab.isLive ? colab.stop() : colab.start() } label: {
            Label(colab.isLive ? "Stop" : "Go Live (nearby)",
                  systemImage: colab.isLive ? "stop.fill" : "dot.radiowaves.left.and.right")
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(colab.isLive ? EchoelTheme.onPrimary : EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(colab.isLive ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: colab.isLive ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var shareButton: some View {
        Button { colab.share(project: currentSession()) } label: {
            Label("Share current session", systemImage: "square.and.arrow.up.on.square")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
        }
        .buttonStyle(.plain)
        .disabled(colab.connectedPeerNames.isEmpty)
        .opacity(colab.connectedPeerNames.isEmpty ? 0.4 : 1)
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            ForEach(colab.connectedPeerNames, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.checkmark").foregroundStyle(EchoelTheme.accent)
                    Text(name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Spacer()
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nearby").font(EchoelTheme.font(13, .medium)).foregroundStyle(EchoelTheme.text)
            if colab.discovered.isEmpty {
                Text("Searching…").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            }
            ForEach(colab.discovered) { peer in
                HStack(spacing: 8) {
                    Image(systemName: "iphone").foregroundStyle(EchoelTheme.dim)
                    Text(peer.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Spacer()
                    Button { colab.invite(peer.name) } label: {
                        Text("Invite").font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    private func incomingCard(_ from: String, _ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session from \(from)")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
            Text("\(project.name) · \(project.style.displayName) · \(project.key.shortName) · \(String(format: "%.0f", project.bpm)) BPM")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { onLoadShared(project); colab.clearIncoming() } label: {
                    Text("Load").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                }
                .buttonStyle(.plain)
                Button { projects.save(project); colab.clearIncoming() } label: {
                    Text("Save").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { colab.clearIncoming() } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.accent.opacity(0.5), lineWidth: 1))
    }
}
#endif
