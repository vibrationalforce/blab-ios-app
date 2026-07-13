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

/// The pure, testable slice of a hosted AU parameter's metadata — exactly what
/// the live bridge (U2b) reads off an `AUParameter` before mapping. A value type
/// so the whole tree→descriptors mapping is unit-tested without AVFoundation.
public struct AUParamMeta: Sendable, Equatable {
    public var address: UInt64
    public var displayName: String
    public var minValue: Float
    public var maxValue: Float
    public var defaultValue: Float
    public var unit: String
    public var valueStrings: [String]?

    public init(address: UInt64, displayName: String,
                minValue: Float, maxValue: Float, defaultValue: Float,
                unit: String = "", valueStrings: [String]? = nil) {
        self.address = address
        self.displayName = displayName
        self.minValue = minValue
        self.maxValue = maxValue
        self.defaultValue = defaultValue
        self.unit = unit
        self.valueStrings = valueStrings
    }
}

public enum AUParameterMapping {

    /// Decode a FourCC OSType (e.g. an AudioComponentDescription manufacturer or
    /// subtype) to a 4-character token, sanitized so it is always dot-safe and
    /// keyPath-legal: any non-alphanumeric byte (space, control, punctuation, or
    /// a zero code) becomes '_'. Always exactly 4 characters.
    ///
    /// Uniqueness note: the sanitization is lossy — two OSTypes differing ONLY in
    /// non-alphanumeric bytes collide to the same token. Real
    /// AudioComponentDescription codes are 4 printable-alphanumeric ASCII chars by
    /// Apple convention, so this is not triggerable with a conforming AU; the
    /// keyPath is treated as stable-and-unique on that assumption (the leaf
    /// address disambiguates params WITHIN a plugin regardless).
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
    /// by zero or emit NaN: a degenerate `min == max` range is widened to a
    /// strictly-greater max, and the default is clamped into the (widened) range.
    /// `valueStrings` (for stepped/enum params) become `valueLabels`; an empty
    /// display name falls back to the keyPath so the UI always shows something.
    public static func descriptor(manufacturer: UInt32, subType: UInt32,
                                  address: UInt64, displayName: String,
                                  minValue: Float, maxValue: Float, defaultValue: Float,
                                  unit: String, valueStrings: [String]?) -> ParameterDescriptor {
        let kp = keyPath(manufacturer: manufacturer, subType: subType, address: address)
        // Preserve the AU's ascending range; widen only the degenerate equal case
        // so `normalized` (which guards max > min) still yields a usable 0…1.
        // The widen must survive Float32 precision: a flat `min + 1` no-ops above
        // 2^24 (ULP > 1), so scale the bump to the magnitude — `max(1, |min|·1e-3)`
        // stays > 0 ULPs across the whole Float range while keeping the common
        // min==0 case a clean 0…1. `nextUp` fallback covers the extreme where even
        // that rounds away (near .greatestFiniteMagnitude).
        let rMin = minValue
        let rMax: Float
        if maxValue > minValue {
            rMax = maxValue
        } else {
            let widened = minValue + Swift.max(1, abs(minValue) * 1e-3)
            rMax = widened > minValue ? widened : minValue.nextUp
        }
        let def = Swift.min(rMax, Swift.max(rMin, defaultValue))
        return ParameterDescriptor(
            keyPath: kp,
            displayName: displayName.isEmpty ? kp : displayName,
            min: rMin, max: rMax, defaultValue: def,
            unit: unit,
            valueLabels: (valueStrings?.isEmpty ?? true) ? nil : valueStrings)
    }

    /// Map a whole hosted plugin parameter tree (U2): every `AUParamMeta` →
    /// its descriptor, order preserved. The live bridge extracts the metas from
    /// `auAudioUnit.parameterTree.allParameters`, calls this, and hands the result
    /// to `EchoelParameterRegistry.register` (replace-by-keyPath keeps position).
    public static func descriptors(manufacturer: UInt32, subType: UInt32,
                                   params: [AUParamMeta]) -> [ParameterDescriptor] {
        params.map {
            descriptor(manufacturer: manufacturer, subType: subType, address: $0.address,
                       displayName: $0.displayName, minValue: $0.minValue,
                       maxValue: $0.maxValue, defaultValue: $0.defaultValue,
                       unit: $0.unit, valueStrings: $0.valueStrings)
        }
    }
}
