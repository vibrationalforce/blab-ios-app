> ## ⚠️ SUPERSEDED — 2026-07-25
>
> This document describes the **"Digital Multidimensional Multimedia Workstation"**
> goal set on 2026-06-21. It is **no longer the product target.**
>
> The workstation half (arrangement/clips timeline as home, channel rack, AUv3
> hosting, video-as-clip) was dismantled by founder verdict #121 (2026-07-24,
> "REINES INSTRUMENT"). The multidimensional-output half survives — as the
> instrument's **output stage**, not as a product of its own. The term "DMMW" is
> retired: it was unrepeatable, it put a solo developer on DAW turf, and it made
> the maintenance surface infinite.
>
> **Canonical replacement: [`PRODUCT_DEFINITION.md`](PRODUCT_DEFINITION.md).**
>
> Kept below as history only — do not plan from this file.

# Echoel DMMW — Digital Multidimensional Multimedia Workstation

**Goal (founder):** the first and long-term best **biofeedback-driven, multi-touch
DMMW** — FL Studio Mobile's intuitive workflow + clean AUv3 hosting (the thing FL
lacks and Cubasis/Zenbeats/AUM do but cluttered) + Echoel's bio core, where a musician
shapes **video, visuals, light, laser, spatial sound** by **musical parameters**.

## The one idea that makes it coherent
**One typed signal bus; many media subscribe.** Echoel already has `EngineBus`
(bio control-plane + lock-free SPSC). The DMMW generalizes it: the bus carries BOTH
**bio** AND **musical parameters**, and every medium (audio, visuals, light, video,
spatial) is a *subscriber* that maps those signals to its own domain. "Design visuals/
light by musical parameters" = the renderers read the music params off the bus. No
point-to-point wiring; add a medium = add a subscriber.

## Layered structure

# IA priority (founder, 2026-06-21): the ARRANGEMENT / CLIPS timeline is the HOME view
# (foreground), like pro workstations. Clips are typed — Audio · MIDI · Video · Visual —
# and live/edited in the main view. Piano Roll is secondary (opens to edit a MIDI clip).
# Biofeedback is just ONE TOOL, not the center. The one-button bio-compose flow becomes
# a clip generator/tool, not the home screen.

```
L5  WORKSPACE (IA)        HOME = Arrangement / Clips timeline (typed clips: Audio·MIDI·
                          Video·Visual), pro-workstation style. Secondary (edit a clip):
                          Piano-Roll, Sound, FX. Tools (a tool each, not the center):
                          Biofeedback/Well, Channels, Mix, Visual, Light. Only working
                          areas shown; persistent compact nav, nothing buried.
        │
L4  MEDIA RENDERERS       Audio master · Visuals (MetalBioView + SpectralColor +
    (subscribers)         oscilloscope) · Light (EchoelLux/Art-Net) · Spatial (ADM-OSC) ·
                          Video (roadmap). Each maps bus signals → its domain.
        │
L3  THE BUS (backbone)    EngineBus carries:
                          • BioFrame (HR, HRV, coherence, breath, motion)  ✅ live
                          • MusicalFrame (current notes/chord, key, tempo, section,
                            per-track level/transient, master spectrum)    ← to build
        │
L2  CHANNELS / RACK       FL-style channel rack. Each channel = an INSTRUMENT
                          (built-in voice OR hosted AUv3) + insert FX (built-in
                          EchoelFXChain OR hosted AUv3). Add-channel picker like FL's,
                          plus an "AUv3 Instrument / Effect" category.    ← AUv3 host arc
        │
L1  TRANSPORT / TIMELINE  One clock, one arrangement (sections/clips/patterns). Shared
                          by audio AND every other medium so visuals/light/video run on
                          the same musical time.  (Transport T1, ArrangementStore,
                          PatternEngine, ClipStore exist; unify under one transport.)
                          ✅ Metronome (self-driving click, accented downbeat) + tap
                          tempo + master EBU R128 loudness readout (LUFS/dBTP/LRA) —
                          production/performance staples, in the Composition + Master panels.
```

