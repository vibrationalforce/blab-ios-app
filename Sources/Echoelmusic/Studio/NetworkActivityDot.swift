#if canImport(SwiftUI) && canImport(Network)
import SwiftUI

/// What a network output can tell a UI about itself, and nothing more.
///
/// Deliberately two members. Both are already declared, already public and already maintained
/// by all four senders — `OSCSender`, `ADMOSCSender`, `ArtNetSender`, `SACNSender` — so this
/// protocol adds a shared read, not a new mechanism.
@MainActor
public protocol NetworkSendActivity: AnyObject {
    /// The connection is open. NOT evidence that anything has been sent.
    var isActive: Bool { get }
    /// `CFAbsoluteTimeGetCurrent()` of the last datagram handed to the network stack.
    var lastSentTimestamp: TimeInterval { get }
}

/// The three states an output can honestly be in, and the words for each.
///
/// ⚠️ "SENDING" MEANS HANDED TO THE OS, NOT DELIVERED. Every sender's `send` discards the
/// completion error (`.contentProcessed { _ in }`), so nothing in this app knows whether a
/// datagram arrived — UDP would not tell it reliably even if it looked. That is why the third
/// word is never "connected": a wrong IP looks exactly like a right one from in here, and a
/// label promising delivery would be the same overclaim this type exists to remove.
public enum NetworkSendState: Equatable, Sendable {
    /// The output is not running at all.
    case off
    /// A datagram left the device within the freshness window.
    case sending
    /// The connection is open and nothing has left recently. **This is a legitimate steady
    /// state, not a fault** — and saying so is half the point of the type:
    ///   · `ArtNetSender`/`SACNSender` hold the rig's last DMX level and deliberately emit
    ///     nothing while the source is stale and no master/slew value is moving;
    ///   · `ADMOSCSender` skips a scene identical to the one it already streamed;
    ///   · `OSCSender`'s bio egress is refused for a HealthKit/Watch/ring source by
    ///     `BioEgressPolicy`, which can silence a whole session while the connection is fine.
    case openIdle

    public var label: String {
        switch self {
        case .off:      return "off"
        case .sending:  return "sending"
        case .openIdle: return "open, nothing sent"
        }
    }

    /// How long a stamp counts as "just now".
    ///
    /// Chosen against the SLOWEST real sender rather than the fastest: Art-Net ticks about every
    /// 33 ms, but `OSCSender`'s bio egress publishes at roughly 1 Hz, so anything under ~2 s
    /// would make a perfectly healthy OSC output blink between two states. Three seconds is one
    /// visible beat of hysteresis above that. It is a judgement, not a measurement — the only
    /// wrong answer is one that flickers.
    public static let freshnessWindow: TimeInterval = 3.0

    public static func state(isActive: Bool, lastSent: TimeInterval, now: TimeInterval) -> NetworkSendState {
        guard isActive else { return .off }
        guard lastSent > 0, now - lastSent < freshnessWindow else { return .openIdle }
        return .sending
    }
}

/// The row header for one network output: the state dot, the name, and the spoken state.
///
/// ⚠️ IT IS A LEAF, AND THAT IS THE WHOLE REASON THE FILE EXISTS. `lastSentTimestamp` is a
/// TRACKED property on an `@Observable` sender that is stamped at up to ~30 Hz. Reading it in
/// `PatchbayView.body` would register that body — which hosts the host/port `TextField`s and the
/// resolution `Picker` — as a 30 Hz observer, and every rebuild tears down an open Picker
/// popover. That is the 10.76.50 freeze, on the surface an operator uses mid-show. Confining the
/// read here means only this 7 pt dot churns.
@MainActor
struct NetworkOutputHeader: View {
    let name: String
    let sender: any NetworkSendActivity

    /// Own clock, low rate. Without it a stamp that simply STOPS never re-renders anything, so
    /// "sending" would stay on screen forever after the last datagram — the exact defect this
    /// replaces, one property over. 2 Hz is fast enough that the transition reads as immediate
    /// against a 3 s window and slow enough to be invisible as motion.
    private static let tick: TimeInterval = 0.5

    var body: some View {
        // `_ in` on purpose: the timeline's `date` is a wall clock, while `lastSentTimestamp`
        // is `CFAbsoluteTime`. Mixing the two epochs is how a freshness test silently compares
        // numbers ~31 years apart. The tick is used ONLY to re-evaluate; the comparison stays
        // inside one clock.
        TimelineView(.periodic(from: .now, by: Self.tick)) { _ in
            let state = NetworkSendState.state(isActive: sender.isActive,
                                               lastSent: sender.lastSentTimestamp,
                                               now: CFAbsoluteTimeGetCurrent())
            HStack(spacing: 7) {
                // Shape, not colour — the row's original note: green-versus-grey is unreadable
                // for a red-green colour-blind operator on the one surface where reading it
                // wrong means a silent show, and `differentiateWithoutColor` is used nowhere in
                // this codebase. Three states need three shapes, so the middle one is a ring
                // with a dot in it: open, but empty.
                Group {
                    switch state {
                    case .sending:  Circle().fill(EchoelTheme.accent)
                    case .openIdle: Circle().strokeBorder(EchoelTheme.accent, lineWidth: 2.5)
                    case .off:      Circle().strokeBorder(EchoelTheme.border, lineWidth: 1.5)
                    }
                }
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
                Text(name).font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(state.label)
        }
    }
}

/// The live half of the Immersive Stage's status line.
///
/// Its own view for the same reason as `NetworkOutputHeader`: `lastSentTimestamp` moves at up to
/// ~30 Hz, and the stage body hosts drag gestures over every track puck. The two STATIC sentences
/// (no route / connection closed) stay in the parent, because they are computed from flags that
/// change only when the operator changes them.
@MainActor
struct ADMStreamStatusLine: View {
    let sender: any NetworkSendActivity
    let host: String
    let port: UInt16
    /// Object count in the last streamed scene. A parent-passed value on purpose — it is
    /// low-frequency (it changes when the arrangement does), so it costs the parent nothing.
    var objectCount: Int = 0

    private static let tick: TimeInterval = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { _ in
            let state = NetworkSendState.state(isActive: sender.isActive,
                                               lastSent: sender.lastSentTimestamp,
                                               now: CFAbsoluteTimeGetCurrent())
            let objects = "\(objectCount) object\(objectCount == 1 ? "" : "s")"
            Text(state == .sending
                 ? "Sending \(objects) to \(host):\(port)."
                 : "Connection open to \(host):\(port) — \(objects) held, nothing sent just now.")
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Conformances
//
// Retroactive and EMPTY: all four senders already declare both members, publicly, with these
// exact names and types — this protocol names an existing shared shape rather than adding one.
//
// They live here and not in `Sync/` on purpose. `Sync/` imports Foundation and Network; the
// protocol is only ever read by a view, and putting a Studio-side type's name into a sender file
// would point the dependency the wrong way for a layer whose whole job is to know nothing about
// the UI. Same-module retroactive conformance costs nothing and keeps that arrow pointing one way.
extension OSCSender: NetworkSendActivity {}
extension ADMOSCSender: NetworkSendActivity {}
extension ArtNetSender: NetworkSendActivity {}
extension SACNSender: NetworkSendActivity {}
#endif
