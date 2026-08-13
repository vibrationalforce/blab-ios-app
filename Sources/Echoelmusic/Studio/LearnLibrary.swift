// LearnLibrary.swift
// Echoel — the single index behind the "app as a school" idea. Unifies the
// existing teaching content (bio metrics, music theory) plus a safety/scope note
// into one browsable, sectioned model, so a future "Learn" surface binds to ONE
// source instead of many silos. Pure Foundation, unit-tested. No new copy is
// invented here — it reuses BioMetric and MusicTheoryTopic verbatim.

import Foundation

public enum LearnSection: String, CaseIterable, Identifiable, Sendable {
    // #589 — `guide` is deliberately FIRST: `LearnView` renders sections in `allCases` order,
    // and the founder's ask this case answers is "ein leichtes Eintauchen … für alle Sinne —
    // hörbar, sichtbar und spürbar". A newcomer opens Learn and meets the way IN before the
    // reference material. (The rawValue is a storage-shaped token like its neighbours; the
    // enum itself is never persisted — ids like "guide.hear" are built from it.)
    case guide, body, bodyScience, music, light, safety

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .guide:       return "Start Here"
        case .body:        return "Your Body"
        case .bodyScience: return "Body Science"
        case .music:       return "Music Theory"
        case .light:       return "Light & Colour"
        case .safety:      return "Safety & Scope"
        }
    }
}

/// One learnable entry, renderer-agnostic.
public struct LearnEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let section: LearnSection
    public let title: String
    public let summary: String
    public let detail: String

    public init(id: String, section: LearnSection, title: String, summary: String, detail: String) {
        self.id = id
        self.section = section
        self.title = title
        self.summary = summary
        self.detail = detail
    }
}

public enum LearnLibrary {

    /// The way in — one entry per sense, plus the walkthrough and the accessibility note.
    ///
    /// ⭐ EVERY CONTROL NAMED HERE IS QUOTED FROM THE SHIPPING UI, verbatim, and the blocking
    /// bundle enforces the join (`TheGuideNamesOnlyRealControlsTests`): a guide that names a
    /// control the app does not have is the first-instruction defect all over again — #351
    /// already paid for "a finger on the camera brings it to life" being untrue at the moment
    /// it was shown. Rename a control, and the guard names this file as the place to follow.
    ///
    /// ⚠️ NO HEALING LANGUAGE, deliberately, including in the "feel" entry — vocal/tonal work
    /// and haptics are described as practice and self-observation (the Body Science precedent).
    /// The healing theme is a hard product red line, not a style preference.
    public static var guideEntries: [LearnEntry] {
        [
            LearnEntry(
                id: "guide.firstSession", section: .guide,
                title: "Your first three minutes",
                summary: "The app opens as a picture. Here is the way in.",
                detail: "Echoel opens into its living picture — that is the instrument's face, "
                    + "not a loading screen. The \"Studio\" chip brings the controls up in "
                    + "front of it; the X hides the picture. Press the Play button and the "
                    + "instrument starts: it composes in your key and genre, and once it can "
                    + "read your body, your body plays it. Nothing sounds until you start it — "
                    + "silence at launch is by design, not a fault."
            ),
            LearnEntry(
                id: "guide.hear", section: .guide,
                title: "Hear it",
                summary: "Press Play; the music is composed, then your body shapes it.",
                detail: "Play starts a generated take — harmony, melody and bass in one key, "
                    + "at one tempo, in the genre you chose. Your heart and breath then bend "
                    + "its brightness, its swell and its calm in real time. For your own "
                    + "voice in the loop, switch on \"Body voice\" in the Bio panel: a held "
                    + "tone that your breath opens and closes — exhale, and it fades; inhale, "
                    + "and it returns. Toning with it, vowels and hums, is a practice of "
                    + "self-observation: you hear your own breathing pattern as sound."
            ),
            LearnEntry(
                id: "guide.see", section: .guide,
                title: "See it",
                summary: "The picture moves with your body — and it is playable.",
                detail: "The picture breathes with you: pulse, breath and coherence drive its "
                    + "colour and motion, capped below 3 flashes per second. Touch it to play "
                    + "notes — every touch lands in key, so there is no wrong place. It stays "
                    + "playable at every window size. With Reduce Motion on, the picture "
                    + "holds still entirely. You can record it as a share-ready video."
            ),
            LearnEntry(
                id: "guide.feel", section: .guide,
                title: "Feel it",
                summary: "The beat in your hand, the bass in your body.",
                detail: "Switch on \"Haptic beat (feel)\" under \"Tempo & variations\" and the "
                    + "phone pulses on each quarter-note, the downbeat strongest — you can "
                    + "hold time without watching the screen. The sub-bass is tuned to be "
                    + "felt as much as heard: on a sub, in headphones, or through the "
                    + "haptics. Eyes-free by intention: the instrument is playable without "
                    + "looking at it."
            ),
            LearnEntry(
                id: "guide.pulse", section: .guide,
                title: "Give it your pulse",
                summary: "Start the music first — then a finger on the back camera.",
                detail: "After you press Play, lay a fingertip flat over the back camera and "
                    + "flash; the torch lights your skin and Echoel reads your heartbeat "
                    + "from it. Hold still and soft — it locks within seconds and tells you "
                    + "when you can let go. A Bluetooth chest strap (Polar and similar) is "
                    + "the most accurate source and frees your hands: choose it from the "
                    + "pulse pill's source menu. An Apple Watch works via Health, a few "
                    + "seconds behind. The order matters: the camera only starts with the "
                    + "music, so a finger before Play reads nothing."
            ),
            LearnEntry(
                id: "guide.access", section: .guide,
                title: "For every body",
                summary: "Hearing, seeing or feeling — any one of them is a way in.",
                detail: "The three channels above are deliberately redundant: the beat can be "
                    + "felt without being seen, the picture read without being heard, the "
                    + "music followed without the screen. VoiceOver speaks the primary "
                    + "controls, text follows your system size, numbers are typed on a large "
                    + "keypad instead of turned on tiny knobs, and Reduce Motion freezes the "
                    + "visual without stopping the music. If flashing light affects you, "
                    + "turn Reduce Motion on before you start."
            ),
        ]
    }

