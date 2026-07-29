//
//  BioStripView.swift
//  Echoelmusic
//
//  Thin readout strip showing the latest BioSampleFrame published to
//  EngineBus — the body's live numbers (HR / HRV / breath / coherence) plus a
//  source tag. Deliberately minimal: legible numbers first, no extra controls
//  (transport, FX and panels live on the main screen, not here).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BioStripView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read the finger-on-lens flag HERE (this small leaf view), not in the parent
    /// `EchoelStudioView.body`. `fingerDetected` is rewritten ~10 Hz while reading; if the
    /// root body subscribed to it (the old `fingerOnLens:` argument), it re-evaluated 10×/s
    /// and tore down any open `.menu` Picker popover in the Composition panel — the "can't
    /// select the Tonart anymore" freeze. Confining the read to this Picker-free strip keeps
    /// the high-frequency invalidation off the selection menus.
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    /// The shared transport, read HERE (a Picker-free leaf), never in `EchoelStudioView.body`
    /// (freeze rule). Only `isPlaying` is read — a low-frequency start/stop flag — to answer
    /// the survey-universal question "is my body driving the sound right now?" (the activity
    /// light below). `position` (16th-note, high-frequency) is never touched here.
    @Environment(Transport.self) private var transport

    /// True while a camera pulse-read is in progress but no real signal has locked
    /// yet — the strip shows live "reading…" feedback instead of a dead "No signal".
    var measuring: Bool = false
    /// One-tap entry from the otherwise-dead strip: bring the body's pulse in.
    ///
    /// ⛔ OPTIONAL SINCE #234, and `nil` is the case that matters. In `EchoelStudioView`'s
    /// Bio panel this handler was `startBiofeedback()` — i.e. a button labelled "Read pulse"
    /// that started the entire generative session. That is a lying control on its own, and
    /// after the founder's "3 Knöpfe zum Start → einer" it was also a hidden fourth Start,
    /// two taps from the header pill. The panel now passes nothing and the strip shows an
    /// honest "No signal" instead; the one Start is the front plate's own button, on the
    /// same screen. `BioSourceView` still passes a handler and is still right to: its
    /// `arm(true)` really does arm the sensor alone.
    var onStartPulse: (() -> Void)?

    /// Tapped metric → its plain-language explanation sheet ("app as a school").
    @State private var explain: BioMetric?
    /// The leading ⓘ → an overview that explains ALL the numbers at once (founder:
    /// "HRV etc. soll erklärt werden"). Makes the tap-to-learn discoverable.
    @State private var showGuide = false

    /// Brief "pulse locked — you can lift and play now" confirmation. Teaches the
    /// lock-THEN-play flow (device log 2026-07-07: the user played the touch instrument
    /// immediately, so the finger kept lifting and the read never locked). Shown for a few
    /// seconds when the pulse settles, then it gets out of the way. Low-frequency @State.
    @State private var lockedCueVisible = false
    /// Generation token so a later settle cancels an earlier auto-hide (no flicker).
    @State private var lockedCueToken = 0

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            strip
        }
        // When the pulse settles, flash a brief "locked — you can lift & play" cue so the
        // user learns to LOCK first, THEN play (the take tempo is latched, so lifting the
        // finger to play no longer perturbs it). `isSettled` is low-frequency.
        .onChange(of: cameraRPPG.isSettled) { _, settled in
            guard settled, cameraRPPG.isRunning else { return }
            lockedCueToken += 1
            let token = lockedCueToken
            withAnimation(.easeInOut(duration: 0.2)) { lockedCueVisible = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if token == lockedCueToken {
                    withAnimation(.easeInOut(duration: 0.2)) { lockedCueVisible = false }
                }
            }
        }
    }

    /// The one status line above the strip. Recovery/cooling (urgent) wins; otherwise the
    /// brief "pulse locked" confirmation. Both read low-frequency state in THIS leaf, so
    /// they never churn the parent body (freeze rule).
    @ViewBuilder private var statusBanner: some View {
        if cameraRPPG.isRunning, let hint = cameraRPPG.recoveryState.userHint {
            banner(hint, color: EchoelTheme.warning, systemImage: "camera.metering.center.weighted")
        } else if cameraRPPG.permissionDenied, bus.freshBio() == nil {
            // UX-1: denied camera access was a SILENT dead end — the strip kept
            // coaching "Cover camera" which can never work. Name the real fix.
            // Gate on RAW fresh frames (not hasLiveSignal, which excludes the
            // .fallback demo): a user who deliberately picked Simulation must not
            // be nagged about the camera — matches the header pill's suppression.
            banner(PulseCue.cameraDenied.fullHint,
                   color: EchoelTheme.warning, systemImage: "video.slash")
        } else if lockedCueVisible {
            banner("Pulse detected — you can let go & play",
                   color: EchoelTheme.success, systemImage: "checkmark.circle.fill")
        }
    }

    private func banner(_ text: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .accessibilityLabel(text)
    }

    private var strip: some View {
        // Equal-width metric cells that always fit the screen — no left-packing, so a
        // value changing digit-count (or the source tag toggling width) can't reflow
        // its neighbours or overflow the edge (the old "wobble"). The source tag sits
        // in a bounded slot; everything scales down on narrow phones (adaptive).
        HStack(spacing: 6) {
            infoButton
            drivingIndicator
            divider
            metricButton(label: "HR",  value: hrString,        unit: "bpm",   metric: .heartRate)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "HRV", value: hrvString,       unit: hrvUnit, metric: .hrv)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Br",  value: breathString,    unit: "/min",  metric: .breath)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Coh", value: coherenceString, unit: nil,     metric: .coherence)
                .frame(maxWidth: .infinity)
            sourceControl
                .frame(width: 88, alignment: .trailing)
        }
        // lineLimit/scale/font BEFORE the sheets: these are ENVIRONMENT values, and sheet
        // content inherits the environment at the .sheet attachment point — with the old
        // order (sheets first, lineLimit after) every Text INSIDE the info sheets rendered
        // one line, shrunk to 60 %, truncated to "…" (founder, twice: "die Infos über HRV
        // kann man immer noch nicht lesen. Wegen den …"). The width fix in the sheet could
        // never cure that. Strip-only modifiers must sit INSIDE the sheet attachments.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .sheet(item: $explain) { BioMetricInfoView(metric: $0) }
        .sheet(isPresented: $showGuide) { BioMetricsGuideView() }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .foregroundStyle(EchoelTheme.text)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EchoelTheme.text.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Info affordance

    /// Makes the tap-to-learn discoverable: a muted ⓘ at the strip's leading edge that opens
    /// the overview of ALL bio numbers. (Each metric cell is also individually tappable for a
    /// deep-dive — the guide's subtitle says so.) Founder 2026-07-03: "HRV etc. soll erklärt
    /// werden" — the explanations existed but were invisible.
    private var infoButton: some View {
        Button { showGuide = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(EchoelTheme.dim)
                // The advertised tap-to-learn affordance was a bare 12 pt glyph —
                // nearly impossible to hit (AX audit 2026-07-09). Target ≥ the
                // strip's height; glyph unchanged.
                .frame(width: 32, height: 32)
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What these bio numbers mean")
        .accessibilityHint("Opens a plain-language guide to heart rate, HRV, coherence and breathing")
    }

    // MARK: - Activity light ("is my body driving this?")

    /// The one thing the strip answers FIRST (UI survey 2026-07-11 — all five target
    /// groups asked for it): is the body shaping the live sound right now? Honest, not
    /// decorative — GREEN only when a take is PLAYING *and* a fresh, real bio frame exists
    /// (so the body genuinely drives the running generative composition). A dim hollow ring
    /// = a real signal is present but nothing is playing (live, not driving). A faint ring =
    /// no live body. No animation (A11y / ≤3 Hz — the survey's Lena explicitly rejected a
    /// decorative pulse); colour alone carries the state. Accent green stays reserved for the
    /// live/playing bio state, which is exactly what this is.
    private var driving: Bool { transport.isPlaying && hasLiveSignal }

    private var drivingIndicator: some View {
        // Tap opens the same plain-language guide as the ⓘ (survey law #1: the light shows
        // ONE thing at a glance; the meaning is one tap away, not always on screen).
        Button { showGuide = true } label: {
            Group {
                if driving {
                    Circle().fill(EchoelTheme.success)
                } else if hasLiveSignal {
                    Circle().strokeBorder(EchoelTheme.dim, lineWidth: 1)
                } else {
                    Circle().strokeBorder(EchoelTheme.dim.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(width: 7, height: 7)
            .frame(width: 20, height: 20)      // 20 pt touch/hit slack; glyph stays 7 pt
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(driving
            ? "Your body is driving the sound"
            : (hasLiveSignal ? "Body signal live, not driving yet" : "No live body signal"))
        .accessibilityHint("Double tap to learn how your body shapes the sound")
    }

    // MARK: - Metric cells

    /// A metric cell you can tap to learn what it means. Plain button style keeps
    /// the compact strip look; carries an explicit VoiceOver label + hint.
    private func metricButton(label: String, value: String, unit: String?, metric m: BioMetric) -> some View {
        Button { explain = m } label: {
            metric(label: label, value: value, unit: unit)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title), \(value)\(unit.map { " " + $0 } ?? "")")
        .accessibilityHint("Double tap to learn what this means")
    }

    private func metric(label: String, value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(EchoelTheme.dim)
            Text(value)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(EchoelTheme.text.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    // MARK: - Source control (live tag · measuring · one-tap pulse entry)

    /// The right end of the strip. Three honest states, no synthetic data ever:
    /// • a real signal is live → green source tag (HR / PPG / BLE…);
    /// • a pulse read is in progress → live "Reading… / Cover camera" feedback;
    /// • nothing yet → a one-tap button that brings the body in (camera rPPG),
    ///   so the most bio-looking element is the gateway to the instrument, not a
    ///   dead end. Only a real, fresh signal turns it green.
    @ViewBuilder private var sourceControl: some View {
        if hasLiveSignal {
            liveTag
        } else if cameraRPPG.permissionDenied, bus.freshBio() == nil {
            // UX-1: with access denied the camera can never start, so neither
            // "Reading…" nor "Read pulse" is honest — offer the one real door.
            // Raw fresh-frame gate (not hasLiveSignal): the .fallback demo is a
            // deliberate source choice, don't override it with a camera nag.
            openSettingsButton
        } else if measuring {
            measuringTag
        } else if onStartPulse != nil {
            startPulseButton
        } else {
            noSignalTag
        }
    }

    /// The fourth state, added with #234: no signal, and this strip is NOT the place to
    /// start one. It is not the "dead end" the doc above warns about — the Bio panel that
    /// mounts it sits on the front plate, with the labelled Start button in the same view.
    /// Naming that button here is what keeps it a signpost rather than a dead end.
    private var noSignalTag: some View {
        Text("No signal")
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
            .foregroundStyle(EchoelTheme.dim)
            .accessibilityLabel(Text("No body signal yet"))
            .accessibilityHint(Text("Press Create from Within to start; your body then drives the sound."))
    }

    /// The honest replacement for the dead end: camera access is off, and the
    /// only fix lives in the system Settings — one tap takes the user there.
    private var openSettingsButton: some View {
        Button { openAppSettings() } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.slash").font(.system(size: 9))
                Text("Enable camera")
            }
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(EchoelTheme.warning.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
            .foregroundStyle(EchoelTheme.warning)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Camera access is off")
        .accessibilityHint("Opens Settings so you can allow camera access and read your pulse")
    }

    private var liveTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text(sourceText)
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(EchoelTheme.success.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
        .foregroundStyle(EchoelTheme.success)
        .accessibilityLabel("Bio source: \(sourceText)")
    }

    private var measuringTag: some View {
        let amber = EchoelTheme.warning
        let finger = cameraRPPG.fingerDetected
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text(finger ? "Reading…" : "Cover camera")
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(amber.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
        .foregroundStyle(amber)
        .accessibilityLabel(finger ? "Reading your pulse" : "Cover the rear camera and flash to read your pulse")
    }

    /// The old dead "No signal" becomes the one-tap gateway to the live body.
    private var startPulseButton: some View {
        Button { onStartPulse?() } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                Text("Read pulse")
            }
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
            .foregroundStyle(EchoelTheme.dim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read your pulse")
        .accessibilityHint("Starts the camera to read your heartbeat so your body drives the sound")
    }

    /// A real sensor (camera PPG / HealthKit / BLE / Watch / Oura) is publishing
    /// FRESH frames. A frozen reading (dropped strap, lifted finger, stalled Watch)
    /// expires after the freshness window, so the strip stops claiming a live body.
    private var hasLiveSignal: Bool {
        // Gate on `usableBio()` — the SAME per-source window the sound engine uses
        // (ModulationEngine.tick). The fixed-5 s `freshBio()` here made the strip
        // flicker to "No signal" for a Watch/HealthKit source that publishes only
        // every few minutes (its reading stays usable for 90 s and keeps driving
        // the music), so the live indicator now matches whether the body is
        // actually shaping the sound. A truly frozen source still expires.
        if let bio = bus.usableBio(), bio.source != .fallback { return true }
        return false
    }

    private var sourceText: String {
        if let bio = bus.usableBio(), bio.source != .fallback {
            return sourceLabel(bio.source)
        }
        return "No signal"
    }

    // MARK: - Formatting

    private var hrString: String {
        // While the camera is the live source, show the CALM display value (holds the last
        // confident reading through noisy patches) so this number matches the header monitor
        // and doesn't bounce. Music still uses the honest bus HR internally; other sources
        // (BLE/HealthKit) and the pre-lock phase fall back to the bus value.
        if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 {
            return String(format: "%.0f", cameraRPPG.displayBPM)
        }
        guard let v = bus.latestBio?.heartRateBPM else { return "—" }
        return String(format: "%.1f", v)
    }

    /// Physiologically plausible RMSSD window (ms). Camera rPPG's beat-to-beat
    /// timing is noisy and can inflate RMSSD to impossible values (e.g. 500+ ms,
    /// above the mean RR interval) — science-first, we show a real number only
    /// inside this window and "—" otherwise, rather than print a wrong figure.
    private static let plausibleHRVms: ClosedRange<Float> = 3...300

    /// True RMSSD in ms when the source provides a plausible reading; the
    /// normalized [0..1] value for sources that only publish that (HealthKit);
    /// "—" when the ms reading is physiologically impossible (noisy rPPG).
    private var hrvString: String {
        guard let bio = bus.latestBio else { return "—" }
        if Self.plausibleHRVms.contains(bio.hrvRMSSDms) {
            // Whole ms from 10 up ("HRV 15 ms", not "15.2"): the strip cell is the
            // narrowest surface in the app and the decimal was what pushed it into
            // "HRV 15.." truncation on small phones (founder video v173). Sub-10
            // readings keep one decimal — there the digit carries real information.
            return String(format: bio.hrvRMSSDms < 10 ? "%.1f" : "%.0f", bio.hrvRMSSDms)
        }
        if bio.hrvRMSSDms == 0 && bio.hrvNormalized > 0 { return String(format: "%.3f", bio.hrvNormalized) }
        return "—"
    }

    private var hrvUnit: String? {
        guard let bio = bus.latestBio, Self.plausibleHRVms.contains(bio.hrvRMSSDms) else { return nil }
        return "ms"
    }

    /// Physiologically plausible breathing-rate window (breaths/min). A camera pulse read
    /// does not derive respiration, so it publishes 0 — and "0.0 /min" is impossible (you
    /// can't breathe zero times a minute). Show a real number only inside the plausible
    /// window, otherwise "—" (honest: not measured), matching how coherence/HRV behave.
    /// The window itself now lives on `BioSampleFrame`, so this view, the modulation
    /// readout and the EchoelAI narration share one answer to "is there a breath
    /// reading" — they had started to drift apart. `BreathGuideView` still owns a
    /// FOURTH, narrower test (`source == .cameraPPG && breathRate > 0`); it agrees today
    /// only because `RespirationEstimator` clamps to 4…30, which sits inside this window.
    private var breathString: String {
        guard let bio = bus.latestBio, bio.hasMeasuredBreath else { return "—" }
        return String(format: "%.1f", bio.breathRate)
    }

    /// Coherence is real only on sources with beat-to-beat RR (BLE / camera);
    /// HealthKit publishes 0 ("not available"). Show a measured value only for a
    /// FRESH frame whose coherence is > 0 — otherwise "—" (never "0.000", which
    /// would read as "incoherent" rather than "not yet / not available").
    private var coherenceString: String {
        guard let bio = bus.freshBio(), bio.coherence > 0 else { return "—" }
        return String(format: "%.2f", bio.coherence)
    }

    private func sourceLabel(_ source: BioSource) -> String {
        switch source {
        case .oura:       return "Oura"
        case .healthKit:  return "Health"
        case .ble:        return "BLE"
        case .watch:      return "Watch"
        case .cameraPPG:  return "PPG"
        case .faceCam:    return "Face"
        case .fallback:   return "—"
        }
    }
}
#endif
