#if canImport(SwiftUI)
import SwiftUI

// WorkspaceView.swift
// Echoel — the app HOME. Shell flip (founder "Ja", 2026-07-06, from the two-stream
// strategy synthesis in scratchpads/STRATEGY_OPTIMAL_FORM_2026-07-06.md): the calm
// bio-paced SESSION is now the app — the first and only thing a launch shows. The
// whole generative studio (header chrome + transport + EchoelStudioView + floating
// visual) lives behind ONE deliberate "Studio" door as a fullScreenCover. This
// realizes the 2026-07-02 pivot that had been decided but never flipped in the
// shell: before this, the 2,756-LOC studio god-view was home and the Session was a
// hidden modal — exactly inverted. Reversible: swap home/cover back.
//
// Render safety (skill: swiftui-render-safety):
//  • WorkspaceView still owns exactly ONE fullScreenCover (now the studio, was the
//    session) — EchoelStudioView's own ~16-modal chain is untouched and NOT grown.
//  • No high-frequency @Observable is read in this body or StudioShellView's body;
//    live bio stays in leaf views (BioStripView, PulseMonitorMiniLive, Session leaves).

@MainActor
struct WorkspaceView: View {

    /// The one door out of the calm home. LOW-frequency state.
    @State private var showStudio = false

    /// Studio audio must not bleed under the calm Session home: when the studio
    /// door closes, stop the pattern clock. (BeatPlayer is only *called* in the
    /// dismiss closure — never read in body, so no observation is registered.)
    @Environment(BeatPlayer.self) private var player
    @Environment(Transport.self) private var transport

    var body: some View {
        SessionView(presentStudio: $showStudio)
            .background(EchoelTheme.bg.ignoresSafeArea())
            .fullScreenCover(isPresented: $showStudio, onDismiss: stopStudioAudio) {
                StudioShellView()
            }
    }

    /// The Session home is silent by design — leaving the studio while the beat
    /// runs would trap the user with playing music and no visible transport.
    private func stopStudioAudio() {
        if transport.isPlaying { player.pattern.stop() }
    }
}

// MARK: - Studio shell (the second door — the full instrument, unchanged inside)

/// Everything that used to be the shell: brand header + persistent transport +
/// the bio-generative instrument + the floating immersive visual. Present-only —
/// the launch path never constructs this view, which also keeps first-render
/// metadata small (black-screen class shrinks, never grows).
@MainActor
private struct StudioShellView: View {

    @Environment(\.dismiss) private var dismiss

    /// LOW-frequency flag only (isRunning = start/stop) — never a ~10 Hz value in
    /// this body (freeze rule). The live pulse number lives in the bio strip's leaf.
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    /// The immersive visual rides along as a FLOATING, resizable, show/hide window —
    /// toggled from the header monitor, persisted across launches. Default TRUE so
    /// the living Aurora greets the user on entering the STUDIO ("wow von Sekunde 1",
    /// Council 2026-07-03); flash-safe + reduce-motion-aware, one tap to hide.
    @AppStorage("visual.floating.visible") private var floatingVisualVisible = true

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(EchoelTheme.border)
                TransportBar()
                Divider().overlay(EchoelTheme.border)
                // The instrument. Its Session card now RETURNS to the Session home
                // (dismisses this cover) — same muscle memory, inverted shell.
                EchoelStudioView(presentSession: Binding(
                    get: { false },
                    set: { wantsSession in if wantsSession { dismiss() } }
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The immersive visual floats ABOVE the whole studio so its FULLSCREEN
            // size can cover the chrome too (true Vollbild). In the floating sizes it
            // docks bottom-trailing; its transparent area never blocks the header/
            // transport. One Metal path app-wide (GPU rule).
            #if canImport(MetalKit) && canImport(UIKit)
            if floatingVisualVisible {
                FloatingVisualWindow(isPresented: $floatingVisualVisible)
            }
            #endif
        }
        .background(EchoelTheme.bg.ignoresSafeArea())
    }

