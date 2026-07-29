// ExportNamingIsCultureNeutralTests.swift
// Echoel — an exported filename must mean the same thing in Bangkok as in Hamburg.
//
// FOUNDER, 2026-07-29: *"international für alle Kulturen und Hintergründe accessible."*
// Most findings under that heading are presentation — a number punctuated with the wrong
// separator, a label left in English. This one was different: it wrote WRONG DATA into files
// that outlive the session and travel to other people's machines.
//
// `SessionNaming` stamped every export with `Calendar.current`, which is the user's PREFERRED
// calendar, not a shared one. No production caller ever overrode it, so the same take exported
// at the same instant left three different devices as:
//
//     Echoel_2026-07-29_Am_72bpm_A440.mid    de_DE   (Gregorian)
//     Echoel_2569-07-29_Am_72bpm_A440.mid    th_TH   (Buddhist — year +543)
//     Echoel_1447-02-14_Am_72bpm_A440.mid    ar_SA   (Islamic — month and day differ too)
//
// The file's own doc promised "sortable and unambiguous worldwide". It was the one claim in
// that file that was false, and false precisely for the collaboration case the naming scheme
// exists to serve.
//
// ⚠️ WHY THIS TEST IS IN THE BLOCKING BUNDLE (`Tests/CISmoke`) and not beside the existing
// `SessionNamingTests`: those live in `Tests/EchoelmusicTests`, which runs only in the
// NON-blocking Full Test Suite (#208). They also all pass an explicit calendar, which is why
// a fully-tested function shipped this bug for months — every test supplied the argument that
// no caller supplied. A guard against a default has to exercise the DEFAULT.

import Foundation
import XCTest
@testable import Echoelmusic

final class ExportNamingIsCultureNeutralTests: XCTestCase {

    /// A fixed instant, built from UTC components so the test does not depend on where CI runs.
    private func reference() throws -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let d = utc.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 12))
        return try XCTUnwrap(d)
    }

    private func calendar(_ id: Calendar.Identifier) throws -> Calendar {
        var c = Calendar(identifier: id)
        c.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return c
    }

    /// NON-VACUITY FIRST, because without it every other assertion here is unfalsifiable. If
    /// the Buddhist and Islamic calendars did NOT produce a different stamp, a test asserting
    /// "the default matches Gregorian" would pass on a codebase that had never been fixed.
    /// This is the assertion that proves the bug was real and that the others can detect it.
    func testTheNonGregorianCalendarsGenuinelyProduceADifferentStamp() throws {
        let d = try reference()
        let gregorian = try calendar(.gregorian)
        let buddhist = try calendar(.buddhist)
        let ummAlQura = try calendar(.islamicUmmAlQura)

        XCTAssertEqual(SessionNaming.dateStamp(d, calendar: gregorian), "2026-07-29")
        XCTAssertEqual(SessionNaming.dateStamp(d, calendar: buddhist), "2569-07-29",
                       "if this ever equals the Gregorian stamp, the rest of this file is "
                       + "decoration — the calendars would be indistinguishable")
        let islamic = SessionNaming.dateStamp(d, calendar: ummAlQura)
        XCTAssertNotEqual(islamic, "2026-07-29")
        XCTAssertTrue(islamic.hasPrefix("14"),
                      "expected a 15th-century Hijri year, got \(islamic)")
    }

    /// THE ONE THAT MATTERS: the DEFAULT — the path every production caller actually takes —
    /// is Gregorian, whatever calendar the device prefers.
    func testTheDefaultStampIsGregorianRegardlessOfDevicePreference() throws {
        let d = try reference()
        // Compared against an explicitly-Gregorian calendar in the LOCAL zone rather than a
        // hardcoded string, so the assertion is exact wherever CI runs.
        let localGregorian = Calendar(identifier: .gregorian)
        XCTAssertEqual(SessionNaming.dateStamp(d),
                       SessionNaming.dateStamp(d, calendar: localGregorian))
        XCTAssertEqual(SessionNaming.fileCalendar.identifier, .gregorian)
    }

    /// …and the fix must not have bought that by moving to UTC. The stamped day is still the
    /// performer's LOCAL day — a take at 23:00 in Hamburg belongs to that evening's date, not
    /// to tomorrow. This is the half a naive `Calendar(identifier:)`-plus-`TimeZone(UTC)` fix
    /// would silently break, and nobody would notice until a late-night session filed itself
    /// under the wrong day.
    func testTheStampStillFollowsTheLocalDay() {
        XCTAssertEqual(SessionNaming.fileCalendar.timeZone, TimeZone.current)
    }

    /// The whole name, not just the helper — `stem` and `fileName` each carry their own
    /// default and each is a place the old value could survive a partial fix.
    func testTheFullExportNameCarriesTheGregorianDate() throws {
        let d = try reference()
        let stem = SessionNaming.stem(artist: "Echoel", date: d, key: "Am",
                                      bpm: 72, a4Hz: 440)
        let file = SessionNaming.fileName(artist: "Echoel", date: d, key: "Am",
                                          bpm: 72, a4Hz: 440,
                                          part: "Melody", ext: "mid")
        let expected = SessionNaming.dateStamp(d, calendar: Calendar(identifier: .gregorian))
        XCTAssertTrue(stem.contains(expected), "stem lost the Gregorian date: \(stem)")
        XCTAssertTrue(file.contains(expected), "fileName lost the Gregorian date: \(file)")
        XCTAssertFalse(stem.contains("2569"), "a Buddhist year reached the stem")
        XCTAssertFalse(file.contains("2569"), "a Buddhist year reached the filename")
    }

    /// The stamp must stay sortable as plain text — that is the entire reason for `yyyy-MM-dd`
    /// over any localized format, and it is what lets a Thai and a German collaborator's files
    /// interleave correctly in one folder.
    func testStampsSortChronologicallyAsPlainStrings() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let days = [
            DateComponents(year: 2026, month: 1, day: 9, hour: 12),
            DateComponents(year: 2026, month: 1, day: 10, hour: 12),
            DateComponents(year: 2026, month: 2, day: 1, hour: 12),
            DateComponents(year: 2027, month: 1, day: 1, hour: 12)
        ]
        var stamps: [String] = []
        for comps in days {
            let date = try XCTUnwrap(utc.date(from: comps))
            stamps.append(SessionNaming.dateStamp(date, calendar: utc))
        }
        XCTAssertEqual(stamps, stamps.sorted(),
                       "lexical order diverged from chronological order: \(stamps)")
        // Zero-padding is what makes that true — 1-9 must not sort after 1-10.
        XCTAssertEqual(stamps[0], "2026-01-09")
    }
}
