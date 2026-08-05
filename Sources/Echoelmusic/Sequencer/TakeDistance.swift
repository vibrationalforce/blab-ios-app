//
//  TakeDistance.swift
//  Echoelmusic — Sequencer
//
//  ⭐ EINE ZAHL FÜR „KLINGT DAS GLEICH?" (#403 Slice 0).
//
//  Founder, 2026-08-05: *"Mir wäre wichtig, das man nicht das Gefühl hat die Kompositionen
//  klingen gleich. Wenn verschiedene User das selbe preset auswählen … soll er individuell nach
//  der Person klingen. Es wäre schlechtes Marketing, wenn die Songs alle ähnlich klingen."*
//
//  ⭐ WARUM DIE MESSGRÖSSE VOR DEM FEATURE KOMMT. Die naheliegende Reaktion auf diesen Satz ist,
//  mehr Variation einzubauen — und dann steht die nächste Frage sofort im Raum und ist nicht
//  beantwortbar: „ist es jetzt genug anders?" Dieses Repo hat dieselbe Falle schon einmal
//  bezahlt und die Lehre in #314 festgehalten: erst beweisen, was kaputt ist, dann bauen. Ohne
//  eine Zahl ist jede Folgescheibe Geschmackssache, und Geschmackssache konvergiert nicht.
//
//  ⛔ WAS DIESE DATEI NICHT IST, und die Grenze ist scharf: **kein Ähnlichkeitsmaß für
//  Klang.** Sie liest NOTEN, nicht Audio. Timbre, FX, Mischung, Lautheit — alles, was zwei
//  identische Notenfolgen völlig verschieden klingen lassen kann — sind hier unsichtbar. Ein
//  Abstand von 0 heißt „dieselben Noten", nicht „derselbe Klang", und ein grosser Abstand ist
//  kein Beweis, dass ein Mensch einen Unterschied HÖRT. Sie ist ein Regressionsmaß gegen
//  Konvergenz, kein Ersatz für das Ohr des Founders.
//
//  ⚠️ DIE GEWICHTE SIND EIN ANFANG, KEINE PHYSIK. `Weights.balanced` ist gesetzt, damit die
//  Zahl überhaupt existiert; welcher Anteil wie schwer wiegen MUSS, entscheidet die Messung an
//  echten Takes (#403 Slice 2), nicht diese Datei. Deshalb sind die fünf Anteile einzeln
//  abrufbar — wer nur den Gesamtwert liest, verliert genau die Information, die eine
//  Kalibrierung braucht.
//

import Foundation

/// Wie weit zwei Takes musikalisch auseinanderliegen — als Gesamtwert und in fünf benannten
/// Anteilen, jeder in [0, 1].
///
/// Reiner Wert-Typ: keine Allokation ausserhalb der Histogramme, kein Zustand, keine I/O,
/// nichts `@MainActor`. Läuft auf der Control-Plane; der Audio-Thread sieht ihn nie.
public enum TakeDistance {

    // MARK: - Ergebnis

    /// Ein Abstand, aufgeschlüsselt. Jeder Anteil ist in [0, 1]; 0 = nicht unterscheidbar
    /// in dieser Hinsicht, 1 = maximal verschieden.
    public struct Result: Sendable, Equatable {
        /// Welche Tonstufen vorkommen und wie oft — die harmonische Handschrift.
        public let contour: Float
        /// WO im Takt Noten anfangen — die rhythmische Handschrift.
        public let onsets: Float
        /// Wie viele Noten pro Takt.
        public let density: Float
        /// In welcher Lage gespielt wird (mittlere Tonhöhe).
        public let register: Float
        /// Wie laut und wie dynamisch gespielt wird.
        public let velocity: Float
        /// Gewichtetes Mittel der fünf. Der Wert, den man zitiert — nachdem man die fünf
        /// gelesen hat.
        public let overall: Float
    }

