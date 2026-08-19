# TestFlight-Loop — gemessen, dann optimiert (#635, 2026-08-19)

**Founder-Auftrag: „Optimieren TestFlight Loop".** Diese Datei misst zuerst, weil jede
frühere Loop-Behauptung in diesem Repo an einer Schätzung gestorben ist. Alles unten stammt
aus **Lauf 2527** (`389e562`, `run_id=32267814841`), Job-Zeitstempel über
`mcp__github__actions_list method=list_workflow_jobs`, plus dem Job-Log desselben Laufs.

⚠️ **`.github/workflows/**` und `project.yml` sind founder-gated: BERICHTEN, nicht editieren.**
Fünf der sieben Befunde liegen dort. Was in meiner Spur lag, ist gebaut (§Gebaut).

---

## Die gemessene Uhr (Lauf 2527, gesamt 12:47)

| Stufe | Runner | Wartezeit | Laufzeit | Davon |
|---|---|---|---|---|
| Preflight | ubuntu | — | **0:06** | Secret-Prüfung |
| Compile Check | macos-26 | **1:53** | **2:48** | App-Compile 2:17 · Ökosystem-Targets 0:12 |
| iOS | macos-26 | **4:29** | **8:04** | Setup 0:30 · Signing 0:04 · **Archive 4:16** · Export+Upload 1:01 · **ASC-Verify 2:05** |

⚠️ „Signing 0:04" sieht zu schnell aus für Token + Zertifikatsliste + Widerruf + `cert(...)`
und ist deshalb ZWEIMAL gemessen: aus den Job-Zeitstempeln (15:09:19→15:09:23) und aus dem
Job-Log selbst (`15:09:21 Revoking…` → `15:09:23 …installed in keychain`). Es sind wirklich
vier Sekunden — bei genau EINEM zu widerrufenden Zertifikat.
| Summary | ubuntu | — | 0:03 | — |

**Kritischer Pfad = Preflight 0:06 → iOS-Wartezeit 4:29 → iOS 8:04.** Der Compile Check
liegt vollständig PARALLEL und verlängert die Uhr nicht direkt — er verbraucht aber den
zweiten macOS-Runner, und der iOS-Job hat 2:36 länger auf einen gewartet als er.

---

## Befunde, nach (Wert × Sicherheit) sortiert

### 1. Der Compile Check dupliziert den Archive-Compile und torwacht ihn nicht — FOUNDER-GATED
`ios` hat `needs: [preflight]`, **nicht** `needs: [compile_check]`. Ein roter Compile Check
hält den Deploy also nicht auf; der Archive-Schritt würde am selben Fehler ohnehin sterben.
Der 2:17-Schritt „Compile (iOS device SDK, no signing)" beweist damit nichts, was der
Archive nicht vier Minuten später selbst beweist.

**Und auf dem Deploy-Pfad ist er fast immer redundant:** `xcode-compile-check.yml` ist auf
`Sources/** · Tests/** · project.yml · Package.swift · Package.resolved ·
Resources/iOS/Info.plist · scripts/check-infoplist.sh` pfadgefiltert und läuft auf dem
Commit, der den Code einbringt. Der `.deploy/release`-Bump trägt keinen Code — derselbe Baum
ist in aller Regel bereits kompiliert. ⚠️ „In aller Regel", nicht „immer": der Filter deckt
`fastlane/**` und `Resources/` außerhalb der iOS-Info.plist NICHT ab, ein Baum kann sich
zwischen dem letzten compile-geprüften Push und dem Bump also verändert haben.

⭐ **Und die schärfste Fassung des Arguments stand nicht in der ersten Version dieser
Datei, sondern kam aus dem Review:** der Job trägt
`if: … && github.event.inputs.skip_compile_check != 'true'`, und dieser Eingang hat
`default: true`. Bei `workflow_dispatch` läuft er also gar nicht — **er läuft im
Wesentlichen NUR auf dem tokenlosen Push-Pfad**, also genau dort, wo dieser Befund ihn für
wertlos hält, und sonst nirgends.

