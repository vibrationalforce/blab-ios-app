#if canImport(SwiftUI)
import SwiftUI

// ClipLaunchGlyph.swift
// Echoel — the per-clip launch button for Performance mode (founder 2026-07-17:
// "Play Button auf den Clips und Performance Mode"). One tiny LEAF view drawn as
// an overlay on a MIDI region's block in ArrangeTimelineView; the arrange body
// (and RegionBlockView) never read the launch state themselves.
//
// FREEZE LAW (the recurring menu-freeze ship-blocker): the ONLY observation this
// leaf registers is `TimelineRegionPlayer.launchGeneration` — a LOW-FREQUENCY
// hook that bumps on launch requests + fired boundary transitions (user taps +
// quantize boundaries), never per transport tick. `launchState(laneID:)` reads
// @ObservationIgnored engine state, so it does NOT register observation — reading
// `launchGeneration` is what re-evaluates this leaf. Confining that read HERE
// (not in the arrange root / RegionBlockView body) keeps a 10 Hz-class observer
// out of any ancestor of an open Picker/menu.
//
// FLASH LAW (W3C WCAG epilepsy, max 3 Hz): the "about to start / about to stop"
// blink toggles every `blinkPeriod` = 0.4 s → 2.5 transitions/s, safely under
// 3 Hz. It runs ONLY while queued/queuedStop (a paused `.animation` schedule
// otherwise), so an idle/playing glyph costs nothing.

/// A single MIDI clip's launch/stop glyph. Idle = ▶ (tap launches at the chosen
/// quantize); queued = ▶ blinking ("gleich"); playing = ◼ accent; queuedStop =
/// ◼ blinking ("stoppt gleich"). Tap on any non-idle state stops/cancels the
/// lane's launch.
@MainActor
struct ClipLaunchGlyph: View {
    @Environment(TimelineRegionPlayer.self) private var player

    /// The region this glyph launches, and its lane (the launch machine is
    /// per-lane — one region overrides its lane's arrangement at a time).
    let regionID: UUID
    let laneID: UUID
    let quantize: LaunchQuantize

    /// This region's role in its lane's single launch state.
    private enum Phase { case idle, queuedStart, playing, queuedStop }

    private static let blinkPeriod: Double = 0.4   // 2.5 transitions/s ≤ 3 Hz (flash law)
    private static let size: CGFloat = 28          // HIG touch target

    var body: some View {
        // Observation hook (see FREEZE LAW note): reading launchGeneration is what
        // registers this leaf as a (low-frequency) observer; launchState() alone
        // reads @ObservationIgnored state and would never refresh.
        let _ = player.launchGeneration
        let phase = Self.phase(for: regionID, state: player.launchState(laneID: laneID))
        return Button {
            if phase == .idle {
                player.launchRegion(regionID, quantize: quantize)
            } else {
                player.stopLaunched(laneID: laneID, quantize: quantize)
            }
        } label: {
            glyph(phase)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(phase))
        .accessibilityHint(phase == .idle
                           ? "Launches this clip at the next \(quantize.displayName) boundary"
                           : "Stops this clip at the next \(quantize.displayName) boundary")
    }

    @ViewBuilder
    private func glyph(_ phase: Phase) -> some View {
        let blinking = (phase == .queuedStart || phase == .queuedStop)
        let active = (phase != .idle)
        let symbol = (phase == .playing || phase == .queuedStop) ? "stop.fill" : "play.fill"
        // Paused schedule for a still glyph (no timer while idle/playing); the
        // blink drives only the two transitional states, ≤ 3 Hz.
        TimelineView(.animation(paused: !blinking)) { tl in
            let lit = !blinking
                || Int(tl.date.timeIntervalSinceReferenceDate / Self.blinkPeriod) % 2 == 0
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? EchoelTheme.onPrimary : EchoelTheme.text)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(active ? EchoelTheme.accent : EchoelTheme.fill.opacity(0.92)))
                .overlay(Circle().strokeBorder(EchoelTheme.border, lineWidth: 1))
                .opacity(lit ? 1 : 0.3)
        }
        .frame(width: Self.size, height: Self.size)
    }

    // MARK: - Pure state mapping

    /// This region's glyph phase from its lane's single launch state. A lane can
    /// carry many regions but only one launch — every OTHER region shows idle.
    private static func phase(for regionID: UUID, state: LaneLaunchState) -> Phase {
        switch state {
        case .idle:
            return .idle
        case .queued(let queuedRegionID, _, let current):
            if queuedRegionID == regionID { return .queuedStart }        // this one is queued to start
            if current?.regionID == regionID { return .playing }         // still sounding, being replaced
            return .idle
        case .playing(let clip):
            return clip.regionID == regionID ? .playing : .idle
        case .queuedStop(let clip, _):
            return clip.regionID == regionID ? .queuedStop : .idle
        }
    }

    private static func accessibilityLabel(_ phase: Phase) -> String {
        switch phase {
        case .idle:        return "Launch clip"
        case .queuedStart: return "Clip queued to launch"
        case .playing:     return "Stop clip"
        case .queuedStop:  return "Clip queued to stop"
        }
    }
}
#endif
