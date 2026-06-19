// CommunityLibrary.swift
// Echoel — loads community-curated presets bundled under Resources/Community/
// into the in-app libraries. This closes the community loop: a submission ->
// GitHub issue -> triage Action opens a PR that drops JSON here -> merging it
// ships the preset, and it appears in-app on the next build.
//
// Best-effort by design: a missing folder or a bad file yields an empty list,
// so the app ALWAYS falls back to the built-in curated set — never a crash,
// never a regression. (If SwiftPM/Xcode flatten the resource subdirectory, the
// lookup simply returns nil and we degrade gracefully; the SPM bundling is
// covered by CommunityLibraryTests so a flatten shows up in CI, not silently.)

import Foundation

public enum CommunityLibrary {

    /// Bundled community FX presets (`Resources/Community/fx/*.json`).
    public static let fx: [FXPreset] = load("Community/fx", as: FXPreset.self)

    /// Bundled community synth patches (`Resources/Community/patches/*.json`).
    public static let patches: [SynthPatch] = load("Community/patches", as: SynthPatch.self)

    /// Decode every `*.json` in a bundled subdirectory; skip anything that fails.
    static func load<T: Decodable>(_ subdir: String, as type: T.Type) -> [T] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: subdir) else {
            return []
        }
        let decoder = JSONDecoder()
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
    }
}
