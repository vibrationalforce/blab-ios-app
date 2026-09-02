# PLAN — Per-Lane SynthPatch Authoring (#23 completion)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


> Founder-Quelle #23: „each MIDI track carries its own optional SynthPatch" —
> per-Instrument-Klangfarbe pro Spur, wie ein echtes DAW.
> Council 2026-07-18: **stage it — persist first (testbar), Live-Preview-auf-der-
> richtigen-Stimme später (geräteabhängig).** Gate: proceed (PLAN this cycle).

## IST-Zustand (investigiert 2026-07-18)

Der Kern ist SCHON DA — nur die Editor-Tür ist nicht spur-spezifisch verdrahtet:

| Baustein | Status | Datei |
|---|---|---|
| `TimelineLane.patch: SynthPatch?` (persistiert, Codable) | ✅ existiert | `Sequencer/Timeline.swift:53` |
| Sekundär-Lanes wenden `lane.patch` bei Region-Load an | ✅ verdrahtet | `MultiRollFanout.patch(forSlot:in:rollLane:)` → `slotPatchSink` (TimelineRegionPlayer:594/668/960) → `LaneVoiceRack.applyPatch(slot:_:)` (App:618) |
| `PatchEditorView` hat `onApply: (SynthPatch)->Void` Hook | ✅ existiert, ungenutzt | `Studio/PatchEditorView.swift:23/25`, apply bei `:91/92` (`voice.apply(patch); onApply(patch)`) |
| **Editor-Tür editiert die GLOBALE `PolySynthVoice`, NICHT die Lane** | ❌ die Lücke | `ArrangeTimelineView.swift:428-435` — `PatchEditorView(initial: synth.appliedPatch)` OHNE `onApply` → Edits treffen nur die geteilte Stimme, nie `lane.patch` |
| Primär-Roll-Lane == globale `PolySynthVoice` (keine persistierte per-Lane-Patch) | ⚠️ Design-Frage | — |

Der Kommentar an der Tür gibt es selbst zu: *„Honest limit (multi-roll pending):
this edits THE melodic instrument all MIDI lanes share today."*

## DESIGN-SPANNUNG (Council-Kern)

1. **Live-Apply-Ziel divergiert:** `PatchEditorView` live-applied jeden Tick auf
   die env-gebundene GLOBALE `voice` (`@Environment(PolySynthVoice.self)`). Für
   eine SEKUNDÄR-Lane müsste das auf DEREN Rack-Stimme
   (`LaneVoiceRack.applyPatch(slot:)`) gehen, nicht die globale. Das ist der
   geräte-riskante Teil (kein lokaler Compiler → nicht blind).
2. **Primär-Lane-Patch-Persistenz:** heute IST die Primär-Lane die globale Stimme;
   ihr Klang = der live-editierte `appliedPatch` (nicht per-Lane persistiert).
   Entscheidung: Primär-Lane bekommt AUCH `lane.patch` (persistiert), das beim
   Play/Region-Load auf die globale Stimme angewandt wird — symmetrisch zu den
   Sekundär-Lanes. So überlebt die Primär-Klangfarbe Save/Load und ist pro
   Session-Dokument ehrlich, statt nur flüchtiger globaler Zustand.

## SLICES (jede reviewer-gated; Golden-Gate = globaler Editor byte-identisch wenn keine Lane übergeben)

### S1 — `TimelineStore.setLanePatch(laneID:_:)` + Tests [PUR, Linux-CI, 0 Geräterisiko]
- `TimelineStore.setLanePatch(laneID: UUID, _ patch: SynthPatch?)`: setzt `lane.patch`
  (nil = zurück auf Default/geteilt), EIN Undo-Schritt (Dokument-Historie), gleiches
  Muster wie `setLaneTranspose`/`setLaneDetune` (Pitch-Familie-Spine, HARNESS_LEDGER).
- **Additive-Codable ist schon erfüllt** (`lane.patch` existiert + decodet). KEIN
  neues Feld → kein Song-Verlust-Risiko.
- Tests: setLanePatch setzt/löscht; nil-Collapse; Undo/Redo; andere Lane-Felder
  bleiben unberührt. Alle headless-testbar (kein Audio).
- **Reviewer:** code-reviewer (Store-Mutation, Undo-Kohärenz).

### S2 — `.patch(lane)` Modal-Payload + persist via onDismiss [reviewer-gated, kein Render-Pfad]
- **S1 ✓ (b2f7750):** `TimelineStore.setLanePatch(_:patch:)` + 4 Tests, code-reviewer 0 Defekte.
- `ArrangeTimelineView` Modal-Enum: `case patch` → `case patch(TimelineLane)` (Payload
  wie `.laneFX(let lane)` schon hat); `id: return "patch-\(l.id)"`. **KEINE neue `.sheet`** —
  nur Payload an bestehendem Case (Sheet-Ketten-Gesetz respektiert; EIN `.sheet(item:)`).
