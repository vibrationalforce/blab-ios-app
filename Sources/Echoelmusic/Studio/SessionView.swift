//
//  SessionView.swift
//  Echoelmusic — Studio
//
//  THE Session screen (warm-restart cycle 5): one screen, one purpose — start,
//  put a finger on the camera, and let the tone breathe with you toward your
//  resonance pace. Presented as WorkspaceView's FIRST fullScreenCover (its own,
//  small modal — the EchoelStudioView sheet chain is untouched, render-safety rule).
//
//  Render-safety discipline:
//   • This body reads only LOW-frequency state (isRunning). The live numbers
//     (pace, elapsed) come from @ObservationIgnored fields refreshed by a
//     TimelineView LEAF — zero 10 Hz observation churn in any ancestor.
//   • The pulse-lock feedback reuses the existing BioStripView leaf pattern via
//     PulseMonitorMiniLive-style isolation: the camera publisher is read ONLY
//     inside SessionPulseLeaf.
//
//  Honest copy: self-observation and self-regulation — the guide follows the
//  measured body; no therapy/medical/brainwave language (research 2026-07-05).
//

#if canImport(SwiftUI)
import SwiftUI

struct SessionView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionEngine.self) private var session
    @Environment(EngineBus.self) private var bus
    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif

    /// Whether THIS screen started the camera (so Stop only tears down what it set up
    /// — if the studio's bio strip already runs the camera, we leave it running).
    @State private var startedCamera = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if session.isRunning {
                runningBody
            } else {
                idleBody
            }
            Spacer()
            controls
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Session")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer()
            Button {
                stopSession()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(width: 32, height: 32)
                    .background(EchoelTheme.fill, in: RoundedRectangle(cornerRadius: EchoelTheme.radius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close session")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Idle

    private var idleBody: some View {
        VStack(spacing: 14) {
            Text("Breathe with the tone")
                .font(EchoelTheme.font(22, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Text("Place a finger over the camera. The tone eases from your own pace toward your resonance breathing — and backs off whenever your body isn't following. For self-observation.")
                .font(EchoelTheme.font(13))
                .foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            // Mandated safety line on the feature surface itself (onboarding is
            // one-time; bio-safety review 2026-07-05).
            Text("Not while driving or operating machinery. Not a medical device.")
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 2)
        }
    }

    // MARK: - Running (live numbers live in LEAVES only)

    private var runningBody: some View {
        VStack(spacing: 20) {
            #if canImport(AVFoundation)
            SessionPulseLeaf()
            #endif
            SessionGlowLeaf()
            SessionPaceLeaf()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        Button {
            if session.isRunning {
                stopSession()
            } else {
                startSession()
            }
        } label: {
            Text(session.isRunning ? "End Session" : "Start")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(session.isRunning ? EchoelTheme.text : EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    session.isRunning ? AnyShapeStyle(EchoelTheme.fill) : AnyShapeStyle(EchoelTheme.text),
                    in: RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge)
                        .stroke(EchoelTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .accessibilityLabel(session.isRunning ? "End session" : "Start session")
    }

    // MARK: - Actions

    private func startSession() {
        #if canImport(AVFoundation)
        if !cameraRPPG.isRunning {
            startedCamera = true
            let bus = self.bus
            Task { await cameraRPPG.start(publishing: bus) }
        }
        #endif
        session.start(subscribing: bus)
    }

    private func stopSession() {
        session.stop()
        #if canImport(AVFoundation)
        if startedCamera {
            cameraRPPG.stop()
            startedCamera = false
        }
        #endif
    }
}

// MARK: - Leaves (the ONLY places live values are read — freeze rule)

/// Guided breathing pace + elapsed time. `currentPaceBpm`/`elapsedSeconds` are
/// @ObservationIgnored (no invalidation), so a TimelineView drives the refresh —
/// 2 Hz is plenty for a value that changes over minutes, and only THIS leaf redraws.
private struct SessionPaceLeaf: View {
    @Environment(SessionEngine.self) private var session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 6) {
                Text(String(format: "%.1f", session.currentPaceBpm))
                    .font(EchoelTheme.font(56, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .monospacedDigit()
                Text("breaths / min — follow the tone")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(EchoelTheme.dim)
                Text(Self.clock(session.elapsedSeconds))
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.dim)
                    .monospacedDigit()
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Guided breathing pace")
    }

    static func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// The breathing LIGHT — the visual layer of the session, phase-locked to the tone.
/// Both measure from the SAME epoch (`session.startedAtHostTime`; the audio clock is
/// re-zeroed at start), so the light's swell and the audible swell coincide.
///
/// Safety + design, by construction:
///  • the rate comes from `currentPlan.entrainment` — the flash-safe EntrainmentPlan
///    (≤3 Hz, outside 4–70 Hz, capped depth; at breath paces it's ~0.1 Hz anyway);
///  • OPACITY-ONLY animation on a plain accent disc (Uncodixfy: no scale, no glow
///    stacking, no neon) — a functional guide light, not decoration;
///  • never saturated red (`allowSaturatedRedFlicker` is always false; accent is green);
///  • TimelineView(.animation) redraws only THIS leaf; the plan struct is
///    @ObservationIgnored, so no observation churn reaches any ancestor.
private struct SessionGlowLeaf: View {
    @Environment(SessionEngine.self) private var session
    /// Reduce Motion → steady glow, no pulsing (WCAG 2.3.3; matches BreathGuideView/
    /// FlashGuard convention — bio-safety review 2026-07-05).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let plan = session.currentPlan.entrainment
            let now = ctx.date.timeIntervalSinceReferenceDate
            let t = max(0, now - session.startedAtHostTime)
            // visualPhaseOffset keeps the phase CONTINUOUS across pace changes —
            // without it a rate republish jumps the gate by t·Δhz cycles (the
            // bio-safety HIGH: discontinuous brightness steps at up to 10 Hz).
            let gate = (plan.visualIsSteady || reduceMotion)
                ? 0.5
                : EntrainmentEngine.gate(atSeconds: t, hz: plan.visualPulseHz,
                                         phaseOffset: session.visualPhaseOffset)
            // Base visibility + capped modulation depth (≤ maxBrightnessDelta = 0.5).
            let level = 0.10 + plan.brightnessDelta * gate * 0.8
            Circle()
                .fill(EchoelTheme.accent)
                .opacity(level)
                .frame(width: 180, height: 180)
        }
        .accessibilityHidden(true)   // the pace text below carries the information
    }
}

#if canImport(AVFoundation)
/// Pulse-lock feedback — reads the ~10 Hz camera publisher in its OWN body only
/// (the WorkspaceView 10.76.50 rule). Number appears only when trustworthy.
private struct SessionPulseLeaf: View {
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraRPPG.displayBPM > 0 ? EchoelTheme.accent : EchoelTheme.dim)
                .frame(width: 8, height: 8)
            Text(cameraRPPG.displayBPM > 0
                 ? "\(Int(cameraRPPG.displayBPM)) bpm"
                 : "finding your pulse — hold still")
                .font(EchoelTheme.font(13))
                .foregroundStyle(cameraRPPG.displayBPM > 0 ? EchoelTheme.text : EchoelTheme.dim)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pulse status")
    }
}
#endif
#endif   // canImport(SwiftUI)
