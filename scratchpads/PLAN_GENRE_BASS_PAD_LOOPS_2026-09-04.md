# PLAN — Richtig gute Bass- und Pad-Loops: Deep Tech · Dark Minimal · Deep House · Psy Prog House

**Founder 2026-09-04, wörtlich:** „Ich will richtig gute Bass und Pad etc Loops für Deep tech,
dark minimal, deep house, psy prog House etc haben."

**Lesart (Produktdefinition, `docs/dev/PRODUCT_DEFINITION.md`):** Loops = das, was der
generative Motor im Loop-Modus (`studioLocked`, fester BPM, `LoopBarLength` 1…16 Takte) baut und
was Keep-Last/MIDI-Export mitnimmt. KEINE Sample-Bibliothek (Drums/Samples sind mit #166/#167
Founder-Entscheidung gelöscht). Die Frage ist also: **klingt der ERZEUGTE Bass und das ERZEUGTE
Pad in diesen vier Stilen wie ein Produzent es bauen würde — und wo ist das heute strukturell
unmöglich?**

---

## 0 · Gemessen (2026-09-04, `git grep` auf `fa6c271`)

| Frage | Befund | Stelle |
|---|---|---|
| Gibt es die vier Genres? | **Deep House ✓** (`.deepHouse`, offered). **Tech House ✓** (`.techHouse`) und **Minimal Techno ✓** (`.minimalTechno`) sind die nächsten Nachbarn von „Deep Tech" und „Dark Minimal", aber NICHT dieselben Genres. **Psy Prog House ✗** — `.psytrance` existiert (140…150, phrygisch, arpeggiert, padOctave 2) und ist seit 2026-07-24 per Ohr NICHT offered; Progressive-Psy/Psy-Prog-House (~128…136, rollender Offbeat-Bass, minor) fehlt ganz. | `MusicStyle.swift:134` (`offered`), `:268/:313/:340/:433` |
| Wie entsteht der BASS? | **`appendBass` ist genre-blind.** Downbeat = Chord-Root; NUR wenn `!sustained && motion > 0.32 && len ≥ 4` läuft ein Root/Quinte-Walk auf 8teln (motion > 0.62) oder Vierteln; ruhiger Körper ⇒ EIN gehaltener Root pro Section. Kein Offbeat-Bass (House), kein rollender 16tel-Bass (Psy), kein langer dunkler Sub (Dark Minimal). Der `RoleRhythm.Character` aus dem Mood-Panel ist ein NUTZER-Override (default `nil`) und formt nur den Walk, wenn der Walk überhaupt erreicht wird. | `BioComposer.swift:1527ff`, `Input.bassRhythm :210` |
| Welche STIMME spielt den Bass? | **Dieselbe wie das Pad.** `outputVoice(for: .bass)` liefert `voice` (= `polyVoice`); nur `.lead` hat eine eigene Stimme. Der Bass ist also das Genre-Pad-Patch („House Chord", „Minimal Stab") eine Oktave tiefer. Kein Bass-Patch pro Genre. | `PianoRollView.swift:876-883`, `applyLeadPatch :949` |
| Was macht der Sub? | `SubBassVoice` ist ABGELEITET, nicht komponiert: pro Tick die TIEFSTE hörbare aktive Note −12, oktavgefaltet in sein Felt-Band. Solange irgendetwas klingt (auch nur das Pad), klingt der Sub — ein Genre-Rhythmus erreicht ihn NICHT. Sinus + `SubCharacter` (Oktav-Obertöne, tanh), Attack/Release ~15 ms, keine Hüllkurve, kein Filter. | `feltSubPitch :1246`, `SubBassVoice.swift:380ff`, `SubCharacter.swift` |
| Wie entsteht das PAD? | Genre-Profil (`HarmonicProfile`: Progression/Tones/Oktave) + `chordArticulation` aus `beatArchetype`: deepHouse = `.skank` (Offbeat-8tel, 2 Steps kurz), techHouse/minimal = `.stab` (auf die Zählzeiten, +8tel bei Erregung), detroit = `.comp`. Pad-Patch pro Genre ✓ (`GenrePatches`), FX-Preset pro Genre ✓ (`GenreFX`), Mix pro Genre ✓ (`mixLevels`). `padRhythm` = Nutzer-Override, default `nil`. | `MusicStyle.swift:651-672`, `chordOnsets :1880`, `GenrePatches.swift:73ff` |
| Loop-Form | 1 Takt = 16 Steps; `loopBars` > 1 ⇒ pro Takt eigener Detail-Seed + `progressionPhase + b` (verschiedene Takte, gleiche Struktur). | `EchoelStudioView.swift:9823-9842` |
| Wächter, die JEDE Änderung überleben muss | `GenreFamilyDistinctnessTests` (Fingerabdruck articulation/scale/prog/tones/padOctave/arp/sus eindeutig über `offered`), `BassRhythmOverrideTests` (`bassRhythm: nil` ⇒ BYTE-IDENTISCHER Take — das Golden-Gesetz), `PadRhythmOverrideTests`, `GenreSwingReachesTheClockTests`, `GenreTempoFoldTests`, `TheGenreVocabularyStaysNeutralTests`, `SubBassFollowsTheToneSystemTests`. | `Tests/CISmoke/` |