- Tür (`activeModal = .patch` an der Lane-Menü-Zeile ~914) → `.patch(lane)`.
- Editor-Seed: `PatchEditorView(initial: lane.patch ?? (istPrimär ? (synth.appliedPatch ??
  SynthPatch(name:"Init")) : SynthPatch(name:"Init")), onApply: { latest = ($0) })`.
- **⚠️ RECON-BEFUND (Editor-Hook, PatchEditorView:91/92):** `onApply` feuert bei JEDEM
  `onChange(of: patch)` — d.h. bei JEDEM Drag-Tick, nicht nur bei „Done". `onApply →
  store.setLanePatch(...)` DIREKT würde `persist()` bei Drag-Rate (~60/s) fluten (jeder
  Tick schreibt `document.lanes[i].patch` + `@Observable`-Invalidierung der ganzen
  `document.lanes`). **LÖSUNG:** onApply schreibt nur ein Host-`@State private var
  pendingLanePatch: (UUID, SynthPatch)?` (billige Zuweisung, KEIN persist); der
  bestehende `.sheet(item:)`-`onDismiss:` (Zeile 212) persistiert EINMAL:
  `store.setLanePatch(id, patch: pending.patch)`. So kein Flut, kein Live-Apply-Change
  (Editor live-applied weiter auf die globale env-`voice` — der ehrliche S2-Limit:
  während des Editierens hört man die globale Stimme, beim Schließen wird `lane.patch`
  persistiert und beim nächsten Region-Load gehört).
- Der bestehende `slotPatchSink`/Re-Prime wendet `lane.patch` bei nächstem Region-Load an
  (Sekundär); Primär-Sink (S2b) wendet auf die globale Stimme an.
- Golden Gate: kein parameterloser `.patch`-Aufruf bleibt übrig (alle Türen tragen jetzt
  die Lane) → kein toter Code, aber der globale Editor bleibt funktional identisch für die
  Primär-Lane (gleicher Seed via `synth.appliedPatch`).
- **Reviewer:** ui-state-reviewer (Modal-Payload, Freeze — Editor liest keine 10-Hz-Bio;
  Sheet-Ketten-Gesetz; onDismiss-Persist-Timing), code-reviewer.

### S2b — Primär-Lane-Patch-Anwendung bei Play/Load [wire, reviewer-gated]
- Primär-Roll-Lane: beim Play/Region-Load `lane.patch` (falls gesetzt) auf die
  globale `voice.apply(...)` anwenden (analog zum Sekundär-`slotPatchSink`, aber slot
  = primär). So ist die Primär-Klangfarbe dokument-persistiert.
- **Reviewer:** code-reviewer + audio-thread-reviewer (apply ist Kontrollebene, kein
  Render — aber Timing bei Region-Load prüfen).

### S3 — Lane-bewusstes Live-Apply-Ziel [GERÄTE-GATED, zuletzt]
- Damit ein Drag im Editor eine SEKUNDÄR-Lane live vorschaut (nicht die globale
  Stimme), muss der Editor eine lane-spezifische Apply-Closure bekommen statt der
  env-`voice`. Council: **das ist der riskante Teil — erst wenn ein Gerät-/Compiler-
  Takt verfügbar ist**, sonst blind-Fehlerrisiko (falsche Stimme / Doppel-Apply).
- Bis dahin: Sekundär-Lane-Patch wird bei Apply persistiert + beim nächsten
  Region-Load gehört (kein Live-Drag-Preview auf Sekundär). Ehrlich, kein Regress.

## GESETZE / RISIKO
- Sheet-Kette: Payload an bestehendem Case, KEINE neue `.sheet`. ✅
- Freeze: Editor liest keine Hochfrequenz-Bio im Body. ✅
- decodeIfPresent: `lane.patch` schon additiv. ✅
- Kein Render-Pfad-Code in S1/S2/S2b (Kontrollebene). S3 erst mit Gerät.
- Rollback je Slice: S1 = Methode+Tests entfernen; S2 = Payload zurück auf
  parameterlos; S2b = Primär-Sink entfernen.

## VERIFY-WEG (Board)
Founder öffnet auf zwei MIDI-Spuren je die Synth-Patch-Tür, gibt jeder eine andere
Klangfarbe, spielt → **beide Spuren klingen unterschiedlich** (heute klingen alle
gleich). Gerät-Hörtest = der Closeout.

## NÄCHSTER TAKT
S1 bauen (pur, test-first, Linux-CI-grün) — der einzige Slice der OHNE Gerät voll
verifizierbar ist. S2/S2b danach reviewer-gated; S3 wartet auf einen Gerät-Takt.
