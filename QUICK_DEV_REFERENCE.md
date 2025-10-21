# 🚀 BLAB Quick Development Reference

**Für schnellen Zugriff während der Entwicklung**

---

## ⚡ Häufigste Commands

```bash
# Development Helper Tool
./blab-dev.sh status        # Projekt-Status
./blab-dev.sh build         # Projekt bauen
./blab-dev.sh test          # Tests laufen lassen
./blab-dev.sh commit        # Interaktiver Commit
./blab-dev.sh feature NAME  # Neuen Feature-Branch erstellen
./blab-dev.sh metrics       # Code-Metriken anzeigen

# Git Basics
git status
git add .
git commit                  # Nutzt .gitmessage Template
git push -u origin <branch>

# Testing
swift test                  # Alle Tests
swift test --filter Audio   # Nur Audio-Tests
swift build                 # Build ohne Run
```

---

## 📁 Wichtigste Files

| File | Zweck |
|------|-------|
| `CLAUDE_CODE_ULTIMATE_PROMPT.md` | **Haupt-Prompt** für Claude Code Development |
| `.github/CLAUDE_TODO.md` | Aktuelle TODO-Liste & Sprint-Planung |
| `BLAB_IMPLEMENTATION_ROADMAP.md` | Komplette Roadmap Phase 0-10 |
| `BLAB_Allwave_V∞_ClaudeEdition.txt` | Vision & System-Architektur |
| `QUICK_DEV_REFERENCE.md` | Diese Datei (Quick-Ref) |
| `blab-dev.sh` | Development Helper Script |

---

## 🎯 Aktuelle Prioritäten (Heute)

### 1️⃣ Bio-Mapping Presets
**Files zu erstellen:**
```
Sources/Blab/Biofeedback/BioMappingPresets.swift
Sources/Blab/Biofeedback/BioParameterMapping.swift
Sources/Blab/UI/PresetSelectionView.swift
Tests/BlabTests/BioMappingPresetsTests.swift
```

**Start:**
```bash
./blab-dev.sh feature bio-mapping-presets
# ... implementierung
./blab-dev.sh commit
```

### 2️⃣ Visual Modes Extensions
**Files zu erstellen:**
```
Sources/Blab/Visual/Modes/SacredGeometryMode.swift
Sources/Blab/Visual/Modes/BrainwaveVisualizerMode.swift
Sources/Blab/Visual/Modes/HeartCoherenceMandalaMode.swift
Sources/Blab/Visual/Shaders/BioReactiveCymatics.metal
```

---

## 🏗️ Code Templates

### Neues BlabNode erstellen

```swift
// Sources/Blab/Audio/Nodes/MyNode.swift
import AVFoundation

class MyNode: BlabNode {
    let id = UUID()
    let name = "My Audio Node"

    // Audio Parameters
    @Published var parameter1: Float = 0.5

    private var audioUnit: AVAudioUnit?

    func process(
        _ buffer: AVAudioPCMBuffer,
        time: AVAudioTime
    ) -> AVAudioPCMBuffer {
        // Process audio here
        return buffer
    }

    func react(to signal: BioSignal) {
        // React to biofeedback
        switch signal {
        case .hrv(let value):
            parameter1 = Float(value / 100.0)
        case .heartRate(let bpm):
            // ...
        default:
            break
        }
    }
}
```

### Neuer Visualization Mode

```swift
// Sources/Blab/Visual/Modes/MyMode.swift
import SwiftUI

class MyMode: VisualizationMode {
    let name = "My Visualization"

    func render(
        context: GraphicsContext,
        size: CGSize,
        audioData: FFTData,
        bioData: BioData,
        time: TimeInterval
    ) {
        // Audio → Visual
        let frequency = audioData.dominantFrequency

        // Bio → Color
        let hue = bioData.hrv.normalized

        // Render
        context.fill(
            Path(ellipseIn: CGRect(
                x: size.width / 2,
                y: size.height / 2,
                width: frequency,
                height: frequency
            )),
            with: .color(.init(hue: hue, saturation: 1, brightness: 1))
        )
    }
}
```

