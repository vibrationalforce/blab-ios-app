// LossyDecoded.swift
// Echoel — the ONE element-tolerant array decode, shared.
//
// THE BUG CLASS IT EXISTS FOR (the "library wipe"). `Codable`'s array decode is
// all-or-nothing: ONE element the field-level `decodeIfPresent` guards cannot absorb
// (a renamed enum case, a wrong-typed value, a field added without a default, a
// half-written file) throws, the surrounding `try?` turns that into nil, the store
// falls back to EMPTY — and the next save writes that empty array back over the file.
// A single bad element therefore destroys the user's ENTIRE library, permanently.
// Wrapping each element so a bad one becomes a hole turns total loss into bounded loss.
//
// Pure Foundation, no I/O — callers own where the bytes come from.

import Foundation

/// Decodes `T`, or yields `nil` for a malformed element — ALWAYS consuming exactly one
/// array slot, which is what keeps the surrounding unkeyed decode from stalling.
public struct LossyDecoded<T: Decodable>: Decodable {
    public let value: T?
    public init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Decode a top-level JSON array ELEMENT-tolerantly.
///
/// Returns `nil` only when `data` is not a JSON array at all — i.e. exactly the case where
/// "nothing usable is saved" is the truth, so a caller's `?? []` is not masking a real
/// failure. A present-but-partly-corrupt array comes back WITH HOLES.
///
/// CALLERS MUST DECIDE WHAT A HOLE MEANS, and the two answers are not interchangeable:
/// - unordered LIBRARY (patches, presets, routes) → drop it with `.compactMap { $0 }`;
/// - POSITIONAL grid (`ClipStore`'s 8 slots, where the index IS the slot) → KEEP the
///   `nil` in place. Compacting there would shift every later element into the wrong
///   cell and fail the count check, turning one corrupt entry into all eight lost.
///
/// `label` names the source in the telemetry line (e.g. `"AppGroupStore: clips.json"`).
/// It is `@autoclosure` so building the string costs nothing on the overwhelmingly
/// common clean read.
public func decodeLossyArray<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    label: @autoclosure () -> String
) -> [T?]? {
    let wrapped: [LossyDecoded<T>]
    do {
        wrapped = try JSONDecoder().decode([LossyDecoded<T>].self, from: data)
    } catch {
        // NOT an array at all — the caller's "nothing usable is saved" branch. Logged WITH
        // the underlying error, because the reason ("expected Array, found Dictionary" vs
        // "unexpected end of file") is what tells a maintainer whether this is a schema
        // change or a truncated write. Swallowing it would leave total loss undiagnosable.
        log.log(.error, category: .system,
                "\(label()) — not a decodable [\(T.self)] array, nothing recovered: \(error)")
        return nil
    }
    let values = wrapped.map(\.value)
    // TELEMETRY — do not remove. Dropping elements is still permanent data loss (the next
    // save re-encodes only the survivors and the bad bytes are gone), it is just BOUNDED
    // loss. Without this line the partly-corrupt case would be the one SILENT failure,
    // which is worse than the all-or-nothing behaviour it replaced: that at least logged
    // when it lost everything. Logged once per read, never per element.
    let dropped = values.filter { $0 == nil }.count
    if dropped > 0 {
        log.log(.error, category: .system,
                "\(label()) — dropped \(dropped)/\(values.count) undecodable \(T.self) element(s)")
    }
    return values
}

// HONEST SCOPE — four private copies of this wrapper predate this file and are still in
// place: `Timeline.Lossy`, `ModulationMatrix.LossyRoute`, `AutomationLane.LossyPoint`, and
// (until it delegated here) `AppGroupStore.Lossy`. They are behaviourally identical; each
// sits inside a custom `init(from:)` that decodes a KEYED container, not a top-level array,
// so they cannot call the function above without restructuring their decoders. Collapsing
// them is cosmetic, touches four persisted-decode paths at once, and buys the user nothing
// — deliberately not done here. Do not read this file as "every array decode is tolerant".
