// ClipSchemaVersionSmokeTests.swift
// Echoel — the clip format's version stamp (#189 slice 3), in the BLOCKING bundle.
//
// WHY THIS ONE EARNS A GATE. `Clip` is where the actual musical content lives — the
// melody, the automation, the media reference. A timeline region is only a `clipID`
// pointer at it. So stamping the arrangement (slice 2) without stamping this would have
// left the notes themselves unversioned while the doc comments read as if persistence
// were covered.
//
// `Clip` uses a THIRD shape for the stamp, and these tests are what make that shape
// safe to rely on. `Project` and `TimelineDocument` keep the decoded value as in-memory
// provenance, which forces a hand-written `encode(to:)`. `Clip` has eleven fields, five
// of which landed after ship, so a hand-written encoder there is a standing invitation to
// add a twelfth and have it vanish on every save. Instead the stamp is never decoded and
// never assigned, and the SYNTHESIZED encoder writes the current version by construction.
// Two things must therefore hold, and neither is visible by reading the struct:
//
//  1. The stamp really is written — synthesis has to pick up a property that no code ever
//     assigns. If it silently did not, the format would be unstamped and look stamped.
//     (Review established it does, and not from language rules alone: `ClipTypeTests`
//     already round-trips `kind`/`mediaRef` through this same custom-decoder-no-encoder
//     shape and passes, so derivation is live here. This test pins it anyway, because that
//     proof is indirect and would evaporate the day someone hand-writes `encode(to:)`.)
//  2. Adding the key must not have cost anything on the way in or out. A clip library is
//     the user's own work; the whole point of `Clip.init(from:)` being `try?`-guarded on
//     every field is that no upgrade may ever empty it.
//
// SCOPE, stated so this file is not read as more than it is: `ClipStore` persists `[Clip?]`
// positionally, so the stamp is PER CLIP. The container is still unversioned — nothing here
// covers a change to the slot count or the nil-slot encoding.

import XCTest
@testable import Echoelmusic

final class ClipSchemaVersionSmokeTests: XCTestCase {

    /// THE ONE THAT CANNOT BE CHECKED BY READING THE CODE: does synthesis actually emit a
    /// property nothing ever assigns? Asserted against the raw JSON, not against the
    /// decoded value — decoding it back would pass even if the key were never written,
    /// because the default would supply it.
    func testTheStampIsActuallyWrittenToTheFile() throws {
        let data = try JSONEncoder().encode(Clip(name: "Take"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, Clip.currentSchemaVersion,
                       "synthesis must emit the stamp — without this the format only LOOKS versioned")
        XCTAssertGreaterThan(Clip.currentSchemaVersion, 0,
                             "0 is reserved for pre-versioning files and must never be current")
    }

    /// A clip saved before the stamp existed still loads, with its content intact. This is
    /// the user's own library; an upgrade may never empty it.
    func testAPreVersioningClipLoadsWithItsContentIntact() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000c1","name":"Old","colorIndex":2,"kind":"midi"}
        """
        let clip = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
        XCTAssertEqual(clip.name, "Old")
        XCTAssertEqual(clip.colorIndex, 2)
        XCTAssertEqual(clip.kind, .midi)
        // Absent stamp does NOT read as 0 here, and that is the deliberate difference from
        // `Project`/`TimelineDocument`: this property is not provenance, it is "what this
        // build writes". A migration reads the file's own value as a local instead.
        XCTAssertEqual(clip.schemaVersion, Clip.currentSchemaVersion)
    }

    /// DOWNGRADE SAFETY — and this one pins LESS than its sibling in
    /// `TimelineSchemaVersionSmokeTests`, so read the difference rather than assume symmetry.
    /// That decoder READS the key, so a future stamp is a real decode path. This one never
    /// reads it, so what is actually asserted is "an unknown key does not throw" — which was
    /// already true before the stamp existed. It is still worth pinning: adding the key is
    /// exactly the moment an older build starts meeting a file it has never seen, and a
    /// decoder that ever became strict about unknown keys would take the user's library with
    /// it. Just do not count it as coverage of the stamp itself.
    func testAFutureClipIsNotVaporized() throws {
        let json = """
        {"schemaVersion":99,"id":"00000000-0000-0000-0000-0000000000c2",
         "name":"FromTheFuture","kind":"midi"}
        """
        let clip = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
        XCTAssertEqual(clip.name, "FromTheFuture")
    }

    /// Round-trip stays lossless with the key added — nothing was displaced on the way
    /// out. Uses a clip carrying the post-ship fields, since those are the ones a wrong
    /// `CodingKeys` edit would drop.
    func testAFullClipRoundTripsUnchanged() throws {
        let clip = Clip(name: "Full", colorIndex: 3, kind: .midi,
                        melody: MelodyClip(notes: [Note(pitch: 60, startStep: 0,
                                                        lengthSteps: 4, velocity: 0.8)]),
                        composerOwned: true)
        let round = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(round, clip, "a field displaced by the new key shows up here")
    }
}
