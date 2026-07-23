# ULTRAARCHITECTURE — Echoel target-map & canonical REIHENFOLGE (2026-07-23)

> **Why this document exists.** The founder asked: *"Macht es Sinn jetzt nochmal mit
> einem richtigen architektonischen Plan der alles abdeckt neu zu beginnen? Somit
> vermeiden wir Probleme die erst gekommen sind durch zu spätes hinzufügen der tasks."*
>
> **Answer: no code rewrite — this map instead.** The recent pain came not from a
> broken foundation but from tasks being *added late with no target-architecture to
> slot them into*. A blanket rewrite would throw away a TestFlight-green, device-
> confirmed, reviewer-verified system and manufacture fresh slop (Joel Spolsky, "never
> rewrite from scratch"). The fix is a **target-architecture map** every future task can
> be placed against, plus **one ranked REIHENFOLGE** — then the existing code converges
> toward it one verified Ralph slice at a time.
>
> **Method (honesty note).** Nine domain agents read the *real source* (CLAUDE.md
> treated as untrusted); every claim below is `file:line`-cited in the domain notes at
> `scratchpads/… (uamaps)`. This is a docs deliverable — it touched no `Sources/` file.

---

## 1. Executive summary — the state of the system

Echoel is a **single-spine, tracks-centric bio-reactive DAW** that ships to TestFlight
today (v10.79.345, both gates green). The architecture is genuinely sound where it
counts: **`EngineBus` is the one real coupling spine**, the protected Rausch triad is
intact, the audio-thread discipline holds (render-side bio via atomic mirrors, no COW),
and the pure-core pattern (DSP/bio math as tested value types) is consistent.

The gaps the map found are **not** "the architecture is wrong." They are three recurring
*shapes* of debt from features landing faster than the structure was tightened:

1. **Two-owner / two-model duplication.** Several concepts have two live implementations
   racing to converge: the song-timeline (legacy `ArrangementStore` vs new
   `TimelineStore`), the transport clock (`PatternEngine.onTick` vs `Transport`), voice
   ownership (app singletons vs `LaneVoiceRack`), routing (four overlapping matrices).
   Each was correct at introduction; none has finished the migration it started.
2. **Built-but-unwired cores.** Complete, tested components with zero live consumers:
   `BioSignalDeconvolver`, `HilbertSensorMapper`, the `BioEventGraph` heartbeat detector
   (fed `cleanedHeart:0`), `BioTempoDirector`, `VideoLanePlayer`, `EchoelCellular`,
   `CloudSyncEngine`, the `ProGate`/`EchoelStore` monetization surface.
3. **Aspirational-vs-enforced invariants.** Laws written in comments but not uniformly
   applied — most dangerously the **`decodeIfPresent` data-loss law**, which is honored
   on new fields but left open on the *identity* fields of the most-edited document, so a
   single rename can vaporize a user's whole song.

**The strategy is convergence, not reconstruction.** Every item in the REIHENFOLGE (§5)
moves the code from one of these shapes toward the single-owner target (§2), cheapest-
highest-value first, each a gated reversible Ralph slice.

---

## 2. Target architecture (the whole intended system, one picture)

```
                         ┌──────────────────────────────────────────┐
   BODY (sensors)        │            EngineBus  (the spine)          │
   ─────────────         │  @MainActor @Observable snapshots          │
   rPPG camera ─┐        │   · latestBio / latestBioEvent (poll)      │
   BLE 0x180D  ─┼─pub→   │   · controllerEvents  SPSC (MIDI, drained) │  →consumers
   HealthKit   ─┤        │   · bioEvents         SPSC (OSC, drained)  │
   Face (flag) ─┘        │   · bioFrames         (REMOVE — undrained) │
                         └──────────────────────────────────────────┘
   one source-selector owns publisher lifecycle (studio dropdown, NOT applyRouting)
        │                         │                        │
        ▼                         ▼                        ▼
   ModulationEngine          Transport (ONE clock)     Senders (one lifecycle owner
   bio→param via             owns the timer, drives    = the patchbay/applyRouting)
   ParameterApplyRouter      priority-ordered subs:    OSC · ADM-OSC · Art-Net · sACN
   (the ONE apply table)     audio→haptics→record      · [Broadcast when HaishinKit]
        │                         │                     all gate BioEgressPolicy,
        ▼                         ▼                     all share one flash/master law
   Voices (ONE ownership: per-lane LaneVoiceRack; singletons retire)
   PolySynth · SubBass · BioReactive · Sampler · third-party AUv3 (aumu, hostable)
        │
        ▼
   AudioEngine master bus → (target) master FX bus → out
        │
        ▼
   Persistence: AppGroupStore (one engine) · every doc has schemaVersion + the
   decodeIfPresent law on EVERY field · UserDefaults stores folded in · decode-fail telemetry
        │
        ▼
   VISUAL: ONE MetalBioView (enforced single mount) ← BioVisualParams (ONE body→look owner)
   LIGHT:  Art-Net + sACN, blackout-wins, flash ≤3Hz     VIDEO: one VideoLanePlayer coordinator
```

**The hard boundaries (must survive convergence):**
- **AUv3 DSP-isolation:** the appex compiles `Sources/Echoelmusic/DSP/` + 3 named `Core/`
  files *in isolation* (`project.yml:184-193`, `dependencies: []`). DSP/ files stay
  Core/Sequencer-free forever. **Target: make this machine-checked, not convention.**
- **BioEgressPolicy (App Store 5.1.3):** HealthKit/.watch/.oura frames never leave the
  device via any sender. **Target: the gate lives *inside* every sender (incl.
  `sendModulation` and Multipeer), never at a callsite a new caller can skip.**
- **Protected Rausch triad READ-ONLY** — map/wire, never simplify.
- **Audio thread:** lock/alloc/ObjC/GCD-free; bio applied render-side via mirrors.
- **No health/therapy/wellness claim; flash ≤3 Hz (WCAG); NaN-sanitized at every
  DSP/bio/persisted boundary.**

---

## 3. Cross-cutting invariants (master list — any future task must honor)

1. **One coupling spine.** New modules couple only via `EngineBus`; no new side-channels.
2. **Every persisted `Codable` field decodes non-destructively** (`decodeIfPresent`/
   tolerant + sensible default, `id`→`UUID()` fold) so a rename degrades one field, never
   the document. One corrupt element never vaporizes its array or doc.
3. **Every persisted-to-disk document carries a real `schemaVersion: Int`** with a
   forward-only migration hook (today: none do; `SpatialScene`'s version is wire-only).
4. **BioEgressPolicy gate lives inside the sender** — no HealthKit-derived data (raw or
   abstracted) egresses over OSC/ADM/Art-Net/sACN/Multipeer/Broadcast.
5. **One clock (`Transport`) owns the timer and orders all step consumers by priority.**
6. **One voice-ownership model** (per-lane rack); one apply table (`ParameterApplyRouter`).
7. **DSP/ files import only Foundation/Accelerate** (appex isolation).
8. **Audio thread:** no lock/malloc/ObjC/GCD/file-I/O; bio via atomic mirror render-side.
9. **Protected triad (BioEventGraph/HilbertSensorMapper/BioSignalDeconvolver) READ-ONLY.**
10. **Flash ≤3 Hz rate-based slews; blackout wins and never itself flashes.**
11. **Determinism:** stored seeds reproduce bit-identically; never `Hasher` (process-random)
    to fold identity — use the `SeededRNG`/UUID-fold.
12. **No health/therapy/esoteric claim** in any user-facing copy, OSC address, or mapping.
13. **SwiftUI render safety:** no growing the `.sheet` chain; no ~10 Hz `@Observable` read
    in any ancestor of a menu host (leaf-confine live bio reads).
14. **One parameter control** (`EchoelValueField` + `EchoelNumberPad`) — no raw `Slider`.
15. **Deploy is tokenless** (`.deploy/release` + `MARKETING_VERSION` bump → `testflight.yml`);
    no signing/bundle-id/App-Group churn on a re-trigger.

---

## 4. Per-domain map (condensed; full cited notes in the uamaps working set)

**AUDIO/DSP** — one master bus (`AudioEngine`), voices + FX chains per voice.
Target: retire the app-singleton voices in favor of per-lane `LaneVoiceRack`; a master FX
bus so FX/bio-modulation reaches every voice, not only `polyVoice`.
Gaps: [HIGH] two voice-ownership models coexist · [MED] `EchoelCellular` dead code ·
[MED] stale `EchoelDDSP` header (COW smell already closed by #83/#90/#94) · [MED] FX panel
+ FXBioModulator pinned to `polyVoice.fxChain` only.

**BIO** — clean bus contract; three live publishers through one `HRVNormalization`.
Target: fully consume the protected triad (`BioSignalDeconvolver`→cleaned samples→
`BioEventGraph` heartbeat); decide the door-less Session cluster once.
Gaps: [MED] `BioSignalDeconvolver` unwired · [MED] `BioEventGraph` heartbeat fed
`cleanedHeart:0` (graph heartbeats never fire) · [MED] `HilbertSensorMapper` unwired ·
[MED] Session/SessionView door-less but live-wired (decision debt) · [LOW] `.watch`/`.oura`
dead enum tags · face scaffold latent Info.plist need.

**DAW/TIMELINE** — the migration frontier.
Gaps: [HIGH] `Transport` is a partial mirror, not the driving clock (musical dispatch
rides `PatternEngine.onTick`; Transport carries only haptics+record) · [HIGH] two song-
timeline models (`ArrangementStore` legacy vs `TimelineStore` new) both fed every tick ·
[MED] tempo write-authority split (read `transport.tempo`, write `pattern.setTempo`) ·
[MED] `BioTempoDirector` built+tested but unwired (founder's breathing-tempo lane dead) ·
[LOW] automation edits not undoable.

**UI/STUDIO** — one Studio view carries too much.
Gaps: [HIGH] `EchoelStudioView` 4485-line god-view (body + 11 panels + bio/camera/generate
engine) — the exact aggregate-generic size the metadata-limit law fights · [MED] dead
`toolsSection`/`openTool` island (~200 lines, unreachable) · [MED] `MeditationView`
door-less only via dead code (its `.fullScreenCover` slot still sits in the sensitive
chain) · [MED] duplicated look-blend **raw `Slider`** in two views (one-control-law breach)
· [LOW] two owners of musical-identity controls synced by notification.

**VIDEO/VISUAL** — more ships than CLAUDE.md claims; some scaffolds mislead.
Gaps: [MED] `ChromaKey.metal` dead (400-line pipeline, zero Swift consumers) · [MED] two
`MetalBioView` mount sites both `capturesVideo:true` → double-capture risk (single-path
"invariant" is aspirational) · [MED] `BioVisualParams` hue/complexity discarded by
MetalBioView (duplicated body→look mapping) · [MED] `VideoLanePlayer` coordinator unwired
(FloatingVideoMonitor re-implements it) · [LOW] dead `.cymatics`/`.mandala` enum looks.

**SYNC/LIGHT/CAST** — senders live, patchbay-driven, egress-gated.
Gaps: [MED] `OSCSender.sendModulation` egresses `/echoelmusic/mod/<key>` **ungated** (a
bio-derived scalar can leave the device though its HealthKit source is blocked) · [MED]
Multipeer egress gate lives in the view, not `sendBio` · [MED] Broadcast has no egress
plan for the rendered stream (design before HaishinKit is linked) · [LOW] 4 near-identical
sender bodies · [LOW] plaintext UDP posture; stream key in UserDefaults.

**AUv3/PLATFORM/CI** — a real embedded shipping instrument (not "deferred").
Gaps: [HIGH] no **blocking** assertion that the appex's signed provisioning grants
`group.com.echoelmusic` (task #86; appex entitlements empty, all appex checks non-blocking)
· [HIGH] `ci.yml` references non-existent schemes (`Echoelmusic-macOS/watchOS/tvOS/
visionOS`) as a `needs:` of `build-archive` → hollow-green or blocked-archive · [MED]
DSP-isolation leak is convention-only (isolated appex compile runs only in testflight
preflight, not the fast gate) · [MED] no CI provisioning retry/backoff.

**CORE/CONTROL-PLANE** — the spine is sound; the routing layer sprawls.
Gaps: [HIGH] `bioEvents` SPSC queue has **two producers** (`BioEventPublisher` +
`PolarH10BioPublisher`) but SPSC requires exactly one → concurrent enqueue corrupts
head/tail when camera+BLE both active (a supported scenario) · [MED] `bioFrames` queue
published-but-never-drained (dead data-plane + multi-producer hazard) · [MED] four
overlapping routing systems, no single owner (two apply paths into the engine) · [MED]
`SignalRoute.amount`/`converterID` persisted but never consumed (converter layer is
scaffold) · [MED] `ProGate`/`EchoelStore`/`ProUnlockView` zero live consumers.

**PERSISTENCE/SCHEMA** — one engine (`AppGroupStore`), three decode disciplines.
Gaps: [HIGH] `AutomationLane` has no custom decoder + `AutomationPoint`/`TimelineLane`/
`TimelineRegion` **identity fields use bare `try decode`** → a single rename throws →
`TimelineDocument.init` rethrows → `AppGroupStore` `try?`→nil → **the whole timeline
document is vaporized** (user loses the song) · [MED] no `schemaVersion` on any disk doc ·
[MED] `try?`-swallow decoders silently reset a malformed present value · [MED] decode
failures invisible (no telemetry) · [LOW] `TrackFXStore`/`MixerStore` on UserDefaults.

---

## 5. The canonical REIHENFOLGE (ranked — take the top item next cycle)

**Ordering law:** data-loss & concurrency correctness → compliance → one-owner convergence
(plan-gated) → unwired-core wiring → dead-code retirement → frontiers. Each item names the
**cheapest reversible first slice** (≤3 files, gated, device-verify where behavioral).

### Tier A — correctness & data-loss (cheap, highest value, roadmap-independent)

**A1 [HIGH] Timeline document decode is data-loss-prone.** A rename of an
Automation/Lane/Region identity field vaporizes the user's whole song.
→ *First slice:* give `AutomationLane` + `AutomationPoint` a defensive `decodeIfPresent`
decoder (`id`→`UUID()` fold, enums→default), mirroring `SynthPatch`/`Project`; test that a
missing field degrades one field, not the document. Then a second slice for
`TimelineLane`/`TimelineRegion` identity fields. *(3 files, tdd-first, ships like #95/#117.)*

**A2 [HIGH] `bioEvents` SPSC has two producers → head/tail corruption when camera+BLE both
run.** → *First slice:* route the BLE `.heartbeat` publish through the same single
producer path as `BioEventPublisher` (one enqueue thread), or add a tiny lock-free
multi-producer guard; concurrency-reviewer gate. *(2 files; audit the real enqueue sites
first — this is a genuine race, verify before "fixing".)*

**A3 [MED] `sendModulation` egress ungated (5.1.3).** A bio-derived `/mod/<key>` scalar can
leave the device though its HealthKit source is blocked. → *First slice:* carry the driving
frame's `source` to the modulation tap and gate on `BioEgressPolicy.allowsEgress`, or (if
the abstraction is deemed acceptable) document the decision explicitly. *(1-2 files;
bio-safety-reviewer.)*

**A4 [MED] Decode-failure telemetry.** `AppGroupStore.load` returns nil silently → a lost
song produces zero signal. → *First slice:* log (os_log) on present-but-undecodable file,
so A1's class is observable in the field. *(1 file.)*

### Tier B — CI / platform integrity (cheap, protects the gates themselves)

**B1 [HIGH] `ci.yml` phantom schemes.** Verify whether `build-test-macos` (+watchOS/tvOS/
visionOS) silently skip or block; prune the matrix to the real iOS scheme so "green" means
green. → *First slice:* read `ci.yml`, confirm behavior, delete the dead matrix jobs.
*(1 file, no Sources risk; RELEASE/CI lead.)*

**B2 [HIGH] App-Groups appex provisioning (task #86).** → *First slice:* add the **blocking**
CI assertion that the appex's signed provisioning grants `group.com.echoelmusic` (gate the
portal-grant + entitlement re-add behind it). *(testflight.yml; founder-gated on the portal
capability.)*

**B3 [MED] DSP-isolation machine-check.** → *First slice:* a grep-guard step (or promote the
isolated `EchoelmusicAUv3` compile into `xcode-compile-check.yml`) that fails if any DSP/
file references a Core/Sequencer type. *(CI only.)*

### Tier C — one-owner convergence (PLAN + Council each; multi-cycle, higher risk)

**C1 [HIGH] One song-timeline model.** Finish the `ArrangementStore`→`TimelineStore`
migration; retire the legacy playback path. *ERST PLAN + Council* (touches persistence +
playback + a live founder surface). *First slice after plan:* stop feeding `ArrangementPlayer`
the tick once `TimelineRegionPlayer` covers its cases.

**C2 [HIGH] One clock.** Make `Transport` own the timer and drive priority-ordered subs;
migrate the `PatternEngine.onTick` consumers onto it one at a time. *ERST PLAN + Council.*
*First slice:* move one consumer (e.g. automation) from the hardcoded chain to a Transport sub.

**C3 [HIGH] One voice-ownership model.** Route the default/roll path through `LaneVoiceRack`;
retire the app-singleton voices. *ERST PLAN + Council.* Enables a master FX bus (fixes the
AUDIO [MED] FX-addressing gap).

**C4 [HIGH] Split the `EchoelStudioView` god-view.** Panel-per-leaf-file + an `@Observable`
view-model; **shrinks the metadata-limit risk.** *ERST PLAN* (high-regression file — behavior-
preserving extraction only, one panel per slice, device-verify each).

**C5 [MED] One routing owner.** Converge the four matrices onto `ParameterApplyRouter`'s
apply table; make `ModulationEngine` apply through it, not a direct closure.

### Tier D — wire the built-but-unwired cores (value already paid for)

**D1 [MED] Protected triad into the live path** — `BioSignalDeconvolver`→cleaned samples→
`BioEventGraph` heartbeat (closes `cleanedHeart:0`); wire `HilbertSensorMapper` when a
channel-array source exists. *(READ-ONLY triad — wiring only.)*
**D2 [MED] `BioTempoDirector`→`Transport.tempo`** — lights up the founder's breathing-tempo
lane (depends on C2). **D3 [MED] `VideoLanePlayer`** as the one video-lane coordinator
(retire the ad-hoc FloatingVideoMonitor path). **D4 [MED] `BioVisualParams`** as the single
body→look owner MetalBioView reads (remove the in-renderer re-derivation).

### Tier E — dead-code retirement & honesty (small, reduces audit noise)

**E1** remove/relabel the undrained `bioFrames` queue · **E2** delete or wire
`ChromaKey.metal` · **E3** retire the `toolsSection`/`openTool` island + its dead modal
slots · **E4** delete `EchoelCellular` or wire it · **E5** fix the stale `EchoelDDSP`
COW-smell header · **E6** enforce single `MetalBioView` mount · **E7** the two remaining raw
`Slider`s → `EchoelValueField`.

### Tier F — frontiers (founder-roadmap, unchanged by this map)

Video export/render (#106, #40) · Loop-management (#104) · Master/stem management (#105) ·
Broadcast/RTMP (HaishinKit link + egress design) · EEG modulation (#61) · EchoelWeather
(#59) · EchoelPublish (#51) · CloudSync phase-1 · monetization decision (`ProGate`/`EchoelStore`).

---

## 6. Stale CLAUDE.md claims this map corrects (feed back in a docs slice)

- **AUv3 "deferred, not active in v10"** — STALE: it's an embedded shipping instrument
  (`aumu`, dep of the app, shipping since build 1543).
- **`ci.yml` "Main CI (SwiftPM build, test, lint)"** — STALE: it's `xcodebuild` on the
  `Echoelmusic` scheme; no `swift build`. Linux SPM build was removed as guaranteed-red.
- **BLE strap "`blehrs.in` start/stops via `applyRouting`"** — STALE: that coupling was
  removed (BLE-3 fix); the one owner is the studio source dropdown.
- **HRV normalization "camera ÷200 vs strap ÷100"** — STALE: already unified to
  `HRVNormalization.ceilingMs = 100` (2026-07-23).
- **"bioEvents/bioFrames queues are reserved/undrained"** — partly STALE: `bioEvents` IS
  drained (OSCSender is its sole consumer); only `bioFrames` is genuinely undrained.
- **`Core/SessionStore.swift` in REPO STRUCTURE** — does not exist (grep zero).
- **"Video page designed + DEFERRED / no recorder"** — STALE: a visual-MP4 recorder + AAC
  mux + Photos export + video lanes + AVPlayer monitor ship; #40 is in progress. Genuinely
  absent: general camera capture, clip trim, timeline→file render.
- **`WorkspaceView` body shape / "EchoelStudioView is a direct child"** — STALE: content is
  `SurfaceHost` (wraps ArrangeTimelineView + EchoelStudioView) + CompositionHeaderStrip.
- **"Art-Net + sACN (unicast) are live"** — sACN default IS unicast; Art-Net default is
  **broadcast** `255.255.255.255`. Both live; the transport nuance is the fix.
- **`EchoelCellular` "reused as FX texture / synth voices"** — STALE: zero consumers (dead).

---

*Prepared by the PM loop from 9 domain-agent reads (5 recovered from the failed
`ultraarchitecture-map` workflow + 4 re-run free-form). Docs-only; no `Sources/` change.
Next: converge via the REIHENFOLGE, Tier A first, one gated Ralph slice per cycle.*
