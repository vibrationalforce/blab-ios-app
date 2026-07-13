// AUParameterBridge.swift
// Echoel — AUv3-structure block U2b. The bridge that makes a hosted plugin's
// parameters first-class Echoel parameters: it registers each into the
// EchoelParameterRegistry (queryable, same ParameterDescriptor shape as an
// internal DDSP param) AND binds each to a live setter through the
// ParameterApplyRouter — so an external plugin's knobs become automatable in the
// track exactly like Echoel's own (the Council's parameter-unification, the
// founder's "in den Spuren", without an engine rewrite).
//
// This file is the FOUNDATION-ONLY, CI-tested core: register + bind + unbind
// over an already-extracted `[AUParamMeta]`. The AVFoundation extraction
// (reading an `AUParameter`/`AUParameterTree` off a loaded `AUAudioUnit` and the
// KVO re-enumeration on tree replace) is the thin U2c layer that calls
// `install`/`uninstall` — no logic there but extraction. Control-plane only
// (@MainActor); the bound setter writes the plugin's own value, never the audio
// render path.

import Foundation

@MainActor
public enum AUParameterBridge {

    /// Register a hosted plugin's parameters into `registry` and bind each to a
    /// live setter, returning the keyPaths bound (hand these to `uninstall` on
    /// unload). `setterFor(address)` yields the setter for one parameter — the
    /// U2c layer returns `{ real in auParameter.value = AUValue(real) }`. The
    /// router feeds it the REAL (denormalized) value, so the plugin gets its own
    /// units. Re-installing the same keyPaths rebinds in place (a plugin may
    /// replace its parameterTree) — newest setter wins, registry keeps position.
    @discardableResult
    public static func install(metas: [AUParamMeta],
                               manufacturer: UInt32, subType: UInt32,
                               into registry: EchoelParameterRegistry,
                               router: ParameterApplyRouter,
                               setterFor: (UInt64) -> (Float) -> Void) -> [String] {
        let descriptors = AUParameterMapping.descriptors(
            manufacturer: manufacturer, subType: subType, params: metas)
        registry.register(descriptors)
        var keyPaths: [String] = []
        keyPaths.reserveCapacity(metas.count)
        for meta in metas {
            let kp = AUParameterMapping.keyPath(
                manufacturer: manufacturer, subType: subType, address: meta.address)
            router.bind(kp, setterFor(meta.address))
            keyPaths.append(kp)
        }
        return keyPaths
    }

    /// Unbind a plugin's parameters on unload. The registry has no removal API,
    /// so descriptors linger — but unbound they drop out of
    /// `automatableDescriptors()` (placebo law) and `applyNormalized` is a safe
    /// no-op, so nothing offers or moves a parameter of a plugin that is gone.
    public static func uninstall(keyPaths: [String], router: ParameterApplyRouter) {
        for kp in keyPaths { router.unbind(kp) }
    }
}
