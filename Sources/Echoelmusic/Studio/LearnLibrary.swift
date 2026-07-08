// LearnLibrary.swift
// Echoel — the single index behind the "app as a school" idea. Unifies the
// existing teaching content (bio metrics, music theory) plus a safety/scope note
// into one browsable, sectioned model, so a future "Learn" surface binds to ONE
// source instead of many silos. Pure Foundation, unit-tested. No new copy is
// invented here — it reuses BioMetric and MusicTheoryTopic verbatim.

import Foundation

public enum LearnSection: String, CaseIterable, Identifiable, Sendable {
    case body, music, light, safety

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .body:   return "Your Body"
        case .music:  return "Music Theory"
        case .light:  return "Light & Colour"
        case .safety: return "Safety & Scope"
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

    /// Body metrics — straight from BioMetric (no duplicated copy).
    public static var bodyEntries: [LearnEntry] {
        BioMetric.allCases.map {
            LearnEntry(id: "body.\($0.rawValue)", section: .body,
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

    /// The single safety/scope entry — reuses the shared disclaimer.
    public static var safetyEntries: [LearnEntry] {
        [LearnEntry(
            id: "safety.scope", section: .safety,
            title: "Self-observation, not diagnosis",
            summary: "What Echoelmusic’s biofeedback is — and is not.",
            detail: BioMetric.disclaimer
                + " Bio readings are most accurate from a chest strap; wrist and "
                + "camera are estimates. Breathing guides are optional and never forced."
        )]
    }

    public static func entries(for section: LearnSection) -> [LearnEntry] {
        switch section {
        case .body:   return bodyEntries
        case .music:  return musicEntries
        case .light:  return lightEntries
        case .safety: return safetyEntries
        }
    }

    /// Everything, section-ordered (Body → Music → Safety).
    public static var all: [LearnEntry] {
        LearnSection.allCases.flatMap { entries(for: $0) }
    }
}
