import Foundation

/// Represents a musical style with contextual metadata for prompt building
struct MusicStyle: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let region: String
    let description: String
    let moods: [String]
    let primaryInstruments: [String]
    let tempoRange: ClosedRange<Int>
    let meters: [String]
    let tonalSystemNames: [String]
    let textureKeywords: [String]
    let rhythmicConcepts: [String]

    /// Suggested default mood for the style
    var defaultMood: String { moods.first ?? "Atmospheric" }

    /// Suggested default tempo (middle of the tempo range)
    var defaultTempo: Int { (tempoRange.lowerBound + tempoRange.upperBound) / 2 }

    /// Suggested default meter
    var defaultMeter: String { meters.first ?? "4/4" }
}

/// Represents a tonal system or scale framework used in global music practice
struct TonalSystem: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let description: String
    let intervalStructure: [String]
    let culturalContext: String
}

/// Represents a concert pitch reference (Kammerton) used in different musical traditions
struct PitchStandard: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let frequency: Double
    let usage: String
    let region: String
}

/// Represents a composition school or philosophy that can influence generative prompts
struct CompositionSchool: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let era: String
    let characteristics: [String]
    let notableFigures: [String]
    let productionNotes: [String]
}

/// Describes a prompt configuration for generating loops, textures and melodies
struct PromptSoundConfiguration {
    let style: MusicStyle
    let tonalSystem: TonalSystem
    let pitchStandard: PitchStandard
    let compositionSchool: CompositionSchool?
    let mood: String
    let tempo: Int
    let timeSignature: String
    let loopLengthBars: Int
    let instrumentation: [String]
    let texturalFocus: [String]
    let rhythmicConcepts: [String]
    let melodicConcept: String

    /// Build a natural language prompt that can be sent to a generative system
    func buildPrompt() -> String {
        var lines: [String] = []

        lines.append("Erzeuge eine mehrspurige, nahtlos loopbare Audiolandschaft im Stil von \(style.name) aus \(style.region).")
        lines.append("Ziel: separate Loops für Percussion, Harmonie, Texturen und Melodie mit \(loopLengthBars)-taktigen Phrasen, die sich ohne hörbare Übergänge wiederholen.")
        lines.append("")

        lines.append("### Kontext")
        lines.append("- Stilbeschreibung: \(style.description)")
        lines.append("- Emotionale Stimmung: \(mood)")
        lines.append("- Tempo: \(tempo) BPM in \(timeSignature)")
        lines.append("- Tonsystem: \(tonalSystem.name) – \(tonalSystem.description)")
        lines.append("- Intervallstruktur: \(tonalSystem.intervalStructure.joined(separator: ", "))")
        lines.append("- Kammerton: \(pitchStandard.name) (\(String(format: "%.1f", pitchStandard.frequency)) Hz, \(pitchStandard.usage))")

        if let school = compositionSchool {
            lines.append("- Kompositionsschule: \(school.name) (\(school.era)) – \(school.characteristics.joined(separator: ", "))")
            lines.append("- Referenzen: \(school.notableFigures.joined(separator: ", "))")
        }

        if !instrumentation.isEmpty {
            lines.append("- Kerninstrumentierung: \(instrumentation.joined(separator: ", "))")
        }

        if !texturalFocus.isEmpty {
            lines.append("- Texturen & Oberflächen: \(texturalFocus.joined(separator: ", "))")
        }

        if !rhythmicConcepts.isEmpty {
            lines.append("- Rhythmische Konzepte: \(rhythmicConcepts.joined(separator: ", "))")
        }

        lines.append("- Melodische Idee: \(melodicConcept)")
        lines.append("")

        lines.append("### Produktionshinweise")
        lines.append("1. Stelle sicher, dass jede Spur als eigenständige Stem-Loop exportiert werden kann (Percussion, Bass, Harmonie, Melodie, Atmosphäre).")
        lines.append("2. Nutze Mikrovariationen pro Takt, damit die Loops organisch wirken, ohne den Groove zu zerstören.")
        lines.append("3. Beschreibe für jeden Loop Start-/End-Hüllkurven, Dynamikbögen und empfohlene Effektketten (z. B. Band-Echo, Körnung, Tape-Sättigung).")
        lines.append("4. Vermerke wichtige Akzente, Call-and-Response-Phrasen und Übergänge innerhalb der \(loopLengthBars) Takte.")
        lines.append("5. Dokumentiere die tonale Verankerung (Grundton, Drone, modale Funktionen) im Kontext von \(tonalSystem.culturalContext).")

        if let school = compositionSchool {
            lines.append("6. Halte die Ästhetik der \(school.name) ein: \(school.productionNotes.joined(separator: ", ")).")
        } else {
            lines.append("6. Verwende hochwertige Klanggestaltung, um die ausgewählte Stimmung zu verstärken, und liefere passende Mastering-Notizen.")
        }

        lines.append("")
        lines.append("### Auslieferung")
        lines.append("- Liefere strukturierte Metadaten mit Tempo, Taktart, Kammerton, Tonsystem, verwendeten Instrumenten und Texturhinweisen.")
        lines.append("- Ergänze eine kurze Storyline, die die kulturelle Herkunft respektvoll erläutert und kreative Einsatzmöglichkeiten skizziert.")
        lines.append("- Beschreibe optionale Variationen (Breaks, Fills, Melodievarianten), die aus demselben Material abgeleitet werden können.")

        return lines.joined(separator: "\n")
    }
}