**Kern-Befund in einem Satz:** Pad-Seite ist pro Genre GEBAUT (Profil · Artikulation · Patch · FX ·
Mix); die **Bass-Seite hat keine einzige Genre-Achse** — weder Rhythmus (ein Walk für alle) noch
Timbre (das Pad-Patch) noch Sub-Gating (der Sub hängt am Pad). „Richtig gute Bass-Loops" ist deshalb
zuerst ein BASS-Auftrag, und zwei der vier genannten Genres existieren nicht.

---

## 1 · Council

**Entscheidung:** Reihenfolge und Zuschnitt der Scheiben für einen Ohr-Auftrag, den keine Session
selbst abnehmen kann.

· **Aesthetic Maximalist:** Der Bass ist heute ein Pad eine Oktave tiefer plus Sinus-Drone — das
  ist der Grund, warum kein Loop „nach Deep Tech" klingt, egal wie gut das Pad ist. Erst
  BASS-GRAMMATIK pro Genre (Offbeat / rollend / lang-dunkel / treibend), dann eigenes BASS-TIMBRE,
  dann die fehlenden Genres. — Sorge: nicht wieder „Regler für alle Genres" bauen, sondern eine
  AUTORISIERTE Figur pro Genre.
· **Shipper:** Scheibe 1 ist reiner Composer-Code (Werttyp, deterministisch, Wächter im
  blockierenden Bundle, `nil` = byte-identisch für jedes Genre ohne Grammatik). Kein Audio-Thread,
  kein Modal, kein neues Framework. — Sorge: das Golden-Gesetz von #253 A3 (`BassRhythmOverrideTests`)
  darf nicht rot werden ⇒ Grammatik nur dort, wo der Genre-Wert sie SETZT.
· **Skeptic:** (1) Der Sub folgt der tiefsten Note — mit Offbeat-Bass läuft er auf dem Downbeat
  auf die Pad-Root und „füllt" das Loch, das der Groove braucht. Scheibe 1 MUSS den Sub-Folger an
  die Bass-Rolle koppeln, wenn eine Grammatik aktiv ist, sonst hört der Founder keinen Unterschied.
  (2) „Deep Tech" und „Dark Minimal" als neue Cases kollidieren mit dem Fingerabdruck-Wächter, wenn
  sie nur „techHouse dunkler" sind — jeder braucht eine eigene Achse (Skala/Voicing/Register).
· **DSP Purist:** Ein Bass-Timbre pro Genre (Scheibe 2) ist ein ZWEITER `PolySynthVoice` mit
  Patch — dasselbe Muster wie `lead`; kein neuer Render-Code. Sub-Gating ist Control-Plane
  (`trigger` läuft auf dem MainActor), nicht Render.
