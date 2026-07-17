# HARNESS LEDGER — the Idea-Maze (read BEFORE you try something "new")

**Why this file exists.** In a long autonomous run the single biggest waste is
re-attempting an approach a *past* (now context-compacted) cycle already proved
is a dead-end — or re-discovering a deploy/CI trick from scratch. This is the
"effective harness for long-running agents" discipline (Anthropic, Nov 2025)
applied to Echoel: keep one durable, append-only map of **what was tried, what
won, and what is a known dead-end**, so the loop climbs instead of circling.

**How to use it (every cycle):**
1. **Before** trying a non-trivial approach, scan the DEAD-ENDS table. If it's
   listed, take the "do this instead" — do NOT re-run the failed path.
2. **After** a cycle, if you hit a real dead-end or found a reliable playbook,
   add ONE row. Keep rows one line, high-signal. Prune duplicates.
3. This complements `SESSION_LOG.md` (narrative history) and `decisions.csv`
   (strategic decisions). This file = tactical "don't retry / always do".

---

## DEAD-ENDS — proven not to work here (do the RIGHT column instead)

| Dead-end (do NOT retry) | Do this instead |
|---|---|
| Grow the `EchoelStudioView` `.sheet`/`.fullScreenCover` chain by appending another modal | Reuse/replace a slot, or one `.sheet(item:)` enum. Past the SwiftUI metadata-decoder limit = SIGSEGV at first render (black screen). `AnyView`-splitting the chain does NOT save it. |
| Read a ~10 Hz `@Observable` (rPPG waveform, bio snapshot, playhead) in a body/ancestor that hosts a `.menu`/Picker | Confine the live read to its own leaf `View`. `AnyView` is NOT an observation boundary. A 10 Hz read in ANY ancestor tears down open menus (the freeze). Audit the PARENT/ROOT, not just the obvious view. |
| `Task { @MainActor }` per frame from a 30 fps camera source | Push into a lock-protected `@unchecked Sendable` queue with zero actor hop; drain in an existing ~10 Hz main-actor poll. Per-frame main-actor tasks starve the SwiftUI executor. |
| `.map(String.init)` / bare `.init` func-refs in a pure Core | Use `.map { $0 }` / an explicit closure. Pure cores pass Linux CI but the iOS Xcode gate adds initializer overloads → "ambiguous" compile error. Scan new cores for this before pushing. |
| `.coordinateSpace(name:)` (and other iOS-16 SwiftUI overloads) | Use `.coordinateSpace(.named(_:))`. Deprecated-since-iOS-17 APIs can fail an `-warnings-as-errors` build. |
| `Double` expressions passed straight into `.frame`/`.position` | Keep view geometry in `CGFloat`; convert to `Double` only at a pure-math boundary. Double→CGFloat is not implicit for non-literals. |
| TestFlight deploy via workflow_dispatch / `gh` / curl GitHub API | Tokenless ONLY: bump+push `.deploy/release` (testflight.yml triggers on that path). Dispatch APIs return 403; the git relay allows only the designated feature branch. |
| `curl` the GitHub API for CI status (even with the gitignored token) | Use the `mcp__github__*` tools. curl → "GitHub access is not enabled for this session". |
| Trust "Quick Test" as a real gate | The real gates are **Xcode Compile Check** (iOS SDK — stricter) + **CI/CD Pipeline** (Linux build+test). Quick Test = lint only. |
| Simplify the Rausch triad (BioEventGraph / HilbertSensorMapper / BioSignalDeconvolver) | READ-ONLY. Do not touch without explicit founder approval. |
| Re-add a Session door, the 6-surface bottom bar, or the Tools grid | Founder-removed. Those files stay compiling but unpresented — do NOT resurface without a founder ask. |
| Diagnose "total silence" as an engine/generate bug when the log shows `generate: N notes, playing=true` | The generative roll is gated by `Timeline.rollSlotGain` (first non-bio MIDI lane's mute/solo/level) → `pianoRoll.mixGain` → `PianoRollView` `laneAudible` gates every `noteOn`. A MUTED "MIDI 1" (or a foreign SOLO, or level 0, or `suppressBuiltIn` via an assigned AUv3) = total silence with notes still generating. Check `rollMixGain` in the generate breadcrumb; the visual-log `level=1.0` is SUMMED VELOCITIES (intent), NOT measured output. |

## PLAYBOOKS — reliably works here

| Situation | Playbook |
|---|---|
| Verify a commit before deploy | Poll `mcp__github__actions_get get_workflow_run` for BOTH gates; green = Xcode Compile Check + CI/CD Pipeline both `conclusion: success`. Overflowing list output → parse the saved file with `scripts/gh-run-status.py`. |
| New pure core (math/model) | Foundation-only, deterministic (SeededRNG/UUID-fold, no Date/Random), `decodeIfPresent` defaults, Linux-testable. Split view math into a pure `*Math` enum. |
| New modal on the Arrange surface | Add an `ArrangeModal` enum case + one `modalEditor` arm — routes through the ONE existing `.sheet(item:)`. Never a new `.sheet`. |
| New surface inside EchoelStudioView (its `.sheet` chain is at the metadata ceiling) | Present IN-PLACE as a section inside an existing `StudioMenu` dropdown panel (e.g. `compositionPanel`), reading only @State snapshots (no 10 Hz observable in the root-body dropdown). No new `.sheet`. |
| Audition/preview a variant of a generate()-built take | Extract generate()'s Input construction into ONE shared `makeComposerInput(advanceEvolution:…overrides)` so the preview scores the EXACT input the take will use (honest), and add nil-default seed overrides to `generate()` so apply replays the picked seeds bit-for-bit. Don't duplicate the composer logic in the preview. |
| Milestone deploy | gates green → bump `.deploy/release` (vX.Y.Z + German notes) → push → TestFlight. Then German status delta to founder. |
| Mandatory reviewers | audio-thread (render paths) · concurrency (`@Observable`/async) · ui-state (Views). Run BEFORE commit; PASS is the gate. |
| Per-instrument feature (per-track sound/genre/mood) | AUDIBLE only via per-lane voices = `LaneVoiceRack` = `FeatureFlags.multiRoll` ON (default OFF, device-gated). Store + wire the per-lane data BEHIND the flag (bit-identical OFF); do NOT ship user-facing per-track SOUND UI while multiRoll is OFF (inert control = worse than none). The keystone flip is a founder/device milestone. |
| MCP (GitHub) down mid-cron | Can't verify gates (no curl-to-github; token+curl blocked). git push still runs CI serverside. Do NOT push device-only `#if AVFoundation` code blind (only the Xcode gate validates it). Restrict to CI-safe pure/doc work; verify gates next tick when MCP returns. |
| Flip/verify a risky keystone flag (multiRoll etc.) before wiring on top | Run a Workflow audit FIRST: N parallel subsystem readers → adversarial verify of blockers → synthesis of go/no-go + edit list. It found multiRoll was ALREADY default-ON with 3 live bugs (bar-1 silence, mute-leak, patch-unwired) that a blind wiring pass would have built on. Audit-first, then single-writer implement the confirmed fixes. |
| Device-only fix that can't run on Linux CI (needs PianoRollModel/AVFoundation) | Extract the DECISION into a pure Foundation enum (e.g. `MultiRollFanout`) the @MainActor class consumes → the bug-fix logic is Linux-CI-tested even though play() isn't. Same pattern as `*Math` view-math splits. |

---

## LEADERBOARD — shipped this run (newest first)

| Version | What shipped | Gates |
|---|---|---|
| v10.79.199+ | Founder live redesign (07-14): Bio→header (tap=info), Transpose removed, Immersive Stage→ADM-OSC egress; then the "alles ist still" root cause (roll-slot lane mute/solo gates the generative melody) + a silenced-instrument guard banner with one-tap "Ton an" | green |
| v10.79.198 | BioVariationMaze audition — "Variationen" card in the Comp dropdown: Explore ranks 6 body-curated groove variations, tap one to play it. Shared makeComposerInput builder (no dup logic); generate() gains nil-default seed overrides. No new sheet, no 10 Hz read | green |
| v10.79.197 | rPPG pulse-lock fix — wired RPPGConditioning.linearDetrend into the periodicity estimate (kills the DC ramp that mean-removal leaves) | green (device-verify pending) |
| v10.79.196 | Adaptive home — arrange timeline fills the screen, instrument zone conditional (chip bar idle, dropdowns on demand); killed the black void | green |
| v10.79.195 | Immersive Stage — Touch room-map, each track a draggable spatial object (SpatialSceneStore + ImmersiveStageMath + ImmersiveStageView) | green |
| v10.79.194 | Multi-Roll (tracks play simultaneously) + per-track Record (arm→play→capture MIDI/bio→Clip+region) | green |

## DEAD-END / PLAYBOOK (2026-07-14 Nacht)
- **DEAD-END: trusting stale Reads after a silent local branch-rewind.** The remote container's local working tree rewound from the branch tip (v212) to an old ancestor (v208) mid-session with a CLEAN `git status`; earlier Read outputs (showing transposeSemitones/EchoelTape) reflected the pre-rewind tree, then grep on the rewound tree found nothing → 20 min of confusion. **DO THIS INSTEAD:** the moment file content contradicts what you just read (a grep finds nothing that a Read showed), run `git rev-parse HEAD` and compare to origin BEFORE re-investigating code. If HEAD ≠ expected, `git fetch origin <branch>` then verify the local HEAD is an ancestor (`git rev-list HEAD --not origin/<branch> | wc -l` == 0 ⇒ no unique local commits) and `git reset --hard origin/<branch>`. Everything pushed is safe on origin.
- **PLAYBOOK: CI-gate visibility can vanish mid-session (GitHub MCP disconnect + no local token + non-interactive = no OAuth).** When it does: (a) git push still works (proxy, not MCP) so deploys continue; (b) rely on the mandatory subagent reviewers (audio-thread/dsp/concurrency/code) as the correctness proxy — they read the actual code; (c) a broken build just fails CI and TestFlight ships nothing (no damage to the existing build); (d) do NOT make blind audio-thread/voice-allocation changes you can't compile-verify — those violate "keine Fehler"; prefer reviewer-fully-verifiable slices (pure value types, mirror-a-shipped-pattern) until gate sight returns; (e) retry MCP each wakeup.
- **PLAYBOOK: per-instrument pitch family = one wiring spine.** Transpose (v210), Detune (v213) both follow: TimelineLane.field (+decodeIfPresent ?? 0) → TimelineStore.setLaneX (clamp) → TimelineDocument.rollSlotX (clamp) → TimelineRegionPlayer slot/rollXSink (fired on region load) → EchoelmusicApp sink wiring (primary→polyVoice, secondary→laneVoiceRack slot) → PolySynthVoice.setX → EchoelPolyDDSP field folded into the ONE noteOn MIDI→Hz exponent → ArrangeTimelineView LaneFX EchoelValueField + rollSlotX onChange (doc-level read = edit-only, freeze-safe) + MultiRollFanout.X(forSlot:) + MultiRollFanoutTests. Oktaver (octave doubler) does NOT fit this spine (it spawns voices, not a frequency offset) — needs its own design + build-verify.

## DEAD-END / PLAYBOOK (2026-07-16 CLIP-3)
- **PLAYBOOK: live-pull equality gates vs. continuously-scrubbed fields.** Any per-step "pull the store's doc and compare" path (mergeMixer, structurallyEqual/refreshStructure) turns EVERY EchoelValueField-scrubbed lane field into a potential ~8 Hz storm: the scrub writes the store on every drag frame, so a field classified "structural" relocates (voice flush + audio-lane restart) for the whole drag. BEFORE building/extending such a gate: enumerate ALL EchoelValueField-bound lane fields (today: level, pan, transposeSemitones, detuneCents) and explicitly assign each to the mixer path (sink-applied live, no reload) or the structural path. The "safe default = structural" rule is right for NEW discrete fields but exactly wrong for drag fields. Sink-applied per-lane voice fields (gain/pan/transpose/detune pattern) always belong in mergeMixer + refreshMixer.
- **PLAYBOOK: AVAudioEngine.connect() wirft NICHT — es RAISED (kAudioUnitErr_FormatNotSupported, uncatchable ObjC).** Jeder neue Verbinde-Pfad für gehostete Units braucht das setFormat-Preflight-Gate VOR attach/connect (effectsAcceptingChainFormat / effectsAcceptingMasterFormat / instrumentAcceptsChainFormat — gegen das Format, das der Pfad WIRKLICH verbindet: Chain ≠ Master). Ein Gate nur auf einem von mehreren Pfaden = Crash wandert zum ungegateten Pfad (AU-1: Lane gated, Browser crashte).
- **TODO-Zyklus (Audio-Review-Advisory PERF-01, vorbestehend N×-verstärkt):** Prime-Attaches unter EINE withGraphPaused-Batch-Pause legen (AudioEngine.swift:807) + attachPlayerNode-Failed-Restart in recoverEngine routen (heute: nur Log, isRunning/degraded bleiben stale, Mix still bis Config-Change). Dazu LOW: Format-Nodes bis Lane-Removal nie gepruned; korrupte Datei nicht memoized (Log-Spam pro Wrap).

## PLAYBOOK (2026-07-16 UX-1)
- **PLAYBOOK: Unterdrückungs-Gate ≠ Claim-Gate — zwei Freshness-Prädikate.** `hasLiveSignal` (schließt `.fallback` aus) beantwortet „darf die UI einen LEBENDEN Körper behaupten?" (grüner liveTag: nein bei Demo). Ein Hinweis/Nag-Unterdrücker („zeige Kamera-verweigert-Banner nur wenn KEINE Quelle liefert") muss dagegen auf ROHES `bus.freshBio() == nil` gehen — die bewusst gewählte Demo zählt als lieferende Quelle. Wer beide Fragen mit demselben Prädikat beantwortet, baut entweder einen Demo-Nag (UX-1 Review-MEDIUM) oder einen lügenden grünen Tag. Bei JEDEM neuen bio-abhängigen UI-Gate zuerst fragen: Claim oder Unterdrückung?
- **PLAYBOOK: Permission-Sackgassen-Muster (wiederverwendbar für Mikro/HealthKit/Bluetooth).** (1) Publisher: `permissionDenied`-Flag, im start()-catch FRISCH vom System gelesen (authorizationStatus — Systemfakt, nie aus dem Error-Typ geraten), nur unter Generation-Guard geschrieben, nach Erfolg geräumt, von stop() unberührt. (2) Typed-Cue-Enum: denied-Case ZUERST in jedem Mapping, actionable. (3) Jede Fläche, die Coaching zeigt, braucht den denied-Zweig VOR dem Coaching — sonst coacht sie Unmögliches. (4) Settings-Tür via bestehendem openAppSettings(). iOS killt die App bei Permission-Wechsel → stale-true über Re-Grant praktisch unmöglich, trotzdem defensiv räumen.

