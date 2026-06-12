// PatchLibrary.swift
// Echoel — the large, curated factory sound library behind "browse a big preset
// database + use them as starting points for prompts". Each entry is a tuned
// SynthPatch with a category and mood/genre tags, stable ids (so user vs factory
// stays distinguishable across relaunch). Pure data; no audio, no SwiftUI.

import Foundation

/// A factory preset with browsing metadata.
public struct LibraryPatch: Identifiable, Sendable, Equatable {
    public var patch: SynthPatch
    public var category: String
    public var tags: [String]
    public var id: UUID { patch.id }

    public init(_ patch: SynthPatch, category: String, tags: [String]) {
        self.patch = patch
        self.category = category
        self.tags = tags
    }
}

public enum PatchLibrary {

    /// Stable UUID for a factory preset index (so ids survive relaunch).
    private static func sid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000B%04d", n)) ?? UUID()
    }

    public static let categories: [String] =
        ["Pads", "Keys", "Bells", "Plucks", "Leads", "Bass", "Drones", "Textures"]

    /// Presets in a category, preserving library order.
    public static func presets(in category: String) -> [LibraryPatch] {
        all.filter { $0.category == category }
    }

    /// Fuzzy search over name + tags + category.
    public static func search(_ query: String) -> [LibraryPatch] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { lp in
            lp.patch.name.lowercased().contains(q)
                || lp.category.lowercased().contains(q)
                || lp.tags.contains { $0.lowercased().contains(q) }
        }
    }

    public static let all: [LibraryPatch] = [
        // MARK: Pads
        LibraryPatch(SynthPatch(id: sid(1), name: "Calm Resonance",
            attack: 0.8, decay: 1.0, sustain: 0.9, release: 3.0,
            harmonicity: 0.92, brightness: 0.22, noiseLevel: 0.01,
            spectralShape: "dark", filterCutoff: 240, reverbMix: 0.35, reverbDecay: 3.0),
            category: "Pads", tags: ["meditation", "warm", "calm", "ambient"]),
        LibraryPatch(SynthPatch(id: sid(2), name: "Breath Pad",
            attack: 1.2, decay: 0.8, sustain: 0.85, release: 4.0,
            harmonicity: 0.8, brightness: 0.35, noiseLevel: 0.05,
            spectralShape: "natural", filterCutoff: 800, reverbMix: 0.4, reverbDecay: 4.0),
            category: "Pads", tags: ["airy", "soft", "meditation"]),
        LibraryPatch(SynthPatch(id: sid(3), name: "Aurora",
            attack: 0.6, decay: 1.5, sustain: 0.8, release: 3.5,
            harmonicity: 0.7, brightness: 0.6, noiseLevel: 0.02,
            spectralShape: "bright", filterCutoff: 3000, filterLFORate: 0.2,
            lfoToFilterDepth: 0.3, reverbMix: 0.45, reverbDecay: 4.5),
            category: "Pads", tags: ["evolving", "wide", "cinematic"]),
        LibraryPatch(SynthPatch(id: sid(4), name: "Velvet",
            attack: 0.9, decay: 1.0, sustain: 0.88, release: 3.2,
            harmonicity: 0.95, brightness: 0.18, spectralShape: "dark",
            filterCutoff: 320, reverbMix: 0.3, reverbDecay: 2.8),
            category: "Pads", tags: ["warm", "lush", "deep"]),

        // MARK: Keys
        LibraryPatch(SynthPatch(id: sid(10), name: "Glass Keys",
            attack: 0.02, decay: 0.8, sustain: 0.4, release: 1.2,
            harmonicity: 0.85, brightness: 0.6, spectralShape: "bright",
            filterCutoff: 4000, reverbMix: 0.25, reverbDecay: 1.5),
            category: "Keys", tags: ["glassy", "clean", "bright"]),
        LibraryPatch(SynthPatch(id: sid(11), name: "Warm Rhodes",
            attack: 0.01, decay: 1.2, sustain: 0.5, release: 1.0,
            harmonicity: 0.9, brightness: 0.4, spectralShape: "natural",
            filterCutoff: 2200, reverbMix: 0.2, vibratoRate: 4, vibratoDepth: 0.08),
            category: "Keys", tags: ["warm", "mellow", "classic"]),
        LibraryPatch(SynthPatch(id: sid(12), name: "Music Box",
            attack: 0.005, decay: 1.5, sustain: 0.1, release: 2.0,
            harmonicity: 0.7, brightness: 0.75, spectralShape: "bell",
            filterCutoff: 6000, reverbMix: 0.35, reverbDecay: 2.5),
            category: "Keys", tags: ["delicate", "bright", "nostalgic"]),

        // MARK: Bells
        LibraryPatch(SynthPatch(id: sid(18), name: "Glass Bell",
            attack: 0.01, decay: 1.5, sustain: 0.2, release: 3.0,
            harmonicity: 0.6, brightness: 0.8, spectralShape: "bell",
            filterCutoff: 6000, reverbMix: 0.45, reverbDecay: 3.5),
            category: "Bells", tags: ["glassy", "shimmer", "meditation"]),
        LibraryPatch(SynthPatch(id: sid(19), name: "Temple Bell",
            attack: 0.005, decay: 2.5, sustain: 0.1, release: 4.0,
            harmonicity: 0.5, brightness: 0.55, spectralShape: "bell",
            filterCutoff: 3500, reverbMix: 0.5, reverbDecay: 5.0),
            category: "Bells", tags: ["metallic", "deep", "ritual"]),
        LibraryPatch(SynthPatch(id: sid(20), name: "Crystal",
            attack: 0.01, decay: 1.8, sustain: 0.15, release: 2.8,
            harmonicity: 0.65, brightness: 0.9, spectralShape: "bright",
            filterCutoff: 8000, reverbMix: 0.4, reverbDecay: 3.0),
            category: "Bells", tags: ["glassy", "sharp", "icy"]),

        // MARK: Plucks
        LibraryPatch(SynthPatch(id: sid(26), name: "Soft Pluck",
            attack: 0.005, decay: 0.3, sustain: 0.0, release: 0.5,
            harmonicity: 0.9, brightness: 0.5, spectralShape: "natural",
            filterCutoff: 2400, reverbMix: 0.2, reverbDecay: 1.2),
            category: "Plucks", tags: ["plucky", "clean", "gentle"]),
        LibraryPatch(SynthPatch(id: sid(27), name: "Koto",
            attack: 0.003, decay: 0.6, sustain: 0.0, release: 0.8,
            harmonicity: 0.8, brightness: 0.6, noiseLevel: 0.02,
            spectralShape: "natural", filterCutoff: 3200, reverbMix: 0.25),
            category: "Plucks", tags: ["organic", "bright", "eastern"]),
        LibraryPatch(SynthPatch(id: sid(28), name: "Harp Pluck",
            attack: 0.004, decay: 1.0, sustain: 0.0, release: 1.4,
            harmonicity: 0.92, brightness: 0.55, spectralShape: "natural",
            filterCutoff: 4000, reverbMix: 0.3, reverbDecay: 1.8),
            category: "Plucks", tags: ["delicate", "warm", "acoustic"]),

        // MARK: Leads
        LibraryPatch(SynthPatch(id: sid(34), name: "Bright Lead",
            attack: 0.02, decay: 0.3, sustain: 0.7, release: 0.6,
            harmonicity: 0.95, brightness: 0.7, spectralShape: "bright",
            filterCutoff: 4500, filterResonance: 0.2, vibratoRate: 5, vibratoDepth: 0.15),
            category: "Leads", tags: ["bright", "expressive", "vibrato"]),
        LibraryPatch(SynthPatch(id: sid(35), name: "Mellow Flute",
            attack: 0.08, decay: 0.4, sustain: 0.8, release: 0.7,
            harmonicity: 0.88, brightness: 0.45, noiseLevel: 0.06,
            spectralShape: "natural", filterCutoff: 2600, vibratoRate: 5, vibratoDepth: 0.1),
            category: "Leads", tags: ["airy", "mellow", "breath"]),
        LibraryPatch(SynthPatch(id: sid(36), name: "Sync Lead",
            attack: 0.01, decay: 0.2, sustain: 0.75, release: 0.4,
            harmonicity: 0.6, brightness: 0.85, spectralShape: "bright",
            filterCutoff: 5000, filterResonance: 0.35, lfoToFilterDepth: 0.25, filterLFORate: 0.3),
            category: "Leads", tags: ["sharp", "evolving", "electronic"]),

        // MARK: Bass
        LibraryPatch(SynthPatch(id: sid(42), name: "Deep Sub",
            attack: 0.01, decay: 0.3, sustain: 0.9, release: 0.4,
            harmonicity: 0.98, brightness: 0.1, spectralShape: "dark",
            filterCutoff: 160, harmonicLevel: 0.9, reverbMix: 0.05),
            category: "Bass", tags: ["deep", "clean", "sub"]),
        LibraryPatch(SynthPatch(id: sid(43), name: "Warm Bass",
            attack: 0.01, decay: 0.4, sustain: 0.7, release: 0.5,
            harmonicity: 0.9, brightness: 0.25, spectralShape: "dark",
            filterCutoff: 400, filterResonance: 0.2, reverbMix: 0.05),
            category: "Bass", tags: ["warm", "round", "analog"]),
        LibraryPatch(SynthPatch(id: sid(44), name: "Gritty Bass",
            attack: 0.005, decay: 0.3, sustain: 0.75, release: 0.4,
            harmonicity: 0.7, brightness: 0.4, noiseLevel: 0.08,
            spectralShape: "natural", filterCutoff: 700, filterResonance: 0.3),
            category: "Bass", tags: ["gritty", "electronic", "punchy"]),

        // MARK: Drones
        LibraryPatch(SynthPatch(id: sid(50), name: "Deep Drone",
            attack: 1.5, decay: 1.0, sustain: 1.0, release: 5.0,
            harmonicity: 0.95, brightness: 0.15, spectralShape: "dark",
            filterCutoff: 220, reverbMix: 0.4, reverbDecay: 6.0),
            category: "Drones", tags: ["meditation", "deep", "dark", "huge"]),
        LibraryPatch(SynthPatch(id: sid(51), name: "Singing Bowl",
            attack: 1.0, decay: 2.0, sustain: 0.9, release: 6.0,
            harmonicity: 0.55, brightness: 0.4, spectralShape: "bell",
            filterCutoff: 1800, reverbMix: 0.5, reverbDecay: 7.0),
            category: "Drones", tags: ["meditation", "metallic", "ritual"]),
        LibraryPatch(SynthPatch(id: sid(52), name: "Cosmic Drift",
            attack: 2.0, decay: 1.5, sustain: 0.95, release: 5.5,
            harmonicity: 0.75, brightness: 0.5, noiseLevel: 0.04,
            spectralShape: "bright", filterCutoff: 2500, filterLFORate: 0.1,
            lfoToFilterDepth: 0.4, reverbMix: 0.5, reverbDecay: 6.5),
            category: "Drones", tags: ["evolving", "wide", "cinematic"]),

        // MARK: Textures
        LibraryPatch(SynthPatch(id: sid(58), name: "Wind Bed",
            attack: 1.0, decay: 1.0, sustain: 0.8, release: 3.0,
            harmonicity: 0.4, brightness: 0.5, noiseLevel: 0.2,
            noiseColor: "pink", spectralShape: "natural", filterCutoff: 1500,
            filterLFORate: 0.15, lfoToFilterDepth: 0.3, reverbMix: 0.4),
            category: "Textures", tags: ["airy", "noise", "ambient"]),
        LibraryPatch(SynthPatch(id: sid(59), name: "Static Field",
            attack: 0.5, decay: 1.0, sustain: 0.7, release: 2.5,
            harmonicity: 0.3, brightness: 0.6, noiseLevel: 0.3,
            noiseColor: "white", spectralShape: "bright", filterCutoff: 4000,
            filterResonance: 0.3, filterLFORate: 0.4, lfoToFilterDepth: 0.4, reverbMix: 0.35),
            category: "Textures", tags: ["gritty", "evolving", "experimental"]),
        LibraryPatch(SynthPatch(id: sid(60), name: "Shimmer Cloud",
            attack: 0.8, decay: 1.5, sustain: 0.75, release: 4.0,
            harmonicity: 0.8, brightness: 0.8, noiseLevel: 0.03,
            spectralShape: "bright", filterCutoff: 6000, reverbMix: 0.55, reverbDecay: 5.0),
            category: "Textures", tags: ["glassy", "wide", "lush"])
    ]
}
