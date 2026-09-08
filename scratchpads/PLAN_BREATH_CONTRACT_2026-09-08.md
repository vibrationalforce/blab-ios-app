# PLAN — the breath contract: sawtooth or lung volume? (2026-09-08)

**Status: PLAN. Nothing built. Council verdict recorded; the build is a later slice.**

## The question

`BioSampleFrame.breathPhase` documents a SAWTOOTH ("0 = exhale start, 0.5 = inhale start").
The one producer that actually moves — `CameraRPPGBioPublisher` — writes
`RespirationEstimator.amplitude`, a soft-clipped SINE where 1 = lungs full (#1135, #1138).

Task #30 was framed as "make the source honour the contract". **That framing is wrong**, and
this plan exists because measuring the consumers inverted it.

## What each consumer actually wants (measured 2026-09-08)

| # | Consumer | Reads | Wants | Sawtooth would… |
|---|---|---|---|---|
| 1 | `BioEventGraph` via `BioEventPublisher:161` | raw | ramp (wrap 1→0 = exhale onset) | **FIX** |
| 2 | `BreathArp.direction(breathPhase:)` | raw | ramp | **FIX** |
| 3 | `PianoRollModel:1155` `sin(phase·π)` | raw | ramp (it humps) | **FIX** |
| 4 | `OSCSender:425` `/echoelmusic/bio/breath/phase` | raw | whatever is documented | neutral (doc follows) |
| 5 | `ADMOSCSender:315` azimuth `(p·2−1)·180` | raw | **smooth** | **BREAK** — object teleports +180→−180 once per breath |
| 6 | `ArtNetSender:294/305` DMX `byte(p)` | raw | **smooth** | **BREAK** — light snaps to blackout once per breath |
| 7 | `SpectralDonutView:120` | raw | smooth | worse |
| 8 | `MetalBioView` (the picture) | `breathPhaseForSound` | **smooth volume** | worse — #1136 just fixed this |
| 9 | `EchoelDDSP.applyBioReactive` `0.5 − 0.5·cos(2πφ)` | `breathPhaseForSound` | ramp (it humps) | FIX-ish, see open question |
| — | `BioPhaser:73` | raw | — | doorless, no production caller |

**Six want smooth, three want a ramp, and the two that would BREAK are the two most
performance-visible outputs a paying user puts in a rig.**

## Council verdict — 2026-09-08

- **Architect:** one moving producer, eight consumers; six want smooth. Changing the source to
  satisfy three and break the two most visible is the wrong direction. Rewrite the CONTRACT.
- **DSP Purist:** every real breath sensor yields a smooth volume-like signal — rPPG via RSA, a
  strap's stretch, HealthKit's rate. A monotone ramp is a synthetic construct, not a
  measurement. Peak/trough detection on a smooth signal is more robust than wrap detection on a
  reconstructed ramp, and does not depend on `periodEMA` being right.
- **Skeptic (strongest objection):** `BioEventGraph` is PROTECTED (Rausch triad, read-only
  without approval) and its breath detector expects a phase. — **Resolved:** the CALLER
  (`BioEventPublisher`) converts volume→phase for that one consumer. A caller-side adapter is
  not a triad change. The objection flips into the cheapest path.
- **Vision-Keeper:** an ADM-OSC object teleporting once per breath looks broken in someone's
  rig. That is the open-standards reputational surface.
- **Aesthetic Maximalist:** a smooth sweep through the room and a light breathing with the
  lungs is the performable gesture. A per-breath snap is a glitch, not an accent.
- **User-Advocate:** the founder asked for "kommen und gehen", never for a sawtooth.
- **Shipper:** (b) is a doc change plus one caller-side adapter. (a) is five consumers and two
  regressions.

**Dissent: none material.** → **Recommendation (b): keep the shipped signal, rewrite the
contract.** Gate: **plan first** — it touches the protected triad's caller, two egress paths,
and a documented OSC address an integrator may already consume.

## The proposed contract

> `breathPhase` — normalised breath EXCURSION, [0..1]. **1 = lungs full, 0 = lungs empty.**
> Smooth and continuous; it does not wrap. Unmeasured is gated by `hasMeasuredBreath`
> (the gate is `breathRate`, unchanged — 0 stays a real position).

Deliberately NOT renamed. `breathPhase` is a persisted-adjacent field name and the OSC address
`/echoelmusic/bio/breath/phase` is published in `CLAUDE.md`; renaming breaks integrators worse
than clarifying does. The doc carries the correction, the name carries the history.

## Slices (each its own cycle, each with a guard)

1. **Doc + guard only.** Rewrite the contract on `BioSampleFrame.breathPhase`, `BioSoundMapping`
   and the OSC section; pin the six smooth consumers. No behaviour change.
2. **`BioEventPublisher` adapter.** Convert volume→ramp locally before calling the protected
   detector: `φ = ((t − lastCrossT)/periodEMA + 0.770) mod 1` (#1138 — 0.770 is EMPIRICAL, the
   ~0.02 over 0.75 is `smoothTau` lag; re-derive if the filters change). Needs those two terms
   exposed from `RespirationEstimator`, which today are private. **This is the only slice that
   makes `BioEventGraph`'s breath events fire at all.**
3. **`BreathArp.direction`** — take direction from the SIGN of the change, not from a phase
   threshold. Rising = inhaling. Simpler than it is today and correct under both shapes.
4. **`PianoRollModel:1155` and `EchoelDDSP.applyBioReactive`** — both hump a value that is
   already a volume, the exact #1136 defect on the sound side. Remove the shaping. ⚠️ This
   CHANGES THE SOUND and needs the founder's ear before and after.

## Open questions — do not build past these

- **Is `amplitude 1 = lungs full` actually true on a body?** It is `RespirationEstimator`'s own
  assertion about RSA phase, never checked here (#1138). If inverted, every mapping above flips
  by half a cycle. **NEEDS-FOUNDER-VERIFY:** breathe deliberately, watch whether the picture is
  widest at full lungs or at empty.
- **Slice 4 changes audio.** The breath swell currently peaks somewhere; after the change it
  peaks at full lungs. That is a sound change, not a bug fix, and it is the founder's call.
- **HealthKit still has no phase at all** (task #31) — a real rate can open the gate on a frozen
  0.5. Whatever the contract says, that path publishes a constant.
