# PLAN — Layer-0 Instrument Home (vision Step 1)

**Founder vision, law #1:** "app open, finger on camera, in 3 seconds it lives and
glows, no menu/setup." Today the app opens into the DAW chrome (header · transport ·
composition strip · timeline · studio), and the living instrument floats as a small
picture-in-picture. This inverts that: **the living instrument is the HOME; the DAW
is behind a button.**

## Key discovery (why this is tiny, not a rewrite)

The vision is ALREADY built + wired in `FloatingVisualWindow`:
- renders the single `MetalBioView` (bio-reactive living visual — the GPU "one Metal
  path app-wide" instance),
- overlays `TouchInstrumentView` at EVERY size (playable multitouch: X=scale-degree,
  Y=octave, area+pressure=velocity, quantized into the key, voiced by `touchSynth`),
- has WAV + MP4 record → Share sheet (the shareable-clip pipeline),
- already supports a `.fullscreen` size that covers the whole chrome ("true Vollbild",
  WorkspaceView.swift:128-135).

It just OPENS at `.small`, docked bottom-trailing. Building a new `InstrumentHomeView`
would create a SECOND `MetalBioView` → violates the one-Metal-path rule. So the correct
minimal slice is to **present the existing fullscreen visual as the opening layer.**

## The slice (3 files, reversible, nothing deleted)

1. `Core/FeatureFlags.swift`
   - add `case instrumentHome = "feature.instrumentHome"`
   - add `static var instrumentHome: Bool { isOn(.instrumentHome) }`

2. `EchoelmusicApp.swift` (~line 448, beside the other registrations)
   - `UserDefaults.standard.register(defaults: [FeatureFlags.Key.instrumentHome.rawValue: true])`
   - DEFAULT-ON via registration (same pattern + rationale as multiRoll/voiceKindRouting):
     a default-OFF flag with no UI to flip it is an un-verifiable deadlock. `set(.instrumentHome,
     false)` stays the one-line rollback lever; the OFF path is bit-identical (old behavior).

3. `Studio/WorkspaceView.swift`
   - add `@AppStorage("visual.floating.size") private var floatingSizeRaw` (same key
     FloatingVisualWindow uses) + `@State private var didSeedInstrumentHome = false`.
   - `.onAppear` on the root ZStack: once per launch, if `FeatureFlags.instrumentHome`,
     set `floatingVisualVisible = true` and `floatingSizeRaw = WindowSize.fullscreen.rawValue`.
     Guard the WindowSize reference under `#if canImport(MetalKit) && canImport(UIKit)`.

## Render-safety compliance (skill: swiftui-render-safety)

- **Sheet chain:** FloatingVisualWindow owns ONLY its own 2 share sheets, NOT part of
  EchoelStudioView's ~18-modal chain. Presenting it fullscreen adds NO sheet to
  EchoelStudioView. ✅
- **10 Hz ancestor read:** the seed uses only @AppStorage (low-freq) + a @State bool +
  a flag read. NO bio/playhead read added to WorkspaceView.body. ✅
- **One Metal path:** still exactly ONE MetalBioView (the FloatingVisualWindow instance).
  No duplication. ✅
- **No teardown:** the DAW VStack stays the first ZStack child (mounted, just covered);
  EchoelStudioView never disappears → no stopEverything → the live session (bio +
  transport) survives while the fullscreen instrument is up. ✅

## Why seed (not just a first-run default)

An active per-launch seed writes fullscreen+visible regardless of the persisted value,
so it demonstrates on the founder's EXISTING install (a pure first-run default would only
affect fresh installs — invisible to device-verify). Guarded once-per-launch by a @State
bool (survives background/foreground), so a user who contracts to the DAW mid-session is
NOT re-fullscreened until the next cold launch. Reversible: flag OFF → the old
"remember last floating size" behavior returns untouched.

## Verify

- `swift build` is NOT the gate (CI is truth): xcode-compile-check.yml + ci.yml.
- Mandatory reviewer before commit: ui-state-reviewer (SwiftUI state-flow + the two
  ship-blocker laws) + code-reviewer.
- Device-verify (founder): app opens into the fullscreen living instrument; playing with
  a finger sounds notes; the contract button drops to the DAW; the session keeps running
  across the toggle.

## Follow-ups (NOT this slice)

- 1b: a clearly-labeled "Studio" cue on the fullscreen visual (if the contract glyph
  isn't discoverable enough after device-verify).
- Step 2: cold-start choreography (camera prompt → pulse lock → first tone).
- Step 3: close the clip loop (record button already exists; ring-buffer "last 20s").
