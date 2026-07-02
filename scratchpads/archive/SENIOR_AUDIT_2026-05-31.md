# Senior Engineering Audit — Echoelmusic (2026-05-31)

Scope: reverse-engineered architecture, root-cause of the one real failing
signal, performance review against the project's hard limits, and a
prioritized refactor strategy. **Read-only analysis — no product behavior is
changed here.** Respects CLAUDE.md: the protected DSP triad
(BioEventGraph / HilbertSensorMapper / BioSignalDeconvolver) is OFF-LIMITS,
and no top-level dirs/targets/deps are added.

> Consolidates five generic "act like a senior X" prompts (architecture audit,
> root-cause debugging, performance, clean-architecture refactor) into one
> grounded review. The "build a startup MVP from scratch / new folder
> structure" framings were declined: Echoelmusic is a working native-iOS
> instrument, not a greenfield web stack, and a blind rebuild would destroy
> shipping code.

---

## 1. Reverse-engineered architecture

**Composition root:** `EchoelmusicApp` (`@main`) constructs every engine in
`init()` (no audio I/O there — deliberate, to avoid the build-1363 launch
crash) and starts them post-UI in `.task` after `audioEngine.prepareGraph()`
→ attach source nodes → `audioEngine.start()`.

**Spine:** `EngineBus` — a **hybrid isolation** design:
- *Control plane* (`@MainActor @Observable`): `latestBio`, `latestControllerEvent`,
  `latestBioEvent` snapshots for SwiftUI + control-plane consumers.
- *Data plane* (lock-free `SPSCQueue` per topic): `bioFrames`,
  `controllerEvents`, `bioEvents` for audio-thread consumers.

**Producers** → `bus.publish(...)`: `HealthKitBioPublisher`,
`PolarH10BioPublisher`, `BioSimulator` (Demo), `MIDIBusPublisher`,
`BioEventPublisher`.
**Consumers**: `BioReactiveSynthVoice` (audible synth), `OSCSender`,
`ModulationEngine` (→ tempo + OSC mod-out), `SessionRecorder`, `BioStripView`.

**Data flow (steady state):**
```
sensor → publish(bio:) ─┬─ bioFrames.enqueue()            (audio-thread path)
                        └─ Task{@MainActor latestBio = f}  (snapshot path)
latestBio ──poll@100ms──> {SynthVoice, OSCSender, ModulationEngine, BioStrip}
ModulationEngine.evaluate(matrix) → setTempo / OSC /mod/* 
```

**Verdict:** the core is genuinely well-architected — single typed bus, no
direct module coupling, audio-thread discipline (pre-allocated buffers,
`nonisolated(unsafe)`, `memcpy`, `WeakBox` to avoid render-closure retain
cycles). The bus pattern is the right backbone to scale features onto.

---

## 2. Problem areas (prioritized)

### P1 — Duplicated subscriber loop (DRY / maintainability)
`OSCSender`, `BioReactiveSynthVoice`, `ModulationEngine`, and `SessionRecorder`
each hand-roll the **same** pattern:
```swift
task = Task { @MainActor [weak self] in
  while !Task.isCancelled { self?.<read latestBio + timestamp-dedup>; try? await Task.sleep(...) }
}
```
Four near-identical copies of lifecycle + dedup. **Refactor (safe, non-functional):**
extract a `BusPollingSubscriber` base/util owning the Task, cancellation,
`isActive`, and `lastFrameTimestamp` dedup; subscribers implement one
`apply(_ frame:)`. Removes ~4× boilerplate and centralizes the dedup rule.

### P2 — Polling instead of event-driven dispatch (perf / scalability)
N subscribers = N 100 ms timers, each re-reading `latestBio` and dedup-ing.
Fine at today's N, but it wakes the CPU 10×/s/subscriber even when bio is
idle, and adds up to 100 ms latency jitter to modulation/OSC. **Recommendation:**
a single bus fan-out (callback list or `AsyncStream` per topic) invoked from
`publish(...)`, so subscribers are *pushed* fresh frames. Bigger change —
defer until after the current feature push; design it so audio-thread
consumers keep using the SPSC queue untouched.

### P3 — `latestBio` snapshot updates asynchronously
`publish(bio:)` sets the snapshot via `Task { @MainActor latestBio = frame }`,
so the snapshot **lags** the SPSC enqueue and is ordered by the actor queue
(surfaced as a real test-timing dependency). Edge case: bursts faster than the
100 ms poll coalesce — acceptable for bio rates, but it means control-plane
consumers can skip intermediate frames. Document as intended, or make the
snapshot write synchronous on the producer's actor.

