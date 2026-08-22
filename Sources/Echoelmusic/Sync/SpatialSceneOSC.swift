//
//  SpatialSceneOSC.swift
//  Echoelmusic — EchoelSync module
//
//  S2 of the Spatial Expansion: turns a SpatialScene (S1) into OSC messages
//  for external immersive renderers, in two open dialects:
//
//  · ADM-OSC (github.com/immersive-audio-live/ADM-OSC) — the namespace the
//    shipping ADMOSCSender already speaks. Objects are 1-BASED, positions
//    spherical, distance normalized:
//      /adm/obj/{n}/position/azimuth    float  -180 … +180  degrees
//      /adm/obj/{n}/position/elevation  float   -90 … +90   degrees
//      /adm/obj/{n}/position/distance   float     0 … 1
//      /adm/obj/{n}/gain                float     0 … 1     linear
//
//  · ADM-OSC Cartesian — same standard, the Cartesian branch of the namespace
//    for renderers/consoles that accept x/y/z object input instead of polar
//    (ITU-R BS.2076 room coordinates, unit-scaled by distance):
//      /adm/obj/{n}/position/x  float   +right   (−left)
//      /adm/obj/{n}/position/y  float   +front   (−back)
//      /adm/obj/{n}/position/z  float   +up      (−down)
//      /adm/obj/{n}/gain        float    0 … 1   linear
//    Derived from the exact SAME SpatialPosition (via `.cartesian`), so an object
//    placed once reaches a polar OR a Cartesian rig without re-authoring.
//
//  · IEM plug-in suite (plugins.iem.at/docs/osc/) — MultiEncoder-style:
//    /<PluginName>/<param><index> with a 0-BASED source index, angles in
//    degrees (same sign convention as ADM: positive azimuth = left/CCW):
//      /MultiEncoder/azimuth{i}    float  degrees
//      /MultiEncoder/elevation{i}  float  degrees
//      /MultiEncoder/gain{i}       float  dB (linear→dB here, floored -60)
//    The MultiEncoder is a direction encoder — it has NO distance parameter,
//    so `distance` is not sent in this dialect (renderer-side room handles
//    it). Documented, not folded silently into gain.
//
//  Pure value-in/value-out formatter (P4 portable, Foundation-only) —
//  golden-file tested without a socket. The network path stays in
//  ADMOSCSender.
//
//  ⛔ THIS HEADER SAID THE SCENE-DRIVEN SEND HAS "NO CALLERS YET" AND THAT IS
//  STALE (#745). Measured with comments stripped: `ADMOSCSender.send(scene:)`
//  occurs twice in code — its declaration AND one call, in `sendIfFresh`,
//  inside the `if streamsScene` branch. The CONCLUSION survives, the
//  REASON does not, and that is the worse half to leave standing (#402): a
//  session that greps for the caller finds one and reads the whole paragraph
//  as obsolete, including the guardrail it exists to state.
//
//  ⭐ The honest reason Release stays bit-identical: `streamsScene` defaults
//  to `false` and its ONLY writer in `Sources/` is a `Toggle` in
//  `ImmersiveStageView` — a view with ZERO construction sites, doorless on
//  purpose (ship-gate 4: light/space "demonstrable, not required for v1").
//  So the branch compiles, is wired, and cannot be entered by a user today.
//  The property that picks WHICH dialect the branch speaks has no writer at
//  all — see `ADMOSCSender.sceneDialect`.
//

import Foundation

/// Which OSC vocabulary an external renderer speaks.
public enum SpatialOSCDialect: Sendable, Equatable {
    /// ADM-OSC v1.0 polar — FletcherMachine, L-ISA, d&b Soundscape, SPAT, Nuendo.
    case admOSC
    /// ADM-OSC v1.0 Cartesian (x/y/z) — for Cartesian-only immersive consoles /
    /// renderers that don't accept polar object input. Same namespace + 1-based
    /// object index as `.admOSC`, position sent as x/y/z instead of az/el/dist.
    case admOSCCartesian
    /// IEM plug-in suite MultiEncoder-style addressing; `plugin` is the OSC
    /// root the plugin instance listens on (default plugin name shown).
    case iemMultiEncoder(plugin: String)

    /// The stock IEM MultiEncoder root.
    public static let iem = SpatialOSCDialect.iemMultiEncoder(plugin: "MultiEncoder")
}

/// Pure SpatialScene → OSC (address, value) formatter. Object order in the
/// scene defines the renderer object index (ADM 1-based, IEM 0-based) — the
/// scene array is the routing table.
public enum SpatialSceneOSCFormatter {

    public static func messages(for scene: SpatialScene,
                                dialect: SpatialOSCDialect) -> [(address: String, value: Float)] {
        switch dialect {
        case .admOSC:
            return admMessages(scene)
        case .admOSCCartesian:
            return admCartesianMessages(scene)
        case .iemMultiEncoder(let plugin):
            return iemMessages(scene, plugin: plugin)
        }
    }

    // MARK: - ADM-OSC (1-based objects, same namespace as ADMOSCSender)

    private static func admMessages(_ scene: SpatialScene) -> [(address: String, value: Float)] {
        var out: [(String, Float)] = []
        out.reserveCapacity(scene.objects.count * 4)
        for (i, obj) in scene.objects.enumerated() {
            let prefix = "/adm/obj/\(i + 1)"
            out.append(("\(prefix)/position/azimuth", obj.position.azimuth))
            out.append(("\(prefix)/position/elevation", obj.position.elevation))
            out.append(("\(prefix)/position/distance", obj.position.distance))
            out.append(("\(prefix)/gain", obj.gain))
        }
        return out
    }

    // MARK: - ADM-OSC Cartesian (1-based objects, x/y/z instead of az/el/dist)

    private static func admCartesianMessages(_ scene: SpatialScene) -> [(address: String, value: Float)] {
        var out: [(String, Float)] = []
        out.reserveCapacity(scene.objects.count * 4)
        for (i, obj) in scene.objects.enumerated() {
            let prefix = "/adm/obj/\(i + 1)"
            // Reuse SpatialPosition's own ADM cartesian derivation (x right, y front,
            // z up, distance-scaled) — one source of truth, so polar and Cartesian
            // outputs can never disagree about where an object is.
            let c = obj.position.cartesian
            out.append(("\(prefix)/position/x", c.x))
            out.append(("\(prefix)/position/y", c.y))
            out.append(("\(prefix)/position/z", c.z))
            out.append(("\(prefix)/gain", obj.gain))
        }
        return out
    }

    // MARK: - IEM MultiEncoder (0-based sources, degrees + dB, no distance)

    private static func iemMessages(_ scene: SpatialScene,
                                    plugin: String) -> [(address: String, value: Float)] {
        var out: [(String, Float)] = []
        out.reserveCapacity(scene.objects.count * 3)
        for (i, obj) in scene.objects.enumerated() {
            let prefix = "/\(plugin)"
            out.append(("\(prefix)/azimuth\(i)", obj.position.azimuth))
            out.append(("\(prefix)/elevation\(i)", obj.position.elevation))
            out.append(("\(prefix)/gain\(i)", decibels(fromLinear: obj.gain)))
        }
        return out
    }

    /// Linear 0…1 → dB, floored at -60 (the IEM per-source gain floor).
    /// Exposed for tests — the floor is part of the dialect contract.
    public static func decibels(fromLinear gain: Float) -> Float {
        guard gain > 0 else { return -60 }
        return max(20 * log10f(gain), -60)
    }
}
