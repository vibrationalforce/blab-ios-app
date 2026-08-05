// TakeDistanceTests.swift
// Echoel — die Zahl, mit der „klingen die Songs alle gleich?" beantwortbar wird. #403 Slice 0.
//
// ⭐ WARUM DIESER WÄCHTER VOR DEM FEATURE KOMMT. Der Founder-Satz vom 2026-08-05 lautet:
// *"Mir wäre wichtig, das man nicht das Gefühl hat die Kompositionen klingen gleich … Es wäre
// schlechtes Marketing, wenn die Songs alle ähnlich klingen."* Die naheliegende Antwort darauf
// ist, mehr Variation einzubauen — und die nächste Frage („ist es jetzt genug anders?") ist ohne
// Messgröße nicht beantwortbar. #314 hält die Lehre fest: erst beweisen, was kaputt ist, dann
// bauen. Diese Datei ist die Hälfte, die das Beweisen möglich macht.
//
// ⭐ ZWEI HÄLFTEN, ABSICHTLICH IN EINER DATEI. Oben stehen die reinen Eigenschaften des Maßes
// (exakt nachrechenbar, keine Komposition beteiligt), unten fährt es echte `BioComposer`-Takes.
// Ein reiner Kern ohne Aufrufer ist derselbe Defekt mit mehr Schritten — dieses Repo hat ihn
// mehrfach bezahlt. Wer nur die obere Hälfte hätte, hätte ein korrektes Lineal, das nie an ein
// Werkstück gehalten wurde.
//
// ⛔ WAS ER NICHT BEWEIST, und die Grenze ist scharf. Er liest NOTEN, nicht Audio. Timbre, FX,
// Mischung und Lautheit sind unsichtbar; ein Abstand von 0 heißt „dieselben Noten", nicht
// „derselbe Klang". Und kein Schwellwert hier ist ein Beleg dafür, dass ein MENSCH einen
// Unterschied HÖRT. Das bleibt beim Ohr des Founders — NEEDS-FOUNDER-VERIFY.
//
// ⚠️ DIE SCHWELLEN SIND BÖDEN, KEINE ZIELE. `minimumCrossBodyDistance` ist so gesetzt, dass
// heutiges Verhalten sie erfüllt und ein KOLLAPS (alle Takes fallen aufeinander) sie reißt.
// Die Frage „reicht das dem Ohr?" beantwortet erst #403 Slice 2 mit gemessenen Zahlen. Wer die
// Schwelle anhebt, ohne gemessen zu haben, baut einen Wächter, der eine Meinung durchsetzt.
//
// ⚠️ DIE SEED-FALTUNG UNTEN IST EINE NACHBILDUNG, KEIN AUFRUF DER APP. Die echte `bioSeed`
// ist privat auf `EchoelStudioView` (@MainActor, eine View) und aus dem blockierenden Bundle
// nicht erreichbar. `foldBody` hat DIESELBE FORM (HR fein quantisiert, die drei normierten
// Werte grob), ist aber eine zweite Implementierung — dieser Test pinnt also die
// UNTERSCHEIDUNGSKRAFT des Maßes, NICHT die App-Verdrahtung. Die Verdrahtung bekommt ihren
// eigenen Wächter mit `PerformerSignature` (#403 Slice 1); bis dahin darf niemand diese Datei
// als Beleg dafür zitieren, dass die App richtig sät.

import Foundation
import XCTest
@testable import Echoelmusic

final class TakeDistanceTests: XCTestCase {

    // MARK: - Hälfte 1: das Lineal (exakt, ohne Komponist)

    /// Zwei identische Takes sind in JEDEM Anteil 0. Der Basisfall — reißt er, misst
    /// nichts darunter mehr etwas Sinnvolles.
    func testIdenticalTakesAreZeroApartInEveryComponent() {
        let take = Self.handmadeTake()
        let d = TakeDistance.distance(take, take)
        XCTAssertEqual(d.contour, 0, accuracy: 1e-6)
        XCTAssertEqual(d.onsets, 0, accuracy: 1e-6)
        XCTAssertEqual(d.density, 0, accuracy: 1e-6)
        XCTAssertEqual(d.register, 0, accuracy: 1e-6)
        XCTAssertEqual(d.velocity, 0, accuracy: 1e-6)
        XCTAssertEqual(d.overall, 0, accuracy: 1e-6)
    }

