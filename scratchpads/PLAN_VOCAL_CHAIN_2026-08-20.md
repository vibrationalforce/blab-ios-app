# PLAN — Vocal Chain (Founder-Ask 2026-08-20)

> "Monitoring und komplette Vocal chain mit Autotune (Charakter Einstellungen), Harmonizer,
> Voice clone!?, Granular Effekt. On Device, mit Interface per Kabel und auch per Bluetooth.
> Alle Latenzen und Kombinationen optimiert für Sessions"

**PLAN ONLY — no code in this cycle.** Every claim below carries the command or the
`file:line` that produced it. Measured 2026-08-20 against `3a54a08`.

---

## 0. ⭐ FOUNDER-UPDATE 2026-08-25 — dieser Plan ist AKTIVIERT, mit einer Änderung

Wörtlich: *"No Voice clone. Monitoring soll Direct on Device funktionieren, latenzfrei und mit
intelligenter Harmonizer und Granular Synthese Effekt Strategie für immersive Musik Erfahrung.
… resourcen sparende Strategie, vermeide Fehler."*

Folgen für die Slices unten: **Voice clone ist NEIN** (Zeile in §1 damit erledigt, nicht mehr
offen) · der Council-Gate-Zusatz "neither before V0 returns" ist vom Founder ÜBERSTIMMT — der
BAU läuft, **V0 bleibt die Hör-Bestätigung** · die #669-Mechanik (AU-Insert, null Zusatz-
Latenz) ist durch "latenzfrei" noch einmal bestätigt · "ressourcenschonend" heißt kleine
Slices mit Pflicht-Review, kein Agent-Feuerwerk. **#822** hat die Pflicht-Vorstufe gebaut:
`EchoelFXChain.processInPlace` (Pointer-Einstieg für den AU-Render-Block), Wächter
`TheChainPointerEntryMatchesTheArrayEntryTests` im blockierenden Bundle.

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

### V0's exact recipe — measured 2026-08-24 (#783), not remembered

This section existed for four days naming NEITHER the door nor the log lines, so the one
instruction that blocks the whole founder ask could not be executed from the file that owns it.
Every string below is copied from source, not retyped — see the ⚠️ at the end for why that
sentence is load-bearing.

**The two doors, both real** (`showInput` has THREE writers; two are findable by a human):
- `mixerPanel` → the card titled **`Voice · your microphone`** → button **`Choose input…`**
  (`EchoelStudioView.swift:3719`). The card's own `Monitor` toggle is a *second* control for
  the same state — the founder does not need it.
- `masterPanel` → **`Audio input`** (`EchoelStudioView.swift:4855`). Same sheet.
- (Third writer: `PlugInInviteRow` at :2008 — appears only when a plug-in is detected.)

**Inside the sheet** (`AudioInputPickerView`) the switch is labelled **`Live monitoring`**
(:143). That is the one toggle V0 asks for.

**The log door:** `Save & Export` panel → **`Diagnostics`** (`EchoelStudioView.swift:8191`).

