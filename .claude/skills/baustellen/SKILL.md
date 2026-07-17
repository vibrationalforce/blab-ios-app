# Baustellen — board-getriebener Closeout-Loop (ECC-Muster, Echoel-eigen)

Adoptiert aus „Everything Claude Code" (Founder-Reel 2026-07-17) sind die MUSTER —
Verification-Loop + Board-Orchestrierung — nicht das Paket (Entscheid in
decisions.csv 2026-07-17). Das Board ist `scratchpads/BAUSTELLEN_BOARD.md`.

## Das Gesetz des Loops

**Keine Baustelle gilt als geschlossen ohne ihren Verify-Weg.** Der Verify-Weg
steht als Spalte am Board und ist fast immer der Founder-Gerätetest (Modus-Lehre:
sein Test IST das Verify; CI-grün ist nur das Gate davor). „Code gepusht" ≠ fertig.

## Loop (jede Session / jeder Heartbeat)

1. **Board lesen** (`scratchpads/BAUSTELLEN_BOARD.md`) — VOR dem Task-Tool; das
   Board ist die konsolidierte Wahrheit, die Task-Liste die Historie.
2. **Oberste AKTIV-Zeile ziehen**, deren nächste Slice nicht blockiert ist.
   Founder-Direktiven des Tages überstimmen die Reihenfolge sofort.
3. **Slice bauen** (integriert, nicht Ein-Punkt — Founder-Verdikt 07-17), Route-
   Spalte beachten (Reviewer-Agent, Plan-Dokument, Copy-Gesetz).
4. **Gates** (Xcode Compile Check + CI/CD) → **jede grüne Runde deployt**
   (`.deploy/release`-Bump) mit deutscher, founder-lesbarer Release-Note, die den
   Verify-Weg als Test-Bitte formuliert („öffne X, prüfe Y").
5. **Board aktualisieren**: Slice-Fortschritt, Verify-Spalte (CI ✓ / Gerät offen /
   Founder ✓ + Build-Nummer), Erledigtes in die ERLEDIGT-Tabelle (nie löschen),
   Blockiertes nach BLOCKIERT mit dem, worauf es wartet.
6. **Lernen persistieren**: echte Dead-Ends/Playbooks → `HARNESS_LEDGER.md`
   (unser Instinct-System), Entscheide → `decisions.csv` + `memory/decisions.md`.

## Board-Pflege-Regeln

- Neue Founder-Asks landen SOFORT als Zeile (Quelle verbatim-Kern + Datum).
- Jede Zeile braucht: Nächste Slice (konkret, heute baubar) + Verify-Weg
  (was der Founder auf dem Gerät sieht/hört). Fehlt einer, ist die Zeile
  unfertig — zuerst schärfen.
- BLOCKIERT-Zeilen nennen exakt das fehlende Artefakt (z.B. „Log nach Neustart");
  bei jedem Founder-Kontakt die oberste Blockade EINMAL freundlich erinnern.
- Maximal ~6 AKTIV-Zeilen; der Rest wartet in OFFEN (Fokus schlägt Breite).

## Grenzen

Ersetzt weder Council (Entscheidungen) noch Ralph-Loop (Build-Disziplin) noch die
harten Gesetze (Audio-Thread, Rausch-Triade, Sheet-Decke, 10-Hz-Regel). Kein
Import externer Skill-Pakete ohne Founder-Entscheid.
