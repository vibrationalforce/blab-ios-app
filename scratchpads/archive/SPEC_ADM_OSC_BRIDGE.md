# SPEC — ADM-OSC Bridge (Echoel → FletcherMachine / immersive rigs)

**Status:** PROPOSED (roadmap: EchoelStage cycle) · logged decisions.csv 2026-06-06
**Doctrine fit:** ✅ open standard, zero SDK, zero new dependency (reuses live `OSCSender`)
**Contact:** Roman — Pyko / Adamson (see `memory/people.md`)

---

## 1. What ADM-OSC is

ADM-OSC = **Audio Definition Model over OSC** — an open industry standard
(github.com/immersive-audio-live/ADM-OSC) for sending **object-based audio
positioning** over OSC. Adamson **FletcherMachine** speaks it natively (also
L-Acoustics L-ISA, d&b Soundscape, Spat, Nuendo, etc. — so this is *not*
Adamson-specific lock-in; one bridge talks to the whole immersive ecosystem).

### Address namespace (v1.0)

```
/adm/obj/{n}/position/azimuth     float   -180 … +180   (degrees)
/adm/obj/{n}/position/elevation   float    -90 … +90    (degrees)
/adm/obj/{n}/position/distance    float      0 … 1      (normalized)
/adm/obj/{n}/position/x           float     -1 … +1     (normalized)
/adm/obj/{n}/position/y           float     -1 … +1
/adm/obj/{n}/position/z           float     -1 … +1
/adm/obj/{n}/gain                 float      0 … 1      (linear, ≤ 1.0)
```

`{n}` = 1-based object index. Polar **or** Cartesian (don't send both for the
same object in the same frame — pick one coordinate system per object).

---

## 2. The Echoel angle

Echoel's differentiator is **the body as controller**. The bridge makes the
body drive *spatial position* of audio objects in an immersive rig:

> Heart / breath / motion / coherence → object position + gain, live, over an
> open standard, into any ADM-OSC renderer.

This is the **EchoelStage** thesis made concrete: Echoel isn't a competitor to
FletcherMachine — it's a **bio-reactive object *source*** that feeds it.

### Proposed default mapping (one "bio object")

| Bio signal        | ADM-OSC target            | Mapping |
|-------------------|---------------------------|---------|
| breath phase 0…1  | `position/azimuth`        | `(phase*2-1)*180` — sound sweeps L↔R with the breath |
| coherence 0…1     | `position/distance`       | `1 - coherence` — coherent = pulled close/intimate; scattered = far |
| HRV 0…1           | `position/elevation`      | `hrv*60` — calm lifts the object |
| motion 0…1        | `gain`                    | `0.3 + motion*0.7` — movement brings it forward |

(All four are already fields on `BioSampleFrame` and already stream as
`/echoelmusic/bio/*`. The bridge is purely a re-address + re-scale.)

A later cycle can expose a small mod-matrix so the performer picks which bio
signal drives which object axis (mirrors the existing modulation matrix).

---

## 3. Implementation sketch (small, additive)

**No new dependency. No protected-DSP touch.** Reuse `OSCSender.encode(address:floats:)`.

Option A (minimal — extend OSCSender):
- Add `var admOSCEnabled: Bool`, `var admHost`, `var admPort`, `var admObjectIndex: Int`.
- Second `NWConnection` to the ADM endpoint (renderers usually listen on a
  different port than TouchOSC's 8000 — make it configurable, e.g. 9000).
- In the 100 ms tick, when enabled, also emit the mapped `/adm/obj/{n}/…` set.

Option B (cleaner — separate `ADMOSCSender`):
- New `Sources/Echoelmusic/Sync/ADMOSCSender.swift`, same shape as `OSCSender`,
  reusing the static `encode`. Subscribes to the same `EngineBus`.
- Pros: keeps the master-prompt `/echoelmusic/*` space pristine; independent
  endpoint/lifecycle; unit-test the bio→ADM scaling in isolation.
- **Recommended.**

### Pure, testable kernel (the only real logic)

```swift
// maps a BioSampleFrame to ADM-OSC (address, value) pairs for object `n`.
// pure value-in/value-out — unit-tested without a socket, like encode().
static func admMessages(for f: BioSampleFrame, object n: Int) -> [(String, Float)]
```

Test (`Tests/ADMOSCTests.swift`): feed known frames, assert azimuth/elevation/
distance/gain land in spec range and follow the mapping. Mirrors the existing
OSCSender encode tests.

---

## 4. Scope / non-goals (this cycle)

- ✅ Out only (Echoel → renderer). No ADM-OSC *receive* yet.
- ✅ One bio object. Multi-object / per-track objects = later.
- ❌ No PosiStageNet / RTTrPM (those are tracking-system protocols, not our role).
- ❌ No FletcherMachine SDK — there is none and we want none; ADM-OSC is the contract.

---

## 5. Validation path (sandbox-honest)

- **Compile-verifiable in CI:** the sender + the pure `admMessages` kernel + tests.
- **NOT verifiable in sandbox:** actual reception by a FletcherMachine (no hardware).
  Interim proof: point it at a desktop OSC monitor (e.g. Protokol / OSCTestApp)
  or a tiny Python `python-osc` receiver and confirm the `/adm/obj/1/…` stream —
  same way TouchOSC was validated for `/echoelmusic/bio/*`.

---

## 6. Trigger to build

Build this in the **EchoelStage** cycle (Installation/Event/Cinema/Theater/Live
Broadcast surface), or sooner if a concrete demo with Roman/Adamson is scheduled.
Until then: documented, decision-logged, ready to drop in.
