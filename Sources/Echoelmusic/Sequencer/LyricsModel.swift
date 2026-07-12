// LyricsModel.swift
// Echoel — W1: syllable→note lyric mapping as a PURE Codable model (founder
// 2026-07-12C: "Lyrics bzw songwriting wie bei ACE Studio soll es geben ja").
//
// Own path, not an ACE copy: everything here is on-device, deterministic and
// user-editable — no server render, no credits. This file is the foundation
// the Roll's lyric lane (W2) and the voice coupling (W3/W4) build on.
//
// SYLLABIFICATION IS A SINGING HEURISTIC, not a dictionary: it prefers OPEN
// syllables (consonant starts the next syllable — "ri-ver", "Lie-be"), which
// is how lyrics are actually distributed under notes in vocal writing. It is
// deterministic (same input → same split, always) and the split is only a
// DEFAULT — the lyric lane lets the writer re-split by hand (W2), and manual
// splits are stored verbatim in the document.
//
// Pure Foundation value types — Linux-CI-tested, no engine coupling.

import Foundation

/// Languages the syllabifier knows cluster rules for. Raw values persist.
public enum LyricLanguage: String, Codable, Sendable, CaseIterable {
    case german, english
}

/// One sung syllable. `isWordEnd` drives hyphen display ("Lie-" vs "be").
public struct LyricSyllable: Codable, Sendable, Equatable {
    public var text: String
    public var isWordStart: Bool
    public var isWordEnd: Bool

    public init(text: String, isWordStart: Bool = true, isWordEnd: Bool = true) {
        self.text = text
        self.isWordStart = isWordStart
        self.isWordEnd = isWordEnd
    }

    /// How the syllable reads under a note: a trailing hyphen when the word
    /// continues on the next syllable (standard vocal-score convention).
    public var displayText: String { isWordEnd ? text : text + "-" }
}

/// One lyric line (verse line). Kept as sequential syllables — word
/// boundaries live on the syllables themselves.
public struct LyricLine: Codable, Sendable, Equatable {
    public var syllables: [LyricSyllable]
    public init(syllables: [LyricSyllable] = []) { self.syllables = syllables }
}

/// The whole lyric document for a song/loop: language + ordered lines.
/// Melisma is NOT stored here — it is a property of the note binding
/// (which notes extend a held syllable), see `LyricsMapper`.
public struct LyricsDocument: Codable, Sendable, Equatable {
    public var language: LyricLanguage
    public var lines: [LyricLine]

    public init(language: LyricLanguage = .german, lines: [LyricLine] = []) {
        self.language = language
        self.lines = lines
    }

    /// All syllables in singing order (lines are sung top to bottom).
    public var allSyllables: [LyricSyllable] { lines.flatMap(\.syllables) }
}

/// One note's lyric assignment. `syllableIndex` indexes into the document's
/// `allSyllables`; nil = untexted note (vocalise). `isMelismaExtension`
/// marks a note that HOLDS the previous syllable (one syllable over n notes).
public struct LyricNoteBinding: Codable, Sendable, Equatable {
    public var noteID: UUID
    public var syllableIndex: Int?
    public var isMelismaExtension: Bool

    public init(noteID: UUID, syllableIndex: Int?, isMelismaExtension: Bool = false) {
        self.noteID = noteID
        self.syllableIndex = syllableIndex
        self.isMelismaExtension = isMelismaExtension
    }
}

// MARK: - Syllabifier (deterministic singing heuristic)

public enum Syllabifier {

    /// Split one word into sung syllables. Deterministic; never returns an
    /// empty array for a non-empty word (unsplittable words come back whole).
    public static func syllables(of word: String, language: LyricLanguage) -> [String] {
        let chars = Array(word)
        guard !chars.isEmpty else { return [] }
        let lower = Array(word.lowercased())

        // 1. Nuclei: indices of vowel-group starts + their ranges. A vowel
        //    RUN is one nucleus (diphthongs stay together: "Lie", "beau").
        var nuclei: [Range<Int>] = []
        var i = 0
        while i < lower.count {
            if isVowel(lower[i], language: language) {
                var j = i + 1
                while j < lower.count, isVowel(lower[j], language: language),
                      isDiphthongContinuation(lower, at: j, language: language) {
                    j += 1
                }
                nuclei.append(i..<j)
                i = j
            } else {
                i += 1
            }
        }

        // English silent final e: "time" has one sung syllable. Exception is
        // consonant+"le" ("ta-ble", "lit-tle") where the le IS the nucleus.
        if language == .english, nuclei.count >= 2,
           let last = nuclei.last, last.count == 1,
           lower[last.lowerBound] == "e", last.upperBound == lower.count,
           last.lowerBound >= 1,
           !isVowel(lower[last.lowerBound - 1], language: .english),
           lower[last.lowerBound - 1] != "l" {
            nuclei.removeLast()
        }

        guard nuclei.count >= 2 else { return [word] }

        // 2. Between consecutive nuclei, choose the split point in the
        //    consonant run: a single consonant opens the NEXT syllable
        //    (open-syllable singing rule); for runs, split before the last
        //    consonant unless an inseparable cluster claims more.
        var cuts: [Int] = []
        for k in 0..<(nuclei.count - 1) {
            let runStart = nuclei[k].upperBound
            let runEnd = nuclei[k + 1].lowerBound
            let runLength = runEnd - runStart
            if runLength <= 0 { cuts.append(runEnd); continue }
            if runLength == 1 { cuts.append(runStart); continue }
            // Default: last consonant starts the next syllable ("Schat-ten").
            var cut = runEnd - 1
            // Widen: keep an inseparable onset cluster with the next syllable
            // ("Zu-cker", "Mor-phing"-style ph, "beau-ti-ful" needs nothing).
            for width in stride(from: min(3, runLength), through: 2, by: -1) {
                let candidate = String(lower[(runEnd - width)..<runEnd])
                if onsetClusters(for: language).contains(candidate) {
                    cut = runEnd - width
                    break
                }
            }
            cuts.append(cut)
        }

        // 3. Assemble.
        var parts: [String] = []
        var start = 0
        for cut in cuts where cut > start {
            parts.append(String(chars[start..<cut]))
            start = cut
        }
        parts.append(String(chars[start...]))
        return parts.filter { !$0.isEmpty }
    }