    /// Wie schwer jeder Anteil im Gesamtwert zählt.
    ///
    /// ⚠️ NICHT AUS DER MUSIKTHEORIE ABGELEITET. Kontur und Rhythmus wiegen am schwersten,
    /// weil sie das sind, was ein Hörer als „ein anderes Stück" erkennt; Velocity am
    /// leichtesten, weil sie zwei ansonsten identische Takes nicht zu zwei Stücken macht.
    /// Das ist eine begründete Setzung und keine Messung — wer sie ändert, muss die
    /// Schwellen in `TakeDistanceTests` mitziehen, sonst misst der Wächter etwas anderes
    /// als sein eigener Name behauptet.
    public struct Weights: Sendable, Equatable {
        public let contour: Float
        public let onsets: Float
        public let density: Float
        public let register: Float
        public let velocity: Float

        public init(contour: Float, onsets: Float, density: Float,
                    register: Float, velocity: Float) {
            self.contour = contour
            self.onsets = onsets
            self.density = density
            self.register = register
            self.velocity = velocity
        }

        public static let balanced = Weights(contour: 0.30, onsets: 0.30, density: 0.15,
                                             register: 0.15, velocity: 0.10)
    }

    // MARK: - Die Messung

    /// Der Abstand zwischen zwei Takes.
    ///
    /// SYMMETRISCH (`distance(a, b) == distance(b, a)`) und REIHENFOLGE-UNABHÄNGIG: ein Take
    /// ist hier eine MENGE von Noten, keine Folge. Beides ist Absicht — der Komponist gibt
    /// seine Noten nicht in garantierter Ordnung heraus, und ein Vergleich, der auf die
    /// Array-Reihenfolge hereinfällt, meldet Unterschiede, die niemand hört.
    ///
    /// Zwei LEERE Takes haben Abstand 0 (nichts gegen nichts ist nicht verschieden); genau
    /// einer leer hat Abstand 1 (Stille gegen Musik ist der größte Unterschied, den es gibt).
    public static func distance(_ a: [Note], _ b: [Note],
                                weights: Weights = .balanced) -> Result {
        if a.isEmpty && b.isEmpty {
            return Result(contour: 0, onsets: 0, density: 0, register: 0, velocity: 0, overall: 0)
        }
        if a.isEmpty || b.isEmpty {
            return Result(contour: 1, onsets: 1, density: 1, register: 1, velocity: 1, overall: 1)
        }

        let contour = totalVariation(pitchClassHistogram(a), pitchClassHistogram(b))
        let onsets = totalVariation(onsetHistogram(a), onsetHistogram(b))
        let density = relativeGap(Float(a.count), Float(b.count))
        let register = spanGap(meanPitch(a), meanPitch(b), span: Self.registerSpan)
        let velocity = velocityGap(a, b)

        let sum = weights.contour + weights.onsets + weights.density
            + weights.register + weights.velocity
        // Ein Gewichtssatz, der sich zu 0 addiert, wäre eine Division durch null. Er ist kein
        // sinnvoller Eingabewert, aber er ist konstruierbar — also wird er beantwortet statt
        // zu explodieren.
        let overall: Float = sum > 0
            ? (contour * weights.contour + onsets * weights.onsets + density * weights.density
               + register * weights.register + velocity * weights.velocity) / sum
            : 0

        return Result(contour: contour, onsets: onsets, density: density,
                      register: register, velocity: velocity,
                      overall: clamp01(overall))
    }

    // MARK: - Konstanten mit Begründung

    /// Ab welcher Differenz der mittleren Tonhöhe der Register-Anteil auf 1 steht: **zwei
    /// Oktaven**. Darunter läuft er linear.
    ///
    /// Warum genau 24 und nicht 12: eine Oktave Unterschied in der mittleren Lage ist zwischen
    /// zwei Takes desselben Genres normal (Bass-lastig gegen Pad-lastig), also wäre sie als
    /// Maximum schon von zwei ganz gewöhnlichen Takes ausgereizt und die Skala oben taub.
    static let registerSpan: Float = 24

    /// Auf wie viele Klassen die Onset-Positionen gefaltet werden: die 16 Sechzehntel eines
    /// 4/4-Takts.
    ///
    /// ⛔ HIER SITZT DIE GRÖSSTE BLINDSTELLE DIESER DATEI, und sie gehört benannt statt
    /// versteckt: die Faltung ist **modulo EIN Takt**. Zwei Takes mit derselben Takt-Figur,
    /// aber völlig verschiedenem Verlauf über acht Takte, sind auf diesem Anteil identisch.
    /// Für #403 ist das tragbar, weil die Frage „klingen zwei Renders desselben Presets
    /// gleich" sich zuerst an der Figur entscheidet — für eine spätere Frage nach der FORM
    /// (Aufbau, Steigerung) reicht dieser Anteil nicht, und dann braucht es einen sechsten.
    static let onsetClasses = 16

