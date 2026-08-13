// TrustWindowTally.swift
// Echoel — #573, the instrument that decides what C3b / the trust rule may be tuned to.
//
// WHY IT EXISTS. The founder's two device logs from v10.79.387 (build 2504) report `body=0`
// on EVERY `generate` line and `bio=0` on EVERY `visual` line across ~11 minutes, while the
// cue read "Locked" and `conf` reached 0.98. #572 removed the three-second engage latch that
// was one cause. It cannot be the whole story: the same logs show `acf` sitting at 0.0–0.3
// for most samples and essentially never reaching `strongAutoFloor`, so
// `pulseTrustworthy`'s SECOND evidence term is the binding one — a signal-quality fact, not
// a gating one. But "most samples" is a hand count over 2 s snapshots, and #566 is exactly
// what happens when a threshold is moved on that kind of evidence.
//
// ⚠️ THIS TYPE CHANGES NO BEHAVIOUR AND IS NOT ALLOWED TO. It counts what the publish gate
// already decided and formats one breadcrumb line. It exists so the NEXT device log answers
// "how often did the gate open, and which clause held it shut" as a measurement instead of
// an inference — the same discipline #567 applied to the breath gate, for the same reason
// written in the founder's C3 note: "changing a threshold blind is how the 2026-08-12
// confusion happened".
//
// ⚠️ AND THE bpm SPREAD IS AN OBSERVATION, NOT A CANDIDATE TERM THAT IS BEING SNUCK IN.
// A third witness — "the estimate is FLAT, whatever the periodicity score says" — is the
// obvious thing to reach for once `acf` is known to be the binding clause. It is reported
// as a raw spread with NO threshold precisely so that reaching for it costs a decision:
// there is no number here for a later cycle to quietly promote into the trust rule. Whether
// a flat estimate is trustworthy is a question the founder's log answers, not this file.

import Foundation

/// Why one publish attempt did or did not reach the bus. Mutually exclusive and exhaustive.
///
/// ⛔ DO NOT re-derive `published` from the thresholds here. `CameraRPPGBioPublisher
/// .trustVerdict` asks `shouldPublish` FIRST and only classifies the failures itself, so this
/// enum cannot drift from the shipped gate — a second spelling of the rule is the #416 defect
/// and this is the file where it would be most invisible.
public enum PulseTrustVerdict: String, Sendable, CaseIterable {
    /// The gate opened; a live frame went to the bus.
    case published = "ok"
    /// No estimate at all (`bpm <= 0`) — the analyzer has nothing, so neither clause applies.
    case noEstimate = "nobpm"
    /// Confidence AND periodicity both under their floors. The honest "no signal" case.
    case bothLow = "both"
    /// Periodicity cleared `trustAutoFloor` but confidence did not, and periodicity also fell
    /// short of the strong-only clause. The peak counter is unsure about a periodic trace.
    case confidenceLow = "conf"
    /// Confidence cleared `displayThreshold` but periodicity did not. THIS is the one the
    /// device logs point at: the readout looks convinced, the second witness never arrives.
    case periodicityLow = "acf"
}

/// A fixed-size window of publish-gate decisions, reduced to one line.
///
/// Pure value type, no clock, no I/O — the caller owns both. Deliberately the same shape as
/// `BioTrustLatch`: the publisher holds it, feeds it, and asks it when to speak.
public struct TrustWindowTally: Sendable, Equatable {

    /// How many publish attempts one line summarises. The publish gate runs at ~1 Hz, so this
    /// is ~30 s per line — the breath line's 5 s cadence would be six times noisier in a file
    /// the founder also reads for launch and crash triage.
    ///
    /// ⚠️ Pinned by its guard as a FLOOR (≥ 1) and by the fact that the line PRINTS it, never
    /// as the literal 30 (#364): a later cycle that wants finer resolution during a specific
    /// hunt must stay able to change it without turning a gate red.
    public static let windowAttempts = 30

    public private(set) var attempts = 0
    public private(set) var published = 0
    public private(set) var noEstimate = 0
    public private(set) var bothLow = 0
    public private(set) var confidenceLow = 0
    public private(set) var periodicityLow = 0

