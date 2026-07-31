// EchoelDecimalTextTests.swift
// Echoel — #232 G. Every adjustable number in the app is read through `EchoelValueField`
// and typed through `EchoelNumberPad`; both printed `String(format: "%.Nf")`, i.e. a C
// decimal POINT for every user on earth. This file pins the locale-aware replacement.
//
// ⚠️ WHY THESE TESTS PASS AN EXPLICIT `Locale` EVERYWHERE: `Locale.current` on CI is
// en_US, so a test written against the default would assert "0.50" and pass for the wrong
// reason — it would be green on the exact device configuration that never had the bug.
// Every assertion below names the locale it is about.
//
// In `Tests/CISmoke` because that is the only bundle that can redden a merge (#208), and
// because the format/parse pair is the kind of thing a later "tidy up" silently inverts.

import Foundation
import XCTest
@testable import Echoelmusic

final class EchoelDecimalTextTests: XCTestCase {

    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    /// The defect itself, in one line.
    func testAGermanPlayerReadsAComma() {
        XCTAssertEqual(EchoelDecimalText.string(0.5, decimals: 2, locale: german), "0,50")
        XCTAssertEqual(EchoelDecimalText.string(0.5, decimals: 2, locale: english), "0.50")
        XCTAssertEqual(EchoelDecimalText.string(-3.25, decimals: 2, locale: french), "-3,25")
    }

    /// NO GROUPING, ever. This is the assertion that would have failed had the helper been
    /// built on `NumberFormatter` (which groups by default): "1.234,50" in a field whose
    /// typed buffer is "1234.5" means the readout and the buffer disagree mid-edit, and the
    /// parse rejects the grouped form. The ranges here are Hz/BPM/ms/dB — grouping buys
    /// nothing and costs a parse hazard.
    func testNoGroupingSeparatorEverAppears() {
        XCTAssertEqual(EchoelDecimalText.string(1234.5, decimals: 1, locale: german), "1234,5")
        XCTAssertEqual(EchoelDecimalText.string(65535, decimals: 0, locale: german), "65535")
        XCTAssertEqual(EchoelDecimalText.string(20000, decimals: 2, locale: french), "20000,00")
    }

    /// The minus stays ASCII in EVERY locale, including ones that print U+2212 in prose.
    /// `EchoelNumberPad`'s sign key writes "-" and `Double.init` parses only "-", so a
    /// prettier minus would render correctly and then fail to commit.
    func testTheMinusSignStaysASCIIAndParsesBack() {
        for locale in [german, english, french, Locale(identifier: "sv_SE")] {
            let text = EchoelDecimalText.string(-12.5, decimals: 1, locale: locale)
            XCTAssertTrue(text.hasPrefix("-"),
                          "\(locale.identifier) rendered \(text) — a non-ASCII minus does not parse")
            XCTAssertEqual(Double(EchoelDecimalText.ascii(text, locale)), -12.5)
        }
    }

    /// Format → parse is a round trip in every locale. This is the contract the keypad
    /// depends on: whatever the readout shows must commit to the same number.
    func testFormatThenParseIsIdentityAcrossLocales() {
        let values: [Double] = [0, 0.5, -0.5, 1, 440, 0.01, -128, 63999, 3.14159]
        for locale in [german, english, french, Locale(identifier: "tr_TR")] {
            for v in values {
                let text = EchoelDecimalText.string(v, decimals: 5, locale: locale)
                let back = Double(EchoelDecimalText.ascii(text, locale))
                XCTAssertNotNil(back, "\(locale.identifier): \"\(text)\" did not parse")
                XCTAssertEqual(back ?? .nan, v, accuracy: 1e-9,
                               "\(locale.identifier): \(v) → \"\(text)\" → \(back as Any)")
            }
        }
    }