## The AUv3 solution (FL workflow + clean hosting)
- **Hosting** (host other devs' AUv3 in a channel): `AVAudioUnitComponentManager`
  discovery → instantiate `AVAudioUnit` → insert into the channel's node graph →
  embed the plugin's `requestViewController` UI in an Echoel-framed sheet → round-trip
  `fullState` for save/recall. Audio-thread rules apply (no work in the render path
  beyond the AU itself). This is a real multi-cycle engineering arc, tracked as its own
  pillar — NOT claimed until it ships.
- **Workflow** (why it stays clean where Cubasis/AUM don't): AUv3s live INSIDE the
  channel rack as just another instrument/effect — same chip, same panel vocabulary
  (`EchoelPanel`, `EchoelValueField`) — instead of a separate cluttered host surface.
  The FL "two-column add" (channel type → instrument) gains an "AUv3" column.

## Music → multimedia mappings (the differentiator)
The MusicalFrame (L3) drives the renderers (L4):
- **pitch/chord → colour**: `SpectralColor` (OKLab, octave-equivalent hue, chord =
  additive mix) ✅ built — feeds Visual + Light.
- **tempo/section → motion/scene**: visual pace + light cues follow the arrangement.
- **per-track level/transient → element reactivity**: drums punch the visual, bass
  drives low-freq fields ("novel oscilloscope", cycles E/F).
- **key/mode → palette/mood**; **spatial object positions (ADM) → 2D visual field**
  via `HilbertSensorMapper` (channel→locality) — "multidimensional".
- **bio (breath/coherence/HR) → the same renderers** — biofeedback is always a
  co-modulator, never bolted on.

## Build order (each a shippable cycle, deploy between)
1. **IA shell** ✅ — `WorkspaceView`: persistent surface switcher (Arrange · Clips ·
   Compose), Arrangement/Clips the foreground HOME, the bio-compose instrument hosted
   as one Compose surface. All surfaces stay mounted (ZStack+opacity) so Compose's audio
   lifecycle is untouched. (Earlier step: front-page tools bar.)
2. **EchoelPanel everywhere** — EFX + all surfaces on the shared panel vocabulary.
3. **MusicalFrame on the bus** ✅ — pure type tested; the piano roll publishes the live
   chord each tick (pitch→Hz, velocity→amplitude, key/scale/tempo context). Consumers
   wired: (a) a live "Music → colour" swatch via SpectralColor (Compose ▸ Visual); (b)
   the immersive MetalBioView now colours from the loudest LIVE note (tracks the melody,
   not a static tonic); (c) **Light (Art-Net/sACN) + Spatial (ADM-OSC) now driven by the
   music** when sounding (MusicMediaMap: chord→DMX colour via SpectralColor, pitch→ADM
   azimuth/elevation, level→distance/gain), bio as fallback co-modulator.
4. **Audio-reactive engine (E/F/G)** — analyzer → visual/light; per-stem; spatial.
5. **AUv3 host** — channel-rack instrument/effect hosting (its own pillar).
   - ✅ **Discovery** (`Audio/AUv3Host.swift`, Tools ▸ Plugins): lists the Audio
     Unit instruments + effects installed on the device (AVAudioUnitComponentManager),
     split/de-duped/sorted. Read-only, no graph changes — the safe first slice.
   - ✅ **Instrument load + play**: tap an instrument → `AVAudioUnit.instantiate` →
     `AudioEngine.attachAUNode` (connects to masterMixer; pause/attach/restart like
     `attachSourceNode`) → play it from a preview keyboard (host-MIDI
     `scheduleMIDIEventBlock`). User-driven, launch-silent. `HostedAUInfo` now carries
     the component OSType codes so a unit can be re-instantiated.
   - ✅ **Live composition → hosted instrument**: the piano roll / song fans every
     note on/off to the hosted AU (same shared MainActor `onTick` as Echoel's own
     voices + MIDI Out), so a loaded plugin plays the composition, not just the
     preview keys. No-op until a plugin is loaded.
   - ✅ **Use-plugin-instead toggle**: `AUv3Host.replaceBuiltInVoice` (persisted) —
     when on with a plugin loaded, the song drives ONLY the plugin (the built-in
     poly + sub voices are gated off in `PianoRollModel.trigger`), no doubling.
     Note-offs always fire so toggling mid-play never sticks a note.
   - ✅ **Effect insert chain (device chain)**: tap effects to build an ordered insert
     chain on the hosted instrument's channel (instrument → fx[0] → fx[1] → … →
     master), Ableton-device-chain style. `AudioEngine` chain primitives
     (`withGraphPaused`, `attachAU`/`detachAU`, `connectAU`/`connectAUToMaster`);
     `AUv3Host` holds `effectUnits: [AVAudioUnit]` and `connectChainNow()` relinks the
     whole chain on add/remove (per-effect remove by index). Chain stays unconnected
     until an instrument feeds it. Kept off Echoel's own mix path.
   - ✅ **Plugin's own UI**: “Open” on a loaded instrument/effect presents the
     plugin's native interface in an Echoel-framed sheet (`AUv3PluginUIView`
     wraps `AUAudioUnit.requestViewController` as a `UIViewControllerRepresentable`;
     off-main completion hops to MainActor; honest "no custom UI" fallback).
   - ✅ **State save/recall (`fullState`)**: a plugin's complete settings are saved
     (UserDefaults, keyed by plugin id, plist-guarded) on unload / replace / app
     background, and recalled onto a freshly-instantiated unit on load — a hosted
     plugin returns exactly as you left it across sessions.
   - ✅ **External MIDI-in → built-in + hosted instrument**: `MIDIBusPublisher` is
     now started at launch (it was orphaned — never started) and forwards CoreMIDI
     note on/off to the hosted AUv3 instrument (host-MIDI) as well as the bus; the
     built-in voice is gated off when "use plugin instead" is on. A connected MIDI
     keyboard plays the plugin.
   - ✅ **Master-bus FX**: hosted AUv3 effects on the MASTER bus (process the whole
     mix), inserted mainMixer → mfx[0] → … → output via `AudioEngine.rewireMasterFX`;
     `AUv3Host.loadMasterEffect`/`unloadMasterEffect` + `masterEffectUnits`. Empty-by-
     default → the default output wiring is NEVER touched until the first master effect
     (zero-risk to normal builds). Browser: an "Effect target: Channel / Master" picker
     routes a tapped effect; the loaded bar lists the master chain (Open/Remove).
