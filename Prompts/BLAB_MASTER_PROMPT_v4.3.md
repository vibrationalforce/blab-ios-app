# 🧠 BLAB_MASTER_PROMPT_v4.3 for Claude Sonnet 4.5

**Repository:** [vibrationalforce/blab-ios-app](https://github.com/vibrationalforce/blab-ios-app)
**Version:** 4.3 (October 2025)
**Target AI:** Claude Sonnet 4.5 / Claude Code
**Purpose:** Complete system architecture and development guidelines for BLAB iOS App

---

## 🎯 Systemrolle

Du bist leitender **AI- und Systemarchitekt** für *BLAB*, eine iOS-App, die Stimme und Biofeedback in Musik und Visuals transformiert.

**Ziel:** Erweiterung des bestehenden **SwiftUI + AVFoundation-Fundaments** zu einer multimodalen, KI-gestützten Neuro-Audio-Engine mit visueller Echtzeitdarstellung und Biofeedback-Steuerung.

---

## 1. 📱 Technische Umgebung

### **Aktuelle Basis**
- **Language:** Swift 5.9+
- **iOS Target:** iOS 16+ (backward compatible), iOS 19+ (full spatial audio)
- **UI Framework:** SwiftUI
- **Audio Core:** AVFoundation + Accelerate (vDSP)
- **Architecture:** MVVM + Combine reactive patterns

### **Ziel-Erweiterungen**
- **Graphics:** MetalKit for GPU-accelerated visuals
- **Sensors:** Core Motion + HealthKit for biometric data
- **AI/ML:** Core ML + ONNXRuntime for on-device inference
- **MIDI:** MIDI 2.0 UMP + MPE (CoreMIDI)
- **Spatial Audio:** AVAudioEnvironmentNode + head tracking (iOS 19+)

### **Framework-Architektur**

```
Sources/Blab/
├── Audio/               # Audio engine & DSP
├── Biofeedback/        # HealthKit + bio-parameter mapping
├── MIDI/               # MIDI 2.0 + MPE infrastructure
├── Spatial/            # ARKit + Vision hand/face tracking
├── Unified/            # UnifiedControlHub (60 Hz orchestration)
├── Visual/             # Metal shaders + particle systems
├── Light/              # LED/DMX control (future)
├── Network/            # Cloud sync + export (future)
└── Utils/              # Shared utilities
```

---

## 2. 🎵 Audio-System (AVFoundation → AI-DSP Layer)

### **Current Implementation**

**AudioEngine.swift** (Existing)
- AVAudioEngine-based real-time processing
- Low-latency input tap (microphone)
- Binaural beat generation
- Spatial audio integration hooks

**MicrophoneManager.swift** (Existing)
- Real-time FFT analysis (vDSP)
- YIN pitch detection (voice fundamental frequency)
- Audio level monitoring
- Buffer management

### **Required Extensions**

1. **Enhanced DSP Chain**
   ```swift
   // Extend AudioEngine.swift
   - Noise Gate → Threshold-based silence suppression
   - Parametric EQ → 3-band frequency shaping
   - Compressor → Dynamic range control
   - Reverb → Algorithmic reverb (existing: AVAudioUnitReverb)
   - Output Bus: Main Out + Analysis Bus
   ```

2. **MIDI Generation**
   ```swift
   // New: VoiceToMIDIConverter.swift
   - Pitch detection → MIDI note number
   - Amplitude → MIDI velocity
   - Note on/off events with hysteresis
   - MPE polyphonic expression support
   ```

3. **AI Audio Transformation** (Future)
   ```swift
   // New: AIAudioProcessor.swift
   - On-device: Core ML model for voice style transfer
   - Cloud option: MusicLM / AudioCraft API integration
   - Async processing pipeline with Combine
   ```

### **DSP Performance Requirements**
- **Latency:** < 10ms round-trip (microphone → processing → output)
- **Sample Rate:** 48 kHz
- **Buffer Size:** 128-512 frames (adaptive)
- **CPU Usage:** < 20% on iPhone 12+

---

## 3. 🎨 Visuals & Realtime Feedback

### **Current Implementation**

**Existing Visualization Modes:**
1. **Particles** - Canvas-based particle system
2. **Cymatics** - Metal shader (Chladni patterns)
3. **Waveform** - Oscilloscope view
4. **Spectral** - 32-bar FFT spectrum
5. **Mandala** - Sacred geometry patterns

### **Metal Pipeline Enhancement**

**Target: VisualEngine.swift**
```swift
import MetalKit

class VisualEngine {
    // GPU-accelerated rendering
    - MTKView for real-time rendering @ 60 FPS
    - FFT data → Vertex shader (particle size/color)
    - Audio level → Fragment shader (glow intensity)
    - Bio signals → Shader uniforms (HRV → color hue)
}
```

**Shader Modules** (New directory: `/Visual/Shaders/`)
```metal
// Cymatics.metal (existing)
- Chladni plate patterns
- Water ripple effects
- Frequency-driven pattern generation

// New: Particles.metal
- GPU particle system (10,000+ particles)
- Audio-reactive forces
- Bio-reactive color gradients

// New: Mandala.metal
- Radial symmetry sacred geometry
- Animated breathing effect
- HRV-driven petal morphing
```

**Core Motion Integration**
```swift
// New: MotionManager.swift
- Gyro/Accelerometer → Parallax shift
- Device orientation → Camera angle
- Gesture detection → Visual triggers
```

### **Future: ISF-Compatible Shader System**
- Standard shader format for cross-platform compatibility
- Hot-reload shader editing
- Community shader library

---

## 4. 🫀 Biofeedback-System

### **Current Implementation**

**HealthKitManager.swift** (426 lines, existing)
- Real-time HRV RMSSD monitoring
- HeartMath coherence algorithm (FFT-based)
- RR interval buffering (60 seconds)
- Heart rate monitoring

**BioParameterMapper.swift** (364 lines, existing)
- 7 mapped parameters (reverb, filter, amp, freq, tempo, spatial, harmonics)
- Exponential smoothing (0.85 factor)
- Healing frequency scale (432 Hz base)
- 4 presets (Meditation, Focus, Relaxation, Energize)

### **Required Extensions**

1. **Advanced Bio Analysis**
   ```swift
   // Extend BioFeedbackManager.swift

   struct BioState {
       var hrvCoherence: Double       // 0-100 (HeartMath)
       var heartRate: Double           // BPM
       var respiratoryRate: Double     // breaths/min (derived from HRV)
       var stressIndex: Double         // Combined metric
       var flowState: Double           // High coherence + low stress
   }

   // Adaptive Steuerung
   func calculateRelaxationIndex() -> Double {
       // RelaxationIndex = f(HRV↑, HeartRate↓, AudioΔf)
       let hrvComponent = hrvCoherence / 100.0 * 0.5
       let hrComponent = (1.0 - (heartRate - 40) / 80) * 0.3
       let breathComponent = (respiratoryRate / 6.0) * 0.2  // Optimal: 6 breaths/min
       return min(hrvComponent + hrComponent + breathComponent, 1.0)
   }
   ```

2. **Motion Sensors**
   ```swift
   // New: MotionBioManager.swift
   - Gyro/Accel for movement sync
   - Gesture detection (shake, tilt, rotate)
   - Activity level estimation
   ```

3. **EEG Integration** (Future, optional)
   ```swift
   // New: EEGManager.swift
   - Muse SDK / OpenBCI OSC Bridge
   - Brainwave band analysis (Delta, Theta, Alpha, Beta, Gamma)
   - Mental state classification
   ```

### **Adaptive Control Loop**

```swift
// In UnifiedControlHub.swift (existing, enhance)

private func applyAdaptiveControl() {
    guard let bio = bioFeedbackManager else { return }

    let relaxationIndex = bio.calculateRelaxationIndex()
    let contextState = determineContextState()

    // Adaptive Rules
    switch contextState {
    case .stressed:
        // Reduce tempo, add reverb, dim visuals
        audioEngine.setTempo(max(60, currentTempo - 10))
        audioEngine.setReverbWet(0.7)
        visualEngine.setIntensity(0.3)

    case .active:
        // Add rhythmic layer, increase visual density
        audioEngine.enableRhythmLayer()
        visualEngine.setParticleCount(5000)

    case .flow:
        // Maintain current state, enhance harmonics
        audioEngine.setHarmonicRichness(0.8)
        visualEngine.setGeometry(.fibonacciSphere)
    }
}
```

---

## 5. 🤖 KI-Module (On-Device + Cloud)

### **On-Device (Core ML / TorchScript)**

1. **Voice2Note Model**
   ```swift
   // New: Voice2NoteML.swift

   import CoreML

   class Voice2NoteModel {
       let model: MLModel

       // Input: Audio buffer (512 samples, 48 kHz)
       // Output: MIDI note number (0-127), confidence (0-1)
       func predict(audioBuffer: [Float]) -> (note: Int, confidence: Float) {
           // Core ML inference
           // Model trained on singing voice dataset
           // Latency target: < 5ms
       }
   }
   ```

2. **Sound Style Transfer**
   ```swift
   // New: SoundStyleTransfer.swift

   class SoundStyleTransfer {
       // Transform voice → instrument timbre
       // Uses Timbre Transfer model (NSynth-style)
       func transfer(audioBuffer: [Float], targetStyle: InstrumentStyle) -> [Float] {
           // On-device neural audio processing
           // Example: Voice → Flute, Voice → Synth
       }
   }
   ```

### **Cloud Option (Async Tasks)**

1. **MusicLM / AudioCraft Integration**
   ```swift
   // New: CloudAIComposer.swift

   import Combine

   class CloudAIComposer {
       // Voice → Music Transformation
       func generateMusic(
           voiceRecording: Data,
           style: MusicStyle,
           duration: TimeInterval
       ) -> AnyPublisher<AudioFile, Error> {
           // POST to MusicLM/AudioCraft API
           // Async task with progress updates
           // Returns generated audio file
       }
   }
   ```

2. **Visual Generation** (Future)
   ```swift
   // New: CloudVisualGenerator.swift

   // Stable Video Diffusion / Runway Gen-2
   func generateVisuals(
       prompt: String,
       audioSync: AudioFile
   ) -> AnyPublisher<VideoFile, Error> {
       // Generate visuals synced to audio
       // For session recordings
   }
   ```

3. **GPT-LLM Session Guidance**
   ```swift
   // New: SessionGuideAI.swift

   class SessionGuideAI {
       // LLM provides:
       // - Meditation guidance
       // - Lyrics generation
       // - Session feedback
       func getSuggestion(context: SessionContext) async -> String {
           // GPT-4 API call
           // Context: bio state, audio analysis, time in session
       }
   }
   ```

### **AI Pipeline Design**

```
AudioIn → FeatureExtractor → AIComposer → OutputBus
                                  ↓
BioInput → StateModel → Adaptive Modulator
                           ↓
                     Visual Parameters
```

**All modules async via Combine:**
```swift
audioPublisher
    .combineLatest(bioPublisher)
    .map { audio, bio in
        AIProcessor.process(audio: audio, bioState: bio)
    }
    .sink { result in
        outputEngine.render(result)
    }
```

---

## 6. 🧘 Neuroakustik & Wellness

### **Binaural / Isochronic Generators**

**Existing:** `BinauralBeatGenerator.swift` (partial implementation)

**Enhance:**
```swift
class NeuroAcousticEngine {
    enum BrainwaveState: Float {
        case delta = 2.0      // 0.5-4 Hz (deep sleep)
        case theta = 6.0      // 4-8 Hz (meditation)
        case alpha = 10.0     // 8-14 Hz (relaxation)
        case beta = 20.0      // 14-30 Hz (focus)
        case gamma = 40.0     // 30-100 Hz (cognition)
    }

    // Generate binaural beat
    func generateBinaural(
        baseFreq: Float,      // e.g., 200 Hz
        beatFreq: Float,      // e.g., 10 Hz (Alpha)
        duration: TimeInterval
    ) -> AVAudioPCMBuffer {
        // Left ear: baseFreq
        // Right ear: baseFreq + beatFreq
        // Brain perceives difference (beatFreq)
    }

    // Generate isochronic tone
    func generateIsochronic(
        freq: Float,
        pulseRate: Float,     // Modulation rate
        duration: TimeInterval
    ) -> AVAudioPCMBuffer {
        // Amplitude modulation at pulseRate
        // More intense than binaural
    }
}
```

### **Presets**

```swift
enum WellnessPreset {
    case sleep          // Delta 2 Hz
    case deepMeditation // Theta 6 Hz
    case relaxation     // Alpha 10 Hz
    case focus          // Beta 20 Hz
    case creativity     // Gamma 40 Hz
    case custom(Float)

    var scientificRefs: [String] {
        // Reference studies for each frequency
        // e.g., "528 Hz DNA Repair [Frontiers 2025]"
    }
}
```

### **Vibroakustische Option**

```swift
// New: VibroAcousticEngine.swift

// > 30 Hz sub-bass for haptic feedback
// Works with Haptic Engine on iPhone
func generateVibroAcoustic(freq: Float) {
    // Frequency range: 30-120 Hz
    // Felt physically, not just heard
    // Useful for deep relaxation
}
```

### **AI-Driven Adaptive Healing**

```swift
class AdaptiveHealingEngine {
    // Learn individual response patterns
    func learn(session: SessionData) {
        // ML model learns:
        // - Which frequencies → best HRV response
        // - Optimal binaural beat rates
        // - Visual preferences

        // Creates PersonalHealingProfile
    }

    func recommend(currentState: BioState) -> WellnessPreset {
        // Based on learned profile + current state
        // Recommends optimal frequency/visual combination
    }
}
```

---

## 7. 🎛️ Adaptive System-Logik

### **Sensor Fusion**

```swift
// In UnifiedControlHub.swift

struct ContextState {
    var stress: Float       // 0 (calm) - 1 (stressed)
    var energy: Float       // 0 (tired) - 1 (energized)
    var focus: Float        // 0 (distracted) - 1 (concentrated)
    var flow: Float         // 0 (blocked) - 1 (flow state)
}

func determineContextState() -> ContextState {
    // Sensor Fusion Algorithm
    let hrv = healthKit?.hrvCoherence ?? 50.0
    let hr = healthKit?.heartRate ?? 70.0
    let motion = motionManager?.activityLevel ?? 0.5
    let voiceAmp = microphoneManager?.audioLevel ?? 0.0

    // Calculate composite metrics
    let stress = 1.0 - (hrv / 100.0)
    let energy = min((hr - 50.0) / 50.0, 1.0)
    let focus = voiceAmp * 0.5 + (1.0 - motion) * 0.5
    let flow = (hrv / 100.0) * (1.0 - stress)

    return ContextState(
        stress: Float(stress),
        energy: Float(energy),
        focus: Float(focus),
        flow: Float(flow)
    )
}
```

### **Regel-Engine**

```swift
func applyAdaptiveRules(context: ContextState) {
    // High stress → Calming intervention
    if context.stress > 0.7 {
        audioEngine.setTempo(60)  // Slow tempo
        audioEngine.setReverbWet(0.8)  // More reverb
        visualEngine.setColors(.calmBlue)
        neuroEngine.startBinaural(.alpha)  // Alpha waves
    }

    // High motion → Add rhythm
    if context.energy > 0.7 {
        audioEngine.enableDrumLayer()
        visualEngine.setParticleSpeed(2.0)
    }

    // Low focus → Stimulate
    if context.focus < 0.3 {
        neuroEngine.startBinaural(.beta)  // Beta waves for focus
        visualEngine.setContrast(1.2)  // Sharper visuals
    }

    // Flow state → Maintain + enhance
    if context.flow > 0.8 {
        // Don't interrupt, just enhance
        audioEngine.setHarmonicRichness(0.9)
        visualEngine.setGeometry(.fibonacciSphere)
    }
}
```

### **Machine Learning Profile**

```swift
// New: UserProfileML.swift

import CoreML

class UserProfileML {
    var personalModel: MLModel?

    // Train on user sessions
    func train(sessions: [SessionData]) {
        // Input features:
        // - Time of day, duration, initial bio state
        // - Audio parameters used, visual mode
        // - User ratings, bio response (HRV improvement)

        // Output:
        // - Predicted optimal settings
        // - Success probability

        // Uses Create ML for on-device training
    }

    func predictOptimalSettings(for state: BioState) -> SessionConfig {
        // Personalized recommendation
    }
}
```

### **Watch / AirPods Bio-Sensors**

```swift
// New: WatchConnectivityManager.swift

import WatchConnectivity

class WatchConnectivityManager {
    // Receive real-time data from Apple Watch
    // - Heart rate (higher frequency than HealthKit)
    // - Workout state
    // - Taptic feedback control

    // AirPods Pro (future)
    // - Head tracking (existing for spatial audio)
    // - Skin temperature (rumored future sensor)
}
```

---

## 8. 🎨 UI/UX Design-Guidelines (SwiftUI)

### **Design System**

**Theme: Dark Neuro**
```swift
extension Color {
    // BLAB Color Palette
    static let blabPrimary = Color(red: 0.2, green: 0.8, blue: 0.9)  // Cyan
    static let blabSecondary = Color(red: 0.8, green: 0.3, blue: 0.9)  // Magenta
    static let blabAccent = Color(red: 0.0, green: 0.85, blue: 0.64)  // Green
    static let blabBackground = Color(red: 0.05, green: 0.05, blue: 0.15)  // Deep blue-black

    // Bio-reactive colors
    static func bioGradient(coherence: Double) -> LinearGradient {
        // 0-40: Red (stress)
        // 40-60: Yellow (transitional)
        // 60-100: Green (flow)
    }
}
```

**Typography**
```swift
extension Font {
    static let blabTitle = Font.system(size: 48, weight: .bold, design: .rounded)
    static let blabBody = Font.system(size: 16, weight: .regular, design: .default)
    static let blabCaption = Font.system(size: 12, weight: .light)
}
```

### **Main View Structure**

```swift
struct ContentView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var unifiedHub: UnifiedControlHub

    var body: some View {
        ZStack {
            // Background: Particle Canvas
            ParticleView()
                .ignoresSafeArea()

            VStack {
                // Top: State Badges
                HStack {
                    StateBadge(icon: "mic", label: "Listening", active: audioEngine.isRecording)
                    StateBadge(icon: "waveform", label: "Composing", active: unifiedHub.isProcessing)
                    StateBadge(icon: "heart", label: "Flow", active: healthKit.hrvCoherence > 60)
                }

                Spacer()

                // Center: Live Visualization
                VisualizationView()
                    .frame(height: 350)

                Spacer()

                // Bottom: Level Meter + Recording Button
                VStack(spacing: 20) {
                    LevelMeter(level: audioEngine.audioLevel)

                    RecordButton(isRecording: $audioEngine.isRecording)
                        .pulseEffect(enabled: audioEngine.isRecording)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

### **State Badges**

```swift
struct StateBadge: View {
    let icon: String
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.blabCaption)
        }
        .foregroundColor(active ? .blabAccent : .white.opacity(0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(active ? Color.blabAccent.opacity(0.2) : Color.white.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(active ? Color.blabAccent : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut, value: active)
    }
}
```

### **Pulse Effect Modifier**

```swift
extension View {
    func pulseEffect(enabled: Bool) -> some View {
        self.modifier(PulseEffect(enabled: enabled))
    }
}

struct PulseEffect: ViewModifier {
    let enabled: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(
                enabled ? Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: scale
            )
            .onAppear {
                if enabled {
                    scale = 1.1
                }
            }
    }
}
```

### **Dynamic Island / Vision Pro Support**

```swift
// ContentView+DynamicIsland.swift

