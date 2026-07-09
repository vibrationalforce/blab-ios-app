# Echoel Tool Naming Map (founder-confirmed 2026-07-09)

Founder directives, reconciled:
- "alle Tools EchoelToolname" (brand CI) +
- "benenne die Tools so, wie du sie in der Programmiersprache nennst" +
- Chosen direction (AskUserQuestion 2026-07-09): **"Klare Namen, Code angleichen"**
  → UI keeps CLEAR labels; CODE types adopt those clear names + `Echoel` prefix
  for genuine engines/tools. Execute **incrementally, one tool per cycle**
  (Ralph Wiggum), like `SpaceReverb → EchoelSpaceReverb` (already done, 7efbc66).

## Scope rule (unchanged policy)
Prefix `Echoel*` for **engines / tools / DSP cores** (the taxonomy). Leave
**value types**, **`*View` SwiftUI screens** (Apple idiom), and **`*Sender`
interop** plain — a `*View` is a screen, not a tool. The "tool" is the engine
behind it; the UI label reflects the taxonomy.

## The EchoelTools taxonomy (source of truth — matches docs/faq.html)
LIVE today: EchoelSynth · EchoelGen · EchoelFX · EchoelMIDI · EchoelBio ·
EchoelNet · **EchoelVis** (GPU bio-visuals = MetalBioView) · EchoelLux.
Planned: EchoelMix · EchoelVid · EchoelStage · EchoelAI.

## Flagship (play surface) — RESOLVED
- **EchoelVis is NOT free** — it is the established name of the *visuals* tool
  (MetalBioView: looks, HR→pulse, coherence→hue, breath→spread; the mapping /
  video-organisation surface the founder remembered). So the play surface can
  NOT be called EchoelVis, and "EchoelVistouch" would blur into it.
- The **play surface** is where EchoelSynth (sound) and EchoelVis (visual) meet
  under the finger → a *touch instrument*. Its default voice is already
  **"Echoel Touch"** (patch, 0b2cc6f). → Canonical name: **EchoelTouch**.
  - Code today: `TouchInstrumentView` / `TouchInstrumentUIView` (Studio/).
  - Per the scope rule these are `*View` screens → they may stay `*View`, but
    the INSTRUMENT concept is "EchoelTouch"; UI label
    "Visual Touch Instrument" → **"EchoelTouch"** (or "Echoel Touch").
  - AWAIT founder nod on the exact spelling (EchoelTouch vs "Echoel Touch").

## Incremental rename backlog (one per cycle; UI label in quotes stays clear)
| UI label today | Code type today | Action (Option A) |
|---|---|---|
| "Visual Touch Instrument" | TouchInstrumentView | → label "EchoelTouch"; instrument = EchoelTouch |
| "Sound" | PatchEditorView | engine = EchoelSynth patch; view stays PatchEditorView; label ok |
| "Routing" | PatchbayView | label ok; type is a screen (leave) |
| "Coherence" (id "meditation") | MeditationView | **fix id "meditation"→"coherence"** (vision: meditation framing retired 2026-07-06B); view → CoherenceView optional |
| "Visual" | MetalBioView | tool = **EchoelVis**; view stays MetalBioView |
| "Plugins" | AUv3BrowserView | label ok (screen) |
| "Broadcast" | BroadcastView | tool = EchoelStage (planned); label ok |
| already-aligned | PianoRollView, AutomationView, AudioClipView, LearnView | no change |

Done so far: `EchoelSpaceReverb` (7efbc66). Highest-value NEXT increments:
(1) id "meditation"→"coherence" (also a vision correctness fix), (2) confirm +
apply the **EchoelTouch** flagship label.

Do NOT big-bang. Each rename = its own cycle, green build/test, like reverb.
