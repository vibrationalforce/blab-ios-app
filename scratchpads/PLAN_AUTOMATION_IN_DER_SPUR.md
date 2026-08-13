# PLAN — Automation in der Spur (REIHENFOLGE Punkt 1)

**Founder-Ask (v10.79.183):** *„AUTOMATION IN DER SPUR (im Clip UND clip-übergreifend, alle
Parameter via `EchoelParameterRegistry`) — ERST PLAN + Council, dann Zyklen."*

Stand: 2026-08-12, Branch `claude/echoelmusic-neustart-auv3-6ri2ek`. Jede Zahl unten ist
gemessen; die Befehle stehen daneben, damit die nächste Sitzung sie neu ableitet statt sie zu
glauben.

---

## 1. Die überraschende Messung: es ist zu ~90 % gebaut

Der Ask liest sich wie ein neues Feature. Gemessen ist er **eine fehlende Tür auf einer
vollständigen Maschine.** Das ändert die Größe der Arbeit um eine Größenordnung und ist der
Grund, warum dieser Plan existiert, bevor irgendein Zyklus beginnt.

| Schicht | Zustand | Beleg |
|---|---|---|
| **Speicher, song-absolut** | `TimelineDocument.automation: [AutomationLane]`, 480-PPQ, persistiert | `Core/TimelineStore.swift:710 ff.` |
| **Speicher, pro Spur** | `TimelineLane.automation: [AutomationLane]` | `Sequencer/Timeline.swift:484` |
| **Speicher, im Clip** | `Clip.automation: [AutomationLane]` | `Sequencer/Clip.swift:189` |
| **Mutation** | `addPoint` · `movePoint` · `removePoint` · `setValue` · `setCurve` — komplett, inkl. Identitäts-Zusammenführung von Legacy-Enum und Registry-keyPath | `TimelineStore.swift:728–795` |
| **Wiedergabe** | `TimelineRegionPlayer` schiebt die Lanes bei `play()` UND bei jedem strukturellen Refresh in `AutomationPlayer`s Timeline-Schicht; eine Automations-Änderung IST strukturell (`structurallyEqual` vergleicht sie) | Kommentar `TimelineStore.swift:711–716` |
| **Anwendung** | `AutomationPlayer.applyStep(_:)` auf jedem Transport-Schritt → `ParameterApplyRouter` → lebende Stimme; kein Audio-Thread-Zugriff | `AutomationPlayer.swift`, gerufen aus `PianoRollView.swift:833` |
| **Zeichen-Mathematik** | `AutomationCanvasMath` (A3: tap-add · drag-move · segment-bend · double-tap-delete), `ClipAutomationEdit`, `TimelineAutomationRowMath` — rein, getestet | 3 Dateien unter `Sequencer/` |
| **Aufnahme** | `BioAutomationRecorder` (1 Parameter), `AutomationGestureRecorder` (N Parameter), `SpatialAutomationMapping` | `Sequencer/` |
| **Parameter-Inventar** | `EchoelParameterRegistry`, keyPath-stabil, in 5 Dateien live | `Core/EchoelParameterRegistry.swift` |

**Was fehlt, gemessen:**

```
git grep -n "addAutomationPoint\|moveAutomationPoint\|removeAutomationPoint\|setAutomationCurve" \
  -- Sources Tests/CISmoke     →  0 Treffer außerhalb von TimelineStore.swift selbst
```

**Null Aufrufer.** Die komplette Mutations-API ist verwaist, seit `TimelineAutomationRow` mit
#473 gelöscht wurde. Ebenso: `RecordController.arm()` hat null Aufrufer (#204), also erreicht
auch der Aufnahme-Pfad keine Lane. `AutomationPlayer.enabled` steht per Default auf `false`
(bewusst konservativ) und hat keinen erreichbaren Schalter.

⚠️ **ZWEI Automations-Systeme, nicht eines — wer das verwechselt, plant am falschen vorbei.**
`AutomationPlayer` hat ein EIGENES persistiertes Dokument (`automation.json`) mit einem
**Drei-Fälle-Enum** `AutomationTarget` (`masterLevel` · `tempo` · `filterCutoff`). Die
`AutomationLane`-Schicht auf Document/Spur/Clip ist davon getrennt und wird in den Player
hineingeschoben. Der Registry-keyPath-Alias existiert bereits auf dem Enum
(`AutomationPlayer.swift:28–40`) und `TimelineAutomationRowMath.sameParameter` führt beide
Identitäten zusammen.