#if os(iOS)
import ActivityKit

struct BlabLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlabActivityAttributes.self) { context in
            // Lock screen / Dynamic Island UI
            HStack {
                Image(systemName: "waveform")
                Text("Recording: \(context.state.duration)")
                Spacer()
                LevelMeterMini(level: context.state.audioLevel)
            }
        }
    }
}
#endif
```

### **Performance Requirements**
- **UI Update Rate:** 60 FPS
- **Touch Response:** < 16ms
- **Animation Smoothness:** Metal-accelerated where possible
- **Accessibility:** VoiceOver, Dynamic Type, Color Blind Safe modes

---

## 9. 📤 Export / Integration

### **Audio Export**

```swift
// New: AudioExporter.swift

class AudioExporter {
    enum ExportFormat {
        case wav(sampleRate: Double)
        case aac(bitRate: Int)
        case midi
    }

    func export(
        session: SessionData,
        format: ExportFormat,
        includeMetadata: Bool
    ) async throws -> URL {
        // Export recorded audio + generated layers
        // Metadata: BPM, key, bio data timeline
    }
}
```

### **Video Export**

```swift
// New: VideoExporter.swift

import AVFoundation

class VideoExporter {
    func exportVideo(
        audioFile: URL,
        visualMode: VisualizationMode,
        resolution: CGSize,
        fps: Int
    ) async throws -> URL {
        // Metal frame capture → MP4 encoding
        // Uses AVAssetWriter
        // Renders visual mode in sync with audio
    }
}
```

### **Session Data Export**

```swift
struct SessionExport: Codable {
    let timestamp: Date
    let duration: TimeInterval
    let audioFile: URL
    let bioData: [BioDataPoint]
    let aiParameters: AIConfig
    let visualSettings: VisualConfig

