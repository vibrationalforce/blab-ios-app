// AudioInputManager.swift
// Echoel — choose the recording input: built-in mic, wired headset, USB/Lightning
// interface, or a Bluetooth device. Enumerates the live inputs and, for each,
// states an HONEST expected monitoring-latency class so the UI can warn before a
// performer relies on a route that physically can't monitor in real time
// (Bluetooth ≈ 150–250 ms; wired/USB ≈ low).
//
// The classifier is pure and cross-platform (keyed on the port-type raw string)
// so it is fully unit-tested on every platform; the AVAudioSession bridge is
// guarded for the platforms that have it (iOS/tvOS/watchOS/visionOS — not macOS).

import Foundation

/// What kind of device an input is, for grouping + iconography.
public enum AudioInputKind: String, Sendable, Codable, CaseIterable {
    case builtIn, wired, usb, bluetooth, carPlay, virtual, other
}

/// Expected latency when this device handles monitoring (round-trip I/O).
/// This is guidance, not a measurement — Bluetooth is a protocol-level limit.
public enum MonitoringLatency: String, Sendable, Codable, CaseIterable {
    case low, medium, high

    /// Short, honest user-facing note.
    public var advice: String {
        switch self {
        case .low:    return "Low latency — good for live monitoring."
        case .medium: return "Some latency — usually fine."
        case .high:   return "High latency (Bluetooth) — record fine, but monitor on wired for timing."
        }
    }
}

/// One selectable input.
public struct AudioInputInfo: Identifiable, Equatable, Sendable, Codable {
    public var id: String          // port UID (stable per device)
    public var name: String
    public var portTypeRaw: String
    public var kind: AudioInputKind
    public var latency: MonitoringLatency
    /// #830 — how many input channels the PORT reports (`nil` = the session did not
    /// say). Read from `AVAudioSessionPortDescription.channels`, so it is the
    /// HARDWARE's claim, not ours. The engine records/monitors the first two at most
    /// (its input clamp and the stereo master graph), and the picker says so on any
    /// row where this exceeds 2 — an 8-in interface is honest instead of silently
    /// truncated. Optional, so the synthesized Codable treats a missing key as `nil`
    /// (the decodeIfPresent law) and older payloads keep decoding.
    public var inputChannelCount: Int?

    public init(id: String, name: String, portTypeRaw: String,
                kind: AudioInputKind, latency: MonitoringLatency,
                inputChannelCount: Int? = nil) {
        self.id = id
        self.name = name
        self.portTypeRaw = portTypeRaw
        self.kind = kind
        self.latency = latency
        self.inputChannelCount = inputChannelCount
    }
}

/// Pure mapping from an `AVAudioSession.Port` raw value to kind + latency class.
/// Cross-platform and dependency-free so it is testable everywhere.
public enum AudioInputClassifier {

    public static func classify(portTypeRaw raw: String) -> (kind: AudioInputKind, latency: MonitoringLatency) {
        switch raw {
        // Built-in
        case "MicrophoneBuiltIn":                       return (.builtIn, .low)
        // Wired. ⛔ "MicrophoneWired" was MISSING until #596's review: it is the
        // ACTUAL rawValue of `AVAudioSession.Port.headsetMic` — "HeadsetMicrophone"
        // and "HeadphonesMicrophone" are guessed names that iOS never sends
        // (`git grep MicrophoneWired` found zero uses before this line). A real
        // wired headset mic therefore fell through to the substring fallback and
        // classified `.other` — wrong kind, wrong latency note, and (since #596)
        // no plug-in invitation. The guessed names stay as harmless defense.
        case "MicrophoneWired", "HeadsetMicrophone", "LineIn", "HeadphonesMicrophone":
                                                        return (.wired, .low)
        // USB / Lightning / external interface
        case "USBAudio", "Thunderbolt", "PCI", "FireWire", "DisplayPort", "HDMI":
                                                        return (.usb, .low)
        // Bluetooth (all profiles — the latency wall)
        case "BluetoothHFP", "BluetoothA2DPOutput", "BluetoothLE":
                                                        return (.bluetooth, .high)
        // Car
        case "CarAudio":                                return (.carPlay, .high)
        // Virtual / network / continuity
        case "Virtual", "AirPlay", "AVB", "ContinuityMicrophone":
                                                        return (.virtual, .high)
        default:
            // Fall back by substring so unknown future ports still classify sanely.
            if raw.contains("Bluetooth") { return (.bluetooth, .high) }
            if raw.contains("USB")       { return (.usb, .low) }
            if raw.contains("Built")     { return (.builtIn, .low) }
            return (.other, .medium)
        }
    }
}

#if canImport(AVFoundation)
import AVFoundation
#endif
import Observation

/// Live input enumeration + selection. On iOS/tvOS/watchOS/visionOS this reads
/// `AVAudioSession` and only chooses which available input is preferred. The session
/// is `.playback` by default and is upgraded to `.playAndRecord` (see
/// AudioConfiguration) only when the user actually records or monitors — so the
/// input list is meaningful once a mic feature is armed. On macOS the system manages
/// the input device, so the list is empty (the UI then shows "managed by the
/// system") — cross-platform so the UI needs no guards.
@MainActor
@Observable
public final class AudioInputManager {

    /// Inputs available right now, classified.
    public private(set) var available: [AudioInputInfo] = []
    /// UID of the currently preferred / active input.
    public private(set) var selectedID: String?
    /// Human name of the current OUTPUT route (e.g. "Hi-X25BT", "iPhone").
    public private(set) var outputRouteName: String = ""
    /// True when the output route is high-latency (Bluetooth / AirPlay / CarPlay):
    /// monitoring your own voice through it is delayed even with a low-latency input.
    public private(set) var outputIsHighLatency: Bool = false