⛔ **UND HIER STAND „ABER DER ZIEL-VORRAT IST BIS HEUTE DREI" — DAS IST FALSCH, und der Beleg
liegt zwölf Zeilen unter dem Enum, das ich gelesen habe (#555).** `applyStep` hat nach der
Enum-Schleife eine ZWEITE:

```swift
for lane in lanes where AutomationTarget.forParameter(lane.parameter) == nil {
    if let n = lane.value(atTick: step * Note.ticksPerStep) {
        router?.applyNormalized(lane.parameter, Float(n))
    }
}
```

**Beliebige Registry-keyPaths werden bereits über `ParameterApplyRouter` verteilt**, dazu je eine
eigene Schleife für die Clip- und die Timeline-Schicht (`dispatchLane`). Das Enum ist der
LEGACY-Schnellpfad für drei persistierte Alt-Identitäten, nicht die Obergrenze.

⭐ **Der echte Engpass ist eine Ebene tiefer und hat eine andere Zahl: die SETTER-BINDUNG.**
Gemessen: die Registry deklariert **15** keyPaths (`grep -o 'keyPath: "[^"]*"'
Sources/Echoelmusic/Core/EchoelParameterRegistry.swift | wc -l`), gebunden sind **6** —
`PolySynthVoice.automatableBases` (`warmth.drive` · die vier Hüllkurven-Zeiten · `amp.level`).
Ungebunden bleiben neun, darunter `osc.brightness`, `osc.harmonicity`, `osc.noiseLevel`,
`mod.vibratoDepth/Rate` und `filter.cutoff`. `router.applyNormalized` auf einen ungebundenen
keyPath ist ein stiller No-op — **also ist eine Lane auf einem dieser neun heute eine Lane, die
nichts bewegt.** `ParameterApplyRouter.automatableDescriptors()` bildet genau die ehrliche
Schnittmenge (Registry ∩ gebunden) und existiert bereits.

**Lehre, und sie ist die dieser Sitzung — ich bin ihr in meinem eigenen Plan aufgesessen:** ich
habe den Ziel-Vorrat am ENUM abgelesen und aufgehört, bevor die nächste Schleife kam. Genau die
#546-Klasse („eine Abbildung ist live, wenn der Schreibvorgang einen UNGATED Lesevorgang
erreicht") und die #552-Klasse (eine halb wahre Behauptung liest sich für jeden richtig, der die
zutreffende Hälfte prüft) — hier gegen mich selbst, in dem Artefakt, das der Founder in der Hand
hat. Ein Enum sieht aus wie eine vollständige Aufzählung; das ist seine ganze Form, und deshalb
hört man dort auf zu lesen.

---

## 2. Die Spannung, die der Plan auflösen muss

Der Ask sagt **„in der Spur"**. Die Spur-OBERFLÄCHE hat der Founder selbst entfernt:
`ArrangeTimelineView` und `ClipView` mit #121 Slice 4 (26. Juli), `TimelineAutomationRow` mit
#473. Der kanonische Grenzsatz aus `docs/dev/PRODUCT_DEFINITION.md` — **Editor ≠ Workstation** —
schneidet „Anordnen von Material über die ZEIT" ausdrücklich weg und behält „der Klang, der
JETZT entsteht".

Das ist kein Widerspruch, den ich wegverhandeln darf, und auch keine Frage, die ich zum sechsten
Mal stellen sollte. Es ist eine Entwurfs-Entscheidung mit zwei ehrlichen Routen:

**Route A — instrumenten-förmig (empfohlen).** Automation gehört dem TAKE, nicht einer
Timeline-Zeile. Sie wird am Instrument aufgenommen (der Körper oder der Finger schreibt sie),
am Instrument gezeigt und am Instrument gelöscht. Kein Timeline-Fenster, keine Spurköpfe, keine
Zeitachse zum Scrollen. Der Speicher darunter bleibt exakt der gemessene — song-absolut und pro
Clip —, weil er das schon ist.
· *Passt zu:* Editor ≠ Workstation · Ship-Gate „Instrument-Complete v1" · der gelöschten UI.
· *Kostet:* der Ausdruck „in der Spur" wird buchstäblich nicht erfüllt.

**Route B — minimale Spur-Zeile zurück.** Eine reduzierte Automations-Zeile pro Spur
wiederherstellen. Der Speicher, die Mathematik und die Wiedergabe stünden bereit; es wäre
überwiegend eine View.
· *Passt zu:* dem Wortlaut des Asks.
· *Kostet:* die erste Rückkehr einer Workstation-Fläche seit dem 26. Juli — und sie kommt nicht
allein, denn eine Automations-Zeile ohne Regionen-Ansicht darüber hat keinen Bezugsrahmen.

---

## 3. Council