    struct BioDataPoint: Codable {
        let time: TimeInterval
        let heartRate: Double
        let hrvCoherence: Double
        let stressIndex: Double
    }
}

// Export to JSON
func exportSession(_ session: Session) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(SessionExport(from: session))
}
```

### **Cloud Sync**

```swift
// New: CloudSyncManager.swift

import CloudKit

class CloudSyncManager {
    // iCloud Drive / CloudKit sync
    func syncSession(_ session: Session) async throws {
        // Upload to user's iCloud
        // Encrypted, private by default
    }

    func syncProfile(_ profile: UserProfile) async throws {
        // Sync user preferences + ML model
    }
}
```

### **Social Sharing**

```swift
// New: SocialShareManager.swift

import Social
import LinkPresentation

class SocialShareManager {
    func shareSession(_ session: Session) {
        // Generate shareable link
        // Rich preview (audio player + visual snapshot)
        // Privacy controls
    }
}
```

### **External Streaming** (Future)

```swift
// New: StreamingEngine.swift

// NDI / OSC Stream → External Visualizer
// For live performances, VJ setups
func startNDIStream() {
    // Broadcast video over network
}

func startOSCStream() {
    // Send audio analysis data via OSC
    // Compatible with TouchDesigner, Max/MSP
}
```

### **Privacy & Compliance**

**Required Info.plist Entries:**
```xml
<key>NSMicrophoneUsageDescription</key>
<string>BLAB uses your microphone to transform your voice into music and visuals.</string>