    /// Zwei LEERE Takes unterscheiden sich nicht — nichts gegen nichts.
    func testTwoSilencesAreNotDifferent() {
        XCTAssertEqual(TakeDistance.distance([], []).overall, 0, accuracy: 1e-6)
    }

    /// Genau EINER leer ist der größtmögliche Unterschied. Stille gegen Musik ist nicht
    /// „ein bisschen anders".
    func testSilenceAgainstMusicIsTheMaximum() {
        let take = Self.handmadeTake()
        XCTAssertEqual(TakeDistance.distance([], take).overall, 1, accuracy: 1e-6)
        XCTAssertEqual(TakeDistance.distance(take, []).overall, 1, accuracy: 1e-6)
    }

    /// Symmetrie. Ein Abstand, der von der Argumentreihenfolge abhängt, ist kein Abstand,
    /// und der Aufrufer in Slice 2 wird beide Richtungen bilden.
    func testTheDistanceIsSymmetric() {
        let a = Self.handmadeTake()
        let b = Self.handmadeTake(pitchOffset: 3, velocityOffset: 0.2, startOffsetSteps: 1)
        let ab = TakeDistance.distance(a, b)
        let ba = TakeDistance.distance(b, a)
        XCTAssertEqual(ab.overall, ba.overall, accuracy: 1e-6)
        XCTAssertEqual(ab.contour, ba.contour, accuracy: 1e-6)
        XCTAssertEqual(ab.onsets, ba.onsets, accuracy: 1e-6)
    }

    /// Ein Take ist eine MENGE, keine Folge. Der Komponist gibt seine Noten nicht in
    /// garantierter Ordnung heraus; ein Maß, das auf die Array-Reihenfolge hereinfällt,
    /// meldet Unterschiede, die niemand hört.
    /// ⚠️ Der Name hieß zuerst „shuffling" und der Rumpf drehte nur um. Eine Umkehrung IST
    /// eine gültige Permutation, der Test war also nie falsch — aber er versprach mehr
    /// Abdeckung als eine einzige feste Vertauschung liefert. Ohne Zufall (der einen
    /// Wächter unreproduzierbar machte) sind es jetzt ZWEI verschiedene Permutationen,
    /// und der Name sagt, was geprüft wird.
    func testTheOrderOfNotesDoesNotMatter() {
        let a = Self.handmadeTake()
        let reversed = Array(a.reversed())
        let rotated: [Note] = Array(a.dropFirst(3)) + Array(a.prefix(3))
        XCTAssertEqual(TakeDistance.distance(a, reversed).overall, 0, accuracy: 1e-6)
        XCTAssertEqual(TakeDistance.distance(a, rotated).overall, 0, accuracy: 1e-6)
        XCTAssertEqual(TakeDistance.distance(reversed, rotated).overall, 0, accuracy: 1e-6)
    }

    /// Eine um eine Oktave verschobene Melodie ist DIESELBE Melodie in einer anderen Lage.
    /// Die Kontur darf sich deshalb nicht rühren, das Register muss es.
    ///
    /// Das ist der Grund, warum `pitchClassHistogram` Tonstufen zählt und nicht Tonhöhen:
    /// sonst zählte dieselbe Tatsache zweimal.
    func testAnOctaveShiftMovesTheRegisterAndNotTheContour() {
        let a = Self.handmadeTake()
        let b = Self.handmadeTake(pitchOffset: 12)
        let d = TakeDistance.distance(a, b)
        XCTAssertEqual(d.contour, 0, accuracy: 1e-6,
                       "Eine Oktavverschiebung lässt die Tonstufen unverändert.")
        XCTAssertGreaterThan(d.register, 0,
                             "Zwoelf Halbtoene hoeher IST eine andere Lage.")
        // 12 von 24 Halbtoen Spanne = genau die Hälfte. Exakt nachrechenbar, deshalb hier
        // gepinnt und nicht bloß „größer null".
        XCTAssertEqual(d.register, 0.5, accuracy: 1e-4)
    }