**What the log will say.** Every line carries the greppable stem `monitor: `
(`AudioEngine.logMonitorOutcome`, :1792 — one message, two sinks, #416):

| line | meaning |
|---|---|
| `monitor: ON (gain G, SR Hz, N ch)` | it worked; the `latency:` line right after is its cost |
| `monitor: OFF` | clean shutdown |
| `monitor: mic permission denied at the dialog` | refused at the prompt |
| `monitor: mic permission previously denied — Settings is the only door` | needs Settings |
| `monitor: session upgrade failed (…)` | `.playAndRecord` claim refused |
| `monitor: input format unusable after the session claim (…) — #628` | 0 Hz / channel-count bail |
| `monitor: engine restart failed (…)` | the graph did not come back |
| `monitor: session downgrade failed (…)` | only on the way OFF, warning-level |
| `monitor: re-arm (…)` | a route change re-armed it |

**No line at all** is itself the answer: the toggle never reached the engine.

⚠️ **A one-character needle nearly turned this correct instruction into a reported defect.**
The shipped release note writes `Voice - your microphone` with a HYPHEN; the code has
`Voice · your microphone` with a MIDDLE DOT, so `grep` returned zero and the door read as
non-existent. **Copy a user-facing label out of the source; never retype it.** Same family as
the `\b`-less needle that matched 283 files at #779.

**V1 — the FX chain reaches the microphone.** One `EchoelFXChain` instance as a monitor
insert between `notchEQ` and `monitorMixer`, driven from a mic-owned preset (NOT the synth's —
two owners of one chain is the #416 shape). This single slice delivers harmonizer, reverb,
delay, saturation, compressor and limiter on the voice, because they are already written.
· Risk: **two owners.** The mic chain and the synth chain must not share a preset object.

### V1's mechanism — the fork is RESOLVED (#669, measured 2026-08-20)

This bullet used to read "an `AVAudioSourceNode`-style block **or** an `AVAudioUnit`" and
left the choice open. It is decided, on a measured latency ground rather than taste, because
the founder's ask is literally *"alle Latenzen und Kombinationen optimiert für Sessions"*.

**First, a correction I owe the plan.** I had registered the blocker as *"`EchoelFXChain` is a
generator, not an insert"*. **That is wrong.** `processBuffer(left:right:frameCount:)` is an
**in-place** processor — it takes buffers and rewrites them, sample by sample through
`processStereo`, with `advanceFilterGlide` once per block. It only *looks* generative because
its one production caller (`PolySynthVoice`) hands it scratch buffers it has just synthesised.
The chain has been insert-shaped all along; what is missing is a NODE to host it.

Equally worth stating, because it changes the size of V1: **the monitor path is already a real
insert rail.** `input → notchEQ (AVAudioUnitEQ) → [voiceTunePitch (AVAudioUnitTimePitch)] →
monitorMixer`, and the autotune brain (`VoicePitchCorrector` → `appliedCents`) already drives
that pitch node. Autotune with character controls is SHIPPED and doored ("Tune to key",
strength, retune). V1 is not "build a vocal chain"; it is "add one node kind to a rail that
runs".

**Option A — `AVAudioSourceNode` fed from the mic tap through a lock-free ring. REJECTED.**
Precedent exists (`MetronomeVoice`, `SessionEngine`, plus `AudioEngine.attachSourceNode`), and
the tap→ring→consumer shape exists too (`MonitorTapWindow`, `RGBSampleQueue`). It is the
cheapest thing to build and the wrong thing to ship:
  · it ADDS latency by construction — one tap buffer plus one render quantum. The monitor tap
    is installed at `bufferSize: monitorTapWindow.size` = **2048 frames ≈ 43 ms at 48 kHz**.
    Even re-tapped at 256 frames it is ~5 ms on top of a floor that is ~9 ms. Adding half
    again to the number the app now prints on screen, in the slice that answers a
    latency-optimisation request, is the wrong direction.
  · the signal would LEAVE the graph and re-enter it, so the direct connection has to be cut
    or both paths sound at once — a second lifecycle owner on a chain that already had one
    (the BLE-3 lesson, one owner per resource).

**Option B — an `AUAudioUnit` subclass hosting the chain. CHOSEN.** A true in-graph insert,
sitting exactly where `notchEQ` sits, with **zero added latency**. Honest costs, stated:
  · **No precedent in this repo** — `git grep -n "class .*: AUAudioUnit\|registerSubclass\|
    AVAudioUnit.instantiate" -- Sources` returns nothing. The only custom-AU-adjacent code is
    Apple's own `kAudioUnitSubType_PeakLimiter` via `AVAudioUnitEffect` (`AutoMixChain:113`).
    This is a first-of-its-kind mechanism and should be its own slice before any DSP rides on it.
  · The contract is fiddly: bus arrays, `allocateRenderResources`, an `internalRenderBlock`
    that must be allocation- and lock-free, and an async `AVAudioUnit.instantiate`.
  · **One small API addition is required and is not optional.** The render block receives an
    `AudioBufferList`, not Swift `Array`s, so `processBuffer(left: inout [Float], …)` cannot be
    called from it without a copy. `EchoelFXChain` needs a pointer entry point —
    `processInPlace(left: UnsafeMutablePointer<Float>, right:, frameCount:)` — doing exactly
    what `processBuffer` does (glide once per block, then `processStereo` per sample). Same
    law, one definition, no scratch buffer, no memcpy (#416).

**Option C — Apple nodes only** (EQ, TimePitch, Distortion, Reverb, Delay). Cheapest and it
ships today, but it cannot deliver the harmonizer or the granular stage the founder named, and
those are the two the repo's own DSP already has. Rejected as an answer to the ask, though it
stays the correct answer for anything Apple genuinely covers.

**Council (compact).** Architect: one node kind, at the place a node already sits — no new
coupling. DSP Purist: `processStereo` is already allocation- and lock-free; the pointer entry
point keeps it that way and adds no second definition. Skeptic: the AU contract is the risk,
not the DSP — build the empty pass-through AU and prove it in the graph BEFORE any stage rides
on it. Shipper: V0 still gates whether any of this can be HEARD; do not start V1 code before
one founder log. User-Advocate: the latency number is now on his screen, so a mechanism that
inflates it would be visibly self-contradicting.
**Gate: proceed to V1 as TWO slices — V1a an empty pass-through `AUAudioUnit` insert proven in
the monitor chain, V1b the chain riding it — and neither before V0 returns.**

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

---

## 6. ⭐ FORTSCHRITT 2026-08-26 — V1b ist GETEILT und die erste Hälfte ist gebaut (#839)

Leiter-Stand, gemessen: **V0** Monitoring läuft am Gerät (v424-Logs: `monitor: ON … insert
in`; der OFF-Absturz ist mit v425/#836 repariert, Geräteprobe offen) · **V1a** ✅
gerätebewiesen · **#822 processInPlace** ✅ · **V1b-1 ✅ (#839): die mic-eigene
`EchoelFXChain` reitet den Insert — NEUTRAL.** Alle 15 Stufen-Flags explizit aus (die
Werks-Defaults Saturation/Chorus/Limiter=AN sind Synth-Tuning und würden den Sänger als
Nebenwirkung färben), Ausgang bit-exakt = Eingang, per E2E-Wächter durch den echten
Render-Block bewiesen (`TheMonitorInsertCarriesTheNeutralChainTests`, umbenannt aus
`…IsAnEmptyPassThroughTests`, #374). Zweck der Neutral-Stufe: der nächste Geräte-Log
attribuiert Knacksen/CPU sauber der KETTE, bevor irgendetwas hörbar wird.

**V1b-2 (offen, nächste Scheibe):** eine hörbare Stufe + Tür — mic-eigenes Preset
(NIE das Synth-Preset, ein Besitzer), Bedienung in `AudioInputPickerView` (bestehendes
Sheet, Sheet-Kette wächst nicht), Start-Kandidat: Harmonizer mit „Follow the key"-Anbindung
an die Tonart. Danach V2 (Latenz-Budget sichtbar) → V3 (BT-Verhalten) → V4 (echte
Granular-Stufe in der Kette, landet damit automatisch auch auf der Stimme).
