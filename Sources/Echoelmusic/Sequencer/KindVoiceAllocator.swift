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
//   .drums(i)     — a LaneDrumKitVoice unit (S2-W2-2)
//   .subBass(i)   — a dedicated lane SubBassVoice (NOT the primary doubling sub)
//   .sampler(i)   — a lane SamplerVoice one-shot unit (S2-W3, "EchoelSampler klingt")
//
// Laws (tested): deterministic (no Date/UUID/random), first-RANK-wins on
// contention (input order irrelevant), poly fallback on kind exhaustion or for
// the v1-deferred kind (bioVoice — plan §6), zero units ⇒ all-poly (the
// flag-OFF shape, bit-identical to today). Foundation-only, no engine, no state.

import Foundation

/// A physical voice in the heterogeneous rack pool (S2-W2). The associated index
/// addresses the unit within its kind: `.poly(rank)` keeps rank == index so the
/// existing PolySynthVoice slot array needs no re-mapping.
public enum PhysicalVoiceRef: Equatable, Sendable, Hashable {
    case poly(Int)
    case drums(Int)
    case subBass(Int)
    case sampler(Int)
}

/// Pure slot→physical-voice allocation for the Multi-Roll rack facade.
public enum KindVoiceAllocator {

    /// Bind each rank slot to a physical voice by its lane's voice kind.
    ///
    /// - Parameters:
    ///   - ordered: the (rank slot, kind) pairs to bind. Order does NOT matter —
    ///     contention is resolved by ascending RANK (first rank wins); a
    ///     duplicate slot keeps its first (lowest-position after sort) binding.
    ///   - drumUnits: how many physical drum-kit units exist (0 = none → drums
    ///     lanes fall back to poly; the flag-OFF shape).
    ///   - subUnits: how many dedicated lane sub-bass units exist (dito).
    ///   - samplerUnits: how many lane sampler one-shot units exist (dito; the
    ///     sample FILE a bound unit plays comes from the lane's `samplePath`,
    ///     outside this pure layer).
    /// - Returns: slot → physical voice. A slot NEVER maps to silence: any kind
    ///   that cannot get its dedicated voice resolves to `.poly(slot)` — exactly
    ///   today's sound, so routing can only get MORE honest, never quieter.
    public static func allocate(ordered: [(slot: Int, kind: LaneVoiceKind)],
                                drumUnits: Int, subUnits: Int,
                                samplerUnits: Int) -> [Int: PhysicalVoiceRef] {
        var out: [Int: PhysicalVoiceRef] = [:]
        var nextDrum = 0
        var nextSub = 0
        var nextSampler = 0
        for entry in ordered.sorted(by: { $0.slot < $1.slot }) {
            guard out[entry.slot] == nil else { continue }   // duplicate slot: first wins
            switch entry.kind {
            case .drums where nextDrum < drumUnits:
                out[entry.slot] = .drums(nextDrum)
                nextDrum += 1
            case .subBass where nextSub < subUnits:
                out[entry.slot] = .subBass(nextSub)
                nextSub += 1
            case .sampler where nextSampler < samplerUnits:
                out[entry.slot] = .sampler(nextSampler)
                nextSampler += 1
            case .poly, .drums, .subBass, .sampler, .bioVoice:
                // Poly by choice, by exhaustion (kind units taken by a lower
                // rank), or by v1 deferral (bioVoice is hold-for-founder —
                // plan §6). Never silence.
                out[entry.slot] = .poly(entry.slot)
            }
        }
        return out
    }
}