    /// Jeder Anteil UND der Gesamtwert liegen in [0, 1] — auch bei absichtlich extremen
    /// Eingaben. Ein Maß, das seinen eigenen Wertebereich verlässt, macht jede spätere
    /// Schwelle bedeutungslos.
    func testEveryComponentStaysInsideItsRange() {
        let quiet = [Note(pitch: 24, startStep: 0, lengthSteps: 16, velocity: 0.0)]
        let loud = (0..<64).map {
            Note(pitch: 100 + ($0 % 20), startStep: $0 % 16, lengthSteps: 1, velocity: 1.0)
        }
        let d = TakeDistance.distance(quiet, loud)
        for (name, value) in [("contour", d.contour), ("onsets", d.onsets),
                              ("density", d.density), ("register", d.register),
                              ("velocity", d.velocity), ("overall", d.overall)] {
            XCTAssertGreaterThanOrEqual(value, 0, "\(name) unter 0")
            XCTAssertLessThanOrEqual(value, 1, "\(name) über 1")
        }
    }

    /// Der Gesamtwert ist ein gewichtetes MITTEL — er kann also nie kleiner als der
    /// kleinste und nie größer als der größte Anteil sein. Reißt das, ist die Gewichtung
    /// falsch normiert und jede Schwelle in Slice 2 misst etwas anderes als ihr Name sagt.
    func testTheOverallLiesBetweenItsOwnComponents() {
        let a = Self.handmadeTake()
        let b = Self.handmadeTake(pitchOffset: 5, velocityOffset: -0.3, startOffsetSteps: 3)
        let d = TakeDistance.distance(a, b)
        let parts = [d.contour, d.onsets, d.density, d.register, d.velocity]
        guard let lo = parts.min(), let hi = parts.max() else { return XCTFail("leer") }
        XCTAssertGreaterThanOrEqual(d.overall, lo - 1e-5)
        XCTAssertLessThanOrEqual(d.overall, hi + 1e-5)
    }

    /// Ein Gewichtssatz, der sich zu null addiert, ist keine sinnvolle Eingabe — aber
    /// konstruierbar. Er muss beantwortet werden, nicht durch null teilen.
    func testAZeroWeightSetDoesNotDivideByZero() {
        let a = Self.handmadeTake()
        let b = Self.handmadeTake(pitchOffset: 7)
        let zero = TakeDistance.Weights(contour: 0, onsets: 0, density: 0,
                                        register: 0, velocity: 0)
        let d = TakeDistance.distance(a, b, weights: zero)
        XCTAssertEqual(d.overall, 0, accuracy: 1e-6)
        XCTAssertTrue(d.overall.isFinite)
        // Die ANTEILE bleiben trotzdem gemessen — nur ihre Zusammenfassung entfällt.
        XCTAssertGreaterThan(d.contour, 0)
    }

    /// NaN darf das Ergebnis nicht vergiften. Die Bausteine werden hier direkt gefahren,
    /// weil `Note` selbst keinen nicht-endlichen Wert durchlässt (alle drei Inits klemmen
    /// NaN-sicher) — die Klammer im Maß ist Tiefenverteidigung, und Tiefenverteidigung
    /// gehört genau dort geprüft, wo sie sitzt.
    ///
    /// Die Argumentreihenfolge ist der Kern: `Swift.max(0, NaN)` ist 0, `Swift.max(NaN, 0)`
    /// ist NaN. Dieses Repo hat für die falsche Reihenfolge schon eine dauerhafte Stille
    /// ausgeliefert.
    func testNonFiniteInputCannotPoisonTheMeasure() {
        XCTAssertEqual(TakeDistance.clamp01(.nan), 0, accuracy: 1e-6)
        XCTAssertEqual(TakeDistance.clamp01(.infinity), 1, accuracy: 1e-6)
        XCTAssertEqual(TakeDistance.clamp01(-.infinity), 0, accuracy: 1e-6)
        XCTAssertTrue(TakeDistance.relativeGap(.nan, 1).isFinite)
        XCTAssertTrue(TakeDistance.spanGap(.nan, 1, span: 24).isFinite)
        XCTAssertTrue(TakeDistance.totalVariation([.nan, 1], [0, 1]).isFinite)
    }

