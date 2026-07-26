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

    /// Anchor purely so `Bundle(for:)` can name "the bundle holding this module's
    /// own compiled code" — a plain enum has no class identity to ask with.
    private final class BundleAnchor {}

    /// Candidate bundles to search, in order. `Bundle.module` exists only under
    /// SwiftPM (`SWIFT_PACKAGE`). Outside that, neither `Bundle.main` nor
    /// `Bundle(for: BundleAnchor.self)` is guaranteed to be "the bundle with
    /// Resources/Community" in every hosted-unit-test configuration — two
    /// project.yml bundling fixes had zero measurable effect on the CI failures
    /// this exists to fix, and the CI log channels available couldn't confirm
    /// which bundle Xcode actually resolves at runtime here, so try both rather
    /// than assume one (2026-07-21).
    /// `internal` (not `private`) purely as a TEST SEAM — see `allJSONURLs`.
    static var candidateBundles: [Bundle] {
        #if SWIFT_PACKAGE
        return [.module]
        #else
        // Dedup on bundleURL, not ObjectIdentifier/instance identity — Bundle has no
        // real Equatable contract, only an internal path-based instance cache that
        // usually (but isn't guaranteed to) collapse repeats; a missed collapse here
        // would silently double-decode every preset (same URL scanned twice), not
        // just waste a scan.
        var seen = Set<URL>()
        var candidates: [Bundle] = []
        for b in [Bundle.main, Bundle(for: BundleAnchor.self)] where seen.insert(b.bundleURL).inserted {
            candidates.append(b)
        }
        return candidates
        #endif
    }

    /// Every `.json` URL found under any candidate bundle's `resourceURL`, walked
    /// once and shared across all loaders (fx/patches/moods) rather than a
    /// separate full tree scan per subdirectory.
    ///
    /// `internal`, not `private`, as a deliberate TEST SEAM. `CommunityLibraryTests`
    /// has been red in CI since the suite was first wired, and TWO project.yml
    /// bundling guesses had zero measurable effect because nothing could observe
    /// which link of the chain actually breaks — the summary step surfaces only the
    /// `Test case '<name>' failed` line, never the assertion message that carries the
    /// diagnosis. `CommunityBundleDiagnosisTests` therefore asserts each link in its
    /// OWN test method, so the failing NAMES alone say where the chain breaks. Those
    /// tests must measure THIS array, not a re-implementation of the walk: a replica
    /// can diverge from the real loader and answer a question nobody asked.
    static let allJSONURLs: [URL] = {
        var urls: [URL] = []
        for bundle in candidateBundles {
            guard let root = bundle.resourceURL,
                  let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "json" {
                urls.append(url)
            }
        }
        return urls
    }()

    /// Decode every `*.json` whose immediate parent-directory chain ends with
    /// `subdir`'s path components, in order (e.g. ".../Community/fx/x.json"
    /// matches subdir "Community/fx" regardless of what precedes "Community").
    /// Matching by path SUFFIX (rather than `Bundle.urls(subdirectory:)`, which
    /// depends on Xcode preserving an exact top-level bundle path) is robust to
    /// wherever the `type: folder` resource reference actually resolves.
    static func load<T: Decodable>(_ subdir: String, as type: T.Type) -> [T] {
        let wanted = subdir.split(separator: "/").map(String.init)
        guard !wanted.isEmpty else { return [] }
        let decoder = JSONDecoder()
        return allJSONURLs
            .filter { url in
                let parentComponents = url.deletingLastPathComponent().pathComponents
                guard parentComponents.count >= wanted.count else { return false }
                return Array(parentComponents.suffix(wanted.count)) == wanted
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
    }
}
