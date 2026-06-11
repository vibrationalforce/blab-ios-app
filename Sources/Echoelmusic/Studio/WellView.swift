#if canImport(SwiftUI)
import SwiftUI

/// "Well" tab — evidence-based breath & coherence. Shows the live coherence
/// score (legible number first), the supporting HR/HRV/breath readouts, and
/// a paced-breathing guide. Resonance breathing near ~6 breaths/min maximizes
/// HRV amplitude (baroreflex resonance) — the pacer guides that rhythm and the
/// coherence number reflects the effect in real time.
///
/// Reads the EngineBus snapshot directly (same pattern as BioStripView). Pure
/// readout + a slow, functional breath animation (≈0.1 Hz — far under the 3 Hz
/// WCAG flash limit). House UI: solid fills, legible numbers first, no glow.
@MainActor
struct WellView: View {

    @Environment(EngineBus.self) private var bus
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    #if canImport(CoreHaptics)
    @Environment(HapticController.self) private var haptics
    #endif

    @State private var breathsPerMin: Double = 6
    @State private var inhaling = false
    @State private var showVisual = false

    /// Seconds per half-breath (inhale or exhale) at the chosen rate.
    private var halfCycle: Double { 30.0 / max(breathsPerMin, 1) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                coherenceHeadline
                readoutRow
                if showHRVDetail { hrvDetailRow }
                pacer
                immersiveButton
                #if canImport(CoreHaptics)
                hapticsToggle
                #endif
                #if canImport(AVFoundation)
                cameraPulseButton
                #endif
                evidenceNote
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        #if os(iOS)
        .fullScreenCover(isPresented: $showVisual) { BioVisualView() }
        #endif
    }

    #if canImport(CoreHaptics)
    /// Arms the eyes-free haptic transport pulse (off by default). A quarter-note
    /// tap you can feel without watching the screen — strong on the down-beat.
    private var hapticsToggle: some View {
        Toggle(isOn: Binding(get: { haptics.isEnabled },
                             set: { haptics.isEnabled = $0 })) {
            Label("Haptic pulse (eyes-free)", systemImage: "hand.tap.fill")
        }
        .tint(EchoelTheme.accent)
        .padding(.horizontal, 4)
    }
    #endif

