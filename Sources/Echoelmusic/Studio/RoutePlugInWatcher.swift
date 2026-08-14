// RoutePlugInWatcher.swift
// Echoelmusic — Studio (#596: the app-wide plug-in invitation)
//
// The gap this closes (measured, PLAN_VOICE_STAGE_2026-08-14.md): the input list in
// `AudioInputPickerView` refreshes on route changes only WHILE THAT SHEET IS OPEN —
// plug a USB interface in anywhere else and the app reacts with nothing. This
// watcher listens app-wide (it lives with the studio, the home surface), and on a
// `.newDeviceAvailable` route change asks the pure brain (`PlugInInvitation`)
// whether the new port is a deliberate plug (wired/USB — never Bluetooth). If so it
// exposes the port's display name; the leaf row below renders the invitation whose
// TAP opens the EXISTING input sheet (`showInput` — slot reuse, no new modal).
//
// WHAT THIS DELIBERATELY DOES NOT DO (the #299/#277 lines, both already paid for):
// no auto-arm — plugging in never starts the mic or monitoring by itself; and no
// category read-back or upgrade — the decision uses only what the route change
// carries under `.playback`. `AVAudioSession.availableInputs` is NOT consulted:
// under `.playback` it is empty, and raising the category to populate it would drag
// other apps' Bluetooth audio to HFP.
//
// Freeze-law shape (10.76.41/50): `invitePortName` changes only on plug/unplug —
// a handful of times per session, nothing like the 10 Hz bio rate — but the reads
// still sit in their own leaf (`PlugInInviteRow`), so the studio body never
// observes this object. The notification arrives on the main queue; the hop into
// the actor is one Task per PLUG EVENT, not per buffer/frame (the 10.76.48 ban
// targets per-frame hops from 30 fps sources).

#if os(iOS) && canImport(AVFoundation)
import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class RoutePlugInWatcher {

    /// The display name of a freshly plugged wired/USB port, or nil (nothing to
    /// invite). Written change-gated; cleared on unplug, dismiss, door-open — AND
    /// (review #596) by a later `.newDeviceAvailable` that carries nothing
    /// qualifying: if AirPods pair while a USB invitation shows, the route no
    /// longer carries the invited port and the line clears rather than naming a
    /// device that is no longer the story. Deliberate, not incidental.
    private(set) var invitePortName: String?

    /// `nonisolated(unsafe)` for exactly one reason: Swift 6 refuses a non-Sendable
    /// stored property in a nonisolated `deinit` ("cannot access property 'token'…",
    /// the b7ea585 gate red). Safety holds by discipline, stated here: every WRITE is
    /// `@MainActor` (`start`/`stop`), and `deinit` runs when the object is uniquely
    /// referenced, so no concurrent access exists. The CLAUDE.md error-table shape.
    @ObservationIgnored private nonisolated(unsafe) var token: (any NSObjectProtocol)?

    /// Idempotent. Observes route changes for the life of the studio.
    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            // The closure is not statically MainActor; hop once per plug event.
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handle(reasonRaw: reasonRaw)
            }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    deinit {
        // Nonisolated cleanup (the CLAUDE.md build-error-table shape): today the
        // studio's `@State` keeps this instance alive for the app's life, but if
        // `EchoelStudioView` ever gains a new identity the block would outlive the
        // watcher and fire into `weak nil` forever. `removeObserver` is thread-safe.
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    /// The user waved the line away, or walked through the door — either way the
    /// invitation's job is done.
    func dismiss() {
        if invitePortName != nil { invitePortName = nil }
    }

    private func handle(reasonRaw: UInt?) {
        guard let raw = reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .newDeviceAvailable:
            let route = AVAudioSession.sharedInstance().currentRoute
            let ports = route.inputs.map {
                PlugInInvitation.PortDescription(type: $0.portType.rawValue,
                                                 name: $0.portName, isInput: true)
            } + route.outputs.map {
                PlugInInvitation.PortDescription(type: $0.portType.rawValue,
                                                 name: $0.portName, isInput: false)
            }
            let name = PlugInInvitation.portName(reasonIsNewDevice: true, ports: ports)
            if name != invitePortName { invitePortName = name }
        case .oldDeviceUnavailable:
            // The invited device (or any device) left — a stale invitation naming an
            // unplugged port would be a lying control.
            dismiss()
        default:
            break
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The invitation line. Renders NOTHING until a wired/USB device is freshly plugged
/// in, so the transport row keeps its exact layout in the normal case — the
/// `AudioDegradedRow` (#585) shape, deliberately. The tap opens the EXISTING input
/// sheet; the ✕ dismisses. Neither button touches the engine — arming stays a
/// consent step inside the sheet (#277).
@MainActor
struct PlugInInviteRow: View {

    /// ⚠️ Read exactly ONE property in this body — `invitePortName`. It changes on
    /// plug/unplug only; keeping the read in this leaf keeps the studio body a
    /// non-observer (10.76.41/50).
    let watcher: RoutePlugInWatcher
    /// Opens the existing `showInput` sheet (slot reuse — no new modal, 10.76.34).
    let onOpen: () -> Void

    var body: some View {
        if let name = watcher.invitePortName {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.accent)
                    .accessibilityHidden(true)
                Button {
                    watcher.dismiss()
                    onOpen()
                } label: {
                    Text("\(name) connected — set up monitoring?")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 34)
                        // 34 pt visual, 44 pt target (review #596 — the ✕ beside it
                        // and #585's Retry both do this; the primary affordance must
                        // not be the one under the HIG floor).
                        .contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the audio input chooser — nothing is recording yet")
                Button {
                    watcher.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(EchoelTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .stroke(EchoelTheme.borderStrong, lineWidth: 1)))
            .accessibilityElement(children: .contain)
        }
    }
}
#endif  // canImport(SwiftUI)
#endif  // os(iOS) && canImport(AVFoundation)
