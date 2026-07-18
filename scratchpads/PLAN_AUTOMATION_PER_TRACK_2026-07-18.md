# PLAN — Per-Track Automation Targeting (Item 1, L2/L4), 2026-07-18

> Founder-REIHENFOLGE Item 1 verlangt „alle Parameter … **in der Spur**". L1
> (im Clip zeichnen: `ClipAutomationView`, S2b, grün) + Cross-Clip
> (`TimelineAutomationRow`, T1) sind gebaut. Die verbleibende EHRLICHKEITS-
> SCHULD ist **L2**: zwei Spuren, die „Filter Cutoff" wählen, editieren
> HEUTE DIESELBE globale Kurve (dokumentiert `TimelineAutomationRow:11-16`).
> Dieser Plan macht „Cutoff DIESER Spur" adressierbar. „ERST PLAN + Council."

## IST-STAND (Voll-Audit Explore-Agent 2026-07-18 — mit Zitaten)

- **Registry:** keyPaths sind GLOBAL, Engine-scoped — `"modul.sektion.param"`
  (`EchoelParameterRegistry.swift:9-11,29`). KEIN `track.<id>`-Namespace. DDSP =
  eine flache globale Liste (`DDSPParameterCatalog.descriptors:126-158`).
- **Router:** `ParameterApplyRouter.applyNormalized(keyPath,n)` = flache
  `[String:(Float)->Void]`-Tabelle (`:33,57-63`) → EINE globale Stimme. Kein
  Lane/Slot-Argument.
- **Pro-Spur-Stimmen EXISTIEREN** (default-on): `LaneVoiceRack.voices:
  [PolySynthVoice]` (`LaneVoiceRack.swift:46,99`), **slot-keyed** (`voice(slot:)
  :138`), Slot↔Lane in der PUREN Fanout-Schicht (`MultiRollFanout.laneID(forSlot:)
  /secondaryLaneIDs :46-79`). **Slots sind rank-instabil zwischen Plays**
  (`:114-115`). Deren Setter (`setGain/setInsert/applyPatch(slot:…)`) sind NICHT
  in Registry/Router.
- **AutomationLane:** `parameter:String`, KEIN trackID (`AutomationLane.swift:74-86`).
  `AutomationPlayer.dispatchLane :242-249` routet unbekannte keyPaths direkt an
  `router.applyNormalized` — **null Player-Änderung für neue keyPaths**.

## DER SEAM (billigster ehrlicher Pfad — kein Model/Player-Refactor)

Ein Parameter wird pro Spur adressierbar durch **String-Namespace**:
`"track.<laneID>.ddsp.filter.cutoff"`. Der Router bindet pro Spur eine Closure,
die **zur Dispatch-Zeit** (nicht Bind-Zeit — Slots sind rank-instabil!) laneID→
slot via `MultiRollFanout` auflöst und den Slot-Setter auf `LaneVoiceRack` ruft.
`AutomationLane`/`AutomationPlayer`/`TimelineDocument` bleiben unberührt (die
Kurve trägt nur einen namespaced String).

## COUNCIL — L2/L4 Seam

**Frage:** Wie „Cutoff DIESER Spur" adressierbar machen, ohne Player/Model-Refactor
und ohne den globalen Automations-Pfad zu brechen?

- **Architect:** String-Namespace + lane-auflösende Router-Closure nutzt die
  bestehende string-getriebene Router-Tabelle → KEINE Router-API-Änderung, KEIN
  neues Store-Modell. `AutomationLane` bleibt gleich (der Namespace lebt IM
  parameter-String). Sauberste Kopplung: pur-Helper (`PerTrackParameterKeyPath`)
  fürs Falten/Parsen, die Verdrahtung liest nur `MultiRollFanout` (existiert).
- **Skeptic:** Die EINE Falle ist Slot-Instabilität — bind-zeitiges Cachen von
  laneID→slot ergibt beim nächsten Play die falsche Spur. Muss zur Dispatch-Zeit
  aufgelöst werden. Zweitens: ohne Auflösung (Spur gelöscht) muss der Write ein
  stiller No-Op sein, nie ein Crash/Fehlgriff auf fremde Spur.
- **DSP-Purist:** Apply-Pfad ist MainActor/Launch-zeitig, kein Audio-Thread. Die
  Slot-Setter auf `LaneVoiceRack` sind schon die Live-Apply-Bahn. Sauber.
- **User-Advocate:** Der Picker muss „Filter cutoff" auf Spur A von Spur B
  unterscheidbar zeigen (displayName mit Spur-Tag). Sonst bleibt die Lüge sichtbar.
- **Shipper:** In Scheiben, test-first-zuerst:
  - **S1 (PUR, jetzt):** `PerTrackParameterKeyPath` — falten/parsen/Pro-Lane-
    Descriptor-Bau. Foundation-only, Linux-CI, 0 Gerät, 0 Kopplung. Tests: roundtrip
    (Base MIT Punkten!), global→nil, malformed→nil, Descriptor-Klon erbt Range/Unit.
  - **S2 (Verdrahtung):** pro Sekundär-Lane die namespaced DDSP-Descriptors in die
    Registry registrieren + Router-Closures binden, die laneID→slot ZUR DISPATCH-
    ZEIT via `MultiRollFanout` auflösen → `LaneVoiceRack`-Slot-Setter. Fehlende
    Auflösung = stiller No-Op. (Geräte-verifiziert — betrifft die Voice-Racks.)
  - **S3 (UI):** der Ziel-Picker (ClipAutomationView / TimelineAutomationRow) bietet
    pro Spur ihre namespaced Params statt/ergänzend zu den globalen.

**Dissens (benannt):** Skeptic würde S2 lieber hinter einem Flag halten, bis die
Slot-Instabilität geräte-verifiziert ist — angenommen: S2 kommt geräte-gated,
S1 ist reiner Spine ohne Laufzeit-Effekt (nichts konsumiert die neuen keyPaths,
bis S2 sie bindet → global byte-identisch). **Gate: proceed mit S1 (pur, jetzt),
S2/S3 als benannte Folge-Slices (S2 geräte-verifiziert).**

## GESETZE
- S1 ist rein additiv, kein Konsument → globaler Pfad byte-identisch (Golden-Gate).
- Slot-Auflösung NUR zur Dispatch-Zeit (S2) — nie bind-zeitig cachen.
- Fehlende Lane/Slot-Auflösung = stiller No-Op, nie Fremdgriff.
- Audio-Thread unberührt (Apply MainActor/Launch-zeitig).
- Kein 10-Hz-Read; keine neue Sheet (S3 erweitert bestehende Picker).
- Conventional Commits + Fable-5-Trailer; Pflicht-Reviewer je Slice.
