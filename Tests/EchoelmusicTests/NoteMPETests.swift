// NoteMPETests.swift
// Echoel — #58 Slice 6: per-note MPE expression OVERRIDES (the "MPE station" seam).
// A note may carry fixed, user-drawn 5D values (bend/slide/pressure) that take
// precedence over the live bio-derived dimension WHERE SET; unset dimensions fall
// through to the body (or to the neutral base when no body is present). The law:
// `mpe == nil` must be byte-identical to today's behaviour AND today's JSON.

import XCTest
@testable import Echoelmusic

final class NoteMPETests: XCTestCase {

    // MARK: - Codable (operators pattern: absent key ⇒ nil; nil ⇒ key absent)

    func testPlainNote_encodesWithoutMPEKey_andDecodesNil() throws {
        let note = Note(pitch: 60, startStep: 0)
        let data = try JSONEncoder().encode(note)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("\"mpe\""),
                       "a plain note's JSON must stay byte-compatible with pre-S6 builds")
        let back = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertNil(back.mpe)
    }

    func testMPERoundTrip_andLegacyDecodeWithoutKey() throws {
        var note = Note(pitch: 64, startStep: 2)
        note.mpe = NoteMPE(bend: -0.25, slide: 0.8, pressure: 1.0)
        let back = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(back.mpe, NoteMPE(bend: -0.25, slide: 0.8, pressure: 1.0))

        // Pre-S6 JSON (no mpe key) decodes with mpe == nil.
        let legacy = #"{"pitch": 60, "startTick": 0, "lengthTicks": 120}"#
        let old = try JSONDecoder().decode(Note.self, from: Data(legacy.utf8))
        XCTAssertNil(old.mpe)
    }

    func testNoteMPE_clampsOnInit() {
        let m = NoteMPE(bend: -3, slide: 7, pressure: -1)
        XCTAssertEqual(m.bend, -1)
        XCTAssertEqual(m.slide, 1)
        XCTAssertEqual(m.pressure, 0)
    }

    func testNoteMPE_nonFiniteInputsAreUnset_neverFullScale() {
        // NaN through generic min/max would land at FULL-SCALE (+1 bend!) — the
        // repo's NaN law is fail quiet/neutral, so non-finite ⇒ dimension unset.
        let m = NoteMPE(bend: .nan, slide: .infinity, pressure: -.infinity)
        XCTAssertNil(m.bend)
        XCTAssertNil(m.slide)
        XCTAssertNil(m.pressure)
        XCTAssertTrue(m.isTransparent)
    }

    func testDecode_clampsOutOfRangeValues() throws {
        // A corrupt/hand-edited clip must not round-trip out-of-range values —
        // decode routes through the clamping init (audio-review LOW).
        let json = #"{"pitch": 60, "startTick": 0, "lengthTicks": 120, "mpe": {"bend": -5, "slide": 7, "pressure": -1}}"#
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(note.mpe, NoteMPE(bend: -1, slide: 1, pressure: 0))
    }

    func testNoteMPE_transparentWhenAllNil() {
        XCTAssertTrue(NoteMPE().isTransparent)
        XCTAssertFalse(NoteMPE(bend: 0).isTransparent,
                       "an explicit centre bend is a SET value, not transparency")
    }

    // MARK: - Merge (pure, MPEExpression.merging)

    func testMerging_nilBioNilOverride_staysNil() {
        XCTAssertNil(MPEExpression.merging(bio: nil, override: nil))
        XCTAssertNil(MPEExpression.merging(bio: nil, override: NoteMPE()),
                     "a transparent override must not conjure an expression")
    }

    func testMerging_transparentOverride_returnsBioUnchanged() {
        let bio = MPEExpression(slideCC74: 100, pressure: 40, bend: 0.1)
        XCTAssertEqual(MPEExpression.merging(bio: bio, override: nil), bio)
        XCTAssertEqual(MPEExpression.merging(bio: bio, override: NoteMPE()), bio)
    }

    func testMerging_overrideWinsPerDimension_othersFallThroughToBio() {
        let bio = MPEExpression(slideCC74: 100, pressure: 40, bend: 0.1)
        let merged = MPEExpression.merging(bio: bio, override: NoteMPE(bend: -0.5))
        XCTAssertEqual(merged?.bend, -0.5)
        XCTAssertEqual(merged?.slideCC74, 100, "unset slide keeps the body's value")
        XCTAssertEqual(merged?.pressure, 40, "unset pressure keeps the body's value")
    }

    func testMerging_overrideOnly_neutralBaseForUnsetDimensions() {
        // No body: set dimensions apply over the NEUTRAL base (slide centre 64,
        // pressure 0, bend 0) so a drawn bend never invents brightness/pressure.
        let merged = MPEExpression.merging(bio: nil, override: NoteMPE(bend: 1.0))
        XCTAssertEqual(merged?.bend, 1.0)
        XCTAssertEqual(merged?.slideCC74, 64)
        XCTAssertEqual(merged?.pressure, 0)
    }

    // MARK: - Model door (S6b: inspector setter)

    @MainActor
    func testSetMPE_routesThroughClampingInit_andCollapsesTransparentToNil() {
        let m = PianoRollModel()
        m.add(pitch: 60, startStep: 0)
        guard let id = m.notes.first?.id else { return XCTFail("note missing") }

        m.setMPE(id: id, bend: -3, slide: nil, pressure: 0.5)
        XCTAssertEqual(m.notes.first?.mpe, NoteMPE(bend: -1, pressure: 0.5),
                       "inspector writes clamp like every other path")

        // Clearing every dimension collapses the override to nil — the note's
        // JSON returns to byte-identical plain form (seam contract).
        m.setMPE(id: id, bend: nil, slide: nil, pressure: nil)
        XCTAssertNil(m.notes.first?.mpe)
    }

    func testMerging_normalizedToWireUnits() {
        // slide/pressure are stored 0…1 and must land as 7-bit wire values.
        let merged = MPEExpression.merging(
            bio: nil, override: NoteMPE(slide: 1.0, pressure: 0.5))
        XCTAssertEqual(merged?.slideCC74, 127)
        XCTAssertEqual(merged?.pressure, 64)   // (0.5 × 127).rounded()
        XCTAssertEqual(merged?.bend, 0)
    }
}
