// ParameterApplyRouter.swift
// Echoel — Automation-in-track cycle 1. The one missing wire between the
// EchoelParameterRegistry catalog ("what can be automated") and the live engine
// ("what actually moves audio"): a keyPath → live-setter dispatch table. This is
// the concrete body of the `apply:` closure that ParameterToolCore.set() and the
// automation playback path have always taken as an injected hole.
//
// Identity: a lane/tool targets a parameter purely by its registry keyPath
// ("modul.sektion.parameter"); the descriptor supplies the range so a normalized
// 0…1 automation value maps to the real value at the write site.
//
// Audio-thread law: this is @MainActor CONTROL-PLANE code. It is fed at the
// transport step rate (≤16/bar), never from a render/DSP block. Each bound setter
// is expected to write the voice's own `nonisolated(unsafe)` atomic-Float mirror
// (e.g. EchoelDDSP.setCutoffScale, AudioEngine.masterVolume, PatternEngine.setTempo)
// which the render thread reads lock-free — so no lock/alloc/ObjC ever reaches audio.
// It lives in Core/ (never DSP/) so the AUv3 target, which compiles DSP/ in
// isolation, never sees it.
//
// Placebo law: the picker offers ONLY keyPaths that are actually bound to a live
// setter (`automatableDescriptors()`), so a user can never author a lane that moves
// nothing. Binding happens at app wiring time (later cycle); this type is pure.

import Foundation

/// Routes a parameter keyPath to the live engine setter bound for it. Pure,
/// control-plane, deterministic — no clock, no RNG, no audio-thread reach.
@MainActor
public final class ParameterApplyRouter {

    private let registry: EchoelParameterRegistry
    /// keyPath → live setter (takes the REAL, already-in-range value).
    private var setters: [String: (Float) -> Void] = [:]

    public init(registry: EchoelParameterRegistry) {
        self.registry = registry
    }

    /// Bind (or replace) the live setter for a keyPath. Called at app wiring time,
    /// e.g. `router.bind("ddsp.filter.cutoff") { voice.setCutoffScale($0) }`.
    public func bind(_ keyPath: String, _ setter: @escaping (Float) -> Void) {
        setters[keyPath] = setter
    }

    /// Apply a NORMALIZED 0…1 value (the automation-lane / tool value): denormalize
    /// through the registry descriptor, then dispatch the real value to the bound
    /// setter. Returns the applied real value, or nil (a safe no-op) when there is no
    /// descriptor to map the value or no setter bound — never a crash.
    @discardableResult
    public func applyNormalized(_ keyPath: String, _ normalized: Float) -> Float? {
        guard let descriptor = registry.descriptor(for: keyPath),
              let setter = setters[keyPath] else { return nil }
        let real = descriptor.denormalized(normalized)
        setter(real)
        return real
    }

    /// Apply a REAL value directly (already in the parameter's units/range) — used
    /// where the caller has computed the real value itself. Returns whether a setter
    /// was bound to receive it.
    @discardableResult
    public func applyReal(_ keyPath: String, _ real: Float) -> Bool {
        guard let setter = setters[keyPath] else { return false }
        setter(real)
        return true
    }

    /// Whether a live setter is bound for this keyPath.
    public func isBound(_ keyPath: String) -> Bool { setters[keyPath] != nil }

    /// Every keyPath that currently has a live setter.
    public var boundKeyPaths: Set<String> { Set(setters.keys) }

    /// The registry descriptors that are ALSO bound to a live setter — i.e. the
    /// parameters a UI may safely offer for automation (no dead lanes). Registry
    /// insertion order is preserved so the picker stays stable.
    public func automatableDescriptors() -> [ParameterDescriptor] {
        registry.all().filter { isBound($0.keyPath) }
    }
}
