//
//  BioEgressPolicy.swift
//  Echoelmusic — Sync
//
//  Pure, testable rule for which bio SOURCES may stream off the device
//  (OSC / ADM-OSC bio frames to user-chosen network targets).
//
//  App Store Guideline 5.1.3: data obtained from the HealthKit store may not be
//  shared with third parties — and once a UDP packet leaves the phone to a
//  user-typed host, we can no longer vouch for where it lands. So the network
//  senders forward ONLY Echoel's OWN measurements (camera rPPG, BLE strap,
//  front-camera face expression, the demo generator) and never frames sourced from
//  Apple Health / Watch / ring bridges. For face expression only the abstracted
//  [0..1] channels egress — never the image. Mirrors the non-circular pattern of
//  `HealthWritePolicy.isWritableSource`
//  (which gates the opposite direction: what we write INTO Health).
//
//  Discrete BioEvents need no gate today: `.heartbeat` events are produced only by
//  the BLE strap's own RR stream (PolarH10BioPublisher), and breath/motion onsets
//  are BioEventGraph derivations of estimated channels — no HealthKit-store values
//  flow through the event queue. Revisit if a HealthKit-fed event producer appears.
//

import Foundation

public enum BioEgressPolicy {

    /// Whether frames from this source may be sent off-device. Only sources
    /// Echoel measures itself (or synthesizes, for the demo) pass; anything
    /// read out of the HealthKit store stays on the device (5.1.3).
    public static func allowsEgress(_ source: BioSource) -> Bool {
        switch source {
        case .ble, .cameraPPG, .faceCam, .fallback:
            // faceCam is measured on-device like rPPG; only the abstracted [0..1]
            // expression channels egress (never the image), same principle as PPG.
            return true
        case .healthKit, .watch, .oura:
            return false
        }
    }
}
