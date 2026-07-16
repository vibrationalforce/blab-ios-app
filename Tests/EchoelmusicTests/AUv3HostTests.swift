// AUv3HostTests.swift
// Echoel — AUv3 discovery: the pure split/de-dupe/sort that powers the plugin browser
// (the actual device scan depends on installed AUs, so we test the categorization).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class AUv3HostTests: XCTestCase {

    private func au(_ name: String, instrument: Bool, id: String? = nil) -> HostedAUInfo {
        HostedAUInfo(id: id ?? "m.\(name)", name: name, manufacturer: "m", isInstrument: instrument)
    }

    func testSplit_separatesInstrumentsAndEffects_sorted() {
        let infos = [au("Zeta", instrument: true), au("alpha", instrument: false),
                     au("Beta", instrument: true), au("Omega", instrument: false)]
        let s = AUv3Host.split(infos)
        XCTAssertEqual(s.instruments.map(\.name), ["Beta", "Zeta"])   // alpha-sorted, case-insensitive
        XCTAssertEqual(s.effects.map(\.name), ["alpha", "Omega"])
    }

    func testSplit_dedupesByID() {
        let infos = [au("Synth", instrument: true, id: "dup"),
                     au("Synth (copy)", instrument: true, id: "dup")]
        XCTAssertEqual(AUv3Host.split(infos).instruments.count, 1)
    }

    func testSplit_empty() {
        let s = AUv3Host.split([])
        XCTAssertTrue(s.instruments.isEmpty)
        XCTAssertTrue(s.effects.isEmpty)
    }

    // MARK: - AU-2 review: a failed restore must NEVER erase the chain record

    @MainActor
    func testRestoreChains_allLoadsFail_recordSurvivesByteIdentical() async throws {
        // The b8258e7 review CRITICAL/HIGH: lazy key reads were clobbered by
        // mid-restore persists, and the final persist forgot transiently-failing
        // plugins (cold AU registry) forever. Harness: an engine-less host makes
        // every load fail early — the three UserDefaults records must survive
        // byte-identical so the NEXT launch retries.
        let d = UserDefaults.standard
        let keys = ["auHost.chain.instrument", "auHost.chain.effects", "auHost.chain.masterEffects"]
        let saved = keys.map { d.data(forKey: $0) }          // hygiene: restore after
        defer {
            for (k, v) in zip(keys, saved) {
                if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
            }
        }
        let instrument = au("LostSynth", instrument: true)
        let fx = [au("LostFX", instrument: false)]
        let masters = [au("LostMaster", instrument: false)]
        d.set(try JSONEncoder().encode(instrument), forKey: keys[0])
        d.set(try JSONEncoder().encode(fx), forKey: keys[1])
        d.set(try JSONEncoder().encode(masters), forKey: keys[2])

        let host = AUv3Host()   // no use(engine:) — every load fails honestly
        await host.restoreChains()

        XCTAssertNil(host.loaded)
        XCTAssertTrue(host.loadedEffects.isEmpty)
        XCTAssertTrue(host.loadedMasterEffects.isEmpty)
        XCTAssertNotNil(host.restoreNotice, "the failure is visible, not silent")
        XCTAssertFalse(host.isRestoringChains, "flag cleared even when everything fails")
        for (i, key) in keys.enumerated() {
            XCTAssertNotNil(d.data(forKey: key), "record \(i) survives for the next launch")
        }
        let survivedInstrument = try JSONDecoder().decode(
            HostedAUInfo.self, from: XCTUnwrap(d.data(forKey: keys[0])))
        XCTAssertEqual(survivedInstrument, instrument, "byte-identical retry record")
        let survivedFX = try JSONDecoder().decode(
            [HostedAUInfo].self, from: XCTUnwrap(d.data(forKey: keys[1])))
        XCTAssertEqual(survivedFX, fx)
        let survivedMasters = try JSONDecoder().decode(
            [HostedAUInfo].self, from: XCTUnwrap(d.data(forKey: keys[2])))
        XCTAssertEqual(survivedMasters, masters)
    }

    // MARK: - Silence trap: Apple Generator "instruments" (founder 2026-07-16)

    func testIsAppleGeneratorRecord_onlyTheFilePlayerTrapMatches() {
        let trap = HostedAUInfo(id: "Apple.AUAudioFilePlayer.x", name: "AUAudioFilePlayer",
                                manufacturer: "Apple", isInstrument: true,
                                componentType: AUv3Host.fourCC("augn"),
                                componentManufacturer: AUv3Host.fourCC("appl"))
        XCTAssertTrue(AUv3Host.isAppleGeneratorRecord(trap))
        // Third-party generators are REAL instruments for many makers — must pass.
        let thirdParty = HostedAUInfo(id: "m.Gen", name: "Gen", manufacturer: "m",
                                      isInstrument: true,
                                      componentType: AUv3Host.fourCC("augn"),
                                      componentManufacturer: AUv3Host.fourCC("Evnt"))
        XCTAssertFalse(AUv3Host.isAppleGeneratorRecord(thirdParty))
        // Apple music devices (AUMIDISynth, AUSampler) are playable — must pass.
        let appleSynth = HostedAUInfo(id: "Apple.AUMIDISynth.x", name: "AUMIDISynth",
                                      manufacturer: "Apple", isInstrument: true,
                                      componentType: AUv3Host.fourCC("aumu"),
                                      componentManufacturer: AUv3Host.fourCC("appl"))
        XCTAssertFalse(AUv3Host.isAppleGeneratorRecord(appleSynth))
        // Effects never match, and legacy records without codes (0) pass through
        // to fail instantiation honestly.
        XCTAssertFalse(AUv3Host.isAppleGeneratorRecord(au("FX", instrument: false)))
        XCTAssertFalse(AUv3Host.isAppleGeneratorRecord(au("Legacy", instrument: true)))
    }

    @MainActor
    func testRestoreChains_appleGeneratorInstrumentRecord_isHealedNotResurrected() async throws {
        // v267 restored EVERY persisted instrument — including one experimental tap
        // on AUAudioFilePlayer (a file-player API unit that never sounds from
        // notes), permanently silencing the track on every launch. An invalid
        // record is HEALED (removed, visibly), not retried: the retention law
        // covers transient cold-registry failures, not impossible instruments.
        let d = UserDefaults.standard
        let key = "auHost.chain.instrument"
        let saved = d.data(forKey: key)
        defer {
            if let saved { d.set(saved, forKey: key) } else { d.removeObject(forKey: key) }
        }
        let filePlayer = HostedAUInfo(id: "Apple.AUAudioFilePlayer.x", name: "AUAudioFilePlayer",
                                      manufacturer: "Apple", isInstrument: true,
                                      componentType: AUv3Host.fourCC("augn"),
                                      componentSubType: AUv3Host.fourCC("afpl"),
                                      componentManufacturer: AUv3Host.fourCC("appl"))
        d.set(try JSONEncoder().encode(filePlayer), forKey: key)

        let host = AUv3Host()
        await host.restoreChains()

        XCTAssertNil(d.data(forKey: key), "the invalid record is gone for good")
        XCTAssertNil(host.loaded, "the mute pseudo-instrument is NOT re-loaded")
        XCTAssertNotNil(host.restoreNotice, "the healing is visible, not silent")
        XCTAssertFalse(host.isRestoringChains)
    }

    // MARK: - AU-2: chain persistence carrier

    func testHostedAUInfo_codableRoundTrip_losslessIncludingComponentCodes() throws {
        // The persisted chain record must re-instantiate EXACTLY this component:
        // the four OSType codes are the identity AVAudioUnit.instantiate needs.
        let info = HostedAUInfo(id: "Eventide.Blackhole.efct", name: "Blackhole",
                                manufacturer: "Eventide", isInstrument: false,
                                componentType: AUv3Host.fourCC("aufx"),
                                componentSubType: AUv3Host.fourCC("blkh"),
                                componentManufacturer: AUv3Host.fourCC("Evnt"))
        let decoded = try JSONDecoder().decode(HostedAUInfo.self,
                                               from: JSONEncoder().encode(info))
        XCTAssertEqual(decoded, info, "every field round-trips, incl. UInt32 codes")

        let chain = [info, HostedAUInfo(id: "m.Synth", name: "Synth",
                                        manufacturer: "m", isInstrument: true)]
        let decodedChain = try JSONDecoder().decode([HostedAUInfo].self,
                                                    from: JSONEncoder().encode(chain))
        XCTAssertEqual(decodedChain, chain, "chain ORDER survives — fx order is audible")
    }
}
#endif
