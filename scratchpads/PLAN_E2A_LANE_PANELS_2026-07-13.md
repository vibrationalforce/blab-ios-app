# PLAN — E2a: Comp/Transp/Mood auf die Spur-Tür (Item 4, 2026-07-13)

Council-Verdikt (2026-07-13): Option **C mit A-Muster** — Transpose zuerst als
Proof, dann Mood, dann Composition, je EIGENER Zyklus. „State heben → Leaf →
zweite Tür", Chip bleibt bis Founder-Test (E2c).

## Kontext
- Item 4 = E2-Plan (`PLAN_DMMW_SHELL_V3_2026-07-12.md`). E1 (Chrome-Reorg) ✅.
  E2a = MIDI-Spur-Tür trägt Comp·Transp·Sound·FX·Synth·Mood. Sound/FX/Synth/
  Automation liegen SCHON auf `ArrangeTimelineView.laneDoor`. Delta = **Comp,
  Transp, Mood**.
- Diese Panels sind KEINE eigenständigen Views — Builder in `EchoelStudioView`,
  gekoppelt an dessen privates `@State` (`mood: MoodProfile`, `transposeSemitones`,
  `moodStore: MoodPresetStore`, `soundMoodX/Y`, `showComposition`, Composition =
  Genre/Key/Kammerton/Tempo).
- GESETZE: Sheet-Kette in EchoelStudioView nicht wachsen (SIGSEGV) — aber die
  Spur-Tür nutzt ArrangeTimelineViews EINEN `.sheet(item:)` (`ArrangeModal`),
  dort ist ein Case sicher. Kein 10-Hz-Read im Root. EchoelValueField für Params.
  E2c: Chip fällt NIE vor wirkendem Ersatz (Founder testet).

## Zyklus 1 — TRANSPOSE (kleinster State: ein Float) — PROOF des Musters
1. **`TranspositionStore`** (neu, `Core/`): `@Observable @MainActor`, `semitones:
   Float` (geklemmt z.B. −24…+24, gerundet auf Ganztöne wie heute), persistiert
   (AppStorage/AppGroup wie andere). Reiner Control-State, kein Audio-Thread.
2. **App-Root**: Store als `@State` in `EchoelmusicApp` konstruieren + via
   `.environment(...)` injizieren (Muster wie TimelineStore/FXBioModulator).
3. **EchoelStudioView umhängen**: `transposeSemitones` @State → Store lesen/
   schreiben. **ALLE Consumer greppen** (`grep -n transposeSemitones` — u.a.
   Visual-Farbe Zeile ~435 `moodSnapshot`/Farb-Transpose) und atomar auf den
   Store zeigen. Verhalten BIT-IDENTISCH (gleiches Clamp, gleiche Rundung,
   gleicher Apply-Pfad in die Visual/Take-Transpose).
4. **`TransposeView`-Leaf** (neu, eigenständig): liest `@Environment(TranspositionStore)`,
   ein `EchoelValueField` (Label "Transpose", Halbtöne, − erlaubt). NUR dieser
   Leaf liest den Store → kein Ancestor-Churn.
5. **ArrangeTimelineView**: `ArrangeModal.transpose` Case (in den bestehenden
   EINEN Sheet-Slot) + Menü-Eintrag in `laneDoor` (MIDI-Spur) "Transpose".
   `modalEditor(.transpose)` → `TransposeView()`.
6. **Studio-Chip bleibt** und zeigt dieselbe `TransposeView` (eine Quelle, zwei
   Türen) — NICHT entfernen (E2c).
7. **Test-first**: `TranspositionStoreTests` (Clamp −24…24, Ganzton-Rundung,
   Persist round-trip). Apply-Pfad-Regression: Visual-Farbe nutzt weiter denselben
   Wert (manueller grep-Beweis + ggf. ein Wert-Test des Farb-Transpose-Helfers).
8. Reviewer: ui-state (Leaf-Isolation, Sheet-Slot) + concurrency (Store @MainActor).

## Zyklus 2 — MOOD (größerer State: MoodProfile + moodStore + soundMoodX/Y)
- `MoodStore`/`MoodEngine` heben (MoodProfile + Preset-Store + Sound-Pad-Position).
  Standalone `MoodView`-Leaf. Spur-Tür-Case + Chip bleibt. Vorsicht: die zwei
  Mood-Pads + Preset-Save-Flow mitnehmen; Save-Sheet ist ein SUBVIEW-Sheet.

## Zyklus 3 — COMPOSITION (Genre/Key/Kammerton/Tempo)
- Composition-State prüfen: liegt Genre/Key/Kammerton/Tempo schon in einem Store
  (BodyTempoField deutet auf geteilten Tempo-State) oder in EchoelStudioView-@State?
  Entsprechend heben. Standalone `CompositionView`-Leaf. Spur-Tür-Case + Chip bleibt.
- ACHTUNG: `BodyTempoField` = die EINE Tempo-Kontrolle; nicht duplizieren.

## Zyklus 4 — E2c: Chips schrumpfen (NUR nach Founder-Test)
- Wenn Founder bestätigt, dass die Spur-Türen wirken: die Studio-Chip-Leiste
  (Comp/Transp/Mood-Chips) entfernen/verkleinern. NICHT vorher. Session-Chip
  bleibt (nicht spur-gebunden; Endziel E4 EchoelBioSynth).

## Fallen (Skeptic)
- `transposeSemitones` speist die Visual-Farbe — beim Heben KEINEN Consumer
  vergessen (grep-Vollständigkeit), sonst driftet die Farbe.
- Nicht in EchoelStudioViews Sheet-Kette anfassen — die Spur-Tür ist ArrangeTimelineView.
- Registry-Migration (Transpose als AUParameter) = E4-Scope, JETZT nicht.
