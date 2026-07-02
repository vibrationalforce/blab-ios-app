# Strategy — USP, Market & Scope (Deep Research, 2026-06-12)

**Trigger:** Owner asked, brutally honest: "Ist wirklich alles drin? Feature Matrix
erweitern? Evaluiere USP. Zu viele Features oder realisierbar wie vorgestellt?
Was ist mit Wellenformen und Video Capture/Edit?"

**Method:** Code verification (what's REAL vs claimed) + 4 cited web-research streams
(bio-music competitors · immersive/lighting standards · iOS DAW landscape · USP/scope).
Citations captured below; some competitor figures from search snippets (flagged), a few
sites returned 403 to WebFetch.

---

## 1. What is REAL today (code-verified, not marketing)

**LIVE & strong (the moat):** bio-reactive synthesis (HR/HRV/breath/coherence → DDSP);
beat sequencer 8×16 + sampler; polyphonic piano roll; session clips + linear arrangement
+ bar-quantized launch; patch editor; hybrid sample+modal drums; FX chain; LUFS export;
open output **MIDI/MPE, OSC, ADM-OSC, Art-Net, sACN** (all wired); bio sources HealthKit
+ universal BLE HR + live camera rPPG; full VoiceOver on the DAW surface.

**NOT real (roadmap/skeleton/dormant), despite vision/website:**
- Video capture/edit/trim — **does not exist as a user feature.** `Video/CameraCapture.swift`
  is rPPG pulse only; `Video/ShortContentRenderer.swift` (generative 9:16 bio-MP4) is dormant,
  NOT wired into the UI.
- Audio **waveform display** — none in the production UI (sample browser, clips, arrangement).
- **Multitrack recording** — only `MultiTrackRecorder()` skeleton instantiated in AudioEngine.
- **RTMP live-streaming** — absent (no HaishinKit, no stream code).

## 2. Market & competitors (cited)

Real-time biosignal → playable synth + MIDI/OSC/light has **no shipping commercial occupant**
— white space, but the *idea* is 35+ yrs old (BioMuse 1988–90) and academically active
(arXiv 2505.03073, 2025). Funded players all occupy **wellness/consumption**, not
performance/instrument:
- **Endel** — HR-reactive generative soundscapes (passive). ~$22M raised, ~$15.8M rev '25,
  UMG deal '23, ~$120/yr. No MIDI/OSC/light. https://endel.io/technology
- **Muse/InteraXon** — EEG meditation, **$60M Oct 2025**. Adjacent = possible *input* device.
- **HeartMath Inner Balance** — HRV **coherence** training, ~$79/yr. Owns "coherence" mindshare
  → never claim we invented it. https://www.heartmath.com/coherenceplus/
- **Brain.fm** — functional focus music, **no biometrics**, $69.99/yr.
- "Biotunes" / "Sonic Bloom" = **not real products** → drop from any deck.

## 3. Output standards — where the moat really is (cited)

1. **Plain OSC = the lingua franca** of TouchDesigner/Max/installation art. `/echoelmusic/bio/*`
   is the highest-value, lowest-friction output. No app bridges HealthKit-bio → OSC for TD/Max
   today (GyrOSC = motion only). **This is the sharpest unserved gap.**
2. **ADM-OSC = most defensible** — spec v1.0 only formalized AES Show 2024, broad pro adoption
   (L-ISA/d&b/DiGiCo/Dolby/Nuendo), almost no consumer-priced sources.
   https://immersive-audio-live.github.io/ADM-OSC/
3. **sACN (HAVE IT) > Art-Net (HAVE IT, commodity).** Echoel is already where pro lighting moves.
4. **MIDI 2.0 = drop as marketing**; **MPE** is the real expressive target.

Buyers = pro/prosumer installation artists, theaters, immersive-audio engineers — **low tens of
thousands globally**, project-based, pay $600–2600 for tools (TouchDesigner/Notch/Resolume).
Prestige-niche, NOT a mass App-Store hit. Named lineage to position to: Lisa Park, Laura Jade,
Jason Snell, Krista Kim.

## 4. iOS DAW landscape — the decisive finding (cited)

Every successful solo/indie iOS music app wins via **"one paradigm, deep" + deliberately NO
video/streaming**: Koala (sampler/constraint, ~$4), Drambo (modular, ~$25), Loopy Pro
(loop/clip, $30), AUM (mixer/host, ~$20) — all **one-time purchase**, none touch video/RTMP.
Above them sits free GarageBand. Sources: synthtalk.net (Koala/Bereza), beepstreet.com (Drambo),
loopypro.com, kymatica.com (AUM).
→ Echoel's "one paradigm" = **bio-as-controller spine**. Video/RTMP/multitrack = the breadth that
sinks indie focus. **Pricing mismatch flagged:** instrument buyers pay once; Echoel currently
ships a subscription (`EchoelStore`) — wellness/Apple pattern, not instrument-buyer pattern.

---

## DECISION / RECOMMENDATION

**Cut from the vision (do NOT build):** in-app video capture/editor, RTMP encoder, full
multitrack DAW. They are commodity, huge effort, and dilute the moat (GarageBand/CapCut/OBS win).

**Deepen the ONE paradigm (build, in order):**
1. **Waveform display** (sample browser + clips) — cheap hygiene, high "real-DAW" feel, low risk.
2. **Bio→OSC/ADM-OSC as a real product:** savable mapping presets/scenes + in-app
   "Connect to TouchDesigner/Max/Resolume" help — turns the raw output into the sellable wedge.
3. **Revive bio-driven generative visuals** (ShortContentRenderer + the Metal BioVisualRenderer,
   rewired to EngineBus off the deprecated SoundscapeEngine) → output via NDI/Syphon to Resolume,
   NOT an in-app encoder.

**Marketing honesty:** lead with OSC + ADM-OSC; Art-Net/sACN = table-stakes; drop MIDI-2.0 and
"we invented coherence" claims; drop phantom competitors. Position to the installation-artist
lineage, not mass consumer. Re-examine subscription vs one-time pricing.

**One-line strategy:** *Be the scientifically-cleaned human body as a live, open-standard object
source for sound, light, and image — and cut everything that doesn't serve that sentence.*