**Der einzige EIGENE Wert des Jobs sind 12 Sekunden:** `xcode-compile-check.yml` baut nur
`-scheme Echoelmusic` (nachgemessen, eine einzige `-scheme`-Zeile). Widgets und Watch werden
**ausschließlich** im Schritt „Compile ecosystem targets" von `testflight.yml` kompiliert.

**Vorschlag (stärkste Fassung):** den `compile_check`-Job auf dem Deploy-Pfad ganz entfallen
lassen und die 12 Sekunden Ökosystem-Compile in den `ios`-Job verlegen, direkt nach
`xcodegen generate` — dort ist der Runner schon warm und das Projekt schon erzeugt.
Ersparnis: **ein kompletter macOS-Runner-SLOT pro Deploy** (~2:48 belegt) und, falls die
Zuteilung der Grund für die 4:29 war, **2–3 Minuten Uhr**. ⚠️ Bewusst „Slot" und nicht
„Kosten": das Repository ist öffentlich, Standard-Runner sind gratis, und `.claude/rules/`
§6 hält fest, dass genau diese Verwechslung schon einmal eine Founder-Frage gekostet hat.
⚠️ Ehrliche Grenze: dass zwei gleichzeitig angeforderte macOS-Runner sich gegenseitig
verzögern, ist EINE Messung (1:53 gegen 4:29), kein bewiesenes Gesetz. Der Runner-Gewinn ist
sicher, der Uhr-Gewinn ist plausibel.

### 2. Der ASC-Verify schläft in 60-Sekunden-Schritten — FOUNDER-GATED
Der Schritt lief 2:05 und fand den Build im zweiten Versuch, also nach genau einem
60-s-Schlaf. Mit 15/15/30/30/60… (gleiche Obergrenze 20 min) landet derselbe Fund nach
~1:05–1:20. **Ersparnis im gemessenen Fall genau 45 s** (ein 60-s-Schlaf durch einen 15-s-Schlaf
ersetzt; die erste Fassung schrieb „~45–60 s", und die Obergrenze ist im gemessenen Fall
unerreichbar). **Risiko null** — die Obergrenze und das
„nicht-fatal"-Verhalten bleiben unangetastet.

