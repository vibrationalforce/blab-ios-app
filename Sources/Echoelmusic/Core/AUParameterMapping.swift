// AUParameterMapping.swift
// Echoel — AUv3-structure block U1. The PURE bridge shape: a hosted Audio Unit's
// parameter metadata → an EchoelParameterRegistry descriptor, so an external
// plugin's knobs become the SAME ParameterDescriptor as an internal DDSP param.
// That single shape is what makes per-track automation identical for internal
// and external parameters (the founder's "in den Spuren", the Council's
// parameter-unification instead of an engine rewrite).
//
// Foundation-only + side-effect-free so CI verifies every rule without a real
// AudioUnit. The LIVE side (U2) reads an `AUParameter`/`AUParameterTree` off a
// loaded `AUAudioUnit` via KVO and calls THESE functions — no logic there but
// extraction. Control-plane only; never reached from a render block.
//
// Identity law: a hosted param's keyPath is "au.<mfr>.<sub>.<address>" — the
// manufacturer + subtype FourCC identify the plugin, the AUParameterAddress
// identifies the knob. Stable across launches as long as the plugin keeps its
// addresses (the AU contract); survives the plugin replacing its parameterTree.

import Foundation

public enum AUParameterMapping {

    /// Decode a FourCC OSType (e.g. an AudioComponentDescription manufacturer or
    /// subtype) to a 4-character token, sanitized so it is always dot-safe and
    /// keyPath-legal: any non-alphanumeric byte (space, control, punctuation, or
    /// a zero code) becomes '_'. Always exactly 4 characters.
    public static func fourCC(_ code: UInt32) -> String {
        let bytes = [UInt8(truncatingIfNeeded: code >> 24),
                     UInt8(truncatingIfNeeded: code >> 16),
                     UInt8(truncatingIfNeeded: code >> 8),
                     UInt8(truncatingIfNeeded: code)]
        let chars = bytes.map { b -> Character in
            let c = Character(UnicodeScalar(b))
            return (c.isASCII && (c.isLetter || c.isNumber)) ? c : "_"
        }
        return String(chars)
    }

    /// The stable registry keyPath for a hosted AU parameter:
    /// "au.<mfrFourCC>.<subFourCC>.<address>".
    public static func keyPath(manufacturer: UInt32, subType: UInt32,
                               address: UInt64) -> String {
        "au.\(fourCC(manufacturer)).\(fourCC(subType)).\(address)"
    }

    /// Map a hosted AU parameter's metadata into a `ParameterDescriptor`. Ranges
    /// come straight from the AU (honest — the plugin's own clamps apply at the
    /// write site). Guards so downstream normalize/denormalize can never divide
    /// by zero or emit NaN: a degenerate `min == max` range is widened by 1, and
    /// the default is clamped into the (widened) range. `valueStrings` (for
    /// stepped/enum params) become `valueLabels`; an empty display name falls
    /// back to the keyPath so the UI always shows something.
    public static func descriptor(manufacturer: UInt32, subType: UInt32,
                                  address: UInt64, displayName: String,
                                  minValue: Float, maxValue: Float, defaultValue: Float,
                                  unit: String, valueStrings: [String]?) -> ParameterDescriptor {
        let kp = keyPath(manufacturer: manufacturer, subType: subType, address: address)
        // Preserve the AU's ascending range; widen only the degenerate equal case
        // so `normalized` (which guards max > min) still yields a usable 0…1.
        let rMin = minValue
        let rMax = maxValue > minValue ? maxValue : minValue + 1
        let def = Swift.min(rMax, Swift.max(rMin, defaultValue))
        return ParameterDescriptor(
            keyPath: kp,
            displayName: displayName.isEmpty ? kp : displayName,
            min: rMin, max: rMax, defaultValue: def,
            unit: unit,
            valueLabels: (valueStrings?.isEmpty ?? true) ? nil : valueStrings)
    }
}
