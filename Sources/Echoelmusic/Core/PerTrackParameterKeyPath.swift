// PerTrackParameterKeyPath.swift
// Automation-in-Spur L2/L4 spine (per-track targeting). Today automation
// keyPaths are engine-GLOBAL ("ddsp.filter.cutoff"), so two tracks that pick
// the same parameter edit the SAME curve. That honesty debt used to be documented in
// another file and is written out HERE now, because the file it lived in is gone:
//
//     DATA MODEL (honest): timeline automation lives in `TimelineDocument.automation`
//     — parameter-keyed, DOCUMENT-wide, song-absolute. GLOBAL targets (master level,
//     tempo, router-bound registry params) are one curve shared across tracks BY
//     DESIGN. L2/L4: a SECONDARY lane may additionally carry a PER-TRACK target — the
//     rack-voice params namespaced as `track.<laneID>.<base>` — so a curve drawn for
//     that track moves only that track's voice (the shared-curve debt is resolved
//     where it matters). Per-track targets exist only for lanes that own a rack slot;
//     never the roll lane, never a global-only param.
//
// ⛔ TWO CITATIONS DIED HERE, IN THE TWO DIFFERENT WAYS THIS REPO KEEPS PAYING FOR.
// First it read "TimelineAutomationRow:11-16" — a LINE RANGE, the most brittle fact
// this repo writes down; #472 moved that file's contents and the range was wrong the
// same day. It was replaced by a quoted PHRASE (`DATA MODEL (honest):`), which does
// survive an insertion — and then #473 deleted the whole file, which no phrasing
// survives. So the block is INLINED rather than cited a third time. The rule the two
// failures share: a pointer is only as durable as the thing it points at, and prose
// about THIS file's contract belongs in THIS file.
// ⚠️ One sentence was rewritten rather than copied. The original ended "The picker
// offers per-track targets only for lanes that own a rack slot" — that picker was in
// the deleted view. There is no picker today; the NAMESPACE is what exists, and the
// restriction is a property of the namespace, not of a UI that no longer ships.
//
// This pure namespace makes a parameter
// addressable PER TRACK by folding the lane's UUID into the keyPath:
//
//     "track.<laneID>.ddsp.filter.cutoff"
//
// The string-keyed router (ParameterApplyRouter) can then bind a lane-
// resolving closure per namespaced keyPath, and AutomationPlayer.dispatchLane
// already routes unknown keyPaths straight through — so NO player/model change
// is needed to carry a per-track curve. This file is the pure fold/parse/
// descriptor-build seam only (S1): Foundation-only, no coupling, and nothing
// consumes these keyPaths until the wiring slice (S2) binds them, so the global
// automation path stays byte-identical (golden-gate).
//
// The UUID string carries no '.', so the first '.' after the prefix cleanly
// ends the id even though the base keyPath itself contains dots.

import Foundation

public enum PerTrackParameterKeyPath {

    /// Namespace prefix. A keyPath beginning with this addresses one track.
    public static let prefix = "track."

    /// Fold a lane id + a base engine keyPath into a per-track keyPath.
    /// `make(<laneID>, "ddsp.filter.cutoff") -> "track.<uuid>.ddsp.filter.cutoff"`.
    public static func make(laneID: UUID, base: String) -> String {
        "\(prefix)\(laneID.uuidString).\(base)"
    }

    /// Parse a per-track keyPath back into (laneID, base). Returns nil for a
    /// GLOBAL keyPath (no `track.` prefix) or a malformed one (bad UUID / empty
    /// base) — callers treat nil as "not per-track, route globally".
    public static func parse(_ keyPath: String) -> (laneID: UUID, base: String)? {
        guard keyPath.hasPrefix(prefix) else { return nil }
        let afterPrefix = keyPath.dropFirst(prefix.count)
        // The UUID string contains no '.', so the first '.' ends the id.
        guard let dot = afterPrefix.firstIndex(of: ".") else { return nil }
        let idPart = String(afterPrefix[afterPrefix.startIndex..<dot])
        guard let id = UUID(uuidString: idPart) else { return nil }
        let base = String(afterPrefix[afterPrefix.index(after: dot)...])
        guard !base.isEmpty else { return nil }
        return (id, base)
    }

    /// True iff this keyPath is a well-formed per-track keyPath.
    public static func isPerTrack(_ keyPath: String) -> Bool {
        parse(keyPath) != nil
    }

    /// Clone global descriptors into per-track descriptors for ONE lane:
    /// keyPath namespaced, displayName prefixed with a short lane tag so the
    /// target picker distinguishes "Filter cutoff" on track A vs track B.
    /// Ranges / units / defaults / labels are inherited verbatim — it is the
    /// SAME engine parameter, only addressed per track.
    public static func descriptors(for laneID: UUID,
                                   laneLabel: String,
                                   from base: [ParameterDescriptor]) -> [ParameterDescriptor] {
        base.map { d in
            ParameterDescriptor(
                keyPath: make(laneID: laneID, base: d.keyPath),
                displayName: laneLabel.isEmpty ? d.displayName : "\(laneLabel) · \(d.displayName)",
                min: d.min, max: d.max, defaultValue: d.defaultValue,
                unit: d.unit, valueLabels: d.valueLabels)
        }
    }
}
