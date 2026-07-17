# PLAN — „Die AUv3-Struktur muss sitzen" (Founder + Council 2026-07-13)

Founder: „Vorallem muss die ganze AUv3-Plugin-Struktur sitzen. Wenn wir alles in AUv3
machen ist es vielleicht einfacher das in die Spuren zu etablieren? AUM fürs Routing,
durchdacht wie Ableton, präzise + stabil wie Reaper, leichtes Handling wie FL Studio."

**Council-Verdikt (einstimmig, Founder bestätigt):** KEIN interner Engine-Rewrite nach
AUv3. Nativer Kern bleibt (AVAudioEngine + Swift-DSP, bio-gekoppelt, Rausch-Triad/DDSP
lock/alloc-frei). Die Vereinheitlichung = die **Parameter-Abstraktion** (`EchoelParameter
Registry`), nicht die Plugin-Implementierung. Priorität: dieser Block JETZT, vor Record.
Entscheidung geloggt in `decisions.csv` 2026-07-13.

## Was „die AUv3-Struktur sitzt" konkret heißt (Ist → Ziel)
- **Ist:** 1 geshippter AUv3 (Bio-Synth `augn/echl`, DSP/ isoliert). App ist AUv3-HOST
  (`AUv3Host`: Discovery via AVAudioUnitComponentManager, lädt EIN Instrument in den Graph,
  `replaceBuiltInVoice`). `AUv3BrowserView`/`AUv3PluginUIView` existieren. `EchoelParameter
  Registry` hat einen Design-Note für den KVO-Bridge externer Param-Trees — noch nicht gebaut.
  `TimelineLane` hat KEIN AU-Belegungs-Feld.
- **Ziel (die 4 Vorbilder als Eigenschaften, nicht als Rewrite):**
  - **AUM = Routing:** pro Timeline-Spur eine Chain (Quelle → Insert-AUs → Gain/Pan → Bus).
  - **Ableton = Modell:** klares Session/Arrange, eine Spur = ein Instrument + FX-Kette.
  - **Reaper = Präzision/Stabilität:** sample-genaues Scheduling, Plugin-Crash isoliert den
    Graph nicht, robuste State-Recall (fullState round-trip). Eigene Härtungs-Zyklen.
  - **FL = Handling:** Belegung pro Spur in 1–2 Taps, sichtbar, umkehrbar.

## Zyklen (Ralph-Wiggum, test-first wo pur)
- **U1 — AU-Param → Descriptor-Mapping (pur, CI-testbar). ← DIESER ZYKLUS.**
  Reine Funktion: `AUParameter`-Metadaten (identifier/address, min/max/default, unit,
  valueStrings, flags) → `ParameterDescriptor` mit stabilem keyPath `au.<mfr>.<sub>.<addr>`.
  Kein AVFoundation-Instanz nötig zum Testen (synthetische Eingaben). Rev: Architect + DSP Purist.
- **U2 — Live-KVO-Bridge:** ein geladenes `AUAudioUnit` beobachten (parameterTree, re-enumerate
  on replace), gemappte Descriptors in die Registry registrieren (`au.`-Prefix), Router-Setter
  binden (`scheduleParameterBlock`/`setValue`). Damit sind externe Params automatisierbar wie
  interne — „Automation in den Spuren" für eigen+fremd. Rev: Concurrency + DSP Purist. Device-gated.
- **U3 — Per-Spur-Belegung sichtbar:** `TimelineLane` bekommt eine optionale AU-Instrument/FX-Ref
  (Codable, decodeIfPresent); Spurkopf zeigt Belegung + Browser-Tür pro Spur. Rev: UI-State + User-Advocate.
- **U4 — Per-Spur-Chain/Routing (AUM-Ziel):** Insert-Kette pro Spur (Quelle→FX→Gain/Pan→Bus).
  Rev: Architect + audio-thread-reviewer.
- **U5 — Stabilität/State-Recall (Reaper-Ziel):** fullState round-trip, Plugin-Load-Fehler
  isoliert, kein Graph-Absturz. Eigener Härtungs-Zyklus. Rev: Skeptic + e2e.
- **C5b (parallel, klein):** die vereinheitlichten Params im Automations-Sheet der Spur wählbar
  (der `extraAutomatableDescriptors`-Picker zeigt jetzt auch `au.`-Params, sobald U2 bindet).

## Reihenfolge nach diesem Block (Founder-bestätigt)
AUv3-Block (U1–U5 + C5b) → dann C6 Play/Stop pro Clip → C7 Bio-Record → C8 Param-Record →
später flexible Clip-Länge + Taktarten.