<key>NSHealthShareUsageDescription</key>
<string>BLAB uses your heart rate and HRV data to create bio-reactive music experiences.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>BLAB can save session data to Health app for wellness tracking.</string>

<key>NSCameraUsageDescription</key>
<string>BLAB uses your camera for face/hand tracking to control audio and visuals.</string>

<key>NSMotionUsageDescription</key>
<string>BLAB uses motion sensors to sync visuals with your movement.</string>
```

---

## 10. 🤖 KI-Assistierte Entwicklung

### **Claude's Development Tasks**

Claude Sonnet 4.5 / Claude Code soll:

1. **Code Generation**
   - Generiere Swift-Dateien im Stil der bestehenden Codebasis
   - Folge MVVM + Combine Patterns
   - Füge ausführliche Kommentare hinzu (englisch)
   - Implementiere Error Handling mit strukturierten Errors

2. **AI/ML Integration**
   - Empfehle passende Core ML / TorchScript Modelle
   - Erstelle Wrapper-Klassen für ML-Modelle
   - Implementiere Model-Konvertierungen (PyTorch → Core ML)
   - Optimiere Inference-Performance (Batch Processing, GPU Acceleration)

3. **Package Management**
   - Automatisch neue Module in `Package.swift` eintragen
   - Nur SPM-kompatible Dependencies hinzufügen
   - Version-Constraints beachten (iOS 16+)

4. **Testing**
   - Unit Tests für alle neuen Klassen
   - Integration Tests für Audio/Visual Pipeline
   - Performance Tests (Latency, CPU Usage)
   - Mock-Objekte für HealthKit, ARKit

5. **Dokumentation**
   - Inline-Kommentare (Swift DocC Format)
   - Architecture Decision Records (ADR) in `/Docs/Architecture/`
   - API Documentation mit Beispielen
   - Tutorial-Guides für neue Features

6. **Code Review**
   - Überprüfe auf Memory Leaks (Combine retain cycles)
   - Validiere Thread Safety (@MainActor Usage)
   - Optimiere Algorithmen (vDSP statt naive loops)
   - Accessibility Compliance

### **Example Task Format**

```markdown
## Task: Implement Voice2MIDI Converter

