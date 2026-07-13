# QA-Audit — externe AUv3-Türen (Item 3), 2026-07-13

Read-only Code-QA (kein Crash, keine ungesicherten Indizes, keine harten Sackgassen —
jede Sheet hat funktionierendes „Done"). 6 Befunde, gerankt. Fixes einzeln, Ralph-Takt.

## Behoben
- **#1 MEDIUM — Overclaim State-Recall (BEHOBEN, f8aa5ae).** Browser sagte „Settings are
  saved and recalled across sessions", real nur `fullState` (Knobs) pro Plugin-ID; die
  geladene Plugin-AUSWAHL wird beim Start nicht re-instanziiert. Copy ehrlich gemacht.
  Echtes Auto-Reload = U5.

## Offen (Follow-ups, gerankt)
- **#2 MEDIUM — Concurrent loads ohne Guard.** `AUv3Host.load`/`loadMasterEffect` async
  mit `await instantiate`; Browser-Rows feuern je ein `Task { await host.load }` ohne
  Row-Disable. `isLoading` ist Display-Flag, kein Mutex → zwei schnelle Taps: Spinner
  räumt früh ab (last-writer-wins), Replace/Detach-Branch kann gegen mid-flight-Instrument
  laufen. FIX: Re-Entrancy-Guard (ignorieren/queuen während `isLoading`) und/oder Rows
  disablen. **NÄCHSTER Item-3-Zyklus (braucht concurrency-reviewer, live load path).**
- **#3 MEDIUM — U3b-Belegung wird stale + ist heute klanglich inert** (Routing wartet auf
  Multi-Roll). Badge/Summary impliziert aktives Plugin; nach Unload/Swap zeigt
  `lane.instrument` weiter das alte Ref. Als „persisted intent" dokumentiert (Commit +
  CLAUDE.md), aber User weiß nicht, dass es (noch) nichts hört. Optionen: Assign hinter
  echtes Routing gaten ODER Summary annotieren „(gilt, sobald Per-Spur-Routing kommt)".
  → Founder-Entscheid ODER mit Multi-Roll auflösen.
- **#4 LOW-MED — Plugin-UI-Sheet evtl. leer** für AUs ohne eigene UI (`AUv3PluginUIView`
  bei nil `requestViewController`). Kein Dead-End (Done dismisst), aber keine „kein
  Interface"-Meldung. FIX: Leerfall-Text.
- **#5 LOW — `loadError` bleibt stale** über Browser-Close/Reopen (nur bei nächstem
  Load-Start geleert). FIX: bei `onAppear`/`scan()`/erfolgreichem `unload` clearen.
- **#6 LOW — Doppelte Effekt-Insertion** ohne Cue (Tap zweimal = zwei Instanzen; laut
  Kommentar beabsichtigt). FIX: dezenter Hinweis/Bestätigung.

## Verwandt: U5 (echtes State-Recall, deferred)
Auto-Reload der letzten Rig-Auswahl beim Start (Instrument + Insert-FX + Master-FX
re-instanziieren, dann `restoreState`). Berührt live audio graph (async) → e2e-Review.
Löst #1 in echt und macht #3 klanglich real (in Verbindung mit Multi-Roll-Routing).

## Kategorie-Verdikte (clean)
- Index-Safety: CLEAN (alle `indices.contains`-guarded; parallele Arrays sync, kein await
  dazwischen, @MainActor seriell).
- `isLoading` stuck-true: nur im Concurrent-Fall (#2) erreichbar; Single-Load do/catch
  räumt auf beiden Pfaden ab.