    /// Verschieden lange Histogramme sind ein Programmierfehler, kein Eingabewert — sie
    /// dürfen den Index nicht sprengen.
    func testMismatchedHistogramsDoNotCrash() {
        XCTAssertTrue(TakeDistance.totalVariation([0.5, 0.5], [1]).isFinite)
        XCTAssertTrue(TakeDistance.totalVariation([], [1]).isFinite)
    }

    // MARK: - Hälfte 2: das Lineal an echten Takes

    /// VORBEDINGUNG für alles darunter — und zwar für den TEILWEISEN Ausfall, nicht für den
    /// vollständigen.
    ///
    /// ⛔ Die erste Fassung dieses Kommentars begründete den Test damit, dass bei leeren Takes
    /// „JEDER Abstand 1" wäre und die Schwellen darunter trivial erfüllt. Das ist genau
    /// verkehrt herum, und dieselbe Datei widerlegt es 120 Zeilen weiter oben: zwei LEERE
    /// Takes haben Abstand **0** (`testTwoSilencesAreNotDifferent`). Fielen alle fünf Körper
    /// aus, würde der Wächter darunter also FEHLSCHLAGEN statt falsch grün zu werden.
    ///
    /// Der echte Grund steht hier, weil eine falsche Begründung in diesem Repo schlimmer ist
    /// als gar keine: gefährlich ist der TEILAUSFALL. Erzeugen einige Körper Noten und andere
    /// nicht, bekommen genau diese Paare den Maximalwert 1 — und heben den Mittelwert über
    /// den Boden, ohne dass irgendetwas an der Musik verschieden wäre. Das ist die
    /// #376-Falle: grün aus einem Grund, den der Name nicht nennt.
    func testEveryTestBodyActuallyProducesNotes() {
        for body in Self.bodies {
            let notes = Self.take(body, genre: .acidTechno, evolution: 0)
            let message = "Koerper \(body.label) erzeugt keine Noten; jedes Paar mit ihm bekaeme den Maximalwert 1 und wuerde den Mittelwert unten heben, ohne dass Musik verschieden waere."
            XCTAssertFalse(notes.isEmpty, message)
        }
    }

    /// Der Founder-Satz, als Zahl: fünf verschiedene Körper, EIN Preset, kein Eingriff.
    /// Keine zwei Takes dürfen aufeinanderfallen, und im Mittel müssen sie messbar
    /// auseinanderliegen.
    ///
    /// ⚠️ Die Schwelle ist ein BODEN gegen Kollaps, kein Qualitätsurteil. „Klingt für ein
    /// Ohr verschieden genug" ist damit NICHT bewiesen.
    func testDifferentBodiesDoNotCollapseOntoOneTake() {
        let takes = Self.bodies.map { Self.take($0, genre: .acidTechno, evolution: 0) }
        var distances: [Float] = []
        for i in 0..<takes.count {
            for j in (i + 1)..<takes.count {
                let d = TakeDistance.distance(takes[i], takes[j]).overall
                let message = "\(Self.bodies[i].label) und \(Self.bodies[j].label) erzeugen denselben Take; zwei Menschen bekaemen dieselbe Datei."
                XCTAssertGreaterThan(d, 0, message)
                distances.append(d)
            }
        }
        let mean = distances.reduce(0, +) / Float(distances.count)
        let message = "Mittlerer Abstand zwischen Koerpern \(mean) liegt unter dem Boden \(Self.minimumCrossBodyDistance); die Takes konvergieren."
        XCTAssertGreaterThan(mean, Self.minimumCrossBodyDistance, message)
    }

