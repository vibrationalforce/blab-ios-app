// TrackFXDecodeSmokeTests.swift
// Echoel — the per-bus insert settings survive an ordinary edit (#189 slice 4), in the
// BLOCKING bundle.
//
// WHY THIS ONE EARNS A GATE, and why it is not just a version stamp. `TrackFX` had a fully
// SYNTHESIZED decoder, and `TrackFXStore.read` turns any throw into `.off`. That pairing
// meant two everyday edits silently erased the user's filter and drive on all three buses,
// with no error anywhere: adding a non-optional field (`keyNotFound` — the bug that already
// fired on `SynthPatch`, #95, and took the whole patch library), or touching
// `ChannelInsertFX.FilterType`, a raw-value enum whose synthesized decode throws
// `dataCorrupted` on a case it does not know.
//
// Neither failure is visible by reading the struct, and neither would go red anywhere else.
// `TrackFXStoreTests` (non-blocking, #208) does round-trip through JSON — but always through
// THIS build's own encoder, so every file it reads already has every key and only known enum
// cases. That is precisely the file shape that cannot fail. These tests write the JSON by
// hand, which is the only way to stand in for a build that is not this one.

import XCTest
@testable import Echoelmusic

final class TrackFXDecodeSmokeTests: XCTestCase {

    /// THE ONE THAT WOULD HAVE COST THE USER THEIR SOUND. A filter type from a NEWER build
    /// must cost the FILTER CHOICE only — not cutoff, not resonance, not drive, and above
    /// all not the whole bus. Before the defensive decoder this threw, and the store's
    /// `try?` turned the throw into a full reset to `.off`.
    func testAnUnknownFilterTypeCostsTheFilterNotTheWholeBus() throws {
        let json = #"{"filter":99,"cutoffHz":420,"resonance":3.5,"drive":0.6}"#
        let fx = try JSONDecoder().decode(TrackFX.self, from: Data(json.utf8))
        XCTAssertEqual(fx.filter, .off, "an unrecognised type degrades to no filtering")
        XCTAssertEqual(fx.cutoffHz, 420, accuracy: 1e-3)
        XCTAssertEqual(fx.resonance, 3.5, accuracy: 1e-6)
        XCTAssertEqual(fx.drive, 0.6, accuracy: 1e-6, "the drive the user dialed must survive")
    }

    /// A field that is absent — a future removal, a partial write — falls back to `.off`'s
    /// value, NOT to the memberwise default. The difference is audible: the memberwise
    /// `cutoffHz` default is 1200 Hz, so falling back there would darken a bus that was
    /// sitting full open. `.off` rests at 18 kHz, which reads as "no insert dialed".
    func testAMissingFieldFallsBackToPassthroughNotToTheMemberwiseDefault() throws {
        let json = #"{"filter":1,"resonance":1.2,"drive":0.25}"#
        let fx = try JSONDecoder().decode(TrackFX.self, from: Data(json.utf8))
        XCTAssertEqual(fx.cutoffHz, TrackFX.off.cutoffHz)
        XCTAssertNotEqual(fx.cutoffHz, TrackFX(filter: .off).cutoffHz,
                          "the memberwise default is the WRONG fallback — pin the difference")
        XCTAssertEqual(fx.filter, .lowPass, "the fields that ARE present are untouched")
        XCTAssertEqual(fx.resonance, 1.2, accuracy: 1e-6)
    }

    /// A number the file CAN hold but a `Float` cannot: `1e39` is a legal JSON number and a
    /// perfectly good `Double`, but it is past `Float.greatestFiniteMagnitude`. The old
    /// synthesized decoder threw on it and the store answered with a full reset of the bus.
    /// Now it costs that one field.
    ///
    /// Deliberately asserted on the OUTCOME, not on the mechanism, because the two guards
    /// cover each other and I could not determine from here which one fires: Foundation may
    /// reject an out-of-`Float`-range number (the `try?` catches it) or hand back
    /// `.infinity` (the `isFinite` check catches it). Either way the field lands on the
    /// fallback and the bus survives, which is the whole promise. Naming one mechanism would
    /// have been a guess dressed as documentation — and JSON has no NaN or Infinity literal,
    /// so this number is the closest a real file can get to a poisoned value.
    func testAnOutOfFloatRangeNumberCostsOneFieldNotTheBus() throws {
        let json = #"{"filter":1,"cutoffHz":1e39,"resonance":2,"drive":0.4}"#
        let fx = try JSONDecoder().decode(TrackFX.self, from: Data(json.utf8))
        XCTAssertTrue(fx.cutoffHz.isFinite, "an unusable cutoff must never reach makeInsert")
        XCTAssertEqual(fx.cutoffHz, TrackFX.off.cutoffHz)
        XCTAssertEqual(fx.filter, .lowPass, "the finite neighbours are not collateral damage")
        XCTAssertEqual(fx.resonance, 2, accuracy: 1e-6)
        XCTAssertEqual(fx.drive, 0.4, accuracy: 1e-6)
    }

    /// A FINITE, complete file must be bit-identical through the new decoder.
    ///
    /// Precisely what this catches, since the obvious reading is wrong: NOT a field "dropped
    /// from the decoder" — the compiler forces every stored property to be initialised in
    /// `init(from:)`, so an omission is a build error, not a test failure. What it catches is
    /// a SWAPPED key, e.g. `cutoffHz` read out of `.resonance`. That is the realistic slip in
    /// a hand-written decoder with four same-typed fields, and nothing else would find it.
    func testACompleteSettingSurvivesTheDefensiveDecoderUnchanged() throws {
        let fx = TrackFX(filter: .highPass, cutoffHz: 90, resonance: 4.25, drive: 0.8)
        let round = try JSONDecoder().decode(TrackFX.self, from: JSONEncoder().encode(fx))
        XCTAssertEqual(round, fx, "a field dropped from the decoder shows up here")
    }

    /// The stamp is actually written. Asserted against raw JSON, not the decoded value:
    /// decoding it back would pass even if synthesis never emitted the key, because the
    /// property's default would supply it.
    func testTheStampIsActuallyWrittenToTheFile() throws {
        let data = try JSONEncoder().encode(TrackFX.off)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, TrackFX.currentSchemaVersion)
        XCTAssertGreaterThan(TrackFX.currentSchemaVersion, 0,
                             "0 is reserved for pre-versioning files and must never be current")
    }

    /// A setting saved before the stamp existed still loads with its content intact. Every
    /// installed build wrote files in exactly this shape, so this is the realistic upgrade —
    /// and this is the one test here that pins the STAMP's compatibility rather than the
    /// defensive decode: add `"schemaVersion":1` to the fixture and it would pass even under
    /// the old synthesized decoder.
    func testAPreVersioningSettingLoadsWithItsContentIntact() throws {
        let json = #"{"filter":1,"cutoffHz":650,"resonance":2.5,"drive":0.3}"#
        let fx = try JSONDecoder().decode(TrackFX.self, from: Data(json.utf8))
        XCTAssertEqual(fx.filter, .lowPass)
        XCTAssertEqual(fx.cutoffHz, 650, accuracy: 1e-3)
        XCTAssertFalse(fx.isPassthrough, "the dialed insert must still be live after upgrade")
    }
}