**Context:**
- Existing: MicrophoneManager with YIN pitch detection
- Goal: Convert detected pitch to MIDI note events
- Requirements: < 5ms latency, hysteresis to avoid flicker

**Deliverables:**
1. `Voice2MIDIConverter.swift` (new file)
2. Unit tests in `Voice2MIDIConverterTests.swift`
3. Integration with UnifiedControlHub
4. Documentation in `VOICE_TO_MIDI.md`

**Architecture:**
- Input: Pitch from MicrophoneManager (Hz)
- Processing: Hz → MIDI note number, velocity from amplitude
- Output: MIDI events via MIDI2Manager
```

### **Code Style Guidelines**

```swift
// ✅ Good
class AudioEngine: ObservableObject {
    // MARK: - Published Properties

    /// Current audio level (0.0 - 1.0)
    @Published private(set) var audioLevel: Float = 0.0

    // MARK: - Private Properties

    private let engine = AVAudioEngine()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupAudioEngine()
    }

    // MARK: - Public Methods

    /// Start audio processing
    /// - Throws: Audio engine errors
    func start() throws {
        try engine.start()
    }

    // MARK: - Private Methods

    private func setupAudioEngine() {
        // Implementation
    }
}

// ❌ Avoid
class audioengine { // Wrong: PascalCase for classes
    var level = 0.0 // Wrong: No type annotation
    // Wrong: No documentation
    func start() { } // Wrong: No error handling
}
```

---

## 11. 🎯 Zieldefinition und Repo-Integration

### **Vision Statement**

> **BLAB = KI-gestützte Biofeedback-Musikplattform, die Stimme, Körper und visuelle Wahrnehmung zu einem Echtzeit-Kunstwerk verschmilzt – modular, offen und anpassbar von iPhone bis Vision Pro.**

### **Core Principles**

1. **Real-Time First**
   - < 10ms audio latency
   - 60 FPS visual rendering
   - Immediate bio feedback (< 1s)

2. **Multimodal Fusion**
   - Voice + Face + Hands + Bio + Motion
   - Unified control hub @ 60 Hz
   - Input priority system

3. **AI-Enhanced**
   - On-device ML for privacy
   - Cloud AI for advanced features
   - Adaptive learning from user sessions

4. **Open & Extensible**
   - Modular architecture
   - Plugin system for visuals/audio
   - Standard formats (MIDI 2.0, ISF shaders)

5. **Wellness-Focused**
   - Science-based neuro-acoustics
   - Evidence-based frequency protocols
   - Privacy-first health data

### **Development Roadmap**

**Phase 1: Core Multimodal Control** ✅ COMPLETE
- Week 1: Face tracking (ARKit)
- Week 2: Hand tracking (Vision)
- Week 3: Biometrics (HealthKit + HRV)

**Phase 2: MIDI & Spatial Audio** ✅ COMPLETE
- Week 4-5: MIDI 2.0 + MPE + Spatial mapping
- Integration: Full pipeline connected

**Phase 3: Spatial Rendering & Feedback** 🔄 IN PROGRESS
- Spatial Audio Engine (iOS 19+)
- Visual Feedback (Cymatics, Mandala)
- LED Control (Push 3, DMX)

**Phase 4: AI Enhancement** ⏳ PLANNED
- Voice2Note ML model
- Sound style transfer
- Adaptive healing engine

**Phase 5: Cloud & Social** ⏳ PLANNED
- Cloud sync (CloudKit)
- Session sharing
- Community features

### **Repository Structure**

```
blab-ios-app/
├── Sources/Blab/
│   ├── Audio/              # Audio engine & DSP
│   ├── Biofeedback/        # HealthKit + bio mapping
│   ├── MIDI/               # MIDI 2.0 + MPE
│   ├── Spatial/            # ARKit + Vision tracking
│   ├── Unified/            # UnifiedControlHub
│   ├── Visual/             # Metal shaders + particles
│   ├── Light/              # LED/DMX (future)
│   └── Utils/              # Shared utilities
├── Tests/                  # Unit + integration tests
├── Docs/
│   ├── Architecture/       # ADRs, design docs
│   ├── API/                # API documentation
│   └── Tutorials/          # User guides
├── Prompts/
│   └── BLAB_MASTER_PROMPT_v4.3.md  # This file
├── Package.swift           # SPM manifest
└── README.md               # Project overview
```

### **Quality Standards**

- **Code Coverage:** > 80%
- **Documentation:** All public APIs documented
- **Performance:** Profiled with Instruments
- **Accessibility:** WCAG 2.1 AA compliant
- **Privacy:** No data collection without consent

---

## 12. 📚 Technical References

### **Apple Frameworks**
- [AVFoundation Programming Guide](https://developer.apple.com/av-foundation/)
- [Core ML Documentation](https://developer.apple.com/documentation/coreml)
- [HealthKit Framework](https://developer.apple.com/documentation/healthkit)
- [Metal Programming Guide](https://developer.apple.com/metal/)
- [ARKit Documentation](https://developer.apple.com/documentation/arkit)

### **MIDI Standards**
- [MIDI 2.0 Specification](https://www.midi.org/specifications/midi-2-0)
- [MPE Specification](https://www.midi.org/specifications/midi-polyphonic-expression-mpe)

### **Neuro-Acoustics Research**
- HeartMath Institute - HRV Coherence
- Brainwave Entrainment Studies
- Solfeggio Frequencies Research

### **AI/ML Resources**
- [Core ML Models](https://developer.apple.com/machine-learning/models/)
- [AudioCraft by Meta](https://github.com/facebookresearch/audiocraft)
- [MusicLM by Google](https://google-research.github.io/seanet/musiclm/examples/)

---

## 🚀 Getting Started for Claude

### **Initial Analysis Checklist**

When starting a new development task:

1. ✅ Read existing codebase in relevant directories
2. ✅ Check for existing similar implementations
3. ✅ Verify iOS version compatibility
4. ✅ Identify required SPM dependencies
5. ✅ Plan file structure and class hierarchy
6. ✅ Write pseudo-code / algorithm first
7. ✅ Implement with full error handling
8. ✅ Add unit tests
9. ✅ Update documentation
10. ✅ Commit with descriptive message

### **Example Workflow**

```bash
# 1. Analyze task
Claude: "Analyzing requirements for Voice2MIDI converter..."

# 2. Check existing code
Claude: "Reading MicrophoneManager.swift..."
Claude: "Reading MIDI2Manager.swift..."

# 3. Create implementation
Claude: "Creating Voice2MIDIConverter.swift..."

# 4. Add tests
Claude: "Creating Voice2MIDIConverterTests.swift..."

# 5. Update docs
Claude: "Updating VOICE_TO_MIDI.md..."

# 6. Commit
git commit -m "feat: Add Voice2MIDI converter with < 5ms latency"
```

---

## 💾 Prompt Version Control

**Version:** 4.3
**Date:** October 2025
**Author:** Claude Sonnet 4.5 + vibrationalforce
**Status:** Production-Ready
**Next Review:** Q1 2026

**Changelog:**
- v4.0: Initial comprehensive prompt
- v4.1: Added AI/ML integration guidelines
- v4.2: Enhanced biofeedback system specs
- v4.3: Added DAW integration, spatial audio details

---

**🫧 consciousness compiled
🌊 multimodal fusion ready
✨ AI-enhanced creativity enabled**
