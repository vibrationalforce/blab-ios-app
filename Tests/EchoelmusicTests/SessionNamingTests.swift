// SessionNamingTests.swift
// Echoel — the automatic session/export name: artist · date · key · BPM ·
// Kammerton. Guards the format, filename safety, and the trimming rules so the
// name is stable and lands cleanly in a DAW.

import XCTest
@testable import Echoelmusic

final class SessionNamingTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        c.hour = 12   // midday avoids any timezone day-rollover ambiguity
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testStemFormat() {
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 6, 12),
                                   key: "Cm", bpm: 124, a4Hz: 440)
        XCTAssertEqual(s, "Echoel_2026-06-12_Cm_124bpm_A440")
    }

    func testWholeNumbersPrintClean() {
        XCTAssertEqual(SessionNaming.trimmed(124.0), "124")
        XCTAssertEqual(SessionNaming.trimmed(440.0), "440")
    }

    func testDecimalsAreTrimmedToTwoPlaces() {
        XCTAssertEqual(SessionNaming.trimmed(123.5), "123.5")
        XCTAssertEqual(SessionNaming.trimmed(123.50), "123.5")
        XCTAssertEqual(SessionNaming.trimmed(442.42), "442.42")
        XCTAssertEqual(SessionNaming.trimmed(442.426), "442.43") // rounds to 2dp
    }

    func testFractionalBpmAndKammertonInStem() {
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 6, 12),
                                   key: "Ador", bpm: 123.5, a4Hz: 432)
        XCTAssertEqual(s, "Echoel_2026-06-12_Ador_123.5bpm_A432")
    }

    func testFileNameWithPartAndExtension() {
        let f = SessionNaming.fileName(artist: "Echoel", date: date(2026, 6, 12),
                                       key: "Cm", bpm: 124, a4Hz: 440,
                                       part: "Drums-4bar", ext: "mid")
        XCTAssertEqual(f, "Echoel_2026-06-12_Cm_124bpm_A440_Drums-4bar.mid")
    }

    func testFileNameToleratesDottedExtension() {
        let f = SessionNaming.fileName(artist: "Echoel", date: date(2026, 6, 12),
                                       key: "Cm", bpm: 124, a4Hz: 440,
                                       part: "Melody", ext: ".mid")
        XCTAssertEqual(f, "Echoel_2026-06-12_Cm_124bpm_A440_Melody.mid")
    }

    func testArtistIsSanitisedToFilenameSafeToken() {
        // Spaces, slashes and punctuation are stripped; letters/digits survive.
        let f = SessionNaming.fileName(artist: "DJ Echo/Él #1", date: date(2026, 6, 12),
                                       key: "Cm", bpm: 124, a4Hz: 440, part: "", ext: "mid")
        // "Él" — the accented É is not in CharacterSet.alphanumerics ASCII-fold,
        // but l is; the token must contain no spaces or slashes.
        XCTAssertFalse(f.contains(" "))
        XCTAssertFalse(f.contains("/"))
        XCTAssertFalse(f.contains("#"))
        XCTAssertTrue(f.hasPrefix("DJEcho"))
        XCTAssertTrue(f.hasSuffix(".mid"))
    }

    func testEmptyArtistFallsBackToBrandMark() {
        // Founder 2026-07-12: "Es soll am Anfang ein E~" — the default/empty
        // artist stamps the brand mark, and "~" survives sanitisation.
        let s = SessionNaming.stem(artist: "   ", date: date(2026, 6, 12),
                                   key: "Cm", bpm: 124, a4Hz: 440)
        XCTAssertTrue(s.hasPrefix("E~_"))
    }

    func testBrandMarkArtistSurvivesSanitisation() {
        let s = SessionNaming.stem(artist: "E~", date: date(2026, 6, 12),
                                   key: "Cm", bpm: 124, a4Hz: 440)
        XCTAssertEqual(s, "E~_2026-06-12_Cm_124bpm_A440")
    }

    func testNoPartOmitsTrailingUnderscore() {
        let f = SessionNaming.fileName(artist: "Echoel", date: date(2026, 6, 12),
                                       key: "Cm", bpm: 124, a4Hz: 440, part: "", ext: "mid")
        XCTAssertEqual(f, "Echoel_2026-06-12_Cm_124bpm_A440.mid")
    }

    // MARK: - Place token (E2: private, on-device location in the session name)

    func testStemWithPlaceInsertsAfterDate() {
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 7, 10),
                                   key: "Am", bpm: 72, a4Hz: 440, place: "Hamburg")
        XCTAssertEqual(s, "Echoel_2026-07-10_Hamburg_Am_72bpm_A440")
    }

    func testEmptyPlaceKeepsClassicFormat() {
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 7, 10),
                                   key: "Am", bpm: 72, a4Hz: 440, place: "")
        XCTAssertEqual(s, "Echoel_2026-07-10_Am_72bpm_A440")
    }

    func testPlaceIsSanitisedToFilenameSafeToken() {
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 7, 10),
                                   key: "Am", bpm: 72, a4Hz: 440, place: "St. Pauli / Hafen")
        XCTAssertFalse(s.contains(" "))
        XCTAssertFalse(s.contains("/"))
        XCTAssertFalse(s.contains("."))
        XCTAssertTrue(s.contains("_StPauliHafen_"))
    }

    func testUnsanitisablePlaceIsOmittedNotFallback() {
        // A place that sanitises to nothing must vanish, not inject a fallback token.
        let s = SessionNaming.stem(artist: "Echoel", date: date(2026, 7, 10),
                                   key: "Am", bpm: 72, a4Hz: 440, place: "***")
        XCTAssertEqual(s, "Echoel_2026-07-10_Am_72bpm_A440")
    }

    func testFileNameCarriesPlace() {
        let f = SessionNaming.fileName(artist: "Echoel", date: date(2026, 7, 10),
                                       key: "Am", bpm: 72, a4Hz: 440,
                                       part: "Melody", ext: "mid", place: "Hamburg")
        XCTAssertEqual(f, "Echoel_2026-07-10_Hamburg_Am_72bpm_A440_Melody.mid")
    }
}

