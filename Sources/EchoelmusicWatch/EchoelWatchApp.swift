//
//  EchoelWatchApp.swift
//  Echoelmusic — watchOS companion
//
//  Cycle C5 (scaffold). A single SwiftUI watchOS app that mirrors the live
//  vitals the phone publishes into the shared App Group (group.com.echoelmusic)
//  via BioFeedbackManager — the same Foundation-only consumer path the Widget
//  and AUv3 use, so this target compiles without importing the app module.
//
//  ── SCOPE (deliberately small this cycle) ─────────────────────────────────
//    This is the *consumer/glance* half: wrist shows HR / HRV / coherence.
//    The *producer* half (on-wrist HealthKit HR → App Group, so the phone
//    consumes wrist HR) lands CI-verified in C7 — HealthKit workout-session
//    code is too error-prone to add blind.
//
//  ── HARD CONSTRAINT (CLAUDE.md) ───────────────────────────────────────────
//    Apple Watch HR has ~4–5 s latency → display / trend ONLY, never beat-sync.
//
//  ── DESIGN ────────────────────────────────────────────────────────────────
//    Science-first: legible numbers, no flashing, muted. Mirrors the Widget.
//

import SwiftUI

@main
struct EchoelWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchBioView()
        }
    }
}

struct WatchBioView: View {
    private let bridge = BioFeedbackManager()
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    @State private var vitals = BioVitals()
    @State private var hasData = false

    private var bpm: Int { Int(vitals.heartRateBPM.rounded()) }

    /// 0 means "not measured" for both of these (the wrist before its first SDNN sample,
    /// any source with no beat-to-beat RR), so they render "—" — the same rule the in-app
    /// bio strip and the Widget follow. Printing "HRV 0%" on a glanceable surface would
    /// state a specific and alarming observation about the body that nothing measured.
    private var hrvText: String {
        vitals.hrvNormalized > 0 ? "\(Int((vitals.hrvNormalized * 100).rounded()))%" : "—"
    }
    private var coherenceText: String {
        vitals.coherence > 0 ? "\(Int((vitals.coherence * 100).rounded()))%" : "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasData {
                Text("Heart rate").font(.caption2).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(bpm)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    metric("HRV", hrvText)
                    metric("Coh", coherenceText)
                }
            } else {
                Text("Echoelmusic").font(.headline)
                Text("No session yet")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Start a session on iPhone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() {
        if let v = bridge.refreshFromSharedStore() {
            vitals = v
            hasData = true
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).monospacedDigit()
        }
    }
}
