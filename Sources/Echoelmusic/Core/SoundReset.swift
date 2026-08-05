//
//  SoundReset.swift
//  Echoelmusic — Core
//
//  ⭐ THE ONLY COMPLETE SOUND RESET THIS APP HAD WAS DELETING IT (#400).
//
//  On 2026-08-05 the founder reported the instrument playing "schief" (out of tune) and then
//  that DELETING AND REINSTALLING the app cured it. Same binary either side of that, so the
//  cause was a value PERSISTED ON THE DEVICE — and the only remedy available to a player was
//  the one that also destroys every saved patch, take and project they own. That is not a
//  reset, it is an amputation, and it is what this file replaces.
//
//  ⭐ ONE LIST, TWO CONSUMERS. The entries below are keyed by the LABEL each value carries in
//  the launch breadcrumb (`EchoelStudioView.logLaunchMusicalIdentity`, #401). That is not
//  decoration: #401 exists to make the next occurrence answerable from one log line, and this
//  file exists to make it fixable without a reinstall. They must describe the SAME set of
//  values or one of them is lying. `ResetSoundClearsWhatTheLaunchLineReportsTests` asserts
//  every label here is actually emitted there, so adding a value to one and not the other
//  fails the blocking bundle rather than shipping a half-reset.
//
//  ⛔ WHAT IT DELIBERATELY DOES NOT TOUCH, and why the boundary is drawn exactly here:
//  saved patches, projects, takes, the autosave slot and the artist name are the user's WORK.
//  A "reset" that eats those is the reinstall again, wearing a button. This clears the
//  instrument's musical IDENTITY — the settings that decide what a note sounds like — and
//  nothing else. The mix faders are a deliberate second question (#399 caught a bass fader
//  persisted at zero for a whole session); they are not in this slice, so do not describe
//  this as "resets everything".
//
//  ⚠️ REMOVING A KEY IS NOT THE SAME AS APPLYING ITS DEFAULT. Any value CACHED in a live object
//  keeps the old reading — `SessionContext` holds its three in stored properties read once at
//  init. The call site must push those back (see `SessionContext.resetMusicalIdentity()`);
//  clearing alone would leave the old A4 sounding until the next launch, which is precisely the
//  "it needed a reinstall" experience again.
//
//  ⛔ AND THE FIRST VERSION OF THAT PARAGRAPH OPENED WITH A CLAIM IT COULD NOT BACK: "`@AppStorage`
//  re-reads and falls back on its own". That the wrapper's GETTER synchronously re-reads the store
//  is observed behaviour, not documented contract — see the ⛔ block on
//  `EchoelStudioView.resetSoundToDefaults()` for what IS established (no `register(defaults:)`
//  covers these keys; `removeObject(forKey:)` posts KVO and is not the stale-making
//  `removePersistentDomain`) and what is not. Stating the unproven half as fact, in the file whose
//  own thesis is that a comment with a wrong rationale is worse than none, is the same defect one
//  register quieter.
//

import Foundation

/// The instrument's musical identity as a resettable set — the persisted values that decide
/// what a note sounds like, grouped by the name each carries in the launch breadcrumb.
public enum SoundReset {

    /// One reported value and every `UserDefaults` key it actually lives in.
    public struct Entry: Sendable {
        /// The label used in the launch breadcrumb, e.g. `tuning`. Pinned by the guard.
        public let label: String
        /// Every storage key that has to go for this value to be back at factory.
        public let keys: [String]

        public init(label: String, keys: [String]) {
            self.label = label
            self.keys = keys
        }
    }

    /// ⚠️ KEYS COME FROM THEIR OWNER WHERE AN OWNER EXISTS — `StudioDefaultKeys` for the shared
    /// preferences, `SessionContext.keyStorageKeys` / `a4StorageKey` for the two groups that type
    /// deliberately exposes. The THREE remaining string literals below are keys declared with a
    /// raw literal at their single use site in `EchoelStudioView`; repeating them here makes this
    /// the SECOND site (the THIRD, for `toneSystemID`, which `WorkspaceView` also declares raw).
    /// That duplication is the shape of defect `StudioDefaultKeys` exists to prevent, and the
    /// honest fix is promoting all three into that file — a separate slice, because it moves
    /// declarations in two views. Until then the guard scans `EchoelStudioView.swift` for each
    /// literal, so a rename there fails the blocking bundle instead of silently turning one line
    /// of this reset into a no-op.
    ///
    /// ⛔ TWO WRONG NAMES IN THIS PARAGRAPH FOR ONE COMMIT, both found in review. It cited
    /// `SessionContext.storageKeys`, WHICH DOES NOT EXIST — a reader following it finds nothing —
    /// and called the exposure "the session trio", when withholding the artist key is the entire
    /// point of the note beside it. And it said FOUR literals where its own guard iterates three.
    /// A wrong symbol and a wrong count, in the sentence that SCOPES a future slice.
    public static let entries: [Entry] = [
        Entry(label: "key", keys: [StudioDefaultKeys.rootIndex.key,
                                   StudioDefaultKeys.scale.key]
                              + SessionContext.keyStorageKeys),
        Entry(label: "tuning", keys: ["toneSystemID"]),
        Entry(label: "a4", keys: [SessionContext.a4StorageKey]),
        Entry(label: "genre", keys: [StudioDefaultKeys.genre.key]),
        Entry(label: "preset", keys: ["studio.presetIndex"]),
        Entry(label: "articulation", keys: ["studio.articulation"]),
        Entry(label: "bassRhythm", keys: [StudioDefaultKeys.bassRhythm.key]),
        Entry(label: "padRhythm", keys: [StudioDefaultKeys.padRhythm.key]),
        Entry(label: "touchPatch", keys: [StudioDefaultKeys.touchPatchID.key]),
        Entry(label: "glide", keys: [StudioDefaultKeys.touchGlide.key])
    ]

    /// Every key the reset clears, flattened. Order is the breadcrumb's order, which is the
    /// order a reader of the log will look for them in.
    public static var keys: [String] { entries.flatMap(\.keys) }

    /// Remove every musical-identity key. Idempotent, and safe on a store that never held
    /// them — `removeObject(forKey:)` on an absent key is a no-op, which is why a fresh
    /// install can run this without ending up in a different state than one that never did.
    ///
    /// Takes the store as a parameter so the guard can prove the behaviour against a scratch
    /// suite instead of the process's own defaults. Nothing here is `@MainActor`: it touches
    /// no view and no engine, and the caller owns re-applying what it cleared.
    public static func clear(in defaults: UserDefaults) {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