    /// Die Entscheidung aus dem Plan, als Zahl: **die Signatur gehört der PERSON, die
    /// Variation dem MOMENT.** Derselbe Mensch soll bei jedem Render ein neues Stück
    /// bekommen und trotzdem näher bei sich selbst liegen als bei einem Fremden.
    ///
    /// ⚠️ WAS ER BEWEIST UND WAS NICHT — die erste Fassung dieses Kommentars nannte ihn „die
    /// Vorbedingung des Entwurfs", und das war zu viel behauptet. Die „selbe Person"-Paare
    /// unterscheiden sich NUR im Detail-Seed; die „fremde Person"-Paare unterscheiden sich im
    /// `structureSeed`, im Detail-Seed UND in allen vier Bio-Werten (Puls 52→104, HRV
    /// 0,85→0,15 …), und diese Bio-Werte treiben Tempo, Register und Dichte im Komponisten
    /// unabhängig vom Seed. Die Ordnung kann also halten, selbst wenn der `structureSeed`
    /// GAR NICHTS beitrüge. Was dieser Test zeigt, ist die PRODUKT-Eigenschaft: derselbe
    /// Mensch bleibt sich ähnlicher als zwei verschiedene. Die Naht für Slice 1 prüft der
    /// Test direkt darunter, der den Seed isoliert.
    func testTheSamePersonIsCloserToItselfThanToAStranger() {
        // Derselbe Körper, zwei Momente (Skelett gleich, Detail verschieden).
        var sameBody: [Float] = []
        for body in Self.bodies {
            let first = Self.take(body, genre: .acidTechno, evolution: 0)
            let second = Self.take(body, genre: .acidTechno, evolution: 1)
            sameBody.append(TakeDistance.distance(first, second).overall)
        }
        // Verschiedene Körper, derselbe Moment-Index.
        let takes = Self.bodies.map { Self.take($0, genre: .acidTechno, evolution: 0) }
        var crossBody: [Float] = []
        for i in 0..<takes.count {
            for j in (i + 1)..<takes.count {
                crossBody.append(TakeDistance.distance(takes[i], takes[j]).overall)
            }
        }

        let sameMean = sameBody.reduce(0, +) / Float(sameBody.count)
        let crossMean = crossBody.reduce(0, +) / Float(crossBody.count)

        let variationDead = "Derselbe Koerper bekommt bei zwei Renders EXAKT dieselben Noten; dann ist die Variation tot."
        XCTAssertGreaterThan(sameMean, 0, variationDead)
        let notCloser = "Zwei Takes derselben Person (\(sameMean)) liegen nicht naeher beieinander als zwei verschiedener Personen (\(crossMean)); die Wiedererkennbarkeit, die der Founder-Satz verlangt, gibt es dann nicht."
        XCTAssertLessThan(sameMean, crossMean, notCloser)
    }

    /// DIE NAHT, ISOLIERT — der Test, den der darüber nicht leisten kann.
    ///
    /// Hier ist ALLES gleich außer dem `structureSeed`: derselbe Körper, dasselbe Genre,
    /// derselbe Detail-Seed. Was übrig bleibt, ist ausschließlich der Skelett-Strom
    /// (`structureRNG` in `BioComposer.compose` — Progression, Register, Dichte,
    /// Ornament-Platzierung).
    ///
    /// Das ist die echte Vorbedingung für #403 Slice 1: die Entscheidung im Plan lautet
    /// „die Signatur fällt in den `structureSeed`". Wäre dieser Seed folgenlos, hätte die
    /// Personen-Signatur keinen Angriffspunkt und der Plan bräuchte eine andere Naht.
    ///
    /// ⚠️ Auch das ist ein Boden über null, keine Schwelle: WIE VIEL der Skelett-Strom
    /// bewegen soll, ist eine Klang-Entscheidung und gehört Slice 2.
    func testTheSkeletonSeedAloneChangesTheTake() {
        var distances: [Float] = []
        for body in Self.bodies {
            let structure = Self.foldBody(body)
            let detail = structure ^ 0x9E3779B97F4A7C15
            let a = Self.take(body, genre: .acidTechno, structure: structure, detail: detail)
            let b = Self.take(body, genre: .acidTechno,
                              structure: structure ^ 0xA5A5A5A5A5A5A5A5, detail: detail)
            XCTAssertFalse(a.isEmpty, "Take fuer \(body.label) ist leer.")
            distances.append(TakeDistance.distance(a, b).overall)
        }
        let mean = distances.reduce(0, +) / Float(distances.count)
        let message = "Nur der structureSeed wurde geaendert und der Take blieb im Mittel derselbe; dann hat eine Personen-Signatur in diesem Seed keinen Angriffspunkt und #403 Slice 1 braucht eine andere Naht."
        XCTAssertGreaterThan(mean, 0, message)
    }

