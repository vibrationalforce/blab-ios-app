# PLAN H11 — MIDI-Clip-Edit clip-scoped + Rückschreiben (M3) — 2026-07-15

Founder-Mandat: "MIDI Clip und Audio Clip verhalten sich nicht wie von einer
professionellen Software erwartet." Audit abgeschlossen (Explore, 2026-07-15);
Council: proceed.

## Befund (der Bug, exakt)

- Long-press MIDI-Region → "Edit" → `activeModal = .region(region)` →
  `modalEditor` (ArrangeTimelineView:222) liest von der Region NUR den
  Clip-KIND und öffnet `PianoRollView(pattern:, model: pianoRoll)` — die
  **app-weite geteilte Roll** (Env-Instanz, :28/:243). Die Clip-Noten werden
  nie geladen, Edits landen nie im Clip.
- Schlimmer: der Player schreibt bei JEDEM Region-Onset in genau dieses
  geteilte Model (`loadClip` → `pianoRoll.loadRegionArrangement`,
  TimelineRegionPlayer:318; `clearRoll` → `load([])`, :328) — editiert man
  während des Abspielens, clobbert die nächste Region-Grenze die Edits.
- Noten liegen inline im Clip: `Clip.melody: MelodyClip { notes: [Note] }`
  (Clip.swift:19-22/:77), Player fenstert sie pro Region
  (RegionNoteWindow.windowed, TimelineRegionPlayer:312-316).
- `ClipStore` hat KEINE Update-by-id-API (nur setClip(at:)/rename/clear,
  slot-indexbasiert) — das fehlende Stück.
- KEIN Clip-INHALT-Write-back-Präzedenzfall im Repo: alle Timeline-Edits
  (split/merge/trim) mutieren nur Region-Tick-Fenster, nie den Clip.

## Design (ein Zyklus)

1. **`ClipStore.updateMelody(id: UUID, notes: [Note]) -> Bool`** — Slot per
   clip.id finden, `slots[i]?.melody = MelodyClip(notes:)`, `persist()`.
   Ganzwertiges Schreiben (Clip/MelodyClip sind value types) — kein torn read;
   mid-play wird die Änderung ehrlich erst am nächsten Region-Onset hörbar
   (DAW-üblich).
2. **Clip-scoped Editor im BESTEHENDEN `.region`-Slot** (Sheet-Ketten-Gesetz:
   ArrangeTimelineView besitzt genau EIN `.sheet(item:)` — nur Routing in
   `modalEditor`/`editor` ändern, KEIN neues Sheet): für `.region(region)` mit
   Clip-Kind .midi ein Wegwerf-`PianoRollModel()` bauen, Clip-Noten laden,
   `PianoRollView(pattern:, model: wegwerf)` präsentieren.
3. **Rückschreiben bei "Done"**, Swipe-Dismiss = Cancel (Wegwerf-Model
   verwirft sich). Note-Edits sind v1 NICHT im Timeline-Undo (der Undo-Stack
   snapshottet bewusst nur document.regions) — ehrlich dokumentieren;
   Cancel-Semantik ist der Revert-Pfad.
4. **MULTI-BAR-GATE (Skeptic, Datenverlust-Falle):** `foldToBar`/`importNotes`
   falten mehrtaktige Inhalte in EINEN Takt — naives `model.notes`-Rückschreiben
   flacht einen N-Takt-Clip ab. VOR dem Bau verifizieren, wie
   `PianoRollModel` mehrtaktige Arrangements hält (`loadRegionArrangement`,
   `arrangementForExport(bars:)`): (a) verlustfreier Roundtrip möglich →
   ganzen Clip editieren; (b) sonst Editor auf das REGION-Fenster scopen
   (windowed slice rein, slice zurückschreiben, Rest des Clips unangetastet)
   ODER Write-back bei N>1 Takten mit ehrlichem Hinweis deaktivieren —
   NIEMALS stumm abflachen.
5. Tests: updateMelody (id-Lookup, persist, unbekannte id ⇒ false) pur;
   Roundtrip-Gesetz (laden→unverändert schließen ⇒ byte-identische notes);
   Multi-Bar-Gate je nach (a)/(b).
6. Reviewer: code-reviewer + ui-state-reviewer (Modal-Routing, Observation).

Betroffene Dateien: Core/ClipStore.swift · Studio/ArrangeTimelineView.swift
(Routing) · ggf. Studio/PianoRollView.swift (Done-Hook) · Tests. ≤4 Dateien.

## Abgrenzung

- H13 (Audio-Audition/Edit-Tür mit Offset) = eigener Zyklus, gleiche
  Tür-Mechanik, anderer Editor.
- Sekundär-Lanes lesen dieselben Clip-Noten (LaneNotePump, :369/:419) —
  Write-back wirkt automatisch auch dort (nächster Onset), nichts extra nötig.