    /// The parse side is deliberately PERMISSIVE: a value can arrive from a hardware
    /// keyboard, a paste, or a project file written on a differently-configured device, and
    /// none of those are obliged to match `Locale.current`. A German user typing "." on a
    /// Mac keyboard must not be rejected — that was already true before this slice
    /// (`buffer.replacingOccurrences(of: ",", with: ".")`) and must stay true.
    func testBothSeparatorsParseInEitherDirection() {
        XCTAssertEqual(Double(EchoelDecimalText.ascii("0,50", german)), 0.5)
        XCTAssertEqual(Double(EchoelDecimalText.ascii("0.50", german)), 0.5)
        XCTAssertEqual(Double(EchoelDecimalText.ascii("0,50", english)), 0.5)
        XCTAssertEqual(Double(EchoelDecimalText.ascii("0.50", english)), 0.5)
    }

    /// `decimals: 0` must not grow a separator out of nowhere — the integer fields (Port,
    /// Universe, MIDI channel) would then print a character no locale asked for.
    func testZeroDecimalsPrintsNoSeparatorAtAll() {
        for locale in [german, english, french] {
            let text = EchoelDecimalText.string(48000, decimals: 0, locale: locale)
            XCTAssertEqual(text, "48000")
            XCTAssertFalse(text.contains(EchoelDecimalText.separator(locale)))
        }
        // Negative `decimals` cannot reach here from the UI, but a format string built from
        // an unclamped Int is the kind of thing that crashes in front of an audience.
        XCTAssertEqual(EchoelDecimalText.string(7, decimals: -3, locale: german), "7")
    }

    /// Non-finite input passes through as `printf` renders it. Pinned NOT because "nan" is
    /// a good readout — it is not — but because that is exactly what every call site
    /// printed before this file existed, so a difference here would be a silent behaviour
    /// change smuggled in under a localization commit. Guarding NaN belongs at the value's
    /// own boundary (`FloatingPointClamp`), not in a text formatter.
    func testNonFiniteInputIsUnchangedFromThePreviousBehaviour() {
        XCTAssertEqual(EchoelDecimalText.string(.nan, decimals: 2, locale: german),
                       String(format: "%.2f", Double.nan))
        XCTAssertEqual(EchoelDecimalText.string(.infinity, decimals: 2, locale: german),
                       String(format: "%.2f", Double.infinity))
    }

    /// A locale whose separator is neither "." nor "," — the case a two-way `"," ↔ "."`
    /// swap would have missed entirely. Arabic (Egypt) uses U+066B.
    ///
    /// The assertions read the separator out of `Locale` instead of hard-coding U+066B, so
    /// this test degrades to VACUOUS (never to false) if ICU ever reports something else
    /// for ar_EG. That is the deliberate trade: pinning the glyph would redden the one
    /// blocking bundle over an OS data change that harms no user.
    func testALocaleWhoseSeparatorIsNeitherPointNorComma() {
        let arabic = Locale(identifier: "ar_EG")
        let sep = EchoelDecimalText.separator(arabic)
        let text = EchoelDecimalText.string(1.5, decimals: 1, locale: arabic)
        XCTAssertTrue(text.contains(sep), "\(text) does not carry ar_EG's separator \(sep)")
        XCTAssertEqual(Double(EchoelDecimalText.ascii(text, arabic)), 1.5,
                       "a separator that is not \",\" must still normalize back to ASCII")
    }

    /// `localized` is display-only and must be a no-op where the locale already reads ".".
    /// The keypad relies on this: it keeps its buffer in ASCII and maps at draw time, so
    /// `Double(buffer)` and `buffer.contains(".")` stay literally true.
    func testLocalizedIsANoOpForPointLocales() {
        XCTAssertEqual(EchoelDecimalText.localized("12.75", english), "12.75")
        XCTAssertEqual(EchoelDecimalText.localized("12.75", german), "12,75")
        XCTAssertEqual(EchoelDecimalText.localized("", german), "")
        XCTAssertEqual(EchoelDecimalText.localized("-", german), "-")
        // Mid-edit buffers the keypad really produces: "0." after the decimal key, "-0."
        // after sign-then-decimal. Both must render as a partial number, not as garbage.
        XCTAssertEqual(EchoelDecimalText.localized("0.", german), "0,")
        XCTAssertEqual(EchoelDecimalText.localized("-0.", german), "-0,")
    }
}