    /// Der HARTE Fall, und er gehört ausdrücklich in den Wächter: eine gehaltene Fläche.
    /// Die kontemplativen Genres sind die Mitte der Marke und zugleich die, bei denen am
    /// wenigsten passiert — wenn irgendwo alles gleich klingt, dann hier.
    ///
    /// Bewusst nur ein Boden über null und KEINE Schwelle: eine Fläche darf sich weniger
    /// unterscheiden als eine Acid-Linie, ohne dass das ein Defekt wäre. Was hier rot
    /// werden muss, ist der Totalausfall — dass der Körper eine Fläche überhaupt nicht
    /// mehr formt.
    func testASustainedPadStillMovesWithTheBody() {
        let takes = Self.bodies.map { Self.take($0, genre: .drift, evolution: 0) }
        for (index, notes) in takes.enumerated() {
            XCTAssertFalse(notes.isEmpty, "Flaeche fuer \(Self.bodies[index].label) ist leer.")
        }
        var distances: [Float] = []
        for i in 0..<takes.count {
            for j in (i + 1)..<takes.count {
                distances.append(TakeDistance.distance(takes[i], takes[j]).overall)
            }
        }
        let mean = distances.reduce(0, +) / Float(distances.count)
        let message = "Auf einer gehaltenen Flaeche erzeugen fuenf verschiedene Koerper im Mittel denselben Take; der Koerper formt das kontemplative Zentrum der Marke nicht."
        XCTAssertGreaterThan(mean, 0, message)
    }

    // MARK: - Testmaterial

    /// Der Boden für den mittleren Abstand zweier Körper auf einem melodischen Genre.
    ///
    /// ⚠️ GESETZT, NICHT GEMESSEN. Er ist so gewählt, dass heutiges Verhalten ihn deutlich
    /// erfüllt und ein Konvergenz-Defekt ihn reißt. Die Zahl, die dem OHR entspricht,
    /// liefert erst #403 Slice 2 — wer sie hier vorher anhebt, setzt eine Meinung durch.
    static let minimumCrossBodyDistance: Float = 0.05

    /// `Sendable` steht hier AUSDRÜCKLICH und nicht per Inferenz. Ein interner Struct aus
    /// `String` + `Float` bekommt die Konformanz heute geschenkt (SE-0302), und genau
    /// deshalb ist die Stelle heimtückisch: wer später ein Feld mit einer Closure oder einer
    /// Klasse ergänzt, verliert sie still — und rot wird nicht diese Zeile, sondern
    /// `static let bodies` weiter unten, mit einer Meldung über einen Typ, den er gerade gar
    /// nicht angefasst hat. Die Anforderung gehört an die Deklaration, die sie erzeugt.
    struct Body: Sendable {
        let label: String
        let hr: Float
        let hrv: Float
        let coherence: Float
        let breath: Float
    }

