// PlugInInvitation.swift
// Echoelmusic — Studio (#596: the plug-in invitation's pure brain)
//
// Founder ask (2026-08-14): "per angesteckten usb Micro oder Audio Interface
// automatischer Instrument in Erkennung". The measured constraint that shapes this
// (PLAN_VOICE_STAGE_2026-08-14.md): under the default `.playback` session category
// `availableInputs` is EMPTY and stays so — upgrading the category on plug-in would
// drag other apps' Bluetooth audio down to HFP, exactly what #299 ended. So the app
// listens to the ROUTE CHANGE only (fires under `.playback` too) and shows an
// INVITATION; the user opens the existing input sheet and arms monitoring there.
// NO auto-arm (#277 consent shape), NO silent category upgrade.
//
// This file is the decision only — pure Foundation, no AVFoundation import — so the
// "which plug deserves an invitation" rule is testable END-TO-END in CISmoke.
// Port classification is NOT restated here: `AudioInputClassifier.classify` already
// owns the port-type → kind mapping (#416, one definition per decision). A plug
// qualifies when it classifies as `.wired` or `.usb` — the two classes a musician
// plugs in ON PURPOSE. Bluetooth is deliberately OUT: pairing headphones is routine
// listening, not an instrument gesture, and BT monitoring is the high-latency path
// the input sheet already warns about. Built-in / virtual / CarPlay likewise.
//
// ⚠️ HONEST LIMIT, stated where the next session will look: under `.playback` a pure
// USB *microphone* (input-only, no output half) may produce NO route change at all —
// iOS surfaces some input-only devices only once the category is `.playAndRecord`.
// A USB audio INTERFACE (in+out) surfaces via its output half, which carries the
// SAME "USBAudio" port type — that path, the founder's actual ask, stands. ⛔ The
// WIRED-HEADSET class is weaker than the first version of this paragraph implied
// (review #596): under `.playback` a plugged headset surfaces as OUTPUT "Headphones"
// (not wired-classified — deliberately, plain headphones are not an instrument) and
// its MIC half is not in `currentRoute` at all, so the headset invitation may only
// fire once a mic feature has raised the category. The "MicrophoneWired" handling
// is still correct and still required — it is what classifies the port right in the
// input LIST and in any route change that does carry the mic half. Both gaps are
// iOS properties, not bugs here; closing them would need the category upgrade this
// design explicitly refuses.

import Foundation

public enum PlugInInvitation {

    /// One port of the changed route, reduced to what the decision needs.
    public struct PortDescription: Equatable, Sendable {
        /// `AVAudioSession.Port.rawValue` (e.g. "USBAudio", "MicrophoneWired").
        public let type: String
        /// The user-visible port name iOS reports (e.g. "Scarlett 2i2"). May be empty.
        public let name: String
        public let isInput: Bool

        public init(type: String, name: String, isInput: Bool) {
            self.type = type
            self.name = name
            self.isInput = isInput
        }
    }

    /// The display name to invite for, or nil when nothing about this route change
    /// deserves an invitation. Inputs are preferred over outputs (an interface that
    /// shows both halves is named by its mic half); the first qualifying port wins.
    /// An empty iOS-reported name falls back to a generic per kind, so the row never
    /// renders a nameless invitation.
    public static func portName(reasonIsNewDevice: Bool,
                                ports: [PortDescription]) -> String? {
        guard reasonIsNewDevice else { return nil }
        let qualifying = ports.filter { qualifies($0.type) }
        guard let port = qualifying.first(where: { $0.isInput }) ?? qualifying.first
        else { return nil }
        if !port.name.isEmpty { return port.name }
        switch AudioInputClassifier.classify(portTypeRaw: port.type).kind {
        case .usb:   return "USB audio device"
        default:     return "Wired input"
        }
    }

    /// One definition of "plugged in on purpose": the classifier's `.wired`/`.usb`.
    private static func qualifies(_ portTypeRaw: String) -> Bool {
        switch AudioInputClassifier.classify(portTypeRaw: portTypeRaw).kind {
        case .wired, .usb: return true
        default:           return false
        }
    }
}
