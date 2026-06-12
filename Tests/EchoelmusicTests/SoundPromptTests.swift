// SoundPromptTests.swift
// Echoel — on-device prompt → sound-design mapping. Deterministic, in-range,
// vocabulary-driven. Hand-checked directional expectations.

#if canImport(Accelerate)
import XCTest
@testable import Echoelmusic

final class SoundPromptTests: XCTestCase {

    private func base() -> SynthPatch { SynthPatch(name: "Base") }

    func testBrightRaisesBrightnessDarkLowersIt() {
        let b = base()
        XCTAssertGreaterThan(SoundPrompt.apply("bright", to: b).brightness, b.brightness)
        XCTAssertLessThan(SoundPrompt.apply("dark", to: b).brightness, b.brightness)
    }

    func testIntensityModifierScalesTheEffect() {
        let b = base()
        let bright = SoundPrompt.apply("bright", to: b).brightness
        let veryBright = SoundPrompt.apply("very bright", to: b).brightness
        XCTAssertGreaterThan(veryBright, bright, "'very' pushes the descriptor further")
    }

    func testWarmDarkensAndLowersCutoff() {
        let b = base()
        let warm = SoundPrompt.apply("warm", to: b)
        XCTAssertLessThan(warm.brightness, b.brightness)
        XCTAssertLessThan(warm.filterCutoff, b.filterCutoff)
    }

    func testPunchyShortensAttack() {
        let b = base()
        XCTAssertLessThan(SoundPrompt.apply("punchy", to: b).attack, b.attack)
    }

    func testPadLengthensEnvelope() {
        let b = base()
        let pad = SoundPrompt.apply("pad", to: b)
        XCTAssertGreaterThan(pad.attack, b.attack)
        XCTAssertGreaterThan(pad.release, b.release)
    }

    func testUnknownWordsAreIgnored() {
        let b = base()
        XCTAssertEqual(SoundPrompt.apply("xyzzy quux frobnicate", to: b), b,
                       "out-of-vocabulary text leaves the patch unchanged")
    }

    func testEmptyPromptIsIdentity() {
        let b = base()
        XCTAssertEqual(SoundPrompt.apply("   ", to: b), b)
    }

    func testAllParamsStayInRangeForWildPrompt() {
        let p = SoundPrompt.apply("very bright super airy huge lush deep dark warm gritty metallic glassy",
                                  to: base())
        XCTAssertTrue((0...1).contains(p.brightness))
        XCTAssertTrue((0...1).contains(p.harmonicity))
        XCTAssertTrue((0...1).contains(p.harmonicLevel))
        XCTAssertTrue((0...1).contains(p.noiseLevel))
        XCTAssertTrue((0...1).contains(p.sustain))
        XCTAssertTrue((0...1).contains(p.reverbMix))
        XCTAssertTrue((0.001...5).contains(p.attack))
        XCTAssertTrue((20...18_000).contains(p.filterCutoff))
        XCTAssertTrue((0...12).contains(p.vibratoRate))
        XCTAssertTrue((0...12).contains(p.reverbDecay))
    }

    func testRecognizedTermsFindsVocabulary() {
        XCTAssertEqual(SoundPrompt.recognizedTerms(in: "a warm, lush PAD please"), ["warm", "lush", "pad"])
        XCTAssertEqual(SoundPrompt.recognizedTerms(in: "warm warm warm"), ["warm"], "de-duplicated")
        XCTAssertTrue(SoundPrompt.recognizedTerms(in: "nothing here").isEmpty)
    }

    func testDeterministic() {
        let b = base()
        XCTAssertEqual(SoundPrompt.apply("bright airy pad", to: b),
                       SoundPrompt.apply("bright airy pad", to: b))
    }

    func testSuggestionsAreAllRecognizable() {
        XCTAssertFalse(SoundPrompt.suggestions.isEmpty)
        for s in SoundPrompt.suggestions {
            XCTAssertFalse(SoundPrompt.recognizedTerms(in: s).isEmpty, "suggestion '\(s)' has known terms")
        }
    }
}
#endif
