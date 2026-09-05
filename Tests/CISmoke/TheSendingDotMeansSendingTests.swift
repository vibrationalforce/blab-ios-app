import XCTest
@testable import Echoelmusic

/// #996 — the network "sending" dot means a datagram left the device.
///
/// WHY IT EXISTS. All four senders set `isActive = true` ONE LINE after `connect()`, and the
/// Routing rows rendered exactly that flag as "sending". So the dot read "sending" with the
/// engine stopped and no publisher running; and the OSC row read "sending" for a whole session
/// whenever the bus's latest frame was `.healthKit`, because `BioEgressPolicy` refuses that
/// source and nothing on screen says so. `ImmersiveStageView` was worse: it asserted "Streaming
/// N objects to host:port" from the same flag, under a comment promising "one honest line for
/// every state" — the claim of honesty is how it survived review.
///
/// It fires where recovery is impossible: on stage, before doors, with the wrong IP looking
/// exactly like the right one.
///
/// THE FIX IS NOT `stateUpdateHandler`. UDP reaches `.ready` for any routable IPv4 literal, and
/// both light senders default to exactly those (255.255.255.255 and 192.168.1.100) — so that
/// change would leave a wrong-IP rig filled green. `lastSentTimestamp` is stamped by all four
/// senders after handing a datagram to the OS and had ZERO readers; this wires it.
///
/// ⚠️ HONEST GRADING. Six claims. 1-4 exercise `NetworkSendState` directly — a type that does
/// not exist on `HEAD`, so they are new behaviour rather than a before/after. Claim 6 is the
/// LOAD-BEARING structural one (green on the worktree, red on `HEAD`). Claim 5 is green on both
/// by design: `lastSentTimestamp` had zero readers anywhere before this slice, so the claim does
/// not prove the repair — it prevents the hot read from migrating INTO the two host bodies
/// later, which is the one way this fix turns into the 10.76.50 freeze.
///
/// ⚠️ WHAT "SENDING" DOES NOT CLAIM. Every `send` discards its completion error
/// (`.contentProcessed { _ in }`), so nothing here knows a datagram ARRIVED. That is why the
/// third state is never called "connected" — claim 4 pins that word out.
final class TheSendingDotMeansSendingTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — BEHAVIOURAL: the three states, from the real decision function.
    func testAnOpenConnectionThatSendsNothingIsNotSending() {
        let now: TimeInterval = 10_000

        XCTAssertEqual(NetworkSendState.state(isActive: false, lastSent: now, now: now), .off, """
            A closed output reports something other than `.off` — so a stopped engine can still \
            colour a dot on the Routing surface.
            """)
        XCTAssertEqual(NetworkSendState.state(isActive: true, lastSent: 0, now: now), .openIdle, """
            An output that has NEVER sent reports `.sending`. This is the original defect \
            verbatim: `isActive` goes true one line after `connect()`, so without a stamp test \
            the dot lights before a single datagram exists.
            """)
        XCTAssertEqual(NetworkSendState.state(isActive: true, lastSent: now - 0.1, now: now),
                       .sending, "A datagram sent 100 ms ago does not read as sending.")
        XCTAssertEqual(NetworkSendState.state(isActive: true,
                                              lastSent: now - NetworkSendState.freshnessWindow - 1,
                                              now: now), .openIdle, """
            A stamp far outside the window still reads as sending, so "sending" would stay on \
            screen forever after the last datagram — the same lie, one property over.
            """)
    }

    // 2 — the window is chosen against the SLOWEST sender, not the fastest. Art-Net ticks about
    // every 33 ms, but OSC's bio egress publishes at roughly 1 Hz; a window under ~2 s would make
    // a perfectly healthy OSC output blink between two states, which is worse than either lie.
    func testTheWindowClearsTheSlowestSendersCadence() {
        XCTAssertGreaterThanOrEqual(NetworkSendState.freshnessWindow, 2.0, """
            The freshness window dropped to \(NetworkSendState.freshnessWindow) s. OSC bio egress \
            publishes at about 1 Hz, so anything at or under that cadence makes a healthy output \
            flicker between "sending" and "open". If a sender genuinely got faster, say so here \
            with the measurement.
            """)
    }

    // 3 — the words. "open, nothing sent" is a legitimate steady state, not a fault: the light
    // senders hold the rig's last DMX level, ADM skips an unchanged scene, and OSC's bio egress
    // is refused for a HealthKit source. Three states need three distinct words.
    func testTheThreeStatesSayThreeDifferentThings() {
        let labels = [NetworkSendState.off.label,
                      NetworkSendState.sending.label,
                      NetworkSendState.openIdle.label]
        XCTAssertEqual(Set(labels).count, 3, "Two network states share a word: \(labels).")
        for label in labels {
            XCTAssertFalse(label.isEmpty, "A network state has no word at all.")
        }
    }

    // 4 — never "connected". The senders discard every completion error, so nothing in this app
    // knows a datagram arrived; a word implying a confirmed link would be the same overclaim
    // this slice removes, re-spelled.
    func testNoStateClaimsAConfirmedLink() {
        for label in [NetworkSendState.off.label,
                      NetworkSendState.sending.label,
                      NetworkSendState.openIdle.label] {
            XCTAssertFalse(label.lowercased().contains("connect"), """
                A network state says "\(label)". Every sender's `send` discards its completion \
                error, and UDP would not report delivery reliably anyway — so no label here may \
                imply a confirmed link. "open" describes what this app actually knows.
                """)
        }
    }

    // 5 — the freeze law, and the reason this is a leaf at all. `lastSentTimestamp` is a TRACKED
    // property stamped at up to ~30 Hz. Reading it in `PatchbayView` would subscribe the
    // host/port `TextField`s and the resolution `Picker` to a 30 Hz signal (10.76.50), on the
    // surface an operator uses mid-show; in `ImmersiveStageView` it would land on a body hosting
    // a drag gesture over every puck.
    func testTheHotStampIsReadOnlyInALeaf() throws {
        for host in ["Sources/Echoelmusic/Studio/PatchbayView.swift",
                     "Sources/Echoelmusic/Studio/ImmersiveStageView.swift"] {
            let text = try source(host)
            // Comments are allowed to NAME it — they explain why it is not read here.
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("lastSentTimestamp"), """
                \(host) reads `lastSentTimestamp` in its own body. That value is stamped per \
                datagram — up to ~30 Hz on an `@Observable` — so this re-registers the whole \
                surface as a high-frequency observer and tears down any open Picker or drag. \
                The read belongs in `NetworkOutputHeader` / `ADMStreamStatusLine`.
                """)
        }
    }

    // 6 — every output got the honest dot, not just the one that was looked at. A partial
    // fan-out is the same defect as none: one row tells the truth and three keep lying.
    func testAllFourOutputsUseTheHonestHeader() throws {
        let leaf = try source("Sources/Echoelmusic/Studio/NetworkActivityDot.swift")
        for sender in ["OSCSender", "ADMOSCSender", "ArtNetSender", "SACNSender"] {
            XCTAssertTrue(leaf.contains("extension \(sender): NetworkSendActivity {}"), """
                \(sender) no longer conforms to `NetworkSendActivity`, so its Routing row cannot \
                render the honest state. All four senders already declare both members; the \
                conformance is empty by design.
                """)
        }
        let patchbay = try source("Sources/Echoelmusic/Studio/PatchbayView.swift")
        XCTAssertEqual(patchbay.components(separatedBy: "NetworkOutputHeader(name:").count - 1, 1, """
            The Routing rows no longer mount exactly one `NetworkOutputHeader`. All four rows go \
            through one `outputRow`; a second mount means a row was special-cased, which is how \
            three outputs keep an old dot while one gets the new one.
            """)
    }
}