## PLAYBOOK (2026-07-16 Stille-Falle + Keystore)
- **PLAYBOOK: @AppStorage-Divergenz-Detektor.** `grep -rhoE '@AppStorage\("[^"]+"\)' Sources/Echoelmusic --include='*.swift' | sort | uniq -c | sort -rn` zeigt jeden mehrfach deklarierten Key; danach pro Key die Deklarations-Defaults diffen. Jede Mehrfach-Deklaration MUSS durch StudioDefaultKeys laufen (H15-KEYSTORE) — per-Deklaration-Defaults sind eine stille Bug-Klasse (loop 4/8, floating true/false, genre vaporwave/selfObservation waren alle LIVE).
- **PLAYBOOK: Apple-Generator-Falle (AUv3-Hosting).** kAudioUnitType_Generator enthält BEIDES: echte Third-Party-Instrumente UND Apples programmatische File-Player (AUAudioFilePlayer/AUScheduledSoundPlayer), die auf MIDI-Noten nie klingen. Wer Generatoren als Instrumente listet, braucht den Apple-Manufacturer-Filter ('augn'+'appl' → raus), sonst ist ein Tipp = stumme Spur. Persistenz verdoppelt die Falle: App-State (UserDefaults-Record) beim Start HEILEN (Record entfernen + sichtbare Notice — Retention-Gesetz gilt transienten Failures, nicht unmöglichen Instrumenten); Nutzer-DOKUMENT-Refs (TimelineLane.instrument) dagegen NIE beim Laden beschneiden — nur die Hosting-Entscheidung filtern (wanted()-Guard), das Ref bleibt ehrliche Daten. Foundation-only-Schichten brauchen die FourCCs als Literale (0x6175676E/0x6170706C), AudioToolbox fehlt auf Linux.
- **PLAYBOOK: Founder-Screenshot = Diagnose-Gold.** Der Stille-Report wurde ohne Log lösbar, weil die Screenshots die Instrument-Liste (Falle sichtbar) UND den Audio-Fader auf 0.00 zeigten. Bei Geräte-Reports zuerst jedes UI-Detail der Screenshots gegen den Code lesen, dann erst nach Logs fragen.
| 2026-07-16 | PLAYBOOK | SwiftUI-Drag-Jitter-Klasse: eine Geste, deren Live-Delta die LAYOUT-Geometrie des eigenen Hosts ändert (.frame(width:) am trailing-alignten Handle), oszilliert im Default-.local-Raum (r(n+1)=d−r(n), Kante vibriert bei ruhendem Finger). Fix-Muster: DragGesture(coordinateSpace: .named(<stabiler Grid-Raum>)). Render-Transforms (.offset) sind immun — nur Layout-Änderungen füttern zurück. | AUDIT_CLIP_JITTER C1, b35fffa |
| 2026-07-16 | PLAYBOOK | Drag-Deltas in Leaf-Views IMMER @GestureState, nie @State: ScrollView-Arbitration CANCELT Gesten ohne onEnded → @State-Deltas bleiben als Geister-Versatz stehen. @GestureState auto-resettet bei Abbruch; Emphasis-Bools ableiten (delta != 0), nicht separat speichern. | AUDIT_CLIP_JITTER C2, b35fffa |
| 2026-07-16 | DEAD-END (vermutet, device-gated) | .highPriorityGesture auf dem Clip-Body NACH den Handle-Overlays: Parent-High-Priority kann Subview-Gesten (22-pt-Trim-Griffe, device-verifiziert) aushungern. Nicht blind shippen — erst Founder-Recording, dann ggf. Anbringung UNTER den Overlays testen. | AUDIT_CLIP_JITTER C3 |
| 2026-07-17 | PLAYBOOK | Continuation mit non-Sendable ObjC-Objekt (AVAudioUnit) NIE roh resumen — CheckedContinuation.resume ist `sending`, Completion-Handler-Param ist task-isoliert → Swift-6-Compile-Fehler. IMMER @unchecked-Sendable-Box (AVUnitBox-Muster, AUv3Host). Reviewer sagte den exakten CI-Rot voraus (984d68c), Box-Fix (0fd183f) heilte ihn — adversarialer Concurrency-Review VOR dem Gate spart einen ganzen Zyklus. | AUv3Host.swift instantiate |
| 2026-07-17 | DEAD-END | Timeout für nicht-cancelbares await via withThrowingTaskGroup — die Group AWAITET ihr hängendes Child beim Scope-Exit, der Hang zieht nur um. Stattdessen: Completion-Handler-API + Exactly-Once-Gate (ResumeOnce). | AUv3Host.swift |