```
Council — Automation: instrumenten-förmig (A) oder Spur-Zeile zurück (B)?
· Vision-Keeper: A — „Editor ≠ Workstation" ist der Satz, der jede Behalten/Streichen-Frage
  entscheidet, und er wurde für genau diesen Fall geschrieben. Sorge: der Founder hat „Spur"
  gesagt; A erfüllt den Buchstaben nicht und muss das offen sagen, nicht umdeuten.
· Architect: A — der Speicher ist song-absolut UND pro Clip, also trägt er beide Routen. Sorge:
  der Engpass ist die SETTER-BINDUNG, nicht die Ansicht — 15 Registry-keyPaths, 6 gebunden; wer
  mit der Ansicht anfängt, baut eine Tür, hinter der neun Regler nichts bewegen.
  (⛔ Diese Zeile sagte „die DREI Ziele in `AutomationTarget` sind der Engpass" und war am
  Enum abgelesen; die Rücknahme mit dem Beleg steht in Abschnitt 1.)
· Skeptic: keine der beiden, bevor EIN Parameter nachweislich end-to-end läuft. `enabled`
  steht auf `false`, `RecordController.arm()` hat null Aufrufer, und die Mutations-API ist seit
  #473 unbenutzt — nichts davon ist auf einem Gerät je gelaufen. Ein Zeichen-Canvas auf einer
  Kette, deren Wiedergabe niemand beobachtet hat, ist ein Blindflug.
· Shipper: A, und die erste Scheibe ist NICHT die Ansicht. Die billigste ehrliche Bewegung ist
  ein einziger Parameter, aufgenommen und wieder abgespielt, mit einem Beleg auf dem Schirm.
· User-Advocate: A — die Frage des Spielers lautet „warum ändert sich das von selbst?", nicht
  „wo ist meine Automationsspur?". Eine Anzeige, DASS etwas automatisiert ist, kommt vor jeder
  Editier-Möglichkeit.
→ Empfehlung: Route A, und Slice 1 ist die END-ZU-END-Kette an EINEM Parameter, nicht die
  Fläche. Gate: proceed — die ersten zwei Scheiben sind unter beiden Routen identisch, also
  kostet ein späterer Wechsel zu B nichts von ihnen.
```

⭐ **Der Grund, warum das kein `AskUserQuestion` ist:** die Scheiben 1 und 2 sind unter A und B
Wort für Wort dieselben (erst die automatisierbare Menge, dann Sichtbarkeit). Die Routen trennen sich erst bei
Scheibe 3. Eine Frage jetzt würde eine Entscheidung erzwingen, die zwei Zyklen lang nichts
ändert — und `.claude/rules/context.md` §6 sagt, dass eine Founder-Frage teurer ist als jede
Messung. Die Frage wird bei Scheibe 3 gestellt, mit zwei laufenden Zyklen als Beleg.

---

## 4. Scheiben-Folge

Jede ist ein Ralph-Zyklus: ein Punkt, Wächter, Gates, Status-Delta.

