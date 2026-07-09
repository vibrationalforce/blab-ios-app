# Deep Audit + History Revision — Syng.Visibra → Echoel (2026-07-09)

Founder input: the 4 Syng.Visibra concept docs + "zu wenig von der ursprünglichen
Idee übrig … komplett Musik produzieren (Voice clone / Gregorian Harmonizer /
Hackbrett) für Audio/Video/MIDI-MPE/Visual Editing … digital only … alles aus
Apple-Hardware herausholen … Ableton, DaVinci Resolve, TouchDesigner, Resolume,
OBS abhängen in EINER auv3-Host-UND-Plugin App mit Biofeedback … Echoel muss
AUv3 hosten UND selbst als AUv3/IAA in FL Studio, AUM eingebunden werden können."

## History revision — where the idea came from
Syng.Visibra (Förderantrag) = inclusive interactive music platform, 3 parts:
Syng (app: AI music, AI voice synthesis, biofeedback viz, live sessions, DAW +
spatial audio + visuals + distribution, colour-music octave system), a VR headset
(bone-conduction, EEG, spatial audio, brainwave screen), and Visibra (water/light/
sound installation). Grant-scale (€1.0–1.55M, 2yr), wellness/therapy/medical-
diagnostic framing, VR-first, cloud-AI.

**What deliberately changed since (all founder-driven, logged in memory):**
- Wellness/therapy/medical framing → **science-first instrument, NOT wellness**
  (brand rule; the deep-research brief 2026-07-09 hard-codes the do-not-claim list).
- VR headset + Visibra hardware → **digital only, iPhone-first**, "get everything
  out of Apple hardware" (founder, today). VR/EEG/installation = NORTH STAR, not now.
- Cloud AI → **on-device** (privacy; EchoelAI = CoreML roadmap).
- Breathing-exercise/coherence-training centre → **bio-generative performance
  instrument** (2026-07-06B pivot).

## Deep audit — original Syng feature → today
| Syng concept feature | Status in Echoel today |
|---|---|
| AI music generation (chords→melody, beats) | **LIVE** — BioComposer/EchoelGen, 6 curated genres, bio-driven |
| Biofeedback visualization (HRV/coherence) | **LIVE** — EchoelBio + EchoelVis (MetalBioView) |
| Colour-music octave system | **LIVE** — SpectralColor/CIE-1931 (Echoel's own mapping) |
| DAW (clips/arrange/patch/MIDI export) | **LIVE** — PianoRoll, Clips, Arrangement, PatchEditor, MIDI 2.0/MPE |
| Spatial audio | PARTIAL — ADM-OSC object out LIVE; on-device spatial render = roadmap |
| **AUv3 HOST (host other plugins)** | **SUBSTANTIALLY BUILT** — `Audio/AUv3Host.swift`: enumerate, instantiate instrument+FX, insert into engine, MIDI to hosted inst, persist. UI = AUv3BrowserView. Needs: device-verify, polish, surfacing. |
| **Echoel AS AUv3 plugin** | SCAFFOLD — `EchoelmusicAUv3` target (383 lines) exists, **deferred/not shipping**. Needs: finish + ship so FL Studio/AUM/Logic can load Echoel. |
| AI voice synthesis / **voice clone** | ABSENT — no vocal engine. Voice CLONING = heavy ML + consent/legal. |
| **Gregorian/monastic harmonizer** | ABSENT — VocoderCore is a tested-but-unwired core; a pitch/formant harmonizer + choir is a contained DSP build. |
| **Hackbrett** (unified multi-touch A/V/MIDI/visual surface) | PARTIAL — EchoelTouch play surface (finger→note+visual) is the seed; "drives video/MIDI/light too" = roadmap. |
| Video capture/NLE editing (DaVinci-class) | ABSENT — EchoelVid roadmap; no recorder/trim/NLE. |
| Node visuals (TouchDesigner) / VJ (Resolume) | PARTIAL — EchoelVis looks + VJ overlay + Art-Net/sACN LIVE; node graph = roadmap. |
| Live streaming (OBS-class) | ABSENT — BroadcastPublisher compile-scaffold, HaishinKit not linked. |
| Live sessions / collaboration | PARTIAL — MultipeerConnectivity "Live Colabo" present; OSC/ADM-OSC LIVE. |
| Inclusion / multilingual / avatars | ABSENT/roadmap — English only today; accessibility work ongoing. |

## The honest strategic read
"Beat Ableton + DaVinci + TouchDesigner + Resolume + OBS in one app" — matching
each incumbent feature-for-feature is many years each. That is a NORTH STAR, not a
plan, and chasing it is how the focus got diluted. **The winnable wedge is the ONE
thing none of them has: biofeedback-driven, on one Apple device, as BOTH an AUv3
host AND an AUv3 plugin.** That makes Echoel INTEROPERATE with the incumbents
(host their instruments/FX; run Echoel inside their DAWs) instead of trying to
replace all of them — the pragmatic, achievable, differentiated path. Interop first,
replacement never.

## Vision-gate tiers (for the re-incorporation asks)
- **AUv3 host + Echoel-as-AUv3 plugin (the keystone)** → **ADOPT→PRODUCT.** On-vision,
  iOS-native, mostly already built, the single highest-leverage move. Sequence as its
  own multi-cycle workstream: (1) device-verify + harden the existing host, surface it
  cleanly; (2) finish + ship the `EchoelmusicAUv3` plugin so FL Studio/AUM/Logic load
  Echoel; (3) parameter/state/preset round-trip both directions. **Note on IAA:** Apple
  DEPRECATED Inter-App Audio; the modern, App-Store-safe path to "Echoel inside FL
  Studio/AUM" is the AUv3 plugin, not literal IAA — ship AUv3, not IAA.
- **Gregorian/choir harmonizer (EchoelVoice-lite, no cloning)** → **WATCH→likely ADOPT.**
  Contained DSP (pitch-shift + formant + diffuse choir) atop the existing chain; on-brand
  as a sound tool; wire the dormant VocoderCore. Medium effort, high character payoff.
- **Voice clone** → **WATCH/ROADMAP.** Heavy on-device ML + consent/impersonation/legal
  risk; needs a deliberate ethics + model decision before any build.
- **Video NLE / OBS streaming / node visuals** → **ROADMAP/NORTH STAR.** Each is large;
  EchoelVid/EchoelStage/Broadcast already named as roadmap; do NOT start speculatively.
- **VR headset / EEG / Visibra installation** → **NORTH STAR.** Off the digital-only path
  the founder confirmed today; keep parked.

## Recommended next concrete cycle (when founder greenlights)
**AUv3 keystone, step 1:** device-verify `AUv3Host` end-to-end (load a real third-party
AUv3 instrument + effect into a channel, play it, embed its UI, persist), fix what breaks,
and surface "Plugins" as a first-class, honest entry. This turns an already-built-but-
buried capability into a shippable headline — the biggest vision-return per cycle, and it
is the literal thing that lets Echoel "host AUv3 and sit in the chain with Ableton et al."
