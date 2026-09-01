# PLAN — MPE-Zonen (RPN 6,6): wo der Bau WIRKLICH anfängt

**Datum:** 2026-09-01 · **Anlass:** #948/#948b haben die Bend-Basis repariert und dabei den
Sentinel-Rest (`event.note > 0` kann „keine Note" nicht von MIDI-Note 0 unterscheiden)
ausdrücklich an „den Zonen-Parser" verwiesen. Bevor dieser Parser gebaut wird, gehört gemessen,
was er einbringt. **Diese Messung ist das Ergebnis dieses Plans, nicht der Parser.**

---

## 1. Der Befund, und er dreht die Reihenfolge um

CLAUDE.md sagt heute: *„Wer weiterbaut (Zonen), fängt in `MIDIEventParse`/`MIDIInput` an, nicht
in `MIDIBusPublisher`."* **Das ist wahr über den PARSER und schweigt über die DECKE.**

Gemessen am Baum von d6b8dfa:

| Frage | Befehl | Ergebnis |
|---|---|---|
| Wer verbraucht `controllerEvents`? | `git grep -n "controllerEvents" -- Sources` | **genau EIN** `dequeue()`, in `BioReactiveSynthVoice.drainControllerEvents` |
| Ist das Absicht? | `Core/SPSCQueue.swift:167,178` · `Core/EngineBus.swift:669` | ja — **Single-Producer/Single-Consumer**, im Typ begründet |
| Ist es gepinnt? | `Tests/CISmoke/ControllerEventDrainIsPushedTests.swift:68` | ja, über die Zahl der Dateien, die den Hook zuweisen |
| Ist der Verbraucher polyphon? | `BioReactiveSynthVoice` | **nein** — EINE monophone Performer-Stimme |
| Sieht `PolySynthVoice` die Queue? | `git grep -ln ControllerEvent -- Sources` | **nein** (5 Dateien, keine davon `PolySynthVoice`) |

**Konsequenz:** eine MPE-Zone existiert, damit jeder *Member-Kanal* eine EIGENE Note trägt.
Ein Verbraucher, der immer nur eine Note klingen lässt, kann diese Information nicht ausgeben.
Zonen zu parsen, ohne den Verbraucher zu ändern, erzeugt genau das Muster, das CLAUDE.md an
sechs Stellen beklagt: **gebaut, verdrahtet, ohne Wirkung.**

⚠️ Und der Sprung ist kein kleiner: `controllerEvents` ist SPSC. Ein zweiter Verbraucher ist
nicht „noch ein `dequeue()`", sondern ein Bruch des Typvertrags — es braucht entweder einen
Fan-out auf dem MainActor oder eine zweite Queue. Das ist eine **EngineBus-Entscheidung**
(Kontrollebene, Architekt-Sitz), keine Parser-Aufgabe.

---

## 2. Was Zonen HEUTE einbrächten, ehrlich beziffert

Auf einer monophonen Stimme bleiben genau zwei echte Gewinne:

1. **Master-Kanal ≠ Member-Kanal.** Ein Bend auf dem Master-Kanal ist global gemeint, einer auf
   einem Member-Kanal gehört SEINER Note. Heute werden beide gleich behandelt.
2. **Der Sentinel.** Mit einer bekannten Zone kann `MIDIBusPublisher` die aktive Note des
   Member-Kanals in `note:` stempeln — Zweig 1 in `case .pitchBend` (#948) ist genau dafür da
   und heute tot.

**Beides ist hörbar klein.** #948 hat den großen Fehler (Basis A4 statt der klingenden Note)
bereits ohne Zonen behoben. Wer aus „Zonen fehlen" auf „Bend klingt falsch" schließt, schließt
seit d6b8dfa falsch.

---

## 3. Council

- **Architect:** Der Zustand von RPN (CC 101 → 100 → 6, drei Nachrichten, pro Kanal
  akkumuliert) darf NICHT in `MIDIEventParse` — das ist ein reiner `word → event`-Mapper. Er
  gehört in einen eigenen Werttyp mit `feed(cc:value:channel:)`-Reduzierer.
- **Skeptic:** Die teuerste Folge wäre nicht der Code, sondern die KOPIE. „Zonen werden
  erkannt" liest sich sofort als „MPE-Eingang", und das bliebe falsch, solange eine monophone
  Stimme der einzige Verbraucher ist.
- **User-Advocate:** Der spürbare Gewinn ist heute nahe null (siehe §2).
- **Aesthetic Maximalist:** Der expressive Gewinn entsteht erst mit einer polyphonen
  Performer-Stimme — Zonen ohne Polyphonie sind Rohrleitung, kein Ausdruck. **Dissens
  ausdrücklich benannt statt gemittelt:** diese Sitzstimme will die Tiefe, sagt aber, dass sie
  an dieser Stelle nicht durch Zonen entsteht.
- **Shipper:** ≥3 Dateien, neuer Typ, neuer Wächter, kein Gerät zum Prüfen — hoher Preis,
  heute kein hörbarer Ertrag.

**Verdikt: NICHT jetzt bauen.** Nicht weil es falsch wäre, sondern weil die Reihenfolge
falsch wäre.

---

## 4. Die Reihenfolge, wenn es gebaut wird

1. **Verbraucher zuerst.** Entscheiden, WER Member-Kanal-Noten hört — `PolySynthVoice` als
   zweiter Verbraucher (Fan-out oder zweite Queue) oder eine polyphone Performer-Stimme. Das
   ist die Entscheidung, die alles andere bindet, und sie gehört vor jede Parser-Zeile.
2. **Zonen-Zustand** als reiner Werttyp (RPN 101/100/6, pro Kanal, mit Rücksetzern), getestet
   ohne CoreMIDI.
3. **`MIDIInput`/`MIDIBusPublisher`** füttern den Zustand und stempeln `note:` auf
   Member-Kanal-Bends — Zweig 1 von `case .pitchBend` wird damit lebendig, und der
   Sentinel-Rest (#948b) verschwindet an derselben Stelle.
4. **Kopie ZULETZT** und nur, wenn 1–3 stehen. Bis dahin bleibt jede Rücknahme in
   `MIDIEventParse`, `MIDIInput`, `MIDIBusPublisher`, `ContentPipeline/CLAIMS.md`, Store-Text
   und Website unverändert wahr.

---

## 5. Was dieser Plan NICHT tut

Er baut nichts, er nimmt nichts zurück und er verbietet nichts (#364). Er hält EINE Messung
fest, damit die nächste Sitzung nicht am Parser anfängt und die Decke erst drei Tage später
findet. Der Einzeiler in CLAUDE.md ist im selben Commit um den Verweis hierher ergänzt — mehr
nicht, weil die Datei 473 B unter ihrer Decke stand.
