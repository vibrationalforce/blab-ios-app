// EchoelFDNReverb+RoomModel.swift
// Echoel — the Core-side bridge from the Spatial `RoomModel` to the DSP `EchoelFDNReverb`
// core. It lives in Core/ (NOT in the DSP-only AUv3 target's source globs) precisely so the
// DSP core stays self-contained and dependency-free of the Core Spatial types — the AUv3
// target compiles `DSP/EchoelFDNReverb.swift` alone, without `RoomModel`. This file gives
// the main app + tests the ergonomic "reverb driven by a RoomModel" API.

#if canImport(Accelerate)
import Foundation

public extension EchoelFDNReverb {

    /// Build a reverb from a `RoomModel` (its clamped dimensions/decay/diffusion feed the
    /// primitive designated init).
    convenience init(room: RoomModel, sampleRate: Float = 48_000, maxBlock: Int = 2048,
                     mix: Float = 0.25, seed: UInt64 = 0xFD2) {
        self.init(width: room.width, depth: room.depth, height: room.height,
                  decayTime: room.decayTime, diffusion: room.diffusion,
                  sampleRate: sampleRate, maxBlock: maxBlock, mix: mix, seed: seed)
    }

    /// Derive FDN Params directly from a `RoomModel`.
    static func params(from room: RoomModel, sampleRate: Float, seed: UInt64 = 0xFD2) -> Params {
        params(width: room.width, depth: room.depth, height: room.height,
               decayTime: room.decayTime, sampleRate: sampleRate, seed: seed)
    }

    /// Recompute lengths/gains for a new `RoomModel` (control-rate).
    func setRoom(_ room: RoomModel, sampleRate: Float? = nil) {
        setRoom(width: room.width, depth: room.depth, height: room.height,
                decayTime: room.decayTime, diffusion: room.diffusion, sampleRate: sampleRate)
    }
}
#endif
