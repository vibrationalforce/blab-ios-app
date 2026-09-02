# PLAN — Echte Instrumente (Founder 2026-07-04: "klingt alles mega scheiße" → "Ja, bauen")

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Diagnose (Founder-Antwort: "Alles zusammen"): (1) additive DDSP-Synthese hat eine
Klang-Decke, (2) Komposition primitiv (B1–B3 offen), (3) generische Archetyp-Beats.
Dieser Zyklus tauscht (1) — das Fundament: reale Instrumente als Standard-Klangquelle.

## Architektur (null neue Code-Dependencies)

- `Tools/SampledInstrumentVoice.swift` — Apples `AVAudioUnitSampler`, lädt GM-Programme
  aus gebündeltem **GeneralUser GS** (.sf2, freie Lizenz, ~30 MB — Founder hat der
  App-Größe explizit zugestimmt). Graceful absence: ohne Asset `isReady=false`.
- `AudioEngine.attachInstrument(_:)` — pause→attach→connect→restart (Muster
  attachSourceNode); Sampler rendert selbst, unser Render-Pfad unberührt.
- `PianoRollModel`: Protokoll `NoteVoice` (PolySynthVoice + Sampler dahinter);
  Routing in `outputVoice(for:)`: Real-Modus → .lead=Piano-Sampler,
  .harmony=Streicher-Sampler, .bass bleibt Classic-Synth + Sub (sauberes Low-End).
  Note-off-Grouping jetzt per Voice-IDENTITÄT (`sameVoice`), nicht Lead-Flag.
- UI: Composition-Panel „Sound": Real instruments / Classic synth
  (@AppStorage `studio.realSound`, Default Real; Zeile erscheint erst, wenn das
  Asset im Build ist — kein toter Regler).
- Bio bleibt wirksam: Master-FX-Kette (FXBioModulator) formt auch die Sampler.

## Asset-Beschaffung (Sandbox kann nicht downloaden — verifiziert 403)

`.github/workflows/fetch-instruments.yml` (Founder-approved): triggert auf Push von
`.deploy/fetch-instruments`, lädt GeneralUser GS + Lizenz, committet nach
`Sources/Echoelmusic/Resources/Instruments/` (idempotent, Größen+RIFF-Sanity).
Hermetische Builds — kein Download zur Build-Zeit.

## Deploy-Reihenfolge (wichtig)

1. Push A: Code + Workflow + Marker (KEIN Release-Bump) → Fetch-Workflow committet
   das Asset auf den Branch; CI-Gates prüfen den Code (Fallback-Pfad = grün ohne Asset).
2. `git pull` → Asset da? → Push B: `.deploy/release` 10.79.67 → TestFlight-Build
   MIT Instrumenten. (Ohne diese Reihenfolge hörte der Founder keinen Unterschied.)

## Danach (gleiche Baustelle, nächste Zyklen)

- Per-Genre-Programme (ePiano für 80s, warmPad für Ambient, fingerBass …)
- GM-Drumkit (Bank 0x78) für die Archetyp-Beats → echte Drums statt Spielzeug
- B1–B3 Loop-Form/Motiv/Kadenz — Komposition, die Sinn ergibt
- Session One (Entscheidung offen) nutzt dieselbe reale Klangwelt
