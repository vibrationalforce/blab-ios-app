#if canImport(UIKit) && canImport(CoreAudioKit) && os(iOS)
import SwiftUI
import CoreAudioKit
import UIKit

// BluetoothMIDIPairingView.swift
// Echoel — hosts Apple's built-in Bluetooth-MIDI central (CABTMIDICentralViewController)
// inside the Routing panel so a wireless MIDI keyboard/controller can be paired without
// leaving the app. Pairing a controller brings a new CoreMIDI source online, which
// MIDIInput's `.msgSetupChanged` → `connectAllSources()` path auto-connects — so the
// controller's notes drive the synth with ZERO extra wiring here (no MIDIInput change).
// The VC is a self-managing UITableView of nearby BLE-MIDI peripherals; it owns its own
// scan/pair lifecycle (a UIViewControllerRepresentable VC-bridge). iOS-only:
// CoreAudioKit's BLE-MIDI central does not exist on macOS.

/// Bridges `CABTMIDICentralViewController` into SwiftUI. Holds no state of its own —
/// the system view controller manages Bluetooth discovery, the permission prompt, and
/// the pairing lifecycle. Pushed (not sheet-presented) from `PatchbayView`, so it does
/// not grow `EchoelStudioView`'s modal chain.
struct BluetoothMIDIPairingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ vc: CABTMIDICentralViewController, context: Context) {}
}
#endif