    public init() {}

    /// Re-read the available inputs and the current selection.
    public func refresh() {
        #if canImport(AVFoundation) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        let ports = session.availableInputs ?? []
        available = ports.map { port in
            let c = AudioInputClassifier.classify(portTypeRaw: port.portType.rawValue)
            return AudioInputInfo(id: port.uid, name: port.portName,
                                  portTypeRaw: port.portType.rawValue,
                                  kind: c.kind, latency: c.latency,
                                  inputChannelCount: port.channels?.count)
        }
        selectedID = session.preferredInput?.uid ?? session.currentRoute.inputs.first?.uid
        // Output route: a low-latency input (built-in mic) paired with a Bluetooth
        // output (A2DP, ~150–250 ms) still delays self-monitoring — the latency is on
        // the OUTPUT side. Surface it so the monitoring hint is honest.
        let outputs = session.currentRoute.outputs
        outputRouteName = outputs.first?.portName ?? ""
        outputIsHighLatency = outputs.contains { out in
            AudioInputClassifier.classify(portTypeRaw: out.portType.rawValue).latency == .high
        }
        #else
        available = []   // macOS: input device is system-managed (HAL)
        selectedID = nil
        outputRouteName = ""
        outputIsHighLatency = false
        #endif
    }

    /// Prefer the input with the given UID. No-op if it is no longer available.
    public func select(_ id: String) {
        #if canImport(AVFoundation) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // #880 — THE EXPORTED LOG HAD NO RECORD THAT THE USER CHANGED INPUT AT ALL.
        // Every line in this file went to `log.audio` (os_log), and os_log is invisible
        // in `echoel_diag.log` — the whole point of the #859 ladder. So a founder who
        // switched to a headset mic and then hit the `isInputConnToConverter` abort
        // handed over a log in which the switch simply did not happen. `setPreferredInput`
        // moves the hardware input under a possibly-running graph; it is exactly the kind
        // of discrete user event the ladder exists for.
        //
        // ⚠️ PRIVACY, measured rather than assumed: port NAMES already reach the exported
        // file — `latencyBreadcrumb` writes `route:` built from `routeLabel(portName:
        // portType:)` and then `sanitisedRoute`. Borrowing that path is therefore consistent
        // with the established discipline (and gets the Bluetooth marker for free) rather
        // than a new exposure. The raw UID is NOT written: it is opaque to a reader and can
        // be MAC-derived for a Bluetooth device, so it would add risk and no information.
        //
        // ⛔ AND THE FIRST DRAFT BORROWED ONLY HALF OF IT — the reviewer caught a REOPENED
        // #654. `latencyLine` does not write `route`, it writes `sanitisedRoute(route)`,
        // because a port name is the first EXTERNALLY CONTROLLED string this repo puts in the
        // diagnostics file. Skipping it loses three things, and the first is a live defect:
        //   1. `EchoelCrashLog.looksLikeUnseenCrash` is a bare `contains(crashMarker)`, so a
        //      paired device whose name contains that marker would make EVERY later launch
        //      open the crash sheet on a session that never crashed.
        //   2. A newline in a port name splits one rung into two, and `lastScenePhase`
        //      parses this file line by line.
        //   3. No length bound, while `currentLog()` reads the whole file into one String.
        // The existing guard for (1) only covers the `sanitisedRoute` path, so it would have
        // stayed GREEN while this new writer walked around it. Same treatment for the error
        // strings below: `localizedDescription` is OS-supplied and can carry a device name.
        guard let port = (session.availableInputs ?? []).first(where: { $0.uid == id }) else {
            EchoelCrashLog.breadcrumb("input: select IGNORED — uid no longer available")
            log.audio("Input \(id) no longer available", level: .warning)
            return
        }
        EchoelCrashLog.breadcrumb(
            "input: select → "
            + AudioConfiguration.sanitisedRoute(
                AudioConfiguration.routeLabel(portName: port.portName,
                                              portType: port.portType.rawValue)))
        do {
            try session.setPreferredInput(port)
            selectedID = id
            log.audio("Preferred input → \(port.portName) [\(port.portType.rawValue)]")
        } catch {
            EchoelCrashLog.breadcrumb("input: select FAILED ("
                + AudioConfiguration.sanitisedRoute(error.localizedDescription) + ")")
            log.audio("setPreferredInput failed: \(error.localizedDescription)", level: .error)
        }
        #endif
    }

    /// Clear the preferred input (let the system pick the default route).
    ///
    /// ⚠️ DOORLESS — measured 2026-08-29 (#880): `git grep -n "useSystemDefault()" -- Sources`
    /// returns this declaration and nothing else. The picker offers no "system default" row,
    /// so the two rungs below CANNOT fire today. They are kept rather than dropped because
    /// they are the symmetric inverse of `select(_:)` and cost nothing while dormant — the
    /// #527 shape: do not unwire a mechanism a future door would need. But do not read their
    /// absence from a diag log as evidence about the route; read it as "no door".
    public func useSystemDefault() {
        #if canImport(AVFoundation) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // #880: same event, other direction — handing the choice back to the system is a
        // route move too, and it was equally absent from the exported file.
        EchoelCrashLog.breadcrumb("input: select → system default")
        do {
            try session.setPreferredInput(nil)
            refresh()
        } catch {
            EchoelCrashLog.breadcrumb("input: system default FAILED ("
                + AudioConfiguration.sanitisedRoute(error.localizedDescription) + ")")
            log.audio("clearing preferred input failed: \(error.localizedDescription)", level: .error)
        }
        #endif
    }
}