· **Vision-Keeper:** Vier vom Founder benannte Stile ⇒ Genres mit Namen im Picker sind on-vision
  (#254-Muster, „Alles rein, logisch sortiert"). Kein Store-Text-Claim vor dem Ohr.
· **User-Advocate:** Das Ohr entscheidet. Jede Scheibe endet in einem NEEDS-FOUNDER-VERIFY-Satz,
  der sagt, WAS im Loop-Modus zu hören sein soll, und der Deploy-Note.

**Dissens, benannt:** Maximalist will Genres SOFORT („er hat sie genannt"), Shipper will erst
die Grammatik, weil ein neues Genre ohne Bass-Grammatik denselben genre-blinden Walk erbt und den
Founder zweimal hören lässt. **Entschieden: Grammatik zuerst (S1), Timbre (S2), dann drei Genres
(S3–S5), Pad-Bewegung (S6).** Gate: proceed. Founder-Frage: keine — Ambiguität ist keine, die
Reihenfolge ist Handwerk.

---

## 2 · Scheiben (je EIN Ralph-Zyklus, je ein Wächter, je ein Ohr-Satz)

### S1 — `BassGrammar`: eine autorisierte Bass-Figur pro Genre (Composer, pur) — ✅ GEBAUT `cd48695` (Compile Check grün; CI/CD-Testbau starb am #478-Modulcache-Flake, kein Repo-Fehler; Re-Run per API = 403, also fährt der nächste Push)
- **Neu:** `Sequencer/BassGrammar.swift` — `enum BassGrammar` mit benannten Figuren
  (16-Step-Phasen, Länge, Akzent; Körper skaliert Velocity/Dichte, nie die Figur):
  · `offbeatEighths` — House: Bass auf jedem „&" (Phasen 2/6/10/14), kurz; Downbeat frei
    (Deep House, Deep Tech ruhig).
  · `rollingSixteenths` — Psy: Downbeat frei, drei 16tel pro Schlag (Phasen 1/2/3 …), sehr kurz
    (Psy Prog House).
  · `drivingEighths` — Tech: alle 8tel Root, Quinte auf dem letzten „&" der Section (Deep Tech
    erregt, Tech House).
  · `sparseSub` — Dark Minimal: Root auf 1 lang (8 Steps), Quinte-unter auf „3&" (Phase 10), kurz.
  · Kein Case für „Walk": `MusicStyle.bassGrammar` liefert `nil` ⇒ `appendBass` unverändert,
    BYTE-IDENTISCH (das #253-Golden-Gesetz bleibt).
- **Verdrahtung:** `MusicStyle.bassGrammar: BassGrammar?` (deepHouse → offbeat, techHouse →
  driving, minimalTechno → sparseSub; alle anderen nil). `composeHarmonic` bekommt `bassGrammar:`
  OHNE Default (#431/#440/#443), beide Aufrufstellen (`:885`, `:920`) reichen `input.style.bassGrammar`
  durch; `appendBass` wertet die Grammatik VOR der Motion-Guard aus (die Figur IST das Genre, auch
  bei ruhigem Körper — wie `.skank`). `Input.bassRhythm` (Nutzer-Override) gewinnt weiter über die
  Grammatik-Akzente, wenn gesetzt — Präzedenz wie `RoleRhythm` sie schon dokumentiert.
- **Sub-Kopplung (Skeptic 1):** `PianoRollModel.feltSubPitch` bekommt `bassOnly: Bool` — wenn der
  Take eine Bass-Grammatik trägt (Note-Rolle `.bass` mit einer Figur), folgt der Sub NUR den
  `.bass`-Noten; ohne Grammatik das alte Verhalten (byte-identisch). Zustand: `PianoRollModel`
  liest die Flagge vom Take (`lastRawTake.genre.bassGrammar != nil` → `setSubFollowsBassOnly`).
- **Wächter:** `Tests/CISmoke/GenreBassGrammarTests.swift` — (1) `nil`-Grammatik ⇒ Take
  byte-identisch zu heute (Disco-Referenz wie `BassRhythmOverrideTests`); (2) deepHouse: jede
  `.bass`-Note liegt auf Phase ≡ 2 (mod 4), keine auf 0; (3) minimalTechno: erste `.bass`-Note
  Länge ≥ 8; (4) techHouse: `.bass`-Noten auf allen 8teln; (5) Grammatik gilt bei RUHIGEM Körper
  (calm 0.9) genauso wie erregt; (6) Sub-Folger: mit `bassOnly` ignoriert `feltSubPitch` Pad-Noten.
- **Ohr (NEEDS-FOUNDER-VERIFY):** Loop-Modus, Deep House, ruhiger Körper: der Bass sitzt auf den
  „&"s und die 1 ist frei — und der Sub schweigt auf der 1 mit.

### S2 — eigenes Bass-Timbre (zweite Stimme, Muster `lead`) — ✅ GEBAUT (Folge-Commit; Gates ausstehend)
- `EchoelmusicApp`: `bassVoice = PolySynthVoice()` attach; `pianoRoll.start(… bass: bassVoice …)`;
  `outputVoice(for: .bass)` → `bass ?? voice`; `applyBassPatch(_:)`.
- `GenrePatches.bassPatch` pro Genre (House Sub · Tech Bass · Minimal Sub — dunkler, kürzer,
  tiefer geschnitten als das Pad-Patch, trocken, mono), `EchoelStudioView.generate()` wendet es an
  wie `leadPatch` und schaltet die Route NUR für Genres mit Patch (`setBassVoiceActive`) — alle
  anderen Genres spielen den Bass bit-identisch weiter über die Pad-Stimme. ⛔ Hier stand
  „`mixer.bass` → `bassVoice.mixLevel`": `PolySynthVoice` HAT kein `mixLevel`; der Mixer-Bass
  skaliert schon die Velocity (`mixGlued`), also erreicht der Fader die Stimme ohne Fan-out.
  Per-Track-FX-Insert `trackFX.bass` → Bass-Stimme ✓ (vorher lief der Poly-Bass über den
  MELODIC-Insert), Tonsystem + Kammerton + Panic-Inventar ✓.
- Wächter: `TheBassRoleHasItsOwnVoiceTests` — Patch ⇔ Grammatik (E2E), dunkler/kürzer/tiefer/
  trocken/mono gegen das Pad-Patch (E2E), stabile IDs ohne Kollision (E2E), Routing + Fans +
  Panic + App-Verdrahtung (SOURCE-TEXT).
- Risiko: eine Stimme mehr am Engine (CPU ≈ +1 Poly-Stimme) — im Diag-Log `voices=` prüfen.
- Ohr: derselbe Loop — der Bass ist jetzt ein Bass (kurz, dunkel), nicht das Pad tief.

### S3 — Genre `deepTech` („Deep Tech")
- 124…128, default 126; minor; `chordTones [0, 4, 6]` (Root-Quinte-♭7, ohne Terz — neu im
  Roster, vom Fingerabdruck messbar); Progression `[0, 5]`; padOctave 4; `.fourOnFloor`→`.stab`;
  swing 0.08; bassGrammar `drivingEighths`; FX: trocken, Room 0.40, Sat 0.36, Delay 16tel
  gepunktet; Patch: dunkle, kurze Shell (bright 0.28). Mix bass-led (1.16, 0.90, 0.88).
- Alle 9 `MusicStyle`-Switches + `GenreFX` + `GenrePatches` + `offered` + `Category.electronic` +
  Lineage-Text neutral (`TheGenreVocabularyStaysNeutralTests`).
- Wächter: Erweiterung von `GenreFamilyDistinctnessTests.testTheNewGenresAreReachableInThePicker`.

### S4 — Genre `darkMinimal` („Dark Minimal")
- 126…132, default 129; **phrygian** (die ♭2 ist die Dunkelheit; unter den offered ist acid
  arpeggiert-phrygisch, dies ist gehalten-phrygisch ⇒ andere Artikulation); `chordTones [0, 4]`
  Dyade wie minimal, aber **padOctave 3** und Progression `[0, 1]` (i → ♭II) ⇒ Fingerabdruck
  eindeutig; swing 0.02; bassGrammar `sparseSub`; FX: Room 0.30, hohes Damping, Sat 0.12, kein
  Chorus; Patch: sehr dunkel (bright 0.18), langsamer Attack als „Minimal Stab" (Fläche mit Kante).

### S5 — Genre `psyProgHouse` („Psy Prog House")
- 128…136, default 132; minor; `chordTones [0, 2, 4]` Triade, Progression `[0, 6]` (i → VII),
  padOctave 3, **arpeggiert: false**, `.fourOnFloor`→`.stab`; swing 0; bassGrammar
  `rollingSixteenths`; FX: Ping-Pong 16tel wie psytrance, aber Room 0.60, Sat 0.30, Chorus an;
  Patch: Pluck mit langem Release. Abgrenzung zu psytrance (nicht offered) bleibt hörbar: Tempo,
  Register, nicht-arpeggiert.

### S6 — Pad-Bewegung (nach dem Ohr zu S1–S5)
- Filter-LFO-Tiefe pro Genre ist im Patch schon da; offen ist die BAR-Bewegung über den Loop
  (Filter öffnet über 4/8 Takte). Erst planen, wenn der Founder S1–S5 gehört hat.

---

## 3 · Was NICHT gebaut wird
- Keine Samples, keine Drums (#166/#167 Founder). Keine neue Fläche, kein neues Modal (14-Modifier-
  Decke). Kein Store-Text über „vier neue Genres" vor dem Ohr (`ContentPipeline/CLAIMS.md`).
- Kein `Slider` — Grammatik ist ein Genre-Wert, kein Regler; der Nutzer-Override bleibt der
  vorhandene `Picker` im Mood-Panel.

## 4 · Reihenfolge und Gates
S1 → Gates (Compile Check + CI/CD Build for Testing, Wächter transkribiert) → Deploy-Note mit
Ohr-Satz → S2 → Deploy → S3/S4/S5 (je Deploy) → Founder-Ohr → S6.
