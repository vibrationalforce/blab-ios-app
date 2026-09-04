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

### S3 — Genre `deepTech` („Deep Tech") — ✅ GEBAUT (Folge-Commit; Gates ausstehend)
- 124…128, default 126; minor; `chordTones [0, 4, 6]` (Root-Quinte-♭7, ohne Terz — neu im
  Roster, vom Fingerabdruck messbar); Progression `[0, 5]`; padOctave 4; `.fourOnFloor`→`.stab`;
  swing 0.08; bassGrammar `drivingEighths`; FX: trocken, Room 0.40, Sat 0.36, Delay **8tel
  gepunktet** (⛔ hier stand „16tel gepunktet" — das hätte `techHouse`s „kürzeste Delay-Teilung
  der angebotenen Genres" zu einem Gleichstand gemacht; die gepunktete Achtel ist der dubbige
  Schwanz, den Deep Tech ohnehin hat, geteilt mit dubTechno/minimal, keine Einzigartigkeit
  behauptet); Damping 0.56 UNTER techHouse 0.58, damit dessen „fünfter"-Rang hält; Patch: dunkle
  Shell „Deep Shell" F7 (bright 0.28, zwischen Minimal Stab 0.24 und House Shell 0.34); Bass
  „Deep Bass" F8 (bright 0.20, r 0.11, cutoff 760, trocken, mono). Mix bass-led (1.16, 0.90, 0.88).
- Gebaut: 13 `MusicStyle`-Stellen (offered · Category.genres · category · case · displayName ·
  lineage · beatArchetype · tempoRange · defaultTempo · swing · leadPatchName „Deep Sub" [25.
  lead-tragendes Genre → Decke 5] · mixLevels · scale · harmonicProfile) + `GenreFX` +
  `GenrePatches` (Pad + Bass) + `BassGrammar`. ⛔ Der Plan sagte „9 Switches" — es sind 10
  Switches plus drei Listen; gezählt beim Bauen, nicht geschätzt.
- **Zähl-Heime, die mitgezogen sind (16 → 17):** `MoodKnobsSayWhatTheyDoTests` (Pin + Nadel),
  `moodPanel`-Caption „7 of the 17 offered" (die 7 bleibt: die Shell trägt die 7 schon),
  `MIDIClockTests`-Doc (sieben von siebzehn swingen), `EchoelStudioView`-Swing-Kommentar,
  `docs/brainstorming.html` · `docs/tools.html` · `docs/press.html` · `FEATURE_MATRIX.md` ·
  `APP_STORE_LISTING_v1.md` · **`fastlane/*/release_notes.txt`** — die Store-Notiz ist NICHT
  freiwillig: `WebsitePagesAreFindableAndHonestTests.testPublishedGenreAndScaleCountsMatchTheApp`
  liest sie gegen `MusicStyle.offered.count`. Geändert ist nur die ZAHL und der Name in der
  Liste (eine Roster-Tatsache), kein Klang-Versprechen — das bleibt hinter dem Founder-Ohr.
- Wächter: `Tests/CISmoke/GenreDeepTechTests.swift` (7 Ansprüche: Tür, Voicing neu, Stab/Tempo,
  Figur+Patch zusammen, Helligkeits-Achse, FX-Nachbar-Superlative, Romance-7) + Erweiterung von
  `GenreFamilyDistinctnessTests.testTheNewGenresAreReachableInThePicker`. Transkription
  `scratchpad/s3_grade_deeptech.py`: Worktree GREEN (Fingerabdruck über 17 eindeutig, Decke 5,
  ohne-7 = 7, Patch-Suffixe/-Namen ohne Kollision, Raster).
- **Ohr-Satz (NEEDS-FOUNDER-VERIFY):** Deep Tech im Loop-Modus bei 126 — liest sich die terzlose
  Shell als „deep" (Gewicht ohne Dur/Moll-Farbe) und der 8tel-Bass als Drive statt Metronom?

