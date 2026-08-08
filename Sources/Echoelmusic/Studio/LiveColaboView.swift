// LiveColaboView.swift
// Echoel — Live Colabo (nearby). The DMMW "Live Collaboration" surface: go live,
// discover nearby Echoel devices, connect, and share your current session both
// ways. Built on MultipeerSession (Apple MultipeerConnectivity, no external dep).
// Real-time tempo/phase lock (Ableton Link) is a separate device-verified step.
//
// Uncodixfy: solid fills, ≤8px radius, 1px borders, colour/opacity feedback only.

#if canImport(SwiftUI) && canImport(MultipeerConnectivity)
import Foundation
import SwiftUI

@MainActor
struct LiveColaboView: View {

    @Environment(MultipeerSession.self) private var colab
    @Environment(ProjectStore.self) private var projects
    @Environment(EngineBus.self) private var bus
    @Environment(\.dismiss) private var dismiss

    /// Snapshot of the live session to send (provided by the host view).
    let currentSession: () -> Project
    /// Load a received session into the live instrument.
    let onLoadShared: (Project) -> Void

    /// Opt-in per visit (E5): stream own live bio to connected peers ONLY while
    /// this view is open and the toggle is on. Deliberately not persisted —
    /// sharing your pulse is a per-session choice, never a background default.
    @State private var shareBio = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    goLiveRow
                    Text(colab.status)
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)

                    if let invite = colab.pendingInvitation {
                        invitationCard(invite)
                    }

                    if let inc = colab.incoming, let project = inc.project {
                        incomingCard(inc.senderName, project)
                    }

                    if colab.isLive {
                        shareButton
                        if !colab.connectedPeerNames.isEmpty {
                            connectedSection
                            bioSection
                        }
                        discoveredSection
                    } else {
                        Text("Two Echoelmusic devices on the same Wi-Fi find each other here. Go live, connect, and share your session both ways — a starting point to jam from together.")
                            .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Live Colabo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onDisappear { colab.stop() }
            // Own-bio stream: one reading every `PeerReading.sendInterval` while the
            // toggle is on AND this view is open (task dies with the view — bio never
            // streams in the background). Reads the bus inside the task, so no
            // high-frequency observation registers on this body (render safety).
            .task(id: shareBio) {
                guard shareBio else { return }
                while !Task.isCancelled {
                    // ⛔ THIS ASKED `bus.latestBio` UNTIL #508, and that snapshot is
                    // NEVER cleared — its only writer is the publish sink, and neither
                    // `stop()` nor a lost pulse empties it. So putting the phone down
                    // did not stop this loop: it kept re-encoding the SAME frozen frame
                    // 2.5× a second, for the rest of the session, onto other people's
                    // screens, where it reads as a perfectly steady live pulse. That is
                    // #503/#507 across the device boundary, and worse there, because the
                    // held number is a claim about a body the viewer cannot see.
                    //
                    // ⭐ AND IT IS THE ONLY BIO EGRESS PATH WITH THIS SHAPE — measured,
                    // not assumed: `ArtNetSender`, `SACNSender` and `ADMOSCSender` all
                    // read the raw snapshot too, but each ends in
                    // `guard sourceTimestamp != lastFrameTimestamp`, so a frozen frame
                    // is a no-op for a light or a spatial object. This loop had no
                    // dedupe at all, by design (unreliable transport, a receiver that
                    // missed the last packet still needs the next one).
                    //
                    // ⛔ THE 5.1.3 EGRESS GATE USED TO STAND HERE, as a conjunct in this
                    // very `if`, together with a hand-built `BioPeek`. #511 moved it into
                    // `sendBio` (via `BioPeek.egressible(from:)`), and NOT because this
                    // line was wrong — it was correct — but because it was the only thing
                    // standing between a HealthKit-sourced heart rate and another person's
                    // phone, in a view's stream loop, one edit away from being simplified.
                    // #508 had already named that edit as the HAZARD — an ⚠️ prohibition
                    // stood on this line ("dropping this guard because the frame is now
                    // fresh would ship the exact 5.1.3 violation the network senders
                    // forbid") plus a counterweight test written to block it. #511 does
                    // not disagree with that warning; it removes the possibility instead
                    // of relying on a reader heeding it. Freshness is not provenance, and
                    // a 5.1.3 violation does not show up in a hearing test — it shows up
                    // as a rejection. Do not re-add the check here; asking twice is how
                    // one of the two rots.
                    //
                    // ⛔ THE FIRST DRAFT OF THIS BLOCK SAID "#508 even wrote that edit
                    // down", which reads as if the author of the prohibition had PROPOSED
                    // the deletion. It is the inverse of what the parent tree says. The
                    // full retraction, and why this class of error is worse than a stale
                    // number, is on `BioPeek.egressible(from:)`.
                    //
                    // What DOES stay this view's question is `usableBio()`: whether the
                    // measurement is still current is a fact about the bus and its
                    // per-source window, not about who may see it.
                    if let f = bus.usableBio(), !colab.connectedPeerNames.isEmpty {
                        colab.sendBio(f)
                    }
                    try? await Task.sleep(
                        nanoseconds: UInt64(PeerReading.sendInterval * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Pieces

    private var goLiveRow: some View {
        Button { colab.isLive ? colab.stop() : colab.start() } label: {
            Label(colab.isLive ? "Stop" : "Go Live (nearby)",
                  systemImage: colab.isLive ? "stop.fill" : "dot.radiowaves.left.and.right")
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(colab.isLive ? EchoelTheme.onPrimary : EchoelTheme.text)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(colab.isLive ? EchoelTheme.accent : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: colab.isLive ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var shareButton: some View {
        Button { colab.share(project: currentSession()) } label: {
            Label("Share current session", systemImage: "square.and.arrow.up.on.square")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
        }
        .buttonStyle(.plain)
        .disabled(colab.connectedPeerNames.isEmpty)
        .opacity(colab.connectedPeerNames.isEmpty ? 0.4 : 1)
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            ForEach(colab.connectedPeerNames, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.checkmark").foregroundStyle(EchoelTheme.accent)
                    Text(name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Spacer()
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nearby").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            if colab.discovered.isEmpty {
                Text("Searching…").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            }
            ForEach(colab.discovered) { peer in
                HStack(spacing: 8) {
                    Image(systemName: "iphone").foregroundStyle(EchoelTheme.dim)
                    Text(peer.name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
                    Spacer()
                    Button { colab.invite(peer.name) } label: {
                        Text("Invite").font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            }
        }
    }

    /// Side-by-side live bio (E5): my numbers and each peer's numbers, each
    /// person's OWN values — deliberately NO combined "group coherence" score
    /// (decision 2026-06-20: measured, not claimed).
    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $shareBio.animation(.easeInOut(duration: 0.15))) {
                Text("Share my pulse (live)")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            .accessibilityHint("Streams your heart rate and coherence to connected peers while this screen is open. Everyone sees their own numbers side by side.")

            if shareBio {
                OwnBioRow()
            }
            // Peer rows read colab.peerReadings in their OWN leaf (render safety) —
            // this body must not touch that ~2.5 Hz dictionary.
            PeerBioRows()

            Text("Each person's own numbers, side by side — nothing is combined into a shared score.")
                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Explicit consent for a join request (never auto-accepted — audit 2026-07-16):
    /// the user decides WHO connects, because bio sharing may be on.
    private func invitationCard(_ invite: PendingInvitation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(invite.peerName) wants to join")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
            Text(shareBio
                 ? "Joining lets them share sessions with you — and see your live pulse while sharing is on."
                 : "Joining lets them share sessions with you.")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { colab.respondToInvitation(accept: true) } label: {
                    Text("Accept").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                }
                .buttonStyle(.plain)
                Button { colab.respondToInvitation(accept: false) } label: {
                    Text("Decline").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.accent.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(invite.peerName) wants to join your session")
    }

    private func incomingCard(_ from: String, _ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session from \(from)")
                .font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
            Text("\(project.name) · \(project.style.displayName) · \(project.key.shortName) · \(EchoelDecimalText.string(project.bpm, decimals: 0)) BPM")
                .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { onLoadShared(project); colab.clearIncoming() } label: {
                    Text("Load").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.onPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                }
                .buttonStyle(.plain)
                Button { projects.save(project); colab.clearIncoming() } label: {
                    Text("Save").font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { colab.clearIncoming() } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(EchoelTheme.dim)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.accent.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Bio leaves (render safety: the ~10 Hz own-bio and 2–3 Hz peer-bio
// reads live in their OWN leaf bodies so only these rows churn, never the
// sheet's buttons/toggles above.)

/// My own live numbers — reads the bus in ITS body only.
///
/// It asks `usableBio()`, the SAME question the stream loop above asks before sending
/// (#508). That is the point, not a coincidence: this row is the only place a person can
/// see what their peers are being told, so a row that outlives the wire would be a
/// readout of a stream that has stopped.
///
/// ⚠️ THE `TimelineView` IS LOAD-BEARING (the #503 lesson, verbatim). `usableBio()` flips
/// to nil on the passage of TIME, and the event that makes it nil — a source that stopped
/// publishing — is by definition the event that stops invalidating this body. Without a
/// tick the row would freeze at its last evaluation, which is the instant the last frame
/// arrived, and assert liveness forever: the exact defect this slice removes. 1 Hz is
/// chosen against the shortest window it must resolve (`BioSource.freshnessWindow` = 5 s
/// for `.fallback`), and `CFAbsoluteTimeGetCurrent()` is read when the row actually
/// renders — a `TimelineSchedule` context date is the SCHEDULED instant, not the redraw
/// instant, and this body is rebuilt on every publish, which re-phases the schedule.
@MainActor
private struct OwnBioRow: View {
    @Environment(EngineBus.self) private var bus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let f = bus.usableBio()
            bioLine(name: "You",
                    bpm: f?.heartRateBPM ?? 0,
                    coherence: f?.coherence ?? 0,
                    highlight: true)
        }
    }
}

/// Connected peers' latest readings — reads `colab.peerReadings` in ITS body only.
///
/// ⚠️ A ROW STAYS WHEN ITS NUMBERS EXPIRE; it does not disappear (#508). The peer is
/// still CONNECTED — that is information, and it is exactly what `bioLine` already says
/// with "— bpm / coh —" for a zero. Dropping the row instead would shove the layout every
/// time a phone went into a pocket (the #382 class) and would make "gone quiet" look
/// identical to "left the session", which are different facts with different remedies.
/// The name is removed only by disconnect or `stop()`, both of which already clear it.
@MainActor
private struct PeerBioRows: View {
    @Environment(MultipeerSession.self) private var colab

    var body: some View {
        // `String`'s `<` is Unicode CODEPOINT order, not collation: "Ärger" sorts after
        // "Zoe" for a German reader, and any Cyrillic or CJK name lands in a block after
        // every Latin one. These keys are peer DISPLAY NAMES — whatever the other performer
        // called their device — so they are exactly the case where codepoint order is wrong.
        // `localizedStandardCompare` is the Finder-style ordering people expect.
        //
        // Checked, not assumed: this is the only sort of user-authored text that reaches a
        // view. The other `.sorted()` call sites on strings are `ModulationEngine`'s ASCII
        // destination keys (no production consumer) and integer/slot sorts; the three preset
        // stores rank by favourite and recency, never by name.
        ForEach(colab.peerReadings.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }, id: \.self) { name in
            // ⚠️ THE TICK IS INSIDE THE ROW, NOT AROUND THE `ForEach` — the #503 trade,
            // for the same two reasons. (1) Wrapping the loop would put ONE container
            // where a list of sibling rows belongs, and the rows would stop flattening
            // into the enclosing `VStack`. (2) A handful of 1 Hz tickers is the cheap
            // half of that. Without any tick the row freezes at the instant the last
            // packet arrived and therefore asserts a live peer forever — which is the
            // whole defect, since a peer who stopped sending also stopped invalidating
            // this body.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let live = colab.peerReadings[name]?.live(at: CFAbsoluteTimeGetCurrent())
                bioLine(name: name,
                        bpm: live?.bpm ?? 0,
                        coherence: live?.coherence ?? 0,
                        highlight: false)
            }
        }
    }
}

/// One person's row: name · BPM · coherence (their OWN values; `0` shows as "—",
/// mirroring BioSampleFrame's "not available"). Legible numbers first.
@MainActor
private func bioLine(name: String, bpm: Float, coherence: Float, highlight: Bool) -> some View {
    HStack(spacing: 8) {
        Image(systemName: highlight ? "heart.fill" : "heart")
            .font(.system(size: 12))
            .foregroundStyle(highlight ? EchoelTheme.accent : EchoelTheme.dim)
        Text(name).font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            .lineLimit(1)
        Spacer(minLength: 8)
        Text(bpm > 0 ? "\(EchoelDecimalText.string(bpm, decimals: 0)) bpm" : "— bpm")
            .font(EchoelTheme.font(13).monospacedDigit())
            .foregroundStyle(EchoelTheme.text)
        Text(verbatim: coherence > 0
             ? "coh " + EchoelDecimalText.string(coherence, decimals: 2)
             : "coh —")
            .font(EchoelTheme.font(12).monospacedDigit())
            .foregroundStyle(EchoelTheme.dim)
    }
    .padding(.vertical, 6).padding(.horizontal, 10)
    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name): \(bpm > 0 ? "\(Int(bpm)) beats per minute" : "no pulse yet"), coherence \(coherence > 0 ? EchoelDecimalText.string(coherence, decimals: 2) : "not available")")
}
#endif