    /// Best evidence SEEN in this window, whether or not it was seen at the same instant.
    /// Two separate maxima on purpose: `maxConfidence` high with `maxPeriodicity` low over a
    /// whole window is the exact shape that says the second witness — not the first — is what
    /// keeps the body off the bus, and it says so even if the two never peak together.
    public private(set) var maxConfidence = 0.0
    public private(set) var maxPeriodicity = 0.0

    /// Extremes of the ESTIMATE across the window, over attempts with a usable `bpm` only.
    /// Optional rather than NaN-seeded: a window with no estimate at all must be
    /// distinguishable from one whose estimate never moved.
    public private(set) var bpmLow: Double?
    public private(set) var bpmHigh: Double?

    public init() {}

    /// True once the window holds a full line's worth of decisions.
    public var isComplete: Bool { attempts >= Self.windowAttempts }

    /// How far the estimate travelled across the window, or nil when fewer than one usable
    /// estimate was seen. NOT compared against anything here — see the file header.
    public var bpmSpread: Double? {
        guard let low = bpmLow, let high = bpmHigh else { return nil }
        return high - low
    }

    /// Record one decision of the publish gate.
    ///
    /// `bpm`, `confidence` and `autoStrength` are the values the gate itself was given, passed
    /// in rather than re-read: `manageExposure()` can flush the analyzer between reads, and the
    /// publisher's call site already documents at length why all three evidence values must be
    /// the SAME snapshot the verdict was computed from.
    public mutating func note(verdict: PulseTrustVerdict,
                              bpm: Double,
                              confidence: Double,
                              autoStrength: Double) {
        attempts += 1
        switch verdict {
        case .published:      published += 1
        case .noEstimate:     noEstimate += 1
        case .bothLow:        bothLow += 1
        case .confidenceLow:  confidenceLow += 1
        case .periodicityLow: periodicityLow += 1
        }
        // Accumulator FIRST in both `max` calls. `max(x, y)` is `y >= x ? y : x`, so a NaN
        // second argument compares false and the accumulator survives; the other order would
        // let one non-finite sample pin the maximum at NaN for the rest of the window. This
        // is the repo's documented NaN-safety rule, applied where a bio value enters.
        maxConfidence = Swift.max(maxConfidence, confidence)
        maxPeriodicity = Swift.max(maxPeriodicity, autoStrength)
        guard bpm.isFinite, bpm > 0 else { return }
        bpmLow = bpmLow.map { Swift.min($0, bpm) } ?? bpm
        bpmHigh = bpmHigh.map { Swift.max($0, bpm) } ?? bpm
    }

    /// The breadcrumb body (the caller adds the `trust: ` prefix).
    ///
    /// Counts come first because they are the question; the maxima and the spread are the
    /// context that says WHY the counts look the way they do. Zero-attempt windows are
    /// representable and print honestly rather than dividing by zero.
    /// ⚠️ The labels come from `PulseTrustVerdict.rawValue`, never from literals spelled again
    /// here (#416) — and the parts are built through an explicitly typed array rather than a
    /// six-term `+` chain, because #287 turned the blocking gate red on exactly that shape.
    public var summary: String {
        let spreadText = bpmSpread.map { String(format: "%.1f", $0) } ?? "—"
        let confText = String(format: "%.2f", maxConfidence)
        let acfText = String(format: "%.2f", maxPeriodicity)
        let parts: [(PulseTrustVerdict, Int)] = [
            (.noEstimate, noEstimate),
            (.confidenceLow, confidenceLow),
            (.periodicityLow, periodicityLow),
            (.bothLow, bothLow)
        ]
        let blocks = parts.map { "\($0.0.rawValue)=\($0.1)" }.joined(separator: " ")
        let head = "\(published)/\(attempts) ok"
        let tail = "maxConf=\(confText) maxAcf=\(acfText) bpmSpread=\(spreadText)"
        return "\(head) · \(blocks) · \(tail)"
    }
}
