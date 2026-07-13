// ParameterApplyRouterTests.swift
// Automation-in-track cycle 1 — the keyPath→live-setter dispatch router: the
// concrete body of the apply hole ParameterToolCore.set() has always taken.
// Pure/control-plane; proves denormalize+dispatch, no-op safety, and that only
// BOUND descriptors are offered as automatable (no dead automation lanes).

import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class ParameterApplyRouterTests: XCTestCase {

    private func makeRouter() -> (ParameterApplyRouter, EchoelParameterRegistry) {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        return (ParameterApplyRouter(registry: reg), reg)
    }

    // MARK: - Normalized apply = the automation playback path (0…1 lane value)

    func testApplyNormalized_routesDenormalizedRealValueToSetter() {
        let (router, reg) = makeRouter()
        var got: Float?
        router.bind("ddsp.filter.cutoff") { got = $0 }
        let applied = router.applyNormalized("ddsp.filter.cutoff", 0.5)
        // descriptor cutoff is 20…18000 linear → 0.5 = 9010
        let expected = reg.descriptor(for: "ddsp.filter.cutoff")!.denormalized(0.5)
        XCTAssertEqual(got, expected)
        XCTAssertEqual(applied, expected)
    }

    func testApplyNormalized_clampsOutOfRangeViaDescriptor() {
        let (router, _) = makeRouter()
        var got: Float?
        router.bind("ddsp.amp.level") { got = $0 }               // 0…1
        _ = router.applyNormalized("ddsp.amp.level", 9)           // clamps to 1
        XCTAssertEqual(got, 1)
        _ = router.applyNormalized("ddsp.amp.level", -3)          // clamps to 0
        XCTAssertEqual(got, 0)
    }

    func testApplyNormalized_unknownKeyPath_isNoOpReturnsNil() {
        let (router, _) = makeRouter()
        var called = false
        router.bind("ddsp.filter.cutoff") { _ in called = true }
        XCTAssertNil(router.applyNormalized("nope.does.not", 0.5))
        XCTAssertFalse(called)                                    // never crash, never fire
    }

    func testApplyNormalized_boundButNoDescriptor_isNoOp() {
        let (router, _) = makeRouter()
        var called = false
        router.bind("custom.unregistered.param") { _ in called = true }
        // No descriptor → cannot denormalize → no-op (real value is undefined).
        XCTAssertNil(router.applyNormalized("custom.unregistered.param", 0.5))
        XCTAssertFalse(called)
    }

    func testApplyNormalized_descriptorButUnbound_isNoOp() {
        let (router, _) = makeRouter()
        XCTAssertNil(router.applyNormalized("ddsp.osc.frequency", 0.5))   // never bound
    }

    // MARK: - Real apply = direct write when the caller already has the real value

    func testApplyReal_dispatchesRawValueReturnsTrue() {
        let (router, _) = makeRouter()
        var got: Float?
        router.bind("ddsp.osc.frequency") { got = $0 }
        XCTAssertTrue(router.applyReal("ddsp.osc.frequency", 440))
        XCTAssertEqual(got, 440)
    }

    func testApplyReal_unbound_returnsFalseNoCrash() {
        let (router, _) = makeRouter()
        XCTAssertFalse(router.applyReal("ddsp.osc.frequency", 440))
    }

    // MARK: - Binding surface

    func testBind_replacesSetterForSameKeyPath() {
        let (router, _) = makeRouter()
        var a = false, b = false
        router.bind("ddsp.amp.level") { _ in a = true }
        router.bind("ddsp.amp.level") { _ in b = true }
        _ = router.applyReal("ddsp.amp.level", 0.5)
        XCTAssertFalse(a); XCTAssertTrue(b)                       // latest wins
    }

    func testIsBound_and_boundKeyPaths() {
        let (router, _) = makeRouter()
        XCTAssertFalse(router.isBound("ddsp.amp.level"))
        router.bind("ddsp.amp.level") { _ in }
        router.bind("ddsp.filter.cutoff") { _ in }
        XCTAssertTrue(router.isBound("ddsp.amp.level"))
        XCTAssertEqual(router.boundKeyPaths, ["ddsp.amp.level", "ddsp.filter.cutoff"])
    }

    // MARK: - The picker rule: only BOUND descriptors are automatable (no dead lanes)

    func testAutomatableDescriptors_onlyBoundInRegistryOrder() {
        let (router, _) = makeRouter()
        router.bind("ddsp.filter.cutoff") { _ in }
        router.bind("ddsp.amp.level") { _ in }
        router.bind("au.unregistered.knob") { _ in }             // bound but not in registry → excluded
        let kps = router.automatableDescriptors().map(\.keyPath)
        // exactly the two registry-known bound ones, in registry insertion order
        XCTAssertEqual(kps, ["ddsp.amp.level", "ddsp.filter.cutoff"])
    }

    func testAutomatableDescriptors_emptyWhenNothingBound() {
        let (router, _) = makeRouter()
        XCTAssertTrue(router.automatableDescriptors().isEmpty)
    }
}