    /// Split a whole line into flagged syllables (word boundaries kept).
    /// Punctuation stays attached to its word; whitespace separates words.
    public static func syllables(ofLine line: String, language: LyricLanguage) -> [LyricSyllable] {
        let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var out: [LyricSyllable] = []
        for word in words {
            let parts = syllables(of: word, language: language)
            for (idx, part) in parts.enumerated() {
                out.append(LyricSyllable(text: part,
                                         isWordStart: idx == 0,
                                         isWordEnd: idx == parts.count - 1))
            }
        }
        return out
    }

    // MARK: internals

    private static func isVowel(_ c: Character, language: LyricLanguage) -> Bool {
        switch language {
        case .german:  return "aeiouyäöü".contains(c)
        case .english: return "aeiouy".contains(c)
        }
    }

    /// Whether the vowel at `index` continues the run that started before it.
    /// German splits adjacent vowels that are NOT a diphthong ("Me-lo-die" ie
    /// stays, "Bea-te" would split — kept simple: known diphthongs continue,
    /// anything else breaks the run into a new nucleus).
    private static func isDiphthongContinuation(_ lower: [Character], at index: Int,
                                                language: LyricLanguage) -> Bool {
        guard index >= 1 else { return false }
        let pair = String(lower[index - 1...index])
        switch language {
        case .german:
            return ["ei", "ie", "au", "eu", "äu", "ai", "aa", "ee", "oo"].contains(pair)
        case .english:
            // English vowel runs overwhelmingly sing as one nucleus.
            return true
        }
    }

    /// Clusters that must START a syllable together (never split inside).
    private static func onsetClusters(for language: LyricLanguage) -> Set<String> {
        switch language {
        case .german:
            return ["sch", "ch", "ck", "ph", "th", "qu", "pf", "st", "sp",
                    "br", "bl", "dr", "fr", "fl", "gr", "gl", "kr", "kl",
                    "pr", "pl", "tr", "schw", "zw"]
        case .english:
            // tl/dl/kl are not word onsets in English but ARE the sung onset
            // before a consonant+le nucleus ("lit-tle", "han-dle" — the run
            // window holds only consonants, so "tle"-style entries never match).
            return ["sch", "ch", "sh", "th", "ph", "wh", "qu", "ck",
                    "bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr",
                    "pl", "pr", "sc", "sk", "sl", "sm", "sn", "sp", "st",
                    "sw", "tr", "tw", "str", "spr", "thr", "spl",
                    "tl", "dl", "kl"]
        }
    }
}

// MARK: - Mapper (syllables → notes, melisma-aware)

public enum LyricsMapper {

    /// Distribute syllables across notes in singing order (startTick, then
    /// pitch for stable chord ordering). One syllable per note; a note whose
    /// id is in `melisma` HOLDS the previous syllable instead of consuming a
    /// new one (one syllable over n notes). Notes after the last syllable are
    /// untexted (nil — vocalise), never a crash. Pure + deterministic.
    public static func bind(syllables: [LyricSyllable],
                            to notes: [Note],
                            melisma: Set<UUID> = []) -> [LyricNoteBinding] {
        let ordered = notes.sorted {
            $0.startTick != $1.startTick ? $0.startTick < $1.startTick : $0.pitch < $1.pitch
        }
        var bindings: [LyricNoteBinding] = []
        bindings.reserveCapacity(ordered.count)
        var nextSyllable = 0
        var lastConsumed: Int?
        for note in ordered {
            if melisma.contains(note.id), let held = lastConsumed {
                bindings.append(LyricNoteBinding(noteID: note.id,
                                                 syllableIndex: held,
                                                 isMelismaExtension: true))
                continue
            }
            if nextSyllable < syllables.count {
                bindings.append(LyricNoteBinding(noteID: note.id, syllableIndex: nextSyllable))
                lastConsumed = nextSyllable
                nextSyllable += 1
            } else {
                bindings.append(LyricNoteBinding(noteID: note.id, syllableIndex: nil))
            }
        }
        return bindings
    }
}
