#if canImport(SwiftUI)
import SwiftUI

// PatchbayView.swift
// Echoel — the universal routing patchbay made visible. Each SOURCE lists the
// DESTINATIONS it can reach (same type directly, or via a converter like
// pitch→colour); tap to connect/disconnect. "Smart patch" applies every sensible
// connection at once. Honest: each endpoint shows its transport status (live vs
// soon), and the note explains which edges move bytes today. Binds to SignalRouter
// (persisted). See docs/dev/DMMW_ARCHITECTURE.md + Core/SignalRouting.swift.

@MainActor
struct PatchbayView: View {

    @Environment(SignalRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    #if canImport(Network)
    @Environment(ArtNetSender.self) private var artNet
    @Environment(SACNSender.self) private var sacn
    #endif

    /// `true` when hosted as a workspace surface rather than a sheet.
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Routing")
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
                headerBar
                #if canImport(Network)
                lichtSection
                #endif
                ForEach(router.graph.sources) { src in
                    sourceCard(src)
                }
                Text("Tap a destination to route a source to it. Compatible types connect directly or via a converter (e.g. pitch→colour, bio→MIDI CC). Light and spatial follow the music live today; other edges are authored here as their adapters come online.")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
    }

    #if canImport(Network)
    // MARK: - Licht (L1: Grand Master + Blackout, drives Art-Net AND sACN)

    private var lichtSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Licht").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
            HStack(spacing: 10) {
                EchoelValueField(label: "Master", value: grandMasterBinding,
                                 range: 0...1, unit: "", decimals: 2)
                Button {
                    let newState = !artNet.blackout
                    artNet.blackout = newState
                    sacn.blackout = newState
                } label: {
                    Text(artNet.blackout ? "Blackout AN" : "Blackout")
                        .font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(artNet.blackout ? EchoelTheme.onPrimary : EchoelTheme.text)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(artNet.blackout ? EchoelTheme.danger : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(artNet.blackout ? EchoelTheme.danger : EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(artNet.blackout ? "Blackout aktiv — Licht wieder einschalten" : "Blackout — Licht sofort dunkel")
            }
            Text("Master skaliert die Helligkeit aller gesendeten Lichtdaten (Art-Net + sACN). Blackout schaltet sofort dunkel; das Zurückkommen blendet flimmerfrei ein.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// One fader, both protocols — the patchbay is the "kleines Lichtpult".
    private var grandMasterBinding: Binding<Float> {
        Binding(
            get: { artNet.grandMaster },
            set: { v in
                artNet.grandMaster = v
                sacn.grandMaster = v
            }
        )
    }
    #endif

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("\(router.graph.routes.count) connections")
                .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
            Spacer(minLength: 0)
            Button { router.applyAllSuggestions() } label: {
                Label("Smart patch", systemImage: "wand.and.stars")
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
            }
            .buttonStyle(.plain)
            .disabled(router.suggestions().isEmpty)
            Button { router.clearAll() } label: {
                Text("Clear").font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(router.graph.routes.isEmpty)
        }
    }

    // MARK: - Source card

    private func sourceCard(_ src: SignalPort) -> some View {
        let sinks = router.graph.sinks.filter { $0.id != src.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: kindIcon(src.kind)).font(.system(size: 13)).foregroundStyle(EchoelTheme.accent)
                Text(src.name).font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                statusTag(src)
                Spacer(minLength: 0)
            }
            ForEach(sinks) { dst in
                destinationRow(src, dst)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func destinationRow(_ src: SignalPort, _ dst: SignalPort) -> some View {
        let check = router.graph.check(sourceID: src.id, sinkID: dst.id)
        let compatible: Bool = { if case .ok = check { return true } else { return false } }()
        let connected = router.isConnected(src.id, dst.id)
        let conv = converterName(check)
        return Button {
            if compatible { router.toggle(src.id, dst.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: connected ? "checkmark.circle.fill" : (compatible ? "circle" : "minus.circle"))
                    .font(.system(size: 14))
                    .foregroundStyle(connected ? EchoelTheme.accent : (compatible ? EchoelTheme.dim : EchoelTheme.border))
                Image(systemName: kindIcon(dst.kind)).font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                Text(dst.name).font(EchoelTheme.font(13)).foregroundStyle(compatible ? EchoelTheme.text : EchoelTheme.dim)
                if let conv { Text(conv).font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim) }
                Spacer(minLength: 0)
                statusTag(dst)
            }
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!compatible)
        .accessibilityLabel("\(src.name) to \(dst.name)")
        .accessibilityValue(connected ? "connected" : (compatible ? "not connected" : "incompatible"))
    }

    // MARK: - Helpers

    private func converterName(_ check: SignalGraph.ConnectionCheck) -> String? {
        if case let .ok(cid) = check, let cid {
            return router.graph.catalog.converters.first { $0.id == cid }?.name
        }
        return nil
    }

    /// "soon" tag for roadmap transports — keeps the patchbay honest (no dead points).
    @ViewBuilder
    private func statusTag(_ port: SignalPort) -> some View {
        if port.transport.status == .roadmap {
            Text("soon")
                .font(EchoelTheme.font(9, .semibold)).foregroundStyle(EchoelTheme.dim)
                .padding(.horizontal, 5).frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    private func kindIcon(_ kind: SignalKind) -> String {
        switch kind {
        case .controlBio:     return "waveform.path.ecg"
        case .controlMusical: return "music.note"
        case .controlMacro:   return "dial.medium"
        case .note:           return "pianokeys"
        case .controlChange:  return "slider.horizontal.3"
        case .audio:          return "speaker.wave.2"
        case .light:          return "lightbulb"
        case .spatial:        return "move.3d"
        case .clock:          return "metronome"
        case .video:          return "film"
        case .visual:         return "sparkles"
        }
    }
}
#endif
