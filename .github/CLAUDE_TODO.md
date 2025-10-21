# 🎯 BLAB DEVELOPMENT TODO — Claude Code Edition

**Last Updated:** 2025-10-21
**Current Phase:** 1-2 (Audio Enhancement + Visual Upgrade)
**Sprint:** Bio-Mapping Presets + Visual Modes

---

## 🔴 HIGH PRIORITY — Diese Woche

### ✅ COMPLETED
- [x] Projekt-Setup & Repository-Struktur
- [x] Audio Engine Grundstruktur (AVAudioEngine)
- [x] FFT + Pitch Detection
- [x] Binaural Beat Generator
- [x] Spatial Audio Engine
- [x] Node-basierte Architektur (BlabNode)
- [x] Recording System Basis
- [x] Multi-Track Recording
- [x] Visual Engine mit Metal
- [x] Multiple Visualization Modes
- [x] iOS 15+ Kompatibilität
- [x] CI/CD Pipeline (GitHub Actions)

### ⏳ IN PROGRESS

#### 1. Bio-Mapping Presets System (Phase 1.3)
**Deadline:** 2 Tage
**Assigned:** Claude Code
**Status:** 🟡 Ready to Start

- [ ] `Sources/Blab/Biofeedback/BioMappingPresets.swift` erstellen
  - [ ] 10 Presets definieren (Creative, Meditation, Focus, Healing, Energetic, etc.)
  - [ ] Enum mit `.mapping()` Methode
  - [ ] Parameter-Ranges für jedes Preset

- [ ] `Sources/Blab/Biofeedback/BioParameterMapping.swift` implementieren
  - [ ] Struct für Mapping-Konfiguration
  - [ ] `.apply(to bioData: BioData)` Methode
  - [ ] Kalman Filter für Signal-Smoothing

- [ ] `Sources/Blab/UI/PresetSelectionView.swift` UI
  - [ ] Picker für Preset-Auswahl
  - [ ] Live-Preview der Parameter
  - [ ] Visual Feedback bei Preset-Wechsel

- [ ] Tests
  - [ ] `Tests/BlabTests/BioMappingPresetsTests.swift`
  - [ ] Unit Tests für alle 10 Presets
  - [ ] Integration Test mit HealthKit Mock

- [ ] Integration
  - [ ] In ContentView einbinden
  - [ ] UserDefaults für Preset-Persistence

**ChatGPT Handoff:** Nach Implementation → Performance Review

---

#### 2. Visual Modes Extensions (Phase 2.2)
**Deadline:** 3 Tage
**Assigned:** Claude Code
**Status:** 🟡 Ready to Start

- [ ] `Sources/Blab/Visual/Modes/SacredGeometryMode.swift`
  - [ ] Golden Ratio Spirale
  - [ ] Fibonacci Patterns
  - [ ] Metatron's Cube Option
  - [ ] Audio Frequency → Rotation Speed
  - [ ] HRV → Color Shift

- [ ] `Sources/Blab/Visual/Modes/BrainwaveVisualizerMode.swift`
  - [ ] EEG-Style 8-Channel Darstellung
  - [ ] Jeder Kanal = ein Binaural State
  - [ ] Alpha/Beta/Theta/Delta Waves
  - [ ] Real-time FFT Integration

- [ ] `Sources/Blab/Visual/Modes/HeartCoherenceMandalaMode.swift`
  - [ ] Radiales Mandala-Pattern
  - [ ] Pulsiert mit Herzfrequenz
  - [ ] Coherence → Symmetrie-Grad
  - [ ] HRV → Farbverlauf

- [ ] Metal Shader Optimierung
  - [ ] `BioReactiveCymatics.metal` Shader
  - [ ] Uniforms für HRV, Coherence, Heart Rate
  - [ ] Performance: 60 FPS auf allen Devices

- [ ] UI Integration
  - [ ] Mode-Switcher erweitern
  - [ ] Settings für jede Mode
  - [ ] Smooth Transitions zwischen Modes

**ChatGPT Handoff:** Metal Shader Performance Profiling

---

## 🟡 MEDIUM PRIORITY — Nächste Woche

### 3. Audio Engine Ultra-Low-Latency (Phase 1.1)
**Status:** 🔵 Planned

- [ ] Real-Time Scheduling Implementation
  - [ ] DispatchQueue `.userInteractive` für Audio Thread
  - [ ] Audio Thread Priority auf `.realtime` setzen
  - [ ] Buffer Size Auto-Tuning

- [ ] Latency Measurement System
  - [ ] Round-trip Latency messen
  - [ ] Dashboard für Monitoring
  - [ ] Target: < 5ms

- [ ] AudioConfiguration Optimierung
  - [ ] Device-spezifische Configs
  - [ ] iPhone 16 Pro Max: 128 Frames
  - [ ] Ältere Devices: 256-512 Frames

**ChatGPT Handoff:** Performance Profiling + Optimierung

---

### 4. Advanced Export Formats (Phase 4.3)
**Status:** 🔵 Planned

- [ ] AAC Export
  - [ ] AVAssetWriter mit AAC Codec
  - [ ] 256 kbps Quality

- [ ] ALAC Export (Apple Lossless)
  - [ ] Lossless Compression
  - [ ] M4A Container

