# PLAN — Vocal Chain (Founder-Ask 2026-08-20)

> "Monitoring und komplette Vocal chain mit Autotune (Charakter Einstellungen), Harmonizer,
> Voice clone!?, Granular Effekt. On Device, mit Interface per Kabel und auch per Bluetooth.
> Alle Latenzen und Kombinationen optimiert für Sessions"

**PLAN ONLY — no code in this cycle.** Every claim below carries the command or the
`file:line` that produced it. Measured 2026-08-20 against `3a54a08`.

---

## 1. What already exists (and the founder cannot see)

| Ask | State | Evidence |
|---|---|---|
| Monitoring | Engine wired, door reachable | `AudioEngine.setInputMonitoring`, `AudioInputPickerView` |
| **Autotune + character** | **BUILT AND DOORED** | `VoicePitchCorrector` (pure, allocation-free: `key`, `a4Hz`, `strength`, `retuneSpeed`); UI at `AudioInputPickerView.swift:236-255` — "Tune to key" + **Amount** + **Tune**, with "1.00 is the classic hard-snap" copy |
| Harmonizer | BUILT, **wrong bus** | `DSP/EchoelHarmonizer.swift`; reached only through `EchoelFXChain` |
| Granular | Machinery only, no stage | `EchoelHarmonizer` is "a granular/delay-line shifter" (`:15`). There is NO standalone granular effect |
| Interface (cable / BT) | Classified + warned | `AudioInputPickerView` prints "~150–250 ms" and names the route |
| **Voice clone** | **ZERO** | `git grep -lni "voice clone\|CoreML\|\.mlmodel" -- Sources` → nothing |

### The architectural fact that decides the whole plan

The monitor chain is **three nodes**:

```
inputNode → notchEQ (feedback guard) → [voiceTunePitch] → monitorMixer → masterMixer
```
(`AudioEngine.swift:1843-1853`)

`EchoelFXChain` — harmonizer · reverb · delay · chorus · saturation · bitcrush · widener ·
compressor · limiter · filter · tape · flanger · phaser · tremolo, **15 stages** — is
constructed at exactly two places, and **neither is the microphone**:

```
git grep -n "EchoelFXChain(" -- Sources
  Tools/BioReactiveSynthVoice.swift:154
  Tools/PolySynthVoice.swift:333
  (+ two FXCuratedLibrary previews)
```

**The complete vocal chain is one connection away from the microphone and nobody has made it.**
That is the good news in this plan: the DSP is written, audio-thread-clean by construction
(it already runs in the render path of two voices), and tested.

---

## 2. The blocker that comes first

Everything above is behind the **Live monitoring** toggle, and on build 2531 that toggle
refuses ("Monitoring could not start — try again") — measured from the founder's own clip
at 13:43:49, inside his diag-log window.

**A chain whose first link does not close is not a chain.** #650 made the refusal name itself
in the file the founder exports; it did not fix it. Slice 0 is therefore: ship #650, get one
diag log with a `monitor:` line, and repair the exit it names.

Ordering this first is not caution — it is the only way the next four slices can be *heard*.

---

## 3. Ordered slices

**V0 — the refusal names itself.** Deploy `3a54a08`, one founder take, read the `monitor:`
line, fix that exit. Nothing below is testable before this.

**V1 — the FX chain reaches the microphone.** One `EchoelFXChain` instance as a monitor
insert between `notchEQ` and `monitorMixer`, driven from a mic-owned preset (NOT the synth's —
two owners of one chain is the #416 shape). This single slice delivers harmonizer, reverb,
delay, saturation, compressor and limiter on the voice, because they are already written.
· Audio-thread: the chain's `processBuffer` already runs in a render path; the insert must be
  an `AVAudioSourceNode`-style block or an `AVAudioUnit`, allocation-free, no locks.
· Risk: **two owners.** The mic chain and the synth chain must not share a preset object.

**V2 — per-stage latency, stated not guessed.** The founder asked for "alle Latenzen und
Kombinationen optimiert". The honest form is a measured budget the UI *shows*:
| Source | Latency | Status |
|---|---|---|
| IO buffer in + out | `setPreferredIOBufferDuration` (`AudioConfiguration.swift:149`) — iOS may grant something else (`AudioEngine.swift:1179`) | measurable on device |
| notch EQ | one biquad, no added delay | known |
| pitch stage | `AVAudioUnitTimePitch` — inherent, **unmeasured here** | device probe |
| harmonizer | delay-line shifter, `maxDelaySeconds: 0.12` (`EchoelHarmonizer.swift:55`); the *used* grain delay is smaller | needs the read, not the max |
| BT output | ~150–250 ms | physics, not tunable |
Deliverable: one live "monitor latency" readout, per active stage, from real values.

**V3 — Bluetooth stops being a warning and becomes behaviour.** Today the app *tells* the
user BT monitoring is loose. Better: when the output route is high-latency, monitoring
defaults OFF with one line saying why, and recording stays untouched — BT records fine. The
copy for this already exists at `AudioInputPickerView.swift:259`.

**V4 — a real granular stage.** This is the only item the founder named that has no DSP at
all. `EchoelHarmonizer`'s delay-line machinery is the starting point, not the feature.
New stage in `EchoelFXChain`, so it lands on both the voice and the synth for free.

---

## 4. Voice clone — FOUNDER-GATED, and this is the measured cost

There is no code, no CoreML import, no `.mlmodel` anywhere in `Sources/`. Shipping it means:

- **A dependency posture change.** `Package.swift` has `dependencies: []`; the repo's rule is
  ZERO external deps. An on-device converter means either a bundled model (tens of MB in the
  app, App Store size + review) or CoreML plus a trained model we do not have.
- **A privacy surface.** Capturing a person's voice to build a model of it changes the
  privacy nutrition label and `PrivacyInfo.xcprivacy`, and needs the App Store
  Release-Compliance seat before submission.
- **A latency question it may not survive.** Neural voice conversion is frame-based with a
  lookahead; "optimiert für Sessions" and "voice clone in the monitor path" may be
  incompatible. It could be an OFFLINE (post-take) effect instead — a different product.

**Not blocking the rest.** V1 designs the insert point so a converter is one more stage; that
costs nothing today and is good architecture regardless. The decision is needed only when V4
is done.

---

## 5. Council

· **Architect** — the chain is a synth insert; making it a mic insert is one node, but two
  owners of one preset is the trap. Separate preset object, or it drifts.
· **DSP Purist** — proceed: `EchoelFXChain` is already audio-thread-clean in two render
  paths. The pitch and harmonizer stages carry inherent delay; state it, do not hide it.
· **Skeptic** — "alle Latenzen optimiert" is unfalsifiable as written. V2 turns it into a
  number on screen, which is the only version that can be wrong.
· **User-Advocate** — the founder is asking for things he already owns. That is a
  DISCOVERABILITY failure as much as a feature gap: Amount and Tune sit behind a toggle that
  refuses.
· **Shipper** — V0 then V1. V1 alone delivers three of the five named features.

**Gate: proceed with V0 → V1 → V2 → V3 → V4. Voice clone holds for the founder's word,
and holding it blocks nothing.**
