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

    public init(id: String, name: String, portTypeRaw: String,
                kind: AudioInputKind, latency: MonitoringLatency) {
        self.id = id
        self.name = name
        self.portTypeRaw = portTypeRaw
        self.kind = kind
        self.latency = latency
    }
}

/// Pure mapping from an `AVAudioSession.Port` raw value to kind + latency class.
/// Cross-platform and dependency-free so it is testable everywhere.
public enum AudioInputClassifier {

    public static func classify(portTypeRaw raw: String) -> (kind: AudioInputKind, latency: MonitoringLatency) {
        switch raw {
        // Built-in
        case "MicrophoneBuiltIn":                       return (.builtIn, .low)
        // Wired
        case "HeadsetMicrophone", "LineIn", "HeadphonesMicrophone":
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
                                  kind: c.kind, latency: c.latency)
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
        guard let port = (session.availableInputs ?? []).first(where: { $0.uid == id }) else {
            log.audio("Input \(id) no longer available", level: .warning)
            return
        }
        do {
            try session.setPreferredInput(port)
            selectedID = id
            log.audio("Preferred input → \(port.portName) [\(port.portType.rawValue)]")
        } catch {
            log.audio("setPreferredInput failed: \(error.localizedDescription)", level: .error)
        }
        #endif
    }

    /// Clear the preferred input (let the system pick the default route).
    public func useSystemDefault() {
        #if canImport(AVFoundation) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInput(nil)
            refresh()
        } catch {
            log.audio("clearing preferred input failed: \(error.localizedDescription)", level: .error)
        }
        #endif
    }
}