### 3. `BUILD_NUMBER` kann sich bei einem Re-Run wiederholen — FOUNDER-GATED, ZUVERLÄSSIGKEIT
`BUILD_NUMBER: ${{ github.run_number }}` (`testflight.yml:55`). `run_number` zählt beim
**Re-Run NICHT hoch** — nur `run_attempt` tut das. Ein Re-Run eines gescheiterten Deploys lädt
also dieselbe Build-Nummer erneut hoch, und App Store Connect weist sie ab. Genau deshalb hat
in diesem Repo ein gescheiterter Deploy immer einen neuen `.deploy/release`-Bump gekostet
statt eines Knopfdrucks. Reparatur: `run_number * 100 + run_attempt` (oder gleichwertig) — **aber NICHT „eine
Zeile", und die erste Fassung dieses Absatzes schrieb genau das.** `github.run_number` trägt
die Build-Nummer an ZWEI gekoppelten Stellen: `testflight.yml:55` (`BUILD_NUMBER`) und
`:552` (`EXPECTED_BUILD`, die Zahl, nach der der ASC-Verify pollt). Wer nur eine ändert,
bekommt bei JEDEM Deploy die falsche Warnung „not visible within 20 min". Ehrlich ist:
**zwei Zeilen plus ein erneutes Lesen des Verify-Schritts.** Dieselbe Klasse wie der
„Wiederanschalten ist EINE Zeile"-Slogan, den CLAUDE.md als gefährlicher einstuft als eine
falsche Zahl — weil es der Satz ist, aus dem der nächste Zyklus seinen Aufwand schätzt.
Wächter steht jetzt (#635 Claim 6), deckt aber nur `:55`.

### 4. Der Deploy feuert auf JEDEM Branch, ohne Umgebungs-Gate — FOUNDER-GATED, SICHERHEIT
Der `push`-Trigger ist nur pfadgefiltert (`.deploy/release`), nicht branch-gefiltert. Eine
einzeilige Änderung an dieser Datei auf einem beliebigen Branch startet einen Job mit
App-Store-Connect-Zugangsdaten, der Zertifikate widerruft und in den Store lädt. Reparatur:
`branches:`-Filter oder eine GitHub-Environment mit Reviewer.

### 5. Jeder Deploy widerruft ALLE Entwickler-Zertifikate des Teams — `fastlane/`, NICHT gated
Gemessen im Job-Log von 2527: `Found 1 development certificate(s), revoking...` →
`Revoked 1` → `Creating fresh Development certificate`. Im Normalfall ist dieses eine das des
VORHERIGEN Laufs, die Schleife ist also ein Laufband und tut niemandem weh.

⛔ **Der Selektor ist aber `alle DEVELOPMENT-Zertifikate`** — in `fastlane/Fastfile`
wörtlich `Certificate.all.select { … t == "DEVELOPMENT" || t == "IOS_DEVELOPMENT" ||
t == "MAC_APP_DEVELOPMENT" }`, danach `dev_certs.each { |c| c.delete! }` (Phrase statt
Zeilennummer zitiert — Zeilennummern altern in diesem Repo an jedem Einschub).
Sobald der Founder auf seinem eigenen Mac ein Entwickler-Zertifikat anlegt, nimmt es der
NÄCHSTE Deploy mit, und Xcode kann lokal nicht mehr aufs Gerät signieren, bis er ein neues
erzeugt. Der Loop kann diesen Unterschied heute nicht sehen: das CI-Zertifikat und das des
Founders sehen in der API gleich aus, und der private Schlüssel des CI-Zertifikats stirbt mit
dem Runner — CI MUSS also jeden Lauf ein frisches erzeugen und dafür einen Platz freimachen.

**Nicht still geändert, weil jede Variante eine Entscheidung ist:**
· (a) Distributions-P12 als Secret / `match` → gar kein Dev-Zertifikat mehr nötig;
· (b) eine Serial-Allowlist als Secret, die das Zertifikat des Founders schützt;
· (c) prüfen, ob ein Release-Archive das Dev-Zertifikat überhaupt braucht — signiert wird mit
  einem DISTRIBUTIONS-Zertifikat; das Dev-Zertifikat existiert nur, damit
  `-allowProvisioningUpdates` die Entwickler-Profile der Extension-Targets erzeugen kann.
  ⚠️ Und der Fastfile-Kommentar sagt etwas SCHWÄCHERES, als die erste Fassung dieses Absatzes
  ihm zuschrieb: er hält fest, dass ANGESAMMELTE Dev-Zertifikate Apples Limit erreichten und
  `-allowProvisioningUpdates` danach die Extension-Profile nicht mehr erzeugen konnte
  („couldn't find iOS App Development provisioning profiles matching
  com.echoelmusic.app.widgets"). Niemand hat den Schritt je entfernt und gemessen. Das
  Argument „messen, nicht annehmen" bleibt — die Aktenlage ist nur dünner als behauptet.
**→ Founder-Frage, keine stille Änderung.**

### 5b. Befund 4 und 5 hängen zusammen — das ist kein Zufall
`concurrency.group` ist auf `github.ref` geschlüsselt. Zwei Branches, die gleichzeitig
`.deploy/release` bumpen, laufen also NEBENEINANDER — und die RACE NOTE im `fastlane/Fastfile`
sagt selbst, das Widerrufen aller Dev-Zertifikate sei „only safe when ONE archive job runs at
a time". **Der fehlende Branch-Filter aus Befund 4 ist das, was die dort dokumentierte
Wettlaufsituation überhaupt erreichbar macht.** Beide Befunde einzeln zu reparieren ist
möglich; sie einzeln zu BEWERTEN ist falsch.

### 6. `MARKETING_VERSION` in `project.yml` steht auf `10.79.372` — 38 Releases zurück
Folgenlos **für den TestFlight-Pfad**, weil `testflight.yml` die Zeile vor jedem Build per
`sed` überschreibt — **und genau diese `sed` ist die eine Stelle, an der der Loop still das
Falsche ausliefern kann.** Ab jetzt bewacht (#635 Claim 4). ⚠️ Sonst nirgends:
`xcode-compile-check.yml` patcht `DEVELOPMENT_TEAM` und `BUILD_NUMBER`, aber NICHT
`MARKETING_VERSION`, und ein lokales `xcodegen generate` patcht gar nichts — jeder Build
außerhalb von TestFlight trägt also `10.79.372`. Für ein Compile-Gate egal, für ein lokales
Archiv des Founders nicht.

### 7. Der 20-Minuten-Verify ist absichtlich nicht fatal — BEHALTEN
Er endet mit `::warning::` und Exit 0, weil Apples Ingest langsamer sein darf als der Job.
Das ist richtig so und darf beim Optimieren nicht „aufgeräumt" werden.

---

## Gebaut in diesem Zyklus (in meiner Spur)

`Tests/CISmoke/TheShippedVersionComesFromTheReleaseFileTests.swift` — sechs Behauptungen, die
aus der Prosa in `.deploy/release` ein ausführbares Gesetz machen. Bewacht wird die einzige
**stille** Fehlerklasse des Loops: grüner Lauf, grüner Upload, falsche Version im App-Header.
· 1 Version wird überhaupt abgeleitet · 2 sie steht auf Zeile 1 · 3 der Workflow leitet noch
so ab UND Ableiten/Patchen bleiben gepaart (`greps >= 1` und `greps == seds` — **nicht** eine
`== 2`-Zählung: die wäre an Befund 1 dieses selben Berichts rot geworden, während die
benannte Behauptung wahr bleibt, #364) · 4 `project.yml` trägt noch die Schreibweise, die die
`sed` braucht (`>= 1`; NULL ist die Gefahr, „mehr als eins" war eine falsche Begründung —
die `sed` hat weder Adresse noch `/g` und patcht jede passende Zeile gleich) · 5 die Ableitung
ist die der Shell, an synthetischen Fällen bewiesen (bare `X.Y.Z` verliert, ein `v` ÜBER
Zeile 1 gewinnt) · 6 die Build-Nummer.
**Null Regressionen, und das steht so im Kopf der Datei** — nach §3 der CISmoke-Regeln:
0 Regressionen · 0 Anker-Abwesenheit · 6 Gegengewichte, davon Claim 5 zusätzlich ein
FORWARD-Wächter. Die Datei existiert auf dem Elternbaum nicht, dort hat also KEINE
Behauptung ein Verdikt; die drei gelesenen Dateien sind aber byte-identisch, also wären alle
sechs auch dort grün. **Zwei Reparaturen kamen aus dem Pflicht-Review und nicht von mir:**
Claim 3 hätte den eigenen Vorschlag dieses Berichts verboten, Claim 4 trug eine Begründung,
die die `sed` gar nicht hergibt.

## Reihenfolge, falls der Founder freigibt

1. **#3** (Build-Nummer beim Re-Run) — Zuverlässigkeit, eine Zeile, spart einen ganzen Zyklus
   pro gescheitertem Deploy.
2. **#1** (Compile-Check-Job vom Deploy-Pfad nehmen, Ökosystem-Compile in den iOS-Job) —
   ein Runner weniger pro Deploy, wahrscheinlich 2–3 min Uhr.
3. **#2** (Poll-Intervall) — ~1 min, risikolos.
4. **#4** (Branch-Filter / Environment) — Sicherheit.
5. **#5** (Zertifikats-Radius) — braucht eine Entscheidung, danach eine Probe.
