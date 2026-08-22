# PLAN — dem Vollbild-Visual eine Tür geben (offene Aufgabe #270)

**Stand:** 2026-08-22, gemessen gegen `2a1ae15`. **Noch nicht gebaut** — dieser Plan existiert,
weil die Scheibe einen VERTRAG hat, den der Quelltext selbst aufgeschrieben hat, und ein halb
ausgeführter Vertrag ist schlechter als keiner.

## Was heute unerreichbar ist — und es ist fertig gebaut

`.fullScreenCover(isPresented: $showVisual)` in `EchoelStudioView` enthält eine vollständige,
polierte Fläche: das Vollbild-`MetalBioView`, den `visualVJOverlay`, den Donut-Renderer
(`SpectralDonutView`), einen Aufnahmeknopf und einen Schließen-Knopf. **`showVisual` hat in
`Sources/` keinen Schreiber von `true`** — wortgrenzen-genau zwei Schreiber, der eigene
`@State`-Initialisierer und der Schließen-Knopf, beide `false`.

Das trifft **Ship-Gate 4** („Ausgabe: visual live + kontemplativ auf dem Gerät") direkt: das
schwebende Fenster ist da, das Vollbild nicht.

## Warum es EIN Knopf ist — und trotzdem kein Einzeiler

Der Steckplatz existiert, die Modal-Kette wächst also **nicht** (Black-Screen-Gesetz 10.76.34).
`.onChange(of: showVisual)` ist bereits geschrieben und regelt die GPU-Exklusivität (nur EIN
`MetalBioView` gleichzeitig; das schwebende Fenster wird versteckt und danach wiederhergestellt).
Der Autor hat die Tür also vorbereitet.

Was sie teuer macht, sind die Pflichten, die andere Commits an genau diesen Commit gehängt haben.

## CODE-Pflichten (gemessen: VIER, nicht drei)

1. **Die Tür.** Ein sichtbarer Knopf, kein verstecktes Gesten-Tor — der Cover-Quelltext zitiert
   selbst WCAG 2.2 („don't gate controls behind a hidden gesture"). Natürlicher Ort:
   `visualPanel` („Field"), direkt unter dem vorhandenen „Show/Hide visual window"-Knopf, in
   derselben Form. Kein neues Sheet, keine neue Datei.
2. **`normaliseUnreachableDonutMode()` LÖSCHEN, samt Aufrufstelle** (`EchoelStudioView.swift`,
   im `.onAppear`-Block). Ihr eigener Doc-Kommentar ordnet das wörtlich an: *„DELETE THIS
   TOGETHER WITH THE LINE THAT CALLS IT, IN THE SAME COMMIT THAT GIVES `showVisual` A SETTER
   AGAIN (#227)"*. Bleibt sie stehen, löscht die App bei JEDEM Start eine Einstellung, die der
   Nutzer jetzt setzen kann — aus einer ehrlichen Normalisierung wird ein stiller Zustandsfresser.
   ⚠️ Der Zwilling `normaliseDoorlessLeadMix()` (#255) bleibt UNANGETASTET — andere Bedingung.
3. **Die „Donuts"-Pille in `visualLookStrip`.** Der #227-Grabstein verlangt sie in genau diesem
   Commit zurück, mit der Begründung, das Overlay habe sonst kein Look-Bedienelement mehr.
   ⛔ **Diese Begründung ist vor dem Befolgen NACHZUMESSEN.** Gemessen 2026-08-22: die obere
   Leiste des Covers trägt bereits einen Donut-Umschalter (`Button { spectralDonuts.toggle() }`,
   Icon `circle.hexagongrid.fill`). Das Overlay steht also NICHT ohne Kontrolle da. Die Pille
   blind zurückzuholen baut ein ZWEITES Bedienelement für einen Zustand — genau die #290-Falle.
   Entscheidung gehört in den Commit, nicht in diesen Plan; belegt werden muss, welches der
   beiden Bedienelemente bleibt.
4. **`lookScrub`s Setter löscht `spectralDonuts`.** Heute harmlos (nichts Erreichbares setzt es
   `true`). Mit Tür bedeutet es: wer im Overlay den Look-Regler zieht, verliert stillschweigend
   den Donut-Modus. Der Quelltext nennt das „correct again the day the pill returns" — das ist
   eine BEHAUPTUNG über eine Bedienlogik, keine Messung, und sie gehört am Gerät geprüft.

## WÄCHTER, der rot werden MUSS

`Tests/CISmoke/VisualFineTuneReflowsTests` **Behauptung 6** („das Overlay ist weiter türlos") ist
ein Gegengewicht, das genau für diesen Tag gebaut wurde (#364: es verbietet die Tür nicht). Seine
Fehlermeldung nennt die Prosa-Heimaten. Ebenfalls betroffen: die Kopf-Punkte 6 und 7 derselben
Datei (Punkt 7 sagt ausdrücklich, dass Tür und Donut-Normalisierung **sich gegenseitig
ausschließen**) und `NoDoorlessStudioViewsTests`, das #270 als lebenden Beleg zitiert.

## PROSA-Heimaten — gemessen, nicht gezählt

`git grep -ln "showVisual" -- Sources Tests` liefert heute **10** Dateien; die Türlosigkeit wird
behauptet in `EchoelStudioView.swift` (28 Nennungen, mehrere ⛔-Blöcke), `Core/StudioDefaultKeys.swift`,
`Studio/AnalysisSpectrumView.swift` und in sechs Wächtern (`VisualFineTuneReflowsTests`,
`VisualLookTruthTests`, `NoDoorlessStudioViewsTests`, `AutoModeStartsOffAndOwnsNoTempoTests`,
`ResetSoundClearsWhatTheLaunchLineReportsTests`, `TapTargetFloorTests`) — dazu `CLAUDE.md`.

⚠️ **Die Zahl ist ein Datum, kein Fakt.** Der ausführende Commit misst neu:
`git grep -ln "showVisual" -- Sources Tests` und `git grep -n "showVisual" CLAUDE.md`.
`VisualFineTuneReflowsTests` sagt in seinem eigenen Kopf, dass „neun" dort eine LISTE war und
kein Zensus, und dass mindestens zwei weitere Heimaten existieren — dieselbe Lehre.

## Reihenfolge im ausführenden Commit

1. Messen (die zwei `grep`s oben) — die Liste ist der Arbeitsvorrat.
2. Knopf bauen · Normalisierer + Aufrufstelle löschen.
3. Pflicht 3 und 4 ENTSCHEIDEN und die Entscheidung an den Bedienelementen aufschreiben.
4. Wächter umschreiben (Behauptung 6 wird zur Behauptung „die Tür existiert und ist sichtbar").
5. Alle gemessenen Prosa-Heimaten im SELBEN Commit ziehen (#456).
6. Geräteprobe eintragen: Vollbild öffnen/schließen, GPU-Umschaltung, Querformat — das
   Querformat-Verify, das `VisualFineTuneReflowsTests` als unmöglich zurückziehen musste, wird
   an diesem Tag zum ersten Mal möglich.

## Was dieser Plan NICHT entscheidet

Ob der Founder das Vollbild-Visual überhaupt als Tür will. Es ist als **offene Aufgabe #270**
registriert, nicht als bewusst geparkte Fläche (anders als `ImmersiveStageView` und
`BroadcastView`, die Ship-Gate 4 ausdrücklich als „demonstrierbar, nicht erforderlich" führt).
Der Bau ist damit gedeckt; die Geräteprobe bleibt seine.
