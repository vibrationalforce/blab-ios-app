//
//  BioSourceOption.swift
//  Echoelmusic — Studio
//
//  #616 (GUI-Board Zeile 6, UX#4) — ONE definition (#416) of the bio-source
//  chooser entries, consumed by exactly TWO surfaces:
//   · the header pulse pill's long-press `.contextMenu` (HeaderMonitors — posts
//     `.echoelSelectBioSource`, the chrome stays notification-decoupled), and
//   · the visible "Bio source" row in `bioPanel` (EchoelStudioView.bioSourceRow —
//     calls `selectBioSource` directly; same file, no notification needed).
//  Before #616 the labels lived inline in the pill's menu and the ONLY chooser was
//  the long-press — the least discoverable gesture we ship (the Routing button's
//  own ⛔ block in `bioPanel` calls it that, and #234's a11y half already named
//  the motor-impairment cost).
//
//  ⚠️ THE LABELS SAY "Play with" ON PURPOSE (#234): every entry routes to
//  `selectBioSource`, which hot-swaps the source while a take is live and STARTS
//  A FULL GENERATIVE SESSION when idle. Under bare source names ("Camera light",
//  "Simulation") this menu was a hidden Start — the exact thing the founder
//  counted ("Ich hab jetzt hier 3 Knöpfe zum Start"). "Play with" is honest in
//  BOTH states: idle it starts, running it keeps playing on the new source.
//  `TheBioSourceChooserHasOneDefinitionTests` pins the prefix behaviourally.
//
//  ⚠️ The BLE label carries "— scans for one" because the plain rename dropped a
//  half the user needs: the music starts from neutral defaults immediately,
//  whether or not a strap is ever found. Both halves are true.
//
//  ⚠️ `rawValue`s are the on-the-wire ids `selectBioSource` parses (its private
//  `BioSourceKind(rawValue:)` guard drops anything else SILENTLY — a mismatched
//  id here would be a menu entry that does nothing, the #135 lying-control
//  class). The guard pins the literal set {"camera","ble","sim"} behaviourally;
//  it cannot name the private enum, so the LITERALS are the contract.
//

import Foundation

/// The three bio inputs a player can choose. See the file header for why the
/// labels start with "Play with" and why the raw values are load-bearing.
enum BioSourceOption: String, CaseIterable, Identifiable {
    case camera, ble, sim

    var id: String { rawValue }

    /// Menu-entry label — shared verbatim by the pill's context menu and the
    /// bio-panel row so the two surfaces can never drift apart.
    var menuLabel: String {
        switch self {
        case .camera: return "Play with camera light"
        case .ble:    return "Play with a Bluetooth strap — scans for one"
        case .sim:    return "Play with the simulation"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .ble:    return "dot.radiowaves.left.and.right"
        case .sim:    return "waveform.path"
        }
    }

    /// Short noun for the row's current-value label (and VoiceOver value).
    var shortName: String {
        switch self {
        case .camera: return "Camera light"
        case .ble:    return "Bluetooth strap"
        case .sim:    return "Simulation"
        }
    }
}