### Unit Test Template

```swift
// Tests/BlabTests/MyFeatureTests.swift
import XCTest
@testable import Blab

final class MyFeatureTests: XCTestCase {

    var sut: MyFeature!

    override func setUp() {
        super.setUp()
        sut = MyFeature()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testMyFeature() {
        // Given
        let input = "test"

        // When
        let result = sut.process(input)

        // Then
        XCTAssertEqual(result, "expected")
    }
}
```

---

## 🎨 Design System — Quick Colors

```swift
// In deinem Code verwenden:
BlabColors.primaryBackground  // #0A1628 Deep Ocean Blue
BlabColors.accentGolden       // #FFB700 Golden
BlabColors.accentGreen        // #00D9A3 Biofeedback Green
BlabColors.accentCyan         // #00E5FF Spatial Audio Cyan
BlabColors.warning            // #FF9800
BlabColors.error              // #FF5252
```

---

## 🧪 Testing Checklists

### Audio Feature Testing
- [ ] Buffer processing ohne Crashes
- [ ] Keine Audio Artifacts (Clicks, Pops)
- [ ] Latenz < 10ms
- [ ] CPU Usage < 20%
- [ ] Funktioniert auf iPhone 15 + 16

### Visual Feature Testing
- [ ] 60 FPS auf allen Devices
- [ ] Keine Memory Leaks
- [ ] Smooth Transitions
- [ ] Korrekte Bio-Mapping
- [ ] Metal Shader kompiliert

### Bio Feature Testing
- [ ] HealthKit Permission Handling
- [ ] HRV Werte plausibel (20-100)
- [ ] Coherence Berechnung korrekt
- [ ] Smooth Parameter Changes
- [ ] Funktioniert ohne HealthKit (Simulator)

---

## 🔄 Git Workflow — Cheat Sheet

```bash
# Feature starten
git checkout -b feature/my-feature

# Während der Arbeit
git status
git add .
git commit -m "feat: Beschreibung"

# Feature fertig
./blab-dev.sh test          # Tests laufen lassen
./blab-dev.sh build         # Build checken
git push -u origin feature/my-feature

# Wenn alles grün: Merge oder PR
git checkout main
git merge feature/my-feature
git push
```

---

## 🐛 Debugging Quick Tips

### Audio Debugging
```swift
// Latenz messen
let latency = AVAudioSession.sharedInstance().outputLatency
print("Audio Latency: \(latency * 1000)ms")

// Buffer Info
print("Buffer Duration: \(AVAudioSession.sharedInstance().ioBufferDuration)")
print("Sample Rate: \(AVAudioSession.sharedInstance().sampleRate)")
```

### Visual Debugging
```swift
// FPS Counter
let _ = print("FPS: \(1.0 / deltaTime)")

// Metal Debugging
// Xcode → Product → Scheme → Edit Scheme → Run → Options
// → Metal API Validation: Enabled
```

### Bio Debugging
```swift
// Mock Bio Data (für Simulator)
#if targetEnvironment(simulator)
let mockHRV = 65.0
let mockHeartRate = 70.0
#else
// Real HealthKit data
#endif
```

---

## 📊 Performance Targets

| Metric | Target | Check mit |
|--------|--------|-----------|
| Audio Latency | < 5ms | Instruments Time Profiler |
| Frame Rate | 60 FPS | Instruments Core Animation |
| Memory Usage | < 200 MB | Instruments Allocations |
| CPU Usage (Audio) | < 20% | Instruments Time Profiler |
| App Launch | < 2s | Stopwatch |
| Test Coverage | > 80% | `swift test --enable-code-coverage` |

---

## 🆘 Häufige Probleme & Lösungen

### Problem: Audio Engine startet nicht
**Lösung:**
```swift
// Audio Session richtig konfigurieren
try AVAudioSession.sharedInstance().setCategory(
    .playAndRecord,
    mode: .default,
    options: [.defaultToSpeaker, .allowBluetooth]
)
try AVAudioSession.sharedInstance().setActive(true)
```