**Scheibe 1 — die automatisierbare Menge wird zur geprüften Tatsache (route-neutral).**
⛔ Diese Scheibe hieß „der Ziel-Vorrat wird die Registry" und beschrieb Arbeit, die schon getan
ist (Abschnitt 1). Was wirklich fehlt: die Menge „Registry ∩ gebundener Setter" ist heute **6 von
15** und wird von NICHTS festgehalten. Eine Lane auf einem der neun ungebundenen keyPaths ist ein
stiller No-op — der Spieler zeichnet eine Kurve und hört nichts, und nichts im Repo würde rot.
`ParameterApplyRouter.automatableDescriptors()` bildet die ehrliche Schnittmenge bereits; sie
braucht einen Wächter, bevor eine Fläche aus ihr eine Parameter-Liste baut.
*Wächter (in diesem Zyklus gebaut, #555):* jeder gebundene keyPath ist ein ECHTER
Registry-keyPath (ein Tippfehler im `bind` bindet für immer ins Leere) · `automatableBases` und
die `switch`-Fälle des Setters können nicht auseinanderlaufen (`default: return nil` macht ein
fehlendes `case` zu einem stillen Nicht-Binden) · `ddsp.fx.reverbMix` bleibt UNGEBUNDEN, solange
`EchoelDDSP.useConvolutionReverb` `false` ohne Schreiber ist (#546) — sonst wäre der erste neue
Automations-Regler ein Placebo.
*Danach, als eigene Scheibe:* die neun einzeln prüfen und binden, was wirklich Audio bewegt.
**#556 hat sie klassifiziert und die Regel ausführbar gemacht** — und dabei gezeigt, dass die
Regel schon ÜBER der Liste stand, nur zwei von sechs Namen nannte: `applyBioReactive` rechnet
`brightness` · `filterCutoff` · `harmonicity` · `noiseLevel` · `vibratoDepth` · `vibratoRate` auf
dem RENDER-Thread aus ihrem `bioBase*`-Anker neu. **Automation darf einen Parameter nur besitzen,
wo sie der EINZIGE Schreiber ist; sonst besitzt sie den ANKER.** Direkt gebunden wäre der Regler
für ein paar Millisekunden wirksam und danach vom Körper überschrieben — schlimmer als das
tote-Stufe-Placebo, weil er im Debugger funktioniert. Bleibt danach ungebunden: die zwei
Reverb-Parameter (Stufe aus, #546) und `osc.frequency` (gehört der Noten-Engine pro Note).

**Scheibe 2 — Sichtbarkeit vor Editierbarkeit (route-neutral).**
Ein Leaf-`View`, das ZEIGT, welche Parameter gerade automatisiert sind und mit welchem Wert —
dieselbe Bauform wie `AlwaysOnBioPanelStrip` aus #553, aus demselben Grund (Freeze-Gesetz:
eigener `View`-`struct`, Read im eigenen Rumpf, nie im Root). Beantwortet die Spieler-Frage
„warum ändert sich das von selbst?" und macht Scheibe 1 auf dem Gerät prüfbar, ohne eine
einzige Editier-Geste.
*Wächter:* kein Bio-/Automations-Read im Rumpf des Wirts-Panels; der Strip rendert genau die
Lanes, die der Player anwendet.

**Scheibe 3 — EIN Schreiber (hier trennen sich A und B).**
Route A: der Körper schreibt. `BioAutomationRecorder` existiert, `TakeRecorder` hält ihn; es
fehlt ein erreichbarer Auslöser am Instrument. Route B: der Finger schreibt, über
`AutomationCanvasMath` in einer wiederhergestellten Spur-Zeile.
**Vor dieser Scheibe wird der Founder gefragt** — mit den Scheiben 1 und 2 auf dem Gerät als
Beleg, statt mit einer Vermutung.

**Scheibe 4 — der Schalter. ✅ AUSGELIEFERT mit #561, VOR Scheibe 3, und die Umstellung ist
begründet, nicht vergessen.** `AutomationPlayer.enabled` stand auf `false` und hatte keine Tür.

⛔ **Hier stand: „Er kommt ZULETZT, weil ein Schalter, der etwas Unsichtbares einschaltet, kein
Feature ist." Dieser Grund ist mit Scheibe 2 ABGELAUFEN** — #559 hat den Zustand auf den Schirm
gebracht, also kann der Streifen jetzt `off` neben eine Kurve schreiben, und wer das liest, hat
keine Möglichkeit zu handeln. Eine Fläche, die einen Zustand BENENNT und sein Mittel
zurückhält, ist schlechter als eine, die schweigt.

⭐ **Der zweite Grund ist ein Defekt, kein Feature-Wunsch, und er hängt an keiner Route:** der
Decoder setzt `enabled` bei JEDEM unlesbaren Dokument auf `false` — absichtlich, weil Automation
überschreibt, was der Spieler live eingestellt hat —, und bis #561 konnte nichts in `Sources/`
ihn zurücksetzen. Der eigene Doc-Block von `AutomationState` nannte das eine EINBAHN-TÜR. Ein
konservativer Default ohne Handschalter ist kein Konservatismus, sondern eine Falltür.

**Warum das VOR dem Schreiber sicher ist:** mit nichts Aufgezeichnetem sind An und Aus derselbe
Klang — Master und Tempo wenden nur `if let r = real` an (bei leerer Lane nil), der
Filter-Multiplikator fällt auf sein Neutral ×1 zurück, und genau ×1 schreibt auch der
Aus-Zweig via `setCutoffScale(1)`. Alle drei Hälften sind in
`Tests/CISmoke/TheAutomationSwitchIsSafeToFlipTests.swift` festgenagelt; die konservative
Default-Richtung ist UNVERÄNDERT und wird dort ebenfalls gehalten.

⛔ **Ausdrücklich NICHT in diesem Plan: Undo für Automation.** Der Undo-Stack schnappschusst
ausschließlich `document.regions`, und die Grenze ist im Quelltext begründet (eine zweite Feld-
Historie verunreinigt die Regionen-Historie). Automations-Edits sind heute nicht rückgängig zu
machen — dokumentierte Grenze, in diesem Plan nicht ausgeweitet, und Scheibe 3 muss das in
ihrer eigenen Prosa sagen, statt es zu erben.

---

## 5. Was dieser Plan NICHT beweist

Keine der acht gemessenen Schichten ist je auf einem Gerät beobachtet worden. Die Wiedergabe-
Kette ist aus Quelltext und Kommentaren gelesen, nicht gesehen: `enabled` ist `false`, die
Mutations-API ist seit #473 aufruferlos, `RecordController.arm()` seit #204. **„Zu ~90 % gebaut"
ist eine Aussage über Code, nicht über Verhalten** — und Scheibe 2 existiert genau deshalb an
zweiter Stelle: sie ist der erste Punkt, an dem der Founder etwas sehen kann.
