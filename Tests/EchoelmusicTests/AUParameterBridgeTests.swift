// AUParameterBridgeTests.swift
// AUv3-structure block U2b — the testable core of the live parameter bridge:
// given a hosted plugin's parameter metas, register them into the registry AND
// bind each to a live setter, so the plugin's knobs become automatable exactly
// like internal DDSP params (placebo law: bound → offered, unbound → dropped).
// The AVFoundation extraction (AUParameter → AUParamMeta) is the U2c thin layer;
// this core is Foundation-only so CI verifies register + bind + unbind.

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class AUParameterBridgeTests: XCTestCase {

    private func osType(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for b in s.utf8.prefix(4) { r = (r << 8) | UInt32(b) }
        return r
    }

    func testInstall_registersDescriptors_andBindsSetters() {
        let reg = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: reg)
        var captured: [UInt64: Float] = [:]
        let metas = [
            AUParamMeta(address: 0, displayName: "Cutoff", minValue: 20, maxValue: 20_000,
                        defaultValue: 440, unit: "Hz"),
            AUParamMeta(address: 1, displayName: "Res", minValue: 0, maxValue: 1, defaultValue: 0.3),
        ]
        let kps = AUParameterBridge.install(
            metas: metas, manufacturer: osType("Echl"), subType: osType("filt"),
            into: reg, router: router) { addr in { v in captured[addr] = v } }

        XCTAssertEqual(kps, ["au.Echl.filt.0", "au.Echl.filt.1"])
        XCTAssertNotNil(reg.descriptor(for: "au.Echl.filt.0"))
        XCTAssertEqual(reg.descriptor(for: "au.Echl.filt.0")?.displayName, "Cutoff")
        // Placebo law: bound params are the automatable set.
        XCTAssertEqual(router.automatableDescriptors().map(\.keyPath).sorted(),
                       ["au.Echl.filt.0", "au.Echl.filt.1"])
    }

    func testInstall_normalizedApplyReachesSetterWithRealValue() {
        let reg = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: reg)
        var captured: [UInt64: Float] = [:]
        let metas = [
            AUParamMeta(address: 0, displayName: "Cutoff", minValue: 20, maxValue: 20_000,
                        defaultValue: 440, unit: "Hz"),
            AUParamMeta(address: 1, displayName: "Res", minValue: 0, maxValue: 1, defaultValue: 0.3),
        ]
        _ = AUParameterBridge.install(
            metas: metas, manufacturer: osType("Echl"), subType: osType("filt"),
            into: reg, router: router) { addr in { v in captured[addr] = v } }

        // applyNormalized denormalizes through the registered descriptor.
        router.applyNormalized("au.Echl.filt.1", 0.5)      // 0…1 linear → 0.5
        XCTAssertEqual(captured[1] ?? -1, 0.5, accuracy: 1e-6)
        router.applyNormalized("au.Echl.filt.0", 0.0)      // → min 20 Hz
        XCTAssertEqual(captured[0] ?? -1, 20, accuracy: 1e-2)
    }

    func testUninstall_unbindsSetters_dropsFromAutomatable() {
        let reg = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: reg)
        let metas = [AUParamMeta(address: 5, displayName: "Drive", minValue: 0, maxValue: 1,
                                 defaultValue: 0)]
        let kps = AUParameterBridge.install(
            metas: metas, manufacturer: osType("Echl"), subType: osType("dist"),
            into: reg, router: router) { _ in { _ in } }
        XCTAssertFalse(router.automatableDescriptors().isEmpty)

        AUParameterBridge.uninstall(keyPaths: kps, router: router)
        XCTAssertTrue(router.automatableDescriptors().isEmpty,
                      "unloaded plugin params must drop out of the automatable set")
        // The descriptor lingers in the registry (no removal API) but is inert:
        // applyNormalized is a safe no-op with no setter bound.
        XCTAssertNil(router.applyNormalized("au.Echl.dist.5", 0.7))
    }

    func testInstall_reinstall_replacesSetterInPlace() {
        // A plugin replacing its parameterTree re-installs the same keyPath: the
        // newest setter wins, no duplicate binding.
        let reg = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: reg)
        var which = 0
        let metas = [AUParamMeta(address: 0, displayName: "P", minValue: 0, maxValue: 1, defaultValue: 0)]
        _ = AUParameterBridge.install(metas: metas, manufacturer: osType("Echl"),
                                      subType: osType("syn "), into: reg, router: router) { _ in { _ in which = 1 } }
        _ = AUParameterBridge.install(metas: metas, manufacturer: osType("Echl"),
                                      subType: osType("syn "), into: reg, router: router) { _ in { _ in which = 2 } }
        router.applyNormalized("au.Echl.syn_.0", 0.5)
        XCTAssertEqual(which, 2, "re-install rebinds to the newest setter")
        XCTAssertEqual(router.automatableDescriptors().filter { $0.keyPath == "au.Echl.syn_.0" }.count, 1)
    }
}