/// Central knowledge base describing world music contexts for prompt generation
struct MusicPromptDatabase {
    static let shared = MusicPromptDatabase()

    let styles: [MusicStyle]
    let tonalSystems: [TonalSystem]
    let pitchStandards: [PitchStandard]
    let compositionSchools: [CompositionSchool]
    let texturalDescriptors: [String]
    let melodicConcepts: [String]
    let rhythmicConcepts: [String]

    init() {
        self.tonalSystems = [
            TonalSystem(
                name: "12-TET",
                description: "Gleichstufige Stimmung mit 12 Halbtönen pro Oktave",
                intervalStructure: ["1", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7"],
                culturalContext: "Globaler Standard der westlichen Pop-, Rock- und Klassikproduktion"
            ),
            TonalSystem(
                name: "Just Intonation",
                description: "Reine Intervalle auf Basis von Obertönen",
                intervalStructure: ["1/1", "9/8", "5/4", "3/2", "5/3", "15/8"],
                culturalContext: "Historische und experimentelle westliche Musik, Chöre, reine Stimmungen"
            ),
            TonalSystem(
                name: "Raga Bhairavi",
                description: "Südasiatisches modales System mit Mikrotonalität",
                intervalStructure: ["Sa", "Komal Re", "Komal Ga", "Ma", "Pa", "Komal Dha", "Komal Ni"],
                culturalContext: "Hindustanische klassische Musik, Morgenraga"
            ),
            TonalSystem(
                name: "Maqam Rast",
                description: "Arabisches Maqam mit neutralen Terzen",
                intervalStructure: ["Jins Rast (Sa, Duga, Sikah, Jaharkah)", "Jins Nahawand", "Jins Rast"],
                culturalContext: "Nordafrikanische und Nahost-Traditionen"
            ),
            TonalSystem(
                name: "Pelog",
                description: "Siebenstufiges indonesisches Gamelan-Tonsystem",
                intervalStructure: ["1", "♭2", "♭3", "4", "♭5", "5", "♭6"],
                culturalContext: "Javanisches und balinesisches Gamelan"
            ),
            TonalSystem(
                name: "Insen Scale",
                description: "Japanische pentatonische Skala mit charakteristischen Halbtonschritten",
                intervalStructure: ["1", "♭2", "4", "5", "♭6"],
                culturalContext: "Japanische traditionelle und moderne Musik"
            ),
            TonalSystem(
                name: "Axatse Polyrhythm",
                description: "Ewe-Percussion-Pattern als tonales Raster",
                intervalStructure: ["Timeline-Pattern", "Cross-Rhythmus 3:2"],
                culturalContext: "Westafrikanische polyrhythmische Ensembles"
            ),
            TonalSystem(
                name: "Andalusischer Modus",
                description: "Phrygisch-dominantes System mit Flamenco-Cadenz",
                intervalStructure: ["1", "♭2", "3", "4", "5", "♭6", "♭7"],
                culturalContext: "Flamenco und andalusische Volksmusik"
            )
        ]

        self.pitchStandards = [
            PitchStandard(name: "A440", frequency: 440.0, usage: "Moderner globaler Standard", region: "Weltweit"),
            PitchStandard(name: "A432", frequency: 432.0, usage: "Ganzheitliche und esoterische Produktion", region: "Global"),
            PitchStandard(name: "A415", frequency: 415.0, usage: "Barocke historische Aufführungspraxis", region: "Europa"),
            PitchStandard(name: "Sa240", frequency: 240.0, usage: "Traditionelle Shruti für indische klassische Musik", region: "Südasien"),
            PitchStandard(name: "C523.3", frequency: 523.3, usage: "Balinesisches Gamelan (Saron) Referenz", region: "Indonesien"),
            PitchStandard(name: "Eb453", frequency: 453.0, usage: "Blasorchester der Romantik", region: "Europa"),
            PitchStandard(name: "A444", frequency: 444.0, usage: "Club-/EDM-Produktionen für mehr Brillanz", region: "Global")
        ]

        self.compositionSchools = [
            CompositionSchool(
                name: "Minimal Music",
                era: "1960er bis heute",
                characteristics: ["Phasenverschiebung", "Repetitive Patterns", "Langsame Transformationen"],
                notableFigures: ["Steve Reich", "Philip Glass", "Terry Riley"],
                productionNotes: ["Transparente Layering-Techniken", "Subtile Dynamikverläufe", "Phasings akzentuieren"]
            ),
            CompositionSchool(
                name: "Spectralismus",
                era: "1970er bis heute",
                characteristics: ["Obertonspektren", "Mikrotonalität", "Klangfarbenkomposition"],
                notableFigures: ["Gérard Grisey", "Kaija Saariaho", "Georg Friedrich Haas"],
                productionNotes: ["Spektralanalyse nutzen", "Filterfahrten sorgfältig gestalten", "Raumklang betonen"]
            ),
            CompositionSchool(
                name: "Second Viennese School",
                era: "1900-1930",
                characteristics: ["Atonalität", "Zwölftonreihen", "Expressionistische Gestik"],
                notableFigures: ["Arnold Schönberg", "Alban Berg", "Anton Webern"],
                productionNotes: ["Motivische Verdichtung", "Kontrapunktische Klarheit", "Dissonanzdramaturgie"]
            ),
            CompositionSchool(
                name: "Afrofuturismus",
                era: "1970er bis heute",
                characteristics: ["Science-Fiction-Ästhetik", "Polyrhythmik", "Elektronische Hybridinstrumente"],
                notableFigures: ["Sun Ra", "Janelle Monáe", "Flying Lotus"],
                productionNotes: ["Schimmernde Synthesizerflächen", "Raumfahrt-Sounddesign", "Hybrid-Grooves"]
            ),
            CompositionSchool(
                name: "Nueva Canción",
                era: "1950er-1970er",
                characteristics: ["Politische Lyrik", "Akustische Instrumentierung", "Fokussierte Melodik"],
                notableFigures: ["Violeta Parra", "Mercedes Sosa", "Inti-Illimani"],
                productionNotes: ["Authentische Folkloreinstrumente", "Intime Aufnahmetechniken", "Textverständlichkeit sichern"]
            )
        ]

        self.styles = [
            MusicStyle(
                name: "Afrobeat",
                region: "Westafrika / Nigeria",
                description: "Groovende Polyrhythmik mit Call-and-Response-Horns und hypnotischen Basslines",
                moods: ["Energetisch", "Politisch", "Treibend"],
                primaryInstruments: ["Talking Drum", "E-Bass", "Bläsersektion", "Rhythmusgitarre", "Orgel"],
                tempoRange: 100...126,
                meters: ["4/4"],
                tonalSystemNames: ["12-TET", "Axatse Polyrhythm"],
                textureKeywords: ["Schichtende Percussion", "Funk-Gitarre", "Horn-Shouts"],
                rhythmicConcepts: ["Polyrhythmik 12/8 über 4/4", "Synkopierte Gitarrenfiguren", "Horch-Breaks"]
            ),
            MusicStyle(
                name: "Gamelan Gong Kebyar",
                region: "Bali, Indonesien",
                description: "Strahlende metallische Ensemblefarben mit dynamischen Crescendi",
                moods: ["Transzendent", "Festlich", "Mystisch"],
                primaryInstruments: ["Gangsa", "Jegog", "Ceng-Ceng", "Gong", "Rebab"],
                tempoRange: 70...140,
                meters: ["4/4", "5/4", "Unregelmäßig"],
                tonalSystemNames: ["Pelog"],
                textureKeywords: ["Glitzernde Metallplatten", "Schimmernde Tremoli", "Chorische Glocken"],
                rhythmicConcepts: ["Kotekan-Interlocking", "Beschleunigte Crescendi", "Gong-Zyklen"]
            ),
            MusicStyle(
                name: "Samba Batucada",
                region: "Brasilien",
                description: "Dichte Percussion-Batterie mit surdo-getriebener Vorwärtsbewegung",
                moods: ["Feierlich", "Extrovertiert", "Carnaval"],
                primaryInstruments: ["Surdo", "Caixa", "Agogô", "Tamborim", "Repinique"],
                tempoRange: 90...140,
                meters: ["2/4"],
                tonalSystemNames: ["12-TET"],
                textureKeywords: ["Polyrhythmische Layer", "Handclaps", "Crowd-Chants"],
                rhythmicConcepts: ["Clave-Varianten", "Ruf-und-Antwort", "Triole vs. Duole"]
            ),
            MusicStyle(
                name: "Nordindischer Khyal",
                region: "Südasien",
                description: "Improvisierte Vokal- und Instrumentalraga mit dronebasierter Begleitung",
                moods: ["Kontemplativ", "Weit", "Spirituell"],
                primaryInstruments: ["Tanpura", "Tabla", "Sarangi", "Bansuri", "Harmonium"],
                tempoRange: 48...96,
                meters: ["Tintal 16", "Jhaptal 10"],
                tonalSystemNames: ["Raga Bhairavi"],
                textureKeywords: ["Drone-Schichten", "Mikrotonale Ornamentik", "Resonanter Raum"],
                rhythmicConcepts: ["Laykari", "Tihai-Schlussfiguren", "Bol-Variationen"]
            ),
            MusicStyle(
                name: "Japanese Ambient",
                region: "Japan",
                description: "Minimalistische Texturen mit weicher Elektronik und akustischen Fragmenten",
                moods: ["Gelassen", "Zen", "Träumerisch"],
                primaryInstruments: ["Synth-Pads", "Shakuhachi", "Feldaufnahmen", "Koto", "E-Piano"],
                tempoRange: 60...90,
                meters: ["4/4", "Freier Puls"],
                tonalSystemNames: ["Insen Scale", "Just Intonation"],
                textureKeywords: ["Diffuse Reverbs", "Granular Layers", "Luftige Harmonien"],
                rhythmicConcepts: ["Asymmetrische Pulsation", "Langsame Beat-Regen", "Subtile Swells"]
            ),
            MusicStyle(
                name: "Andalusischer Flamenco",
                region: "Spanien",
                description: "Virtuose Gitarren mit palmas, cante jondo und expressiver Dynamik",
                moods: ["Passioniert", "Melancholisch", "Virtuos"],
                primaryInstruments: ["Flamencogitarre", "Palmas", "Cajón", "Gesang", "Violine"],
                tempoRange: 90...160,
                meters: ["12/8", "6/8"],
                tonalSystemNames: ["Andalusischer Modus"],
                textureKeywords: ["Rasgueado-Strumming", "Fusspercussion", "Kantige Vocals"],
                rhythmicConcepts: ["Compás 12er Zyklus", "Palmas-Kontrapunkte", "Golpe-Akzente"]
            ),
            MusicStyle(
                name: "Detroit Techno",
                region: "USA",
                description: "Maschineller Drive mit souligen Akkordflächen und futuristischen Synths",
                moods: ["Hypnotisch", "Urban", "Futuristisch"],
                primaryInstruments: ["909-Drums", "Poly-Synth", "FM-Bass", "Field-Recording", "Vocoder"],
                tempoRange: 118...132,
                meters: ["4/4"],
                tonalSystemNames: ["12-TET"],
                textureKeywords: ["Maschinelles Grollen", "Analoge Sättigung", "Schimmernde Pads"],
                rhythmicConcepts: ["Shuffle-HiHats", "Offbeat Stabs", "Filterfahrten"]
            ),
            MusicStyle(
                name: "Tuva Kehlkopfgesang",
                region: "Zentralasien",
                description: "Mehrstimmiger Gesang mit Obertönen und Steppen-Drone",
                moods: ["Archaisch", "Weit", "Naturverbunden"],
                primaryInstruments: ["Khoomei-Stimme", "Igil", "Doshpuluur", "Rahmentrommel", "Windaufnahmen"],
                tempoRange: 40...80,
                meters: ["Freier Puls", "5/4"],
                tonalSystemNames: ["Just Intonation"],
                textureKeywords: ["Oberton-Schwebungen", "Windrauschen", "Tiefe Drone"],
                rhythmicConcepts: ["Freie Rezitation", "Pulsierende Drones", "Obertonglissandi"]
            ),
            MusicStyle(
                name: "Irish Trad Session",
                region: "Irland",
                description: "Melodische Jigs und Reels mit lebendigem Ensemble-Feeling",
                moods: ["Lebhaft", "Gemeinschaftlich", "Nostalgisch"],
                primaryInstruments: ["Fiddle", "Bodhrán", "Tin Whistle", "Uilleann Pipes", "Bouzouki"],
                tempoRange: 100...132,
                meters: ["6/8", "4/4"],
                tonalSystemNames: ["12-TET", "Just Intonation"],
                textureKeywords: ["Doppelte Fiddles", "Holzige Drones", "Pub-Ambience"],
                rhythmicConcepts: ["Jig-Phrasierung", "Rolls & Cuts", "Bodhrán-Pulse"]
            ),
            MusicStyle(
                name: "Cumbia Andina",
                region: "Andenregion",
                description: "Hybrid aus traditioneller Cumbia und psychedelischen Orgeln",
                moods: ["Psychedelisch", "Tanzbar", "Warm"],
                primaryInstruments: ["Guacharaca", "Congas", "Orgel", "Gitarre", "Synth Flöte"],
                tempoRange: 80...110,
                meters: ["4/4"],
                tonalSystemNames: ["12-TET"],
                textureKeywords: ["Band-Echo", "Tremolo-Orgel", "Analoge Patina"],
                rhythmicConcepts: ["Cumbia-Groove", "Cowbell-Pattern", "Percussion-Fills"]
            ),
            MusicStyle(
                name: "Persischer Dastgah",
                region: "Iran",
                description: "Modal improvisierte Musik mit mikrotonalen Intervallen und Tahrir-Gesang",
                moods: ["Melancholisch", "Meditativ", "Erhaben"],
                primaryInstruments: ["Santur", "Kamancheh", "Tar", "Tombak", "Setar"],
                tempoRange: 54...96,
                meters: ["Daryamad", "Chaharmezrab"],
                tonalSystemNames: ["Maqam Rast"],
                textureKeywords: ["Zarte Tremoli", "Holzige Resonanzen", "Atemreiche Vocals"],
                rhythmicConcepts: ["Avaz freie Einleitung", "Gushe-Wechsel", "Daramad-Themen"]
            )
        ]

        self.texturalDescriptors = [
            "Körnige Pads",
            "Schimmernde Metallperlen",
            "Staubige Vinyl-Atmosphäre",
            "Raumige Field-Recordings",
            "Analoges Bandflattern",
            "Subtile Sidechain-Swells",
            "Verwaschene Chöre",
            "Organische Foley-Schichten"
        ]

        self.melodicConcepts = [
            "Call-and-Response zwischen Hauptstimme und Echo",
            "Aufsteigende Sequenzen mit modaler Drehung",
            "Drohnenbasierte Melismatik",
            "Minimalistische Motivverschiebung",
            "Pentatonischer Leitgedanke mit Ornamentik",
            "Improvisierte Skalenfahrten über Bordun",
            "Gritty Synth-Licks mit Portamento",
            "Chorisches Thema in parallelen Intervallen"
        ]

        self.rhythmicConcepts = [
            "3:2 Cross-Rhythmus",
            "Clave-basierte Synkopen",
            "Swingende 16tel-Unterteilungen",
            "Asymmetrische 5er Akzentgruppe",
            "Hocket-Technik",
            "Backbeat mit perkussiven Ghostnotes",
            "Kaskadierende Toms",
            "Rolling Triplets"
        ]
    }

    /// Returns tonal systems that match the provided style
    func tonalSystems(for style: MusicStyle) -> [TonalSystem] {
        tonalSystems.filter { style.tonalSystemNames.contains($0.name) }
    }

    /// Returns composition schools that are relevant to the style (basic heuristic by region or mood)
    func compositionSchools(for style: MusicStyle) -> [CompositionSchool] {
        if style.moods.contains(where: { $0.contains("Spirituell") || $0.contains("Meditativ") }) {
            return compositionSchools.filter { $0.name != "Second Viennese School" }
        }
        if style.region.contains("USA") || style.region.contains("Urban") {
            return compositionSchools.filter { $0.name != "Nueva Canción" }
        }
        return compositionSchools
    }

    /// Returns pitch standards that may be appropriate for the style
    func pitchStandards(for style: MusicStyle) -> [PitchStandard] {
        switch style.name {
        case "Gamelan Gong Kebyar":
            return pitchStandards.filter { $0.region == "Indonesien" } + pitchStandards.filter { $0.name == "A432" }
        case "Nordindischer Khyal":
            return pitchStandards.filter { $0.region == "Südasien" } + pitchStandards.filter { $0.name == "A432" }
        case "Persischer Dastgah":
            return pitchStandards.filter { $0.region == "Südasien" || $0.region == "Global" }
        case "Tuva Kehlkopfgesang":
            return pitchStandards.filter { $0.region == "Global" || $0.name == "A432" }
        default:
            return pitchStandards
        }
    }

    /// Quick keyword based search over styles
    func searchStyles(keyword: String) -> [MusicStyle] {
        guard !keyword.isEmpty else { return styles }
        let lowercased = keyword.lowercased()
        return styles.filter { style in
            style.name.lowercased().contains(lowercased) ||
            style.region.lowercased().contains(lowercased) ||
            style.description.lowercased().contains(lowercased)
        }
    }
}