    /// Persistent brand header. Left: back-to-Session door + app mark. Centre:
    /// "Echoelmusic" + version. Right: the immersive-visual monitor toggle.
    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Echoelmusic")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                Text(Self.versionString)
                    .font(EchoelTheme.font(9))
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityLabel("Version \(Self.versionString)")
            }
            HStack(spacing: 8) {
                // LEFT: back to the Session (the home). The one way out of the studio.
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 30, height: 30)
                        .background(EchoelTheme.fill, in: RoundedRectangle(cornerRadius: EchoelTheme.radius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close studio — back to the session")
                EchoelLogoMark().frame(width: 22, height: 22)
                Spacer(minLength: 0)
                // RIGHT: immersive-visual monitor — tap to show/hide the floating visual.
                #if canImport(AVFoundation)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { floatingVisualVisible.toggle() }
                } label: {
                    ImmersiveMonitorMini(active: cameraRPPG.isRunning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(floatingVisualVisible ? "Hide floating visual" : "Show floating visual")
                #endif
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(EchoelTheme.bg)
    }

    /// Short version + build, e.g. "v10.35.2 (1550)" — from the bundle, so it always
    /// reflects the actual installed build.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}

// MARK: - Persistent transport bar (DAW chrome)

/// Always-on transport across the instrument: Play/Stop on the left, the Tempo field, and
/// a bars.beats.sixteenths position readout on the right. A LEAF view so its reads never
/// rebuild the instrument tree. It reads only the LOW-frequency Transport state (isPlaying,
/// tempo); the ~10 Hz position lives in its own `TransportPositionView` leaf so the
/// buttons/field don't churn (freeze rule). Play/Stop drives PatternEngine — the clock that
/// RELAYS into Transport — so the position/tempo shown stay authoritative.
@MainActor
private struct TransportBar: View {
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player
    @Environment(MetronomeVoice.self) private var metronome
    // Shared with the Compose panel (same @AppStorage keys + defaults). Read here so a
    // transport-bar tempo edit while LOCKED also persists the locked value — otherwise the
    // next generate() would snap the clock back to the stale lockedBPM.
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    var body: some View {
        HStack(spacing: 12) {
            Button { toggle() } label: {
                Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.text)
                    .frame(width: 38, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(transport.isPlaying ? "Stop" : "Play")

            // NO tempo number here anymore (founder 2026-07-04: "zwei Anzeigen irritieren
            // immernoch") — the chrome's one live number is the PULSE in the bio strip. The
            // musical tempo lives in the Composition panel's BodyTempoField (runs along with
            // the biofeedback rate, 4 decimals, lockable). The lock stays here for one-tap
            // freezing from anywhere; its state mirrors the panel (same @AppStorage).

            lockButton

            Spacer(minLength: 0)

            TransportPositionView()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(EchoelTheme.bg)
    }

    /// FIX the tempo, one tap, always reachable (founder: "Tempo fixen muss aber auch immer
    /// gehen"). Locking freezes the tempo you're hearing right now and stops the body's gentle
    /// tempo-follow — from then on biofeedback only shapes the SOUND (filter/timbre), never the
    /// beat. Same `studio.lockBPM`/`lockedBPM` state as the Composition panel's toggle, so both
    /// stay in sync; freezing here captures the live tempo directly (robust even when that panel
    /// is collapsed and its onChange isn't mounted).
    private var lockButton: some View {
        Button {
            lockBPM.toggle()
            if lockBPM {
                lockedBPM = transport.tempo.rounded()
                player.pattern.setTempo(lockedBPM)   // freeze exactly what's playing (no jump)
                metronome.bpm = transport.tempo
            }
        } label: {
            Image(systemName: lockBPM ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(lockBPM ? EchoelTheme.accent : EchoelTheme.dim)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(lockBPM ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lockBPM ? "Tempo locked — tap to let it follow the body" : "Lock tempo")
        .accessibilityHint("When locked, the beat holds and biofeedback only shapes the sound")
    }

    private func toggle() {
        if transport.isPlaying { player.pattern.stop() }
        else { player.pattern.play() }
    }
}

/// The moving playhead — bars.beats.sixteenths (1-based, DAW convention). Isolated in
/// its OWN leaf because `transport.position` updates on every step (~10 Hz at 120 BPM);
/// keeping the read here means only this tiny label rebuilds, never the transport bar's
/// buttons/field or (crucially) the instrument below. Monospaced so width is steady.
@MainActor
private struct TransportPositionView: View {
    @Environment(Transport.self) private var transport
    /// The loop size (shared @AppStorage with the Compose panel). Read here so the chrome
    /// always SHOWS how big the loop is + where we are inside it (founder: "optische Anzeige,
    /// je nachdem wie groß der Loop umgestellt ist"). Low-frequency — safe in this leaf.
    @AppStorage("studio.loopBars") private var loopBars: LoopBarLength = .four

    var body: some View {
        let pos = transport.position
        let bars = max(1, loopBars.rawValue)
        let barInLoop = pos.bar % bars                 // 0-based bar within the current loop
        let sixteenth = pos.step % Transport.stepsPerBeat
        // Fraction through the whole loop (bars × 16 steps) — drives the slim progress bar.
        let loopFraction = Double(barInLoop * Transport.stepsPerBar + pos.step)
            / Double(bars * Transport.stepsPerBar)
        return HStack(spacing: 8) {
            // Slim loop-progress bar: fills once per loop so the loop length is legible at a
            // glance (opacity/fill only — no glow, per the UI rules).
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.text.opacity(0.12)).frame(width: 44, height: 4)
                Capsule().fill(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: 44 * max(0.02, loopFraction), height: 4)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%d.%d.%d", barInLoop + 1, pos.beat + 1, sixteenth + 1))
                    .font(EchoelTheme.font(14, .medium).monospacedDigit())
                    .foregroundStyle(transport.isPlaying ? EchoelTheme.accent : EchoelTheme.dim)
                Text("loop \(barInLoop + 1)/\(bars)")
                    .font(EchoelTheme.font(10).monospacedDigit())
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue("Bar \(barInLoop + 1) of \(bars), beat \(pos.beat + 1)")
    }
}
#endif