final class MusicalKeyShortNameTests: XCTestCase {

    func testMinorAndMajorTags() {
        XCTAssertEqual(MusicalKey(root: 0, scale: .minor).shortName, "Cm")
        XCTAssertEqual(MusicalKey(root: 0, scale: .major).shortName, "Cmaj")
        XCTAssertEqual(MusicalKey(root: 2, scale: .dorian).shortName, "Ddor")
    }

    func testSharpsRenderFilenameSafe() {
        // C# minor → "Csm", no '#'.
        let k = MusicalKey(root: 1, scale: .minor)
        XCTAssertEqual(k.shortName, "Csm")
        XCTAssertFalse(k.shortName.contains("#"))
    }

    func testEveryScaleHasANonEmptyDistinctTag() {
        let tags = Scale.allCases.map { $0.shortTag }
        XCTAssertTrue(tags.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(tags).count, tags.count, "scale tags must be distinct")
    }
}

@MainActor
final class SessionContextTests: XCTestCase {

    private func ctx() -> SessionContext {
        let d = UserDefaults(suiteName: "SessionContextTests-\(UUID().uuidString)")!
        return SessionContext(defaults: d)
    }

    func testDefaultsAreBrandMarkCMinor440() {
        let c = ctx()
        XCTAssertEqual(c.artistName, "E~")
        XCTAssertEqual(c.a4Hz, 440)
        XCTAssertEqual(c.key.shortName, "Cm")
    }

    func testStoredOldDefaultEchoelMigratesToBrandMark() {
        // "Echoel" was OUR old default, not a user's choice — a stored copy
        // migrates to "E~"; a genuine user name is untouched (next test).
        let suite = "SessionContextTests-migrate-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set("Echoel", forKey: "echoel.artistName")
        XCTAssertEqual(SessionContext(defaults: d).artistName, "E~")
    }

    func testSessionNameComposesFields() {
        let c = ctx()
        c.artistName = "Nova"
        c.adopt(key: MusicalKey(root: 0, scale: .minor))
        c.a4Hz = 432
        let name = c.sessionName(bpm: 124, date: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertTrue(name.hasPrefix("Nova_"))
        XCTAssertTrue(name.contains("_Cm_"))
        XCTAssertTrue(name.contains("_124bpm_"))
        XCTAssertTrue(name.hasSuffix("_A432"))
    }

    func testFileNameUsesContextAndPart() {
        let c = ctx()
        c.adopt(key: MusicalKey(root: 2, scale: .dorian))
        let f = c.fileName(part: "Melody", bpm: 90, date: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertTrue(f.contains("_Ddor_"))
        XCTAssertTrue(f.contains("_90bpm_"))
        XCTAssertTrue(f.hasSuffix("_Melody.mid"))
    }

    func testPersistsAcrossInstances() {
        let suite = "SessionContextTests-persist-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let first = SessionContext(defaults: d)
        first.artistName = "Nova"
        first.a4Hz = 442
        first.adopt(key: MusicalKey(root: 7, scale: .major))
        let second = SessionContext(defaults: d)
        XCTAssertEqual(second.artistName, "Nova")
        XCTAssertEqual(second.a4Hz, 442)
        XCTAssertEqual(second.key.shortName, "Gmaj")
    }

    func testPlaceTokenFlowsIntoNameWhenSet() {
        let c = ctx()
        c.placeToken = "Hamburg"
        let name = c.sessionName(bpm: 72, date: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertTrue(name.contains("_Hamburg_"))
    }

    func testPlaceTokenDefaultsEmptyAndIsTransient() {
        let suite = "SessionContextTests-place-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let first = SessionContext(defaults: d)
        XCTAssertEqual(first.placeToken, "")
        first.placeToken = "Hamburg"
        // Location is resolved live per launch (privacy) — never persisted.
        let second = SessionContext(defaults: d)
        XCTAssertEqual(second.placeToken, "")
    }
}