- [ ] Video Export (MP4 + Visualization)
  - [ ] `VideoExportManager.swift`
  - [ ] Frame-by-Frame Rendering
  - [ ] Audio + Video Kombination
  - [ ] Progress-Tracking UI

- [ ] Dolby Atmos ADM BWF (Advanced)
  - [ ] Multi-Channel WAV Writer
  - [ ] ADM XML Metadata Generator
  - [ ] BWF Chunk Embedding

**ChatGPT Handoff:** Export Performance Optimization

---

## 🔵 LOW PRIORITY — Later

### 5. AI Composition Layer (Phase 5)
**Status:** 🟣 Research Phase

- [ ] CoreML Model Training Pipeline
  - [ ] Dataset Collection (MIDI Files)
  - [ ] Feature Extraction
  - [ ] Model Training (Create ML)

- [ ] BlabComposer.swift
  - [ ] Genre-aware Generation
  - [ ] Mood Detection
  - [ ] Pattern Suggestion

- [ ] Integration
  - [ ] UI for AI Features
  - [ ] Real-time Suggestion Display

---

### 6. Node Graph Visualization (Phase 1.2)
**Status:** 🟣 Design Phase

- [ ] NodeGraphView.swift (Interactive UI)
  - [ ] Drag & Drop Nodes
  - [ ] Visual Connections
  - [ ] Live Parameter Editing

- [ ] NodeManifest System
  - [ ] JSON-based Node Descriptions
  - [ ] Dynamic Node Loading
  - [ ] Custom Node Support

---

## 🛠️ TECHNICAL DEBT

### Code Quality
- [ ] SwiftLint Setup & Enforcement
- [ ] Dokumentation: > 90% Coverage
- [ ] Unit Test Coverage: > 80%
- [ ] Integration Tests für Audio Pipeline
- [ ] UI Tests für kritische Flows

### Refactoring
- [ ] Dependency Injection Container
- [ ] Proper Error Handling überall
- [ ] Remove Force Unwraps
- [ ] Migrate zu Async/Await wo möglich

### Performance
- [ ] Audio Thread CPU < 20%
- [ ] Main Thread nie blockiert
- [ ] Memory Footprint < 200 MB
- [ ] Battery Usage < 5% pro Stunde

---

## 📊 METRICS & GOALS

### Technical KPIs
- Audio Latency: ⏳ TBD → 🎯 < 5ms
- Frame Rate: ✅ 60 FPS → 🎯 120 FPS (ProMotion)
- Crash-Free Rate: ⏳ TBD → 🎯 > 99.9%
- App Launch Time: ⏳ TBD → 🎯 < 2 seconds
- Memory Usage: ⏳ ~150 MB → 🎯 < 200 MB
- Test Coverage: ⏳ ~40% → 🎯 > 80%

### Feature Completion
- Phase 0: ✅ 100%
- Phase 1: ⏳ 60%
- Phase 2: ⏳ 70%
- Phase 3: ✅ 100% (Basic Spatial)
- Phase 4: ⏳ 80%
- Phase 5: 🔵 0%

---

## 🔄 HANDOFF TRACKING

### Claude Code → ChatGPT Codex

**Pending Handoffs:**
- [ ] Bio-Mapping Presets (nach Implementation)
- [ ] Visual Modes Extensions (nach Metal Shader)
- [ ] Audio Engine Latency (Performance Test)

**Completed Handoffs:**
- [x] Initial Project Structure Review
- [x] iOS 15 Compatibility Audit

---

## 📅 SPRINT PLANNING

### Sprint 1 (2025-10-21 → 2025-10-25)
**Focus:** Bio-Mapping + Visual Modes

**Goals:**
- ✅ Bio-Mapping Presets komplett
- ✅ 3 neue Visual Modes
- ✅ Tests geschrieben
- ✅ Performance Review durch ChatGPT

### Sprint 2 (2025-10-26 → 2025-11-01)
**Focus:** Audio Latency + Export

**Goals:**
- ✅ Audio Latency < 5ms
- ✅ Video Export funktional
- ✅ AAC/ALAC Support
- ✅ Latency Dashboard

### Sprint 3 (2025-11-02 → 2025-11-08)
**Focus:** Node Graph + AI Foundation

**Goals:**
- ✅ NodeGraphView UI
- ✅ AI Composer Basis
- ✅ Pattern Suggestion Engine
- ✅ Genre/Mood System

---

## 🎯 DEFINITION OF DONE

**Feature ist DONE wenn:**
- [x] Code geschrieben & funktional
- [x] Unit Tests geschrieben (> 80% Coverage)
- [x] Dokumentation vollständig (DocC Comments)
- [x] Performance Review durch ChatGPT Codex
- [x] Keine Compiler Warnings
- [x] SwiftLint passes (wenn aktiviert)
- [x] Integration in Main App funktioniert
- [x] Git Commit mit klarer Message
- [x] Push zu Feature Branch

---

## 🤖 AUTOMATION COMMANDS

```bash
# Check TODO Status
grep -r "TODO\|FIXME\|HACK" Sources/

# Run Tests
swift test

# Check Build
swift build

# Line Count
find Sources/ -name "*.swift" | xargs wc -l

# Git Status
git status
git log --oneline -10
```

---

**NEXT ACTION:** Implementiere Bio-Mapping Presets
**BLOCKED BY:** Keine
**DEPENDENCIES:** HealthKitManager (✅ vorhanden)

🌊 *Let's ship this!* ✨
