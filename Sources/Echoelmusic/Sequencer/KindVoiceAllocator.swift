// KindVoiceAllocator.swift
// Echoel — S2-W2-1 (dissolution, "Spur = Instrument", plan
// scratchpads/PLAN_S2W2_VOICEKIND_ROUTING.md §2/§3): the PURE decision layer
// that binds a Multi-Roll rank slot + its lane's voice KIND to a PHYSICAL voice
// in the heterogeneous rack pool.
//
// Rank slots stay the authoritative contract everywhere (LaneVoicePool /
// LaneVoiceRackPlan / MultiRollFanout / all player sinks / the AU host) — the
// ONLY change of meaning happens at the rack boundary, where LaneVoiceRack
// (S2-W2-3) will consult this allocator to route a slot's notes/params to:
//   .poly(rank)   — the existing 4 PolySynthVoice slots (index == rank, so the
//                   established voice(slot:) addressing is unchanged for poly)
//   (⛔ `.drums(i)` — a LaneDrumKitVoice unit — is GONE. The founder removed the drums
//    2026-07-26 ("keine Drums") and the apparatus 2026-07-27 ("erstmal gar nicht mehr rein",
//    #167). `LaneVoiceKind.drums` still exists and falls through to `.poly` like any other
//    kind with no unit, which is what it already did in Release once `attachAll` stopped
//    creating kits.
//    ⚠️ "because it is a persisted rawValue and dropping it would make an old lane fail to
//    decode" stood here and is FALSE — `LaneVoiceKind` is not `Codable` and never reaches
//    disk. See the case's own comment in `LaneVoiceKind.swift`: it is a DEAD case pending a
//    decision, and this fallback arm is belt-and-braces, not a decode guarantee.)
//   .subBass(i)   — a dedicated lane SubBassVoice (NOT the primary doubling sub)
//   .sampler(i)   — a lane SamplerVoice one-shot unit (S2-W3, "EchoelSampler klingt")
//   .bio(i)       — a lane BioReactiveSynthVoice unit (BodyVibe B1 — the last
//                   v1 deferral falls; plan PLAN_BODYVIBE_TRACK_PANEL §B)
//
// Laws (tested): deterministic (no Date/UUID/random), first-RANK-wins on
// contention (input order irrelevant), poly fallback on kind exhaustion,
// zero units ⇒ all-poly (the flag-OFF shape, bit-identical to today).
// Foundation-only, no engine, no state.

import Foundation

/// A physical voice in the heterogeneous rack pool (S2-W2). The associated index
/// addresses the unit within its kind: `.poly(rank)` keeps rank == index so the
/// existing PolySynthVoice slot array needs no re-mapping.
/// ⛔ `.drums(Int)` was a case here and is GONE with #167. It is safe to delete where
/// `LaneVoiceKind.drums` is not: this enum is an allocation RESULT, computed fresh on every
/// rebind and never encoded — nothing on disk names it.
public enum PhysicalVoiceRef: Equatable, Sendable, Hashable {
    case poly(Int)
    case subBass(Int)
    case sampler(Int)
    case bio(Int)
}

/// Pure slot→physical-voice allocation for the Multi-Roll rack facade.
public enum KindVoiceAllocator {

    /// Bind each rank slot to a physical voice by its lane's voice kind.
    ///
    /// - Parameters:
    ///   - ordered: the (rank slot, kind) pairs to bind. Order does NOT matter —
    ///     contention is resolved by ascending RANK (first rank wins); a
    ///     duplicate slot keeps its first (lowest-position after sort) binding.
    ///   - subUnits: how many dedicated lane sub-bass units exist (dito).
    ///   - samplerUnits: how many lane sampler one-shot units exist (dito; the
    ///     sample FILE a bound unit plays comes from the lane's `samplePath`,
    ///     outside this pure layer).
    ///   - bioUnits: how many lane BioReactiveSynthVoice units exist (BodyVibe
    ///     B1; dito — 0 keeps the former deferral shape: bio lanes fall back to
    ///     poly). Defaults to 0 so every pre-B1 call site is unchanged.
    /// - Returns: slot → physical voice. A slot NEVER maps to silence: any kind
    ///   that cannot get its dedicated voice resolves to `.poly(slot)` — exactly
    ///   today's sound, so routing can only get MORE honest, never quieter.
    public static func allocate(ordered: [(slot: Int, kind: LaneVoiceKind)],
                                subUnits: Int,
                                samplerUnits: Int,
                                bioUnits: Int = 0) -> [Int: PhysicalVoiceRef] {
        var out: [Int: PhysicalVoiceRef] = [:]
        var nextSub = 0
        var nextSampler = 0
        var nextBio = 0
        for entry in ordered.sorted(by: { $0.slot < $1.slot }) {
            guard out[entry.slot] == nil else { continue }   // duplicate slot: first wins
            switch entry.kind {
            case .subBass where nextSub < subUnits:
                out[entry.slot] = .subBass(nextSub)
                nextSub += 1
            case .sampler where nextSampler < samplerUnits:
                out[entry.slot] = .sampler(nextSampler)
                nextSampler += 1
            case .bioVoice where nextBio < bioUnits:
                out[entry.slot] = .bio(nextBio)
                nextBio += 1
            case .poly, .drums, .subBass, .sampler, .bioVoice:
                // Poly by choice or by exhaustion (kind units taken by a lower
                // rank). Never silence. `.drums` now ALWAYS lands here — see the
                // header: the kind outlives its voice on purpose.
                out[entry.slot] = .poly(entry.slot)
            }
        }
        return out
    }
}