    /// Body metrics — straight from BioMetric (no duplicated copy).
    public static var bodyEntries: [LearnEntry] {
        BioMetric.allCases.map {
            LearnEntry(id: "body.\($0.rawValue)", section: .body,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Body science — the cited research behind the biofeedback loop (resonance
    /// breathing, HRV coherence, baroreflex). FACTS + self-observation, no claim;
    /// makes the strongest-evidence part of the product visible. See BioScienceInfo.
    public static var bodyScienceEntries: [LearnEntry] {
        BioScienceTopic.allCases.map {
            LearnEntry(id: "bodyScience.\($0.rawValue)", section: .bodyScience,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Music-theory primers — straight from MusicTheoryTopic.
    public static var musicEntries: [LearnEntry] {
        MusicTheoryTopic.allCases.map {
            LearnEntry(id: "music.\($0.rawValue)", section: .music,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Light & colour science — straight from LightScienceTopic (cited facts, no
    /// claim). Grounds Echoel's Light (Art-Net/sACN) + colour output in real
    /// wavelengths; see vision-gate (inspiration.csv) for the brand line.
    public static var lightEntries: [LearnEntry] {
        LightScienceTopic.allCases.map {
            LearnEntry(id: "light.\($0.rawValue)", section: .light,
                       title: $0.title, summary: $0.summary, detail: $0.detail)
        }
    }

    /// Safety & scope. TWO entries, and the first one exists for a reachability
    /// reason worth keeping in mind: `CLAUDE.md` mandates five safety warnings in the
    /// app, and four of them lived ONLY in `OnboardingView` — which renders while
    /// `hasCompletedOnboarding == false` and has no reset path. So every existing
    /// tester, every device restore and any reviewer on a second launch had NO way to
    /// reach "not while driving" or "not under the influence". The two strings written
    /// to solve that (`BioSourceView`, `SessionView`) are both in unreachable views.
    /// Putting them here gives them a permanent home: `LearnView` renders every
    /// section from `entries(for:)`, so this needs no new view and — importantly — no
    /// new `.sheet` (the modifier chain is at its metadata ceiling).
    /// Contraindications come FIRST; the scope note follows.
    public static var safetyEntries: [LearnEntry] {
        [
            LearnEntry(
                id: "safety.contraindications", section: .safety,
                title: "When not to use Echoelmusic",
                summary: "Four limits — read them once, they matter.",
                detail: "Do not use rhythmic audio-visual pacing while driving or "
                    + "operating machinery. Do not use it under the influence of "
                    + "alcohol or drugs. If you are using Echoelmusic alongside any "
                    + "therapeutic programme, coordinate it — and any medication "
                    + "timing — with your own provider; Echoelmusic is not part of a "
                    + "treatment and replaces nothing. Visuals are capped at 3 flashes "
                    + "per second (W3C WCAG) and freeze entirely with Reduce Motion on; "
                    + "if you are photosensitive, turn Reduce Motion on before you "
                    + "start. Stop if you feel unwell."
            ),
            LearnEntry(
                id: "safety.scope", section: .safety,
                title: "Self-observation, not diagnosis",
                summary: "What Echoelmusic’s biofeedback is — and is not.",
                detail: BioMetric.disclaimer
                    + " Bio readings are most accurate from a chest strap; wrist and "
                    + "camera are estimates. Breathing guides are optional and never forced."
            )
        ]
    }

    public static func entries(for section: LearnSection) -> [LearnEntry] {
        switch section {
        case .guide:       return guideEntries
        case .body:        return bodyEntries
        case .bodyScience: return bodyScienceEntries
        case .music:       return musicEntries
        case .light:       return lightEntries
        case .safety:      return safetyEntries
        }
    }

    /// Everything, section-ordered (Start Here → Body → Body Science → Music → Light → Safety).
    public static var all: [LearnEntry] {
        LearnSection.allCases.flatMap { entries(for: $0) }
    }
}