    // MARK: - Anteile

    /// Wie oft jede der zwölf Tonstufen vorkommt, auf Summe 1 normiert.
    ///
    /// Bewusst TONSTUFE und nicht absolute Tonhöhe: eine um eine Oktave verschobene Melodie
    /// ist dieselbe Melodie, und die Lage wird separat als `register` gemessen. Beides in
    /// einen Anteil zu werfen hiesse, denselben Unterschied doppelt zu zählen.
    static func pitchClassHistogram(_ notes: [Note]) -> [Float] {
        var bins = [Float](repeating: 0, count: 12)
        for note in notes {
            // ⚠️ DIESE KLAMMER IST HEUTE UNERREICHBAR, und das gehört dazugeschrieben statt
            // sie mit einer erfundenen Begründung zu rechtfertigen: BEIDE `Note`-Inits UND
            // `Note.init(from:)` klemmen die Tonhöhe auf 0…127, es gibt also keinen Weg,
            // eine negative in dieses Array zu bekommen. Sie steht trotzdem da, weil ein
            // negativer Wert in Swift einen NEGATIVEN Modulo liefert und damit nicht etwa
            // eine falsche Zahl, sondern einen Index-Absturz erzeugt — und weil sie nichts
            // kostet. Wer die Klammern in `Note` je lockert, findet hier keine Lücke.
            let pitch = Swift.max(0, note.pitch)
            bins[pitch % 12] += 1
        }
        return normalized(bins)
    }

    /// Wie oft eine Note auf jedem Sechzehntel des Takts beginnt, auf Summe 1 normiert.
    static func onsetHistogram(_ notes: [Note]) -> [Float] {
        // Die Faltungsbreite ist `Note.ticksPerStep * onsetClasses` — ein 4/4-Takt. Sie steht
        // hier bewusst nur als Erklärung: die Rechnung erreicht sie über den Modulo auf den
        // SCHRITT, nicht über den Tick, und eine ausgerechnete Konstante daneben wäre eine
        // zweite Wahrheit, die still veralten kann.
        var bins = [Float](repeating: 0, count: onsetClasses)
        for note in notes {
            let tick = Swift.max(0, note.startTick)
            let step = (tick / Note.ticksPerStep) % onsetClasses
            bins[step] += 1
        }
        return normalized(bins)
    }

    /// Mittlere Tonhöhe. Nur über nicht-leere Takes aufgerufen.
    static func meanPitch(_ notes: [Note]) -> Float {
        guard !notes.isEmpty else { return 0 }
        let sum = notes.reduce(into: Float(0)) { $0 += Float(Swift.max(0, $1.pitch)) }
        return sum / Float(notes.count)
    }

    /// Lautstärke-Unterschied: mittlere Velocity UND ihre Streuung, je zur Hälfte.
    ///
    /// Die Streuung ist mitgemessen, weil sie den Unterschied zwischen „gespielt" und
    /// „getippt" trägt: zwei Takes können dieselbe mittlere Lautstärke haben und trotzdem
    /// einer flach und einer phrasiert sein. Genau diese Flachheit hat log 2470 als
    /// „Velocity-Dynamik zerstört" gezeigt (siehe `MixerStore.combined`), also ist sie
    /// hier ein eigener Messwert und keine Nebensache.
    static func velocityGap(_ a: [Note], _ b: [Note]) -> Float {
        let (meanA, spreadA) = velocityStats(a)
        let (meanB, spreadB) = velocityStats(b)
        // Velocity lebt in [0, 1], also ist die Differenz bereits normiert. Die Streuung
        // kann höchstens 0,5 werden (zwei Häufungen an den Enden), daher der Faktor 2.
        let meanPart = clamp01(abs(meanA - meanB))
        let spreadPart = clamp01(abs(spreadA - spreadB) * 2)
        return clamp01((meanPart + spreadPart) * 0.5)
    }