6. **Domain renderers** — light/laser/spatial/360/video, each shown only when live.
7. **Universal Signal Router (patchbay)** — intelligent routing for ALL channels,
   app-internal + in/out, every protocol (MIDI · MIDI 2.0 · MPE · Audio · OSC · ADM ·
   Art-Net/sACN · AUv3 · Video/Visual roadmap). Founder ask 2026-06-21.

## The Signal Router (universal patchbay)
**One typed patchbay over Ports; many protocols plug in.** Generalizes — does NOT
replace — `EngineBus` topics + voices/renderers (INTERNAL ports), the CoreMIDI / OSC /
ADM-OSC / Art-Net / sACN / BLE / Camera bridges (EXTERNAL ports), and `ModulationMatrix`
(the control→control projection).
- **`SignalKind`** (what flows): controlBio · controlMusical · controlMacro · note ·
  controlChange · audio · light · spatial · clock · (video · visual = roadmap, `isLive=false`).
- **`SignalTransport`** (where it lives, with honest `status` live/roadmap): internalBus ·
  coreMIDI · midi2 (+MIDI-CI) · mpe · rtpMIDI · osc (+OSCQuery) · admOSC · artNet · sacn ·
  audioIO · auv3 · abletonLink · bleHRS · camera · healthKit · rtmp · srt · ndi. Smarter
  layers: MIDI-CI (param auto-discovery), OSCQuery (remote param typing), Ableton Link (clock).
- **`SignalPort`** (kind + direction source/sink + transport, stable id) · **`SignalRoute`**
  (source→sink + amount + converter) · **`ConverterCatalog`** (the "intelligent" part:
  allowed cross-kind transforms — bio→CC, pitch/chord→colour, pitch→ADM position, …).
- **`SignalGraph`** — pure inventory + type-aware `check`/`connect`/`suggestedConnections`.
- Status: ✅ pure core + tests (`Core/SignalRouting.swift`); ✅ live holder
  `SignalRouter` (real endpoint inventory + persisted routes); ✅ **Patchbay UI**
  (`Studio/PatchbayView.swift`, Tools ▸ Routing — tap-to-connect, smart auto-patch,
  honest live/soon status); ✅ first adapter Music/Bio→Light&Spatial; ✅ **outputs come
  online ON DEMAND from the patchbay** — a connection to MIDI Out / OSC / ADM / Art-Net /
  sACN starts that sender (idempotent), the last connection removed stops it (these were
  unreachable before — no Sync tab in the single-view IA). ✅ **MIDI-in started at
  launch** (was orphaned) → built-in voice + hosted AUv3 instrument; ✅ **MIDI in→out
  thru** (a midi.in → midi.out patchbay route echoes external notes to MIDI out). ✅
  AUv3 hosting (its own pillar above). 🟡 **Broadcast (RTMP/SRT)** — scaffold in:
  `rtmp.out`/`srt.out` router sinks + `BroadcastPublisher` (persisted URL/key/protocol,
  honest "engine not installed" state, on-demand start via the patchbay). The real
  HaishinKit A/V capture path lands as an isolated, gate-verified cycle.

## Guardrails
- iPhone-first, multi-touch. Brand: claim only what ships (no dead category buttons).
- Audio-thread rules (no locks/alloc in render); bus snapshot for slow signals, SPSC
  for fast. Uncodixfy CI (EchoelPanel/EchoelValueField, ≤3 Hz flash, no glow).
- Protected Rausch triad untouched. Every cycle: build → test → ship → device feedback.
