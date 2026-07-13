# QA-Audit — externe AUv3-Türen (Item 3), 2026-07-13 — GESCHLOSSEN

Read-only Code-QA (kein Crash, keine ungesicherten Indizes, keine harten Sackgassen —
jede Sheet hat funktionierendes „Done"). 6 Befunde. Endstand unten.

## Behoben (Code)
- **#1 MEDIUM — Overclaim State-Recall (f8aa5ae).** Browser sagte „Settings are saved
  and recalled across sessions", real nur `fullState` (Knobs) pro Plugin-ID; die
  geladene Plugin-AUSWAHL wird beim Start nicht re-instanziiert. Copy ehrlich gemacht
  („Each plugin's own settings return when you reload it"). Echtes Auto-Reload = U5.
- **#2 MEDIUM — Concurrent loads ohne Guard (7d1ccf2).** `guard !isLoading` in
  `load()`/`loadMasterEffect()` (der @MainActor-Prolog ist synchron → der zweite Tap
  sieht true und returned) + `.disabled(host.isLoading)` auf den Rows. Concurrency-
  reviewed, 0 Issues.
- **#5 LOW — stale loadError (3c9a3e5).** `clearLoadError()` in `onAppear` → ein alter
  Fehler bleibt beim Browser-Reopen nicht stehen.

## Verifiziert — kein Code nötig
- **#4 LOW-MED — leere Plugin-UI: SCHON GELÖST.** `AUv3PluginContainerVC.attach(_:)`
  (AUv3PluginUIView.swift:63-68) behandelt nil `childVC` explizit: „This plugin has no
  custom interface on iOS." Die QA war ein „verify" → bereits abgedeckt.
- **#6 LOW — dup-effect ohne Cue: REDUNDANT.** Die `loadedBar` listet jede Effekt-
  Instanz einzeln (`→ FXName`); Picker-Zeilen geladener Effekte sind `highlighted`.
  Duplikate sind bereits sichtbar → kein Fix.

## Offen — NICHT allein baubar
- **#3 MEDIUM — U3b-Belegung stale + heute klanglich inert** (Routing wartet auf
  Multi-Roll). Badge/Summary impliziert aktives Plugin; nach Unload/Swap zeigt
  `lane.instrument` weiter das alte Ref. Als „persisted intent" dokumentiert. Optionen:
  Assign hinter echtes Routing gaten ODER Summary annotieren — **Founder-Entscheid**
  ODER löst sich mit Multi-Roll (Z6 Per-Spur-Instrument-Verdrahtung).

## Verwandt: U5 (echtes State-Recall, deferred Feature)
Auto-Reload der letzten Rig-Auswahl beim Start (Instrument + Insert-FX + Master-FX
re-instanziieren, dann `restoreState`). Berührt live audio graph (async) → e2e-Review +
Device-Messung. Löst #1 in echt und macht #3 klanglich real (mit Multi-Roll-Routing).

## Kategorie-Verdikte (clean)
- Index-Safety: CLEAN (alle `indices.contains`-guarded; parallele Arrays sync, kein
  await dazwischen, @MainActor seriell).
- `isLoading` stuck-true: war nur im Concurrent-Fall (#2) erreichbar → mit #2 behoben.

**FAZIT:** Item-3-QA geschlossen. Alle substanziellen Befunde behoben; Rest verifiziert
harmlos oder = Founder-Entscheid/Multi-Roll-Scope. Kein offener Code-Punkt.