### Problem: Visual ruckelt
**Lösung:**
1. Check Frame Rate: Metal Frame Debugger
2. Reduce Particle Count bei älteren Devices
3. Use `.drawingGroup()` in SwiftUI

### Problem: HealthKit gibt keine Daten
**Lösung:**
1. Check Permissions in Settings
2. Simulator: Nutze Mock Data
3. Async Requests: Use `await` korrekt

### Problem: Build Errors nach Git Pull
**Lösung:**
```bash
./blab-dev.sh clean
swift package update
swift build
```

---

## 🤖 Claude Code Prompts — Quick Copy

### Feature implementieren
```
Implementiere das Bio-Mapping Presets System gemäß
CLAUDE_CODE_ULTIMATE_PROMPT.md, Sektion "Bio-Mapping Presets".

Files:
- Sources/Blab/Biofeedback/BioMappingPresets.swift
- Sources/Blab/Biofeedback/BioParameterMapping.swift
- Sources/Blab/UI/PresetSelectionView.swift
- Tests/BlabTests/BioMappingPresetsTests.swift

Requirements:
- 10 Presets (Creative, Meditation, Focus, etc.)
- Kalman Filter für Smoothing
- SwiftUI UI mit Live-Preview
- Unit Tests mit > 80% Coverage
```

### Code Review Request
```
Bitte reviewe die Implementation in [File-Path].
Checke:
- Code Quality & Style
- Performance
- Memory Leaks
- Test Coverage
- Dokumentation

Optimierungsvorschläge erwünscht.
```

### Bug Fix Request
```
Bug in [File-Path], Zeile [N]:

**Symptom:** [Beschreibung]
**Expected:** [Erwartetes Verhalten]
**Actual:** [Aktuelles Verhalten]
**Stack Trace:** [falls vorhanden]

Bitte debuggen und fixen.
```

---

## 📞 Koordination mit ChatGPT Codex

**Wann an ChatGPT übergeben:**
- ✅ Nach Feature-Implementation → Performance Review
- ✅ Bei komplexen Bugs → Debugging
- ✅ Vor Release → Code Quality Check
- ✅ Bei Performance-Problemen → Profiling & Optimierung

**Handoff Format:**
```markdown
**Feature:** [Name]
**Branch:** feature/[name]
**Files Changed:**
- path/to/file1.swift
- path/to/file2.swift

**Request:**
- [ ] Performance Profiling
- [ ] Memory Leak Check
- [ ] Code Quality Review
- [ ] Optimization Suggestions

**Known Issues:**
- [Issue 1]
```

---

## 🌊 Entwicklungs-Philosophie (Quick Reminder)

**BLAB-Prinzipien:**
1. **Resonanz vor Funktion** — Code soll fließen
2. **Bio-Adaptive Intelligenz** — System passt sich an User an
3. **Ästhetik = Performance** — Schön UND schnell
4. **Transparenz** — User hat Kontrolle
5. **Modularität** — Alles ist erweiterbar

**Code Quality Standards:**
- Clean Code: Lesbar > Clever
- Type Safety: Nutze Swift's Type System
- Error Handling: Typed Errors, kein Force Unwrap
- Documentation: Jede public API dokumentiert
- Tests: > 80% Coverage

---

## ✅ Daily Checklist

**Morgens:**
- [ ] `git pull origin main`
- [ ] `./blab-dev.sh status`
- [ ] `.github/CLAUDE_TODO.md` checken

**Während der Arbeit:**
- [ ] Code schreiben
- [ ] Tests schreiben (parallel!)
- [ ] Dokumentation schreiben
- [ ] Regelmäßig committen

**Abends:**
- [ ] `./blab-dev.sh test`
- [ ] `./blab-dev.sh build`
- [ ] Final Commit & Push
- [ ] TODO.md updaten

---

**WICHTIGSTE REGEL:**

> Wenn du unsicher bist, schaue in `CLAUDE_CODE_ULTIMATE_PROMPT.md`
> Dort steht ALLES. 🌊

---

**Happy Coding!** ✨

*Generated with Claude Code for BLAB Development*
*Version: V∞.3 | 2025-10-21*