### S4 — Genre `darkMinimal` („Dark Minimal") — ✅ GEBAUT (Folge-Commit; Gates ausstehend)
- ⛔ **Die Spezifikation, die hier stand, hätte DREI blockierende Wächter rot gemacht** —
  `[0, 4]`-Dyade (minimal = „einzige Dyade", `testMinimalIsTheOnlyTwoNoteVoicingInTheRoster` +
  `testNoOtherGenreCopiesEitherNewVoicing`), swing 0.02 (minimal = „kleinster Swing über null"),
  Sat 0.12 (minimal = „sauberste beat-getriebene Kette"). Der Plan war gegen den Klang
  geschrieben, nicht gegen die Wächter; gemessen VOR dem Bauen, nicht am Gate.
- Gebaut: phrygisch; **`[0, 4, 11]`** (Root · Quinte · Quinte eine Oktave höher, +19 über
  `MusicalKey.degree`-Oktav-Wrap — weiter Quint-Stapel, terzlos, DREI Töne, neu im Roster);
  Progression `[0, 1]` (i → ♭II, die Dunkelheit sitzt in der Wurzelbewegung); padOctave 3;
  `.fourOnFloor`→`.stab`; **swing 0.0** (maschinengerade wie Acid); 126…131, default 129;
  bassGrammar `sparseSub` (Figur GETEILT mit minimal, Patch eigen: „Dark Sub" FA, cutoff 560 >
  Minimal Sub 520 und bright 0.15 > 0.14, damit dessen „tiefster/dunkelster"-Kommentar wahr
  bleibt); Pad „Dark Edge" F9 (bright 0.18 — dunkelstes PAD der Stab-Familie, Attack 0.030,
  Sustain 0.55: Fläche mit Kante); FX: Sat **0.16** (über minimal 0.14), Feedback 0.40 (unter
  minimal 0.44), Tone 0.36 (über deepDrone 0.14), Room 0.38, Damping 0.62 (zwischen Acid 0.64
  und dem 0.60-Paar — techHouses „fünfter"-Rang wird SECHSTER, im selben Commit korrigiert).
  Lead „Soft Keys" (26 lead-tragend, Decke 5). Mix (1.18, 0.84, 0.88).
- Zähl-Heime 17 → 18, ohne-Septime 7 → **8** (der Stapel trägt keine 6): Caption „8 of the 18
  offered", MoodKnobs-Pin + Nadel, Swing-Kommentar (ELF bei null), MIDIClock-Doc, drei
  `docs/*.html`, FEATURE_MATRIX (35 Cases), APP_STORE_LISTING, beide `release_notes.txt`.
- Wächter: `Tests/CISmoke/GenreDarkMinimalTests.swift` (5 Ansprüche, jeder Nachbar-Superlativ
  von der Seite des Neulings re-assertiert) + Reachable-Liste. Transkription
  `scratchpad/s4_grade_darkminimal.py`: Worktree GREEN.
- **Ohr-Satz (NEEDS-FOUNDER-VERIFY):** Dark Minimal bei 129 — liest sich der weite Quint-Stapel
  in Oktave 3 mit dem ♭II-Wechsel als „dunkel", ohne zu matschen?

### S5 — Genre `psyProgHouse` („Psy Prog House") — ✅ GEBAUT (Folge-Commit; Gates ausstehend)
- Gebaut wie geplant, mit zwei gemessenen Korrekturen: Progression **`[0, 6, 5]`** (i → VII → VI,
  der absteigende Prog-Vamp) statt `[0, 6]` — und ⛔ der erste Entwurf behauptete „kein anderer
  Arm hat diese Form"; die Transkription fand ZWEI (`deepHouse` offered, `rock`). Neu ist das
  PAAR Triade-auf-Abstieg, und der Wächter misst das Paar. Patch-Name „Prog Pluck" (FB) — ⛔
  „Psy Pluck" war psytrances Name (DB), `GenrePatchesTests` pinnt Eindeutigkeit; Bass „Psy Bass"
  (FC, r 0.08 — kürzeste Hülle aller Bass-Patches, drei Hits pro Beat). Moll-Triade `[0, 2, 4]`,
  padOctave 3, nicht arpeggiert, `.stab`, 128…136/132, swing 0, `rollingSixteenths` — erster
  Besitzer der in S1 vorausgeschriebenen Figur (`GenreBassGrammarTests`: authoredAhead jetzt leer).
  FX: Ping-Pong 16tel wie psytrance (die Familie), aber Mix 0.22 < 0.30, Feedback 0.40 < 0.46,
  Room 0.60 (zwischen techHouse 0.42 und Detroit 0.66), Chorus an — psytrances Preset hat weder
  Chorus noch Reverb, also nicht dasselbe Preset. Einziges offered Four-on-Floor-Genre mit
  Ping-Pong (Wächter). Lead „Pluck" (27 lead-tragend, Decke 5). Mix (1.12, 0.98, 0.90).
- Zähl-Heime 18 → 19, ohne-Septime 8 → 9, Swing-Null ZWÖLF; techHouses Room-Kommentar „vierter"
  war nach S4 schon wieder falsch → kein Rang mehr zitiert.
- Wächter: `Tests/CISmoke/GenrePsyProgHouseTests.swift` (6 Ansprüche, inkl. „ist nicht
  psytrance im House-Tempo": Fenster berühren sich nicht, Modus/Register/Arp verschieden).
  Transkription `scratchpad/s5_grade_psyprog.py`: Worktree GREEN.
- **Ohr-Satz (NEEDS-FOUNDER-VERIFY):** Psy Prog House bei 132 — rollt der 16tel-Bass als Linie
  (nicht als Rasseln), hängt der Pluck ins Ping-Pong, ohne die Triade zu verwischen?

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
