//
//  EchoelWatchApp.swift
//  Echoelmusic — watchOS companion
//
//  Cycle C5 (scaffold). A single SwiftUI watchOS app built on the same
//  Foundation-only BioFeedbackManager path the Widget uses, so this target
//  compiles without importing the app module.
//
//  ⛔ THE ROUTE THIS FILE DESCRIBED IS NOT A ROUTE (#549). The header said it
//  "mirrors the live vitals the phone publishes into the shared App Group", and
//  the scope note said the producer half is "on-wrist HealthKit HR → App Group,
//  so the phone consumes wrist HR". **An App Group container is PER DEVICE.**
//  The watch and the iPhone do not share a `UserDefaults(suiteName:)` — an
//  App Group is shared between processes on ONE device, which is exactly why
//  this same code IS correct for the Widget (same phone) and cannot carry a
//  byte between wrist and phone in either direction. Measured 2026-08-12:
//  `git grep -n "WatchConnectivity\|WCSession" -- Sources` returns NOTHING, so
//  there is no transport in this repo at all.
//
//  ⭐ SO C7 IS NOT A HEALTHKIT TASK, IT IS A TRANSPORT DECISION, and that is the
//  whole point of writing this down: `WCSession` is a new framework, which under
//  CLAUDE.md needs the Council/founder step BEFORE any wrist-HealthKit code is
//  written. Someone picking up "C7: add HealthKit on-wrist HR → App Group" as
//  specified would write correct HealthKit code against a channel that does not
//  exist and could not tell, because…
//
//  ⚠️ …THE FAILURE IS SILENT BY CONSTRUCTION. `refreshFromSharedStore()` returns
//  nil when the container holds nothing, and `hasData == false` renders the
//  perfectly reasonable idle state ("Start a session on iPhone."). A wired
//  route that transports nothing and an unwired one look IDENTICAL on the
//  wrist. That is why this note is here rather than in a backlog file.
//
//  ── SCOPE (deliberately small this cycle) ─────────────────────────────────
//    This is the *consumer/glance* half: wrist shows HR / HRV / coherence —
//    from THIS device's App Group container, which nothing on the watch writes
//    today. The *producer* half is C7 and needs the transport decision above
//    before any HealthKit workout-session code.
//
//  ⚠️ NOBODY HAS SEEN THIS. The target is NOT embedded — `project.yml` keeps
//  `- target: EchoelmusicWatch` commented out under the app's dependencies
//  (signing-safe C5 pattern), so no build ships it. The severity is planning
//  cost, not user impact — and it rises the day the embed is turned on.
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

    /// Same three-state reading as the Widget (#632): only an explicit `true` marks.
    /// `nil` (a payload written before the field existed) stays unmarked rather than
    /// branding a real reading fake.
    private var isDemo: Bool { vitals.synthetic == true }

    /// `.secondary` with a hairline outline, never an accent or a warning colour —
    /// green would assert the body this tag exists to deny.
    private var demoTag: some View {
        Text("Demo")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasData {
                HStack(spacing: 5) {
                    Text("Heart rate").font(.caption2).foregroundStyle(.secondary)
                    if isDemo { demoTag }
                }
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