### P4 — Implicit parameter ownership (coupling risk as modulation grows)
`BioReactiveSynthVoice.applyBioReactive` owns all 7 synth params; `ModulationEngine`
deliberately avoids them and drives `seq.tempo`. This rule is **convention only**,
not enforced — as destinations grow, two writers could fight over one param.
**Recommendation:** a small destination registry that records the owner of each
param so conflicts are caught at registration, not by ear.

### P5 — `bioEvents` SPSC queue has no consumer
`BioEventPublisher` enqueues to `bus.bioEvents`, but consumers read the
`latestBioEvent` *snapshot*, not the queue. The lock-free queue is allocated
and never drained. Either wire a single consumer (it exists for exactly the
heartbeat→beat use case) or document it as snapshot-only to avoid confusion.

### P6 — Deprecated code retained in the tree (maintainability / build time)
`SoundscapeEngine`, `ClipEngine`, `SessionStore.SoundscapeSession`
(circadian/weather fields), and many `Views/*` are kept compilable but unused.
They add cognitive load and compile time. **Recommendation:** move to an
excluded area (Package.swift already excludes `_Deferred/`) in a dedicated
cleanup cycle — *not* mixed into feature work.

---

## 3. Performance review (vs CLAUDE.md hard limits)

| Limit | Finding |
|---|---|
| Audio latency <10 ms, no malloc/locks on audio thread | **Met.** Render closures use a pre-allocated scratch buffer, `memcpy`, no allocation/locks. `WeakBox` avoids retaining the MainActor voice. |
| CPU <30% | Fine. Main avoidable cost = 4 polling timers (see P2). |
| Memory <200 MB | Value types + pre-allocated buffers; no leak patterns spotted. JSON persistence payloads are tiny. |
| Visual 120 fps | Metal renderer not yet on a visible surface (EchoelVis ROADMAP) — not exercised. |
| Bio loop 120 Hz | Publishers run sub-kHz; snapshot poll at 10 Hz. Headroom large. |

No hot-path inefficiencies, unnecessary re-renders, or leaks found. The
biggest *scalability* lever is P2 (push vs poll), not raw optimization.

---

## 4. Root-cause analysis — the one real failing signal

**Symptom:** `quick-test.yml` "🧪 Swift Tests" job fails at step **`swift build`
(Linux)**; every run since ≥#520 (2026-05-25), i.e. pre-existing.

**Confirmed:** it is the *Linux library compile*, not a test assertion (Run
Tests is skipped). iOS/macOS CI + TestFlight archive are **green**, so it does
not gate shipping.

**Why it can't be pinned from the sandbox:** the GH job-log redirect targets
`*.blob.core.windows.net`, which the sandbox egress proxy blocks ("Host not in
allowlist"); there is no Linux Swift toolchain here to reproduce.

**Ranked hypotheses:** (1) a source file references an Apple-only API/type that
only fails to resolve on Linux despite a guard elsewhere; (2) `Observation` /
`@Observable` availability differences on Linux Swift 5.10; (3) a `Bundle.module`
/ resource or C-interop detail. *No unguarded Apple-framework `import` was found
by static scan*, which points at (1)/(2) (a transitively-used symbol).

**Robust fix path (no guessing):** owner opens the failed run and pastes the
`swift build` error (they are not egress-blocked) → targeted platform guard.
Alternatively add a step that tees the compile log to an allowlisted store.

---

## 5. Refactor strategy — what to do, and what NOT to do

**Do (safe, behavior-preserving, in priority order):**
1. P1 — extract the shared `BusPollingSubscriber` (pure refactor, unit-testable).
2. P4 — destination-ownership registry for modulation.
3. P5 — decide + document `bioEvents` consumer story.
4. P6 — quarantine deprecated modules (dedicated cleanup cycle).
5. P2 — push-based bus dispatch (design doc first; larger).

**Do NOT (explicit guardrails):**
- Touch the protected DSP triad without written approval.
- Add top-level dirs/targets/dependencies or "rebuild with a new folder
  structure" — forbidden by CLAUDE.md and unnecessary; the architecture is sound.
- Change product behavior. Each item above is non-functional or additive.

**Bottom line:** Echoelmusic does not need a rebuild. It needs a small DRY pass
(P1), a coupling guardrail (P2/P4), and the Linux-build log to close the one
real red. The bus architecture already scales the feature set we've been
shipping.