    /// Fünf deutlich verschiedene Körper — von ruhig/kohärent bis aufgeregt/unruhig.
    /// Bewusst über den ganzen plausiblen Bereich verteilt und nicht um einen Mittelwert
    /// gestreut: die Frage ist, ob VERSCHIEDENE Menschen verschiedene Musik bekommen.
    static let bodies: [Body] = [
        Body(label: "ruhig",       hr: 52, hrv: 0.85, coherence: 0.90, breath: 0.10),
        Body(label: "entspannt",   hr: 61, hrv: 0.62, coherence: 0.70, breath: 0.35),
        Body(label: "neutral",     hr: 72, hrv: 0.50, coherence: 0.50, breath: 0.50),
        Body(label: "angespannt",  hr: 88, hrv: 0.30, coherence: 0.25, breath: 0.70),
        Body(label: "aufgeregt",   hr: 104, hrv: 0.15, coherence: 0.10, breath: 0.90)
    ]

    /// Faltet einen Körper zu einem stabilen Seed.
    ///
    /// ⛔ Die erste Fassung dieses Kommentars sagte „HR fein quantisiert, die drei normierten
    /// Werte grob" — das ist genau verkehrt herum. Die App skaliert den Puls mit 100 (also
    /// 0,01 BPM Auflösung, GROB) und HRV/Kohärenz/Atemphase mit 100 000 (1e-5, FEIN). Es
    /// steht hier korrigiert, weil das der Absatz ist, den die nächste Session liest, wenn
    /// sie den echten Seed-Wächter für Slice 1 schreibt.
    ///
    /// ⚠️ Und „DIESELBE FORM" war zu stark: die App nimmt drei verschiedene ungerade
    /// Multiplikatoren, rundet und deckelt nach oben; das hier ist ein gleichförmiges FNV-1a
    /// mit `Int()`-Abschneidung und ohne Deckel (`Int(0.35 * 100_000)` ist 34 999, nicht
    /// 35 000). Für die Unterscheidungskraft des Maßes ist das gleichgültig — für einen
    /// Wächter über die App-Faltung wäre es der Unterschied zwischen Prüfen und Nachbauen.
    static func foldBody(_ b: Body) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for value in [UInt64(Swift.max(0, Int(b.hr * 100))),
                      UInt64(Swift.max(0, Int(b.hrv * 100_000))),
                      UInt64(Swift.max(0, Int(b.coherence * 100_000))),
                      UInt64(Swift.max(0, Int(b.breath * 100_000)))] {
            h = (h ^ value) &* 0x100000001b3
        }
        return h == 0 ? 1 : h
    }

    /// Ein Take, wie ihn die App bauen würde: Skelett aus dem Körper, Detail aus dem
    /// Moment. `evolution` ist die Render-Nummer derselben Person.
    static func take(_ body: Body, genre: MusicStyle, evolution: UInt64) -> [Note] {
        let structure = foldBody(body)
        return take(body, genre: genre, structure: structure,
                    detail: structure ^ (evolution &* 0x9E3779B97F4A7C15))
    }

    /// Dieselbe Konstruktion mit BEIDEN Seeds frei wählbar — die einzige Möglichkeit, den
    /// Skelett-Strom vom Detail-Strom zu trennen (`testTheSkeletonSeedAloneChangesTheTake`).
    static func take(_ body: Body, genre: MusicStyle,
                     structure: UInt64, detail: UInt64) -> [Note] {
        let input = BioComposer.Input(
            heartRateBPM: body.hr,
            hrvNormalized: body.hrv,
            coherence: body.coherence,
            breathPhase: body.breath,
            style: genre,
            seed: detail,
            structureSeed: structure)
        return BioComposer.compose(input).notes
    }

    /// Ein von Hand gebauter Take für die exakten Eigenschaften. Bewusst NICHT vom
    /// Komponisten: die obere Hälfte prüft das Lineal, nicht das Werkstück.
    static func handmadeTake(pitchOffset: Int = 0,
                             velocityOffset: Float = 0,
                             startOffsetSteps: Int = 0) -> [Note] {
        let pitches = [60, 62, 64, 67, 69, 72, 64, 60]
        return pitches.enumerated().map { index, pitch in
            Note(pitch: pitch + pitchOffset,
                 startStep: index * 2 + startOffsetSteps,
                 lengthSteps: 2,
                 velocity: Swift.min(1, Swift.max(0, 0.5 + Float(index) * 0.05 + velocityOffset)))
        }
    }
}