    private var immersiveButton: some View {
        Button {
            showVisual = true
        } label: {
            Label("Immersive visual", systemImage: "circle.hexagongrid.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(.green)
    }

    #if canImport(AVFoundation)
    /// Opt-in camera rPPG. Point the front camera at your face (or cover the
    /// back lens with a fingertip) — the bio strip fills in from the camera.
    /// Runtime pulse quality is device-dependent.
    private var cameraPulseButton: some View {
        VStack(spacing: 8) {
            Button {
                if cameraRPPG.isRunning {
                    cameraRPPG.stop()
                } else {
                    Task { await cameraRPPG.start(publishing: bus) }
                }
            } label: {
                Label(cameraRPPG.isRunning ? "Stop camera pulse" : "Measure pulse (camera)",
                      systemImage: cameraRPPG.isRunning ? "stop.circle.fill" : "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(cameraRPPG.isRunning ? EchoelTheme.danger : EchoelTheme.accent)

            if cameraRPPG.isRunning {
                Text("Cover the **rear camera + flash** with a fingertip and hold still.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EchoelTheme.dim)
                Text("Camera pulse is motion-sensitive — movement and bass vibration disrupt the optical signal. For loud or active performance, pair a Bluetooth heart-rate strap (Polar, Wahoo, any standard HR device).")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EchoelTheme.dim)
                measurementControl
            }
        }
    }

    /// Measurement control: a status light (Leuchte) + a lock-progress bar
    /// (Ladebalken) so the user can see acquisition advance to a confident read.
    private var measurementControl: some View {
        let locked = cameraRPPG.isLocked
        let lightColor: Color = !cameraRPPG.fingerDetected ? EchoelTheme.dim
            : (locked ? EchoelTheme.accent : Color.orange)
        let statusText = !cameraRPPG.fingerDetected ? "Place fingertip"
            : (locked ? "Locked" : "Acquiring…")
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(lightColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(EchoelTheme.border, lineWidth: 1))
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
                if cameraRPPG.detectedBPM > 0 {
                    Text("\(Int(cameraRPPG.detectedBPM)) bpm")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(EchoelTheme.text)
                }
            }
            pulseWaveform
            ProgressView(value: locked ? 1 : cameraRPPG.confidence)
                .tint(locked ? EchoelTheme.accent : Color.orange)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// Live pulse waveform ("Stimmungsbild") — the bandpass-filtered signal in
    /// real time. Flat line = no signal reaching the sensor; a clear wave = pulse.
    private var pulseWaveform: some View {
        Canvas { ctx, size in
            // baseline
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height / 2))
            base.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(base, with: .color(EchoelTheme.border), lineWidth: 1)
            // waveform
            let w = cameraRPPG.waveform
            guard w.count > 1 else { return }
            let dx = size.width / CGFloat(w.count - 1)
            let amp = size.height / 2 - 3
            var path = Path()
            for (i, v) in w.enumerated() {
                let x = CGFloat(i) * dx
                let y = size.height / 2 - CGFloat(v) * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(EchoelTheme.accent), lineWidth: 2)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
    }
    #endif

    // MARK: Coherence headline

    private var coherenceHeadline: some View {
        VStack(spacing: 4) {
            Text(coherenceString)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Coherence")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(coherenceCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: Readouts

    private var readoutRow: some View {
        HStack(spacing: 12) {
            readout("HR", hrString, "bpm")
            readout("HRV", hrvString, hrvUnit)
            readout("Breath", breathString, "/min")
        }
    }

    // MARK: HRV detail (time-domain suite, shown only with a real sensor)

    /// True only when a real sensor is supplying instrument-grade HRV (ms).
    private var showHRVDetail: Bool { (bus.latestBio?.hrvRMSSDms ?? 0) > 0 }

    private var hrvDetailRow: some View {
        HStack(spacing: 12) {
            readout("RMSSD", String(format: "%.1f", bus.latestBio?.hrvRMSSDms ?? 0), "ms")
            readout("SDNN", String(format: "%.1f", bus.latestBio?.hrvSDNNms ?? 0), "ms")
            readout("pNN50", String(format: "%.1f", bus.latestBio?.hrvPNN50 ?? 0), "%")
        }
    }

    private func readout(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.monospacedDigit().weight(.semibold))
                if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Breath pacer

    private var pacer: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .scaleEffect(inhaling ? 1.0 : 0.55)
                Text(inhaling ? "Inhale" : "Exhale")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 200)
            .animation(.easeInOut(duration: halfCycle), value: inhaling)

            Stepper(value: $breathsPerMin, in: 4...8, step: 0.5) {
                Text("Pace: \(breathsPerMin, format: .number.precision(.fractionLength(1))) breaths/min")
                    .font(.callout)
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 8)
        // Restarts the breath cycle whenever the pace changes.
        .task(id: breathsPerMin) {
            inhaling = false
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: halfCycle)) { inhaling = true }
                try? await Task.sleep(for: .seconds(halfCycle))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: halfCycle)) { inhaling = false }
                try? await Task.sleep(for: .seconds(halfCycle))
            }
        }
    }

    private var evidenceNote: some View {
        Text("Paced breathing near 6 breaths/min drives baroreflex resonance, which maximizes heart-rate variability. This is for self-observation, not medical diagnosis.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: Formatting

    private var coherenceString: String {
        guard let v = bus.latestBio?.coherence else { return "—" }
        return String(format: "%.3f", v)
    }

    private var coherenceCaption: String {
        guard let v = bus.latestBio?.coherence else { return "Connect a sensor or enable Demo in the strip" }
        switch v {
        case ..<0.34: return "Building — let the breath settle"
        case ..<0.67: return "Steadying"
        default:      return "Strong, steady HRV rhythm"
        }
    }

    private var hrString: String {
        guard let v = bus.latestBio?.heartRateBPM else { return "—" }
        return String(format: "%.1f", v)
    }

    /// Prefer the true RMSSD in ms (instrument-grade); fall back to the
    /// normalized [0..1] value when the source has no real ms (e.g. HealthKit).
    private var hrvString: String {
        guard let bio = bus.latestBio else { return "—" }
        if bio.hrvRMSSDms > 0 { return String(format: "%.1f", bio.hrvRMSSDms) }
        return String(format: "%.3f", bio.hrvNormalized)
    }

    private var hrvUnit: String? {
        guard let bio = bus.latestBio else { return nil }
        return bio.hrvRMSSDms > 0 ? "ms" : nil
    }

    private var breathString: String {
        guard let v = bus.latestBio?.breathRate else { return "—" }
        return String(format: "%.1f", v)
    }
}
#endif