    /// Mittelwert und Standardabweichung der Velocity, beide NaN-sicher.
    static func velocityStats(_ notes: [Note]) -> (mean: Float, spread: Float) {
        guard !notes.isEmpty else { return (0, 0) }
        // ⚠️ AUCH DIESE PRÜFUNG IST HEUTE UNERREICHBAR. Die erste Fassung dieses Kommentars
        // behauptete, ein DEKODIERTER Take umgehe die Klammer — das ist nachweislich falsch:
        // `Note.init(from:)` klemmt die Velocity mit demselben NaN-sicheren `clamped(to:)`
        // wie die beiden anderen Inits. Eine falsche Begründung ist in diesem Repo schlimmer
        // als gar keine, weil die nächste Session sie nicht widerlegen kann.
        // Der ECHTE Grund, dass sie bleibt: ein einzelnes NaN würde Mittelwert UND Streuung
        // in einem Zug vergiften, der Gesamtwert wäre unbrauchbar und NICHTS würde rot —
        // die stillste Art, ein Messgerät zu verlieren. Für ein Instrument, dessen einzige
        // Aufgabe das MESSEN ist, ist das der teuerste denkbare Ausfall, und er kostet hier
        // einen `isFinite`-Vergleich pro Note.
        let values = notes.map { $0.velocity.isFinite ? clamp01($0.velocity) : 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(into: Float(0)) { $0 += ($1 - mean) * ($1 - mean) }
            / Float(values.count)
        return (mean, variance.squareRoot())
    }

    // MARK: - Bausteine

    /// Totale Variationsdistanz zweier auf 1 normierter Verteilungen: `0.5 · Σ|p−q|`.
    ///
    /// Sie ist per Konstruktion in [0, 1] — 0 bei identischer Verteilung, 1 wenn die beiden
    /// keinen einzigen Bin teilen. Genau deshalb steht sie hier und nicht die euklidische
    /// Distanz: der Wertebereich ist bewiesen und nicht durch eine geschätzte Konstante
    /// normiert. Verschieden lange Histogramme sind ein Programmierfehler, kein Eingabewert
    /// — der kürzere wird als fehlend behandelt statt den Index zu sprengen.
    static func totalVariation(_ p: [Float], _ q: [Float]) -> Float {
        let n = Swift.min(p.count, q.count)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += abs(p[i] - q[i]) }
        return clamp01(sum * 0.5)
    }

    /// Symmetrischer relativer Abstand zweier nicht-negativer Zahlen: `|x−y| / (x+y)`.
    ///
    /// In [0, 1], 0 bei Gleichheit, 1 wenn eine der beiden null ist. Bewusst relativ und
    /// nicht absolut: 4 Noten gegen 8 ist ein grosser Unterschied, 104 gegen 108 keiner.
    static func relativeGap(_ x: Float, _ y: Float) -> Float {
        let sum = x + y
        guard sum > 0 else { return 0 }
        return clamp01(abs(x - y) / sum)
    }

    /// Linearer Abstand über eine feste Spanne, oben gekappt.
    static func spanGap(_ x: Float, _ y: Float, span: Float) -> Float {
        guard span > 0 else { return 0 }
        return clamp01(abs(x - y) / span)
    }

    /// Auf Summe 1 normieren. Ein leeres Histogramm bleibt leer — `totalVariation` liefert
    /// dafür 0, was richtig ist: zwei Takes ohne Noten unterscheiden sich nicht.
    static func normalized(_ bins: [Float]) -> [Float] {
        let sum = bins.reduce(0, +)
        guard sum > 0 else { return bins }
        return bins.map { $0 / sum }
    }

    /// NaN-sicher auf [0, 1] klemmen.
    ///
    /// Die Argument-Reihenfolge ist die Regel aus `CLAUDE.md` und keine Stilfrage:
    /// `Swift.max(0, x)` liefert für NaN eine 0, `Swift.max(x, 0)` liefert NaN. Dieses Repo
    /// hat für die falsche Reihenfolge schon eine dauerhafte Stille ausgeliefert.
    static func clamp01(_ x: Float) -> Float {
        Swift.min(1, Swift.max(0, x))
    }
}
