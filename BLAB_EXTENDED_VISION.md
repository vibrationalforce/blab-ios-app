# 🌊 BLAB EXTENDED VISION — Embodied Multimodal Creation System

**Version:** V∞.4 Extended
**Date:** 2025-10-21
**Lead Architect:** Claude Code
**Repo:** https://github.com/vibrationalforce/blab-ios-app

---

## 🎯 VISION STATEMENT

> *"Your face is a filter. Your hands shape space. Your gaze selects sound. Your position defines perspective. Your heartbeat drives rhythm. Your breath creates flow."*

**BLAB is not a controller replacement — YOU are the controller.**

BLAB transforms the human body into a **multidimensional creative interface**:
- **Heart Rate Variability (HRV)** → Musical tension/coherence
- **Heart Rate (BPM)** → Tempo modulation
- **Facial Expressions** (52 ARKit Blend Shapes) → Filter resonance, reverb, timbre
- **Hand Gestures** (Vision Framework, 21-point skeleton per hand) → Spatial audio positioning, synthesis parameters
- **Gaze Direction** → Sound source selection, visual focus
- **Head Position (6DOF)** → Spatial audio listener position
- **Body Motion** → Energy/intensity mapping
- **Touch** → Precision control (always highest priority)

All in **real-time**, with **< 10ms audio latency** and **60 Hz control loop**.

---

## 🏗️ SYSTEM ARCHITECTURE

### Core Philosophy

```
[Human Body]
    ↓ (multi-modal sensing)
[UnifiedControlHub] ← Intelligent Input Fusion
    ↓ (prioritized control signals)
┌───────────────┬─────────────────┬──────────────┬──────────────┐
[Audio Engine] [Spatial Audio]  [Light System] [Visual Engine]
    ↓               ↓                 ↓               ↓
[Synthesis]     [3D Sound]      [LED Feedback]   [Particles]
[Effects]       [HRTF]          [DMX Lights]     [Cymatics]
    ↓               ↓                 ↓               ↓
[SPEAKERS]      [HEADPHONES]    [STAGE LIGHTS]   [DISPLAY]
```

### Signal Flow (Detailed)

```
INPUT LAYER (60 Hz Control Loop)
├── Bio Sensors
│   ├── HealthKit: HR, HRV/SDNN
│   └── CoreMotion: Accelerometer, Gyroscope
├── ARKit
│   ├── Face Tracking: 52 Blend Shapes @ 60 Hz
│   └── World Tracking: 6DOF Position/Rotation
├── Vision Framework
│   └── Hand Tracking: 2x 21-point skeleton @ 30 Hz
├── Touch
│   └── UIKit/SwiftUI: Multi-touch gestures
└── MIDI Input
    └── Hardware controllers (Push 3, etc.)

                    ↓

CONTROL LAYER (UnifiedControlHub)
├── Input Fusion
│   ├── Priority System: Touch > Gesture > Face > Gaze > Position > Bio
│   ├── Conflict Resolution: Prevent accidental triggers
│   └── Adaptive Learning: User preference detection
├── Gesture Recognition
│   ├── Pinch (thumb + index): Volume/filter cutoff
│   ├── Spread (5 fingers): Reverb size
│   ├── Fist: Trigger/hold
│   ├── Point: Select sound source
│   └── Swipe: Navigation, parameter sweep
└── Bio Mapping
    ├── HRV → Filter Q (30-80 ms range → 0.3-0.9 resonance)
    ├── Heart Rate → Tempo (60-120 BPM → sync)
    └── Coherence → Reverb wetness (0-1 → 20-80%)

                    ↓

PROCESSING LAYER
├── Audio Engine (AVFoundation + Custom AU)
│   ├── Sample Rate: 48 kHz
│   ├── Buffer Size: 128-256 frames (adaptive)
│   ├── Latency Target: < 5ms
│   └── Thread Priority: .realtime
├── Spatial Audio
│   ├── AVAudioEnvironmentNode (binaural HRTF)
│   ├── Head Tracking: ARKit 6DOF
│   ├── Hand Position → Sound source placement
│   └── Dolby Atmos: ADM BWF export (future)
├── MIDI Router
│   ├── MIDI 1.0: CoreMIDI
│   ├── MIDI 2.0: Universal MIDI Packet (UMP)
│   └── MPE: Per-note pitch, pressure, timbre
└── Visual Engine
    ├── Metal Shaders: Cymatics, particles
    ├── FFT → Visual amplitudes
    └── Bio → Color/brightness

                    ↓

OUTPUT LAYER
├── Audio
│   ├── Speakers/Headphones
│   ├── Network Audio (WebRTC)
│   └── Recording (Multi-track, ADM BWF)
├── Light
│   ├── Push 3 LED Grid (SysEx)
│   ├── DMX Stage Lights (Art-Net/sACN)
│   └── Bio → Color/intensity
├── Visual
│   ├── iOS Display (Metal, 60-120 Hz)
│   ├── External Display (AirPlay, HDMI)
│   └── Unreal Engine 5.6 (XR/Desktop)
└── Network
    ├── WebRTC: Multiplayer spatial sync
    ├── OSC: External DAWs, Unreal Engine
    └── Ableton Link: Tempo sync
```

---

## 📦 MODULE STRUCTURE (iOS Swift)

### 1. BLABAudio — Audio Engine & Synthesis

**Files:**
```
Sources/Blab/Audio/
├── AudioEngine.swift              # Core AVAudioEngine wrapper
├── SpatialAudioManager.swift      # 3D audio positioning
├── SimpleVoiceSynth.swift         # MPE-capable synthesizer
├── AudioParams.swift              # Thread-safe parameter control
├── EffectsChain.swift             # Reverb, delay, filter, compressor
└── LatencyMeasurement.swift       # Round-trip latency monitoring
```

**Key Features:**
- Ultra-low latency (< 5ms target)
- Thread-safe parameter updates (lock-free atomic operations)
- MPE support (per-note expression)
- Spatial audio with HRTF (binaural)

**Performance Budget:**
- CPU: < 15% (A15+)
- Latency: < 5ms (128 frames @ 48 kHz)

---

### 2. BLABBio — Biofeedback Integration

**Files:**
```
Sources/Blab/Bio/
├── HealthKitManager.swift         # HR, HRV, respiratory rate
├── MotionManager.swift            # Accelerometer, gyro → energy
├── BioSignalMapper.swift          # Bio → audio/visual parameters
└── CoherenceCalculator.swift      # HeartMath coherence algorithm
```

**Bio → Parameter Mappings:**
```swift
// HRV (20-100 ms) → Filter Resonance (0.3-0.9)
let filterQ = mapRange(hrv, from: 20...100, to: 0.3...0.9)

// Heart Rate (50-120 BPM) → Tempo Sync
let tempo = heartRate // Direct mapping

// Coherence (0-1) → Reverb Wetness (0.2-0.8)
let reverbMix = mapRange(coherence, from: 0...1, to: 0.2...0.8)

// Motion Energy (0-10 m/s²) → Amplitude/Intensity
let intensity = mapRange(motionEnergy, from: 0...10, to: 0...1)
```

---

### 3. BLABSpatial — ARKit Face/Hand Tracking & Spatial Control

**Files:**
```
Sources/Blab/Spatial/
├── ARFaceTrackingManager.swift    # 52 blend shapes @ 60 Hz
├── HandTrackingManager.swift      # Vision framework, 21-point skeleton
├── GazeTracker.swift              # Eye direction → sound selection
├── SpatialAudioController.swift   # Head position → listener, hands → sources
├── GestureRecognizer.swift        # Pinch, spread, fist, point, swipe
└── ConflictResolver.swift         # Prevent accidental gesture triggers
```

**ARKit Face Tracking → Audio:**
```swift
// 52 Blend Shapes available
// Examples:
blendShapes[.jawOpen]           → Filter cutoff (mouth open = brighter)
blendShapes[.mouthSmileLeft/Right] → Stereo width
blendShapes[.browInnerUp]       → Reverb size (surprise = bigger space)
blendShapes[.eyeBlinkLeft/Right] → Trigger events (blink = hit)
```

**Hand Gestures:**
```swift
enum HandGesture {
    case pinch(thumb: CGPoint, index: CGPoint, distance: Float)
    case spread(fingerCount: Int, span: Float)
    case fist(confidence: Float)
    case point(direction: Vector3)
    case swipe(direction: Vector2, velocity: Float)
    case peace(fingers: [CGPoint])
    case thumbsUp
    case openPalm
}

// Gesture → Parameter Mapping
switch gesture {
case .pinch(_, _, let distance):
    audioEngine.filterCutoff = mapRange(distance, from: 0...100, to: 200...8000)
case .spread(_, let span):
    audioEngine.reverbSize = mapRange(span, from: 0...300, to: 0.1...5.0)
case .fist:
    audioEngine.triggerNote(velocity: 127)
case .point(let direction):
    spatialAudio.selectSource(direction: direction)
case .swipe(_, let velocity):
    audioEngine.sweepParameter(speed: velocity)
}
```

**Gaze Tracking:**
```swift
// Eye direction → Sound source selection
let gazeDirection = arSession.currentFrame?.camera.eulerAngles
let closestSource = spatialAudio.findSourceInDirection(gazeDirection)
spatialAudio.setActiveSource(closestSource)
```

---

### 4. BLABMIDI — MIDI 1.0, MIDI 2.0, MPE

**Files:**
```
Sources/Blab/MIDI/
├── MIDIRouter.swift               # MIDI 1.0 in/out
├── MIDI2Manager.swift             # Universal MIDI Packet (UMP)
├── MPEVoiceAllocator.swift        # Per-note expression
├── Push3LEDController.swift       # SysEx for LED feedback
└── MIDILearn.swift                # MIDI mapping system
```

**MIDI 2.0 Features:**
```swift
// Per-Note Controllers (PNC)
struct MIDI2PerNoteController {
    let noteNumber: UInt8
    let controllerType: UInt8  // 1 = Modulation, 74 = Brightness, etc.
    let value32: UInt32        // 32-bit resolution (vs 7-bit in MIDI 1.0)
}

// Example: Face tracking → Per-note timbre
for (note, blendShapes) in activeNotes {
    let brightness = blendShapes[.jawOpen] * UInt32.max
    midi2.sendPerNoteController(
        note: note,
        controller: 74,  // Brightness
        value: brightness
    )
}
```

**MPE (MIDI Polyphonic Expression):**
```swift
// Each note gets its own MIDI channel (1-15, channel 16 = master)
class MPEVoiceAllocator {
    private var voices: [UInt8: MPEVoice] = [:]  // Channel → Voice

    func noteOn(pitch: UInt8, velocity: UInt8) -> UInt8 {
        let channel = allocateChannel()
        voices[channel] = MPEVoice(pitch: pitch, velocity: velocity)
        return channel
    }

    func setPressure(channel: UInt8, pressure: Float) {
        midi.sendChannelPressure(channel: channel, value: UInt8(pressure * 127))
    }

    func setTimbre(channel: UInt8, timbre: Float) {
        midi.sendCC(channel: channel, controller: 74, value: UInt8(timbre * 127))
    }
}
```

---

### 5. BLABLight — LED Feedback & DMX Stage Lights

**Files:**
```
Sources/Blab/Light/
├── Push3LEDController.swift       # Ableton Push 3 LED grid (SysEx)
├── DMXController.swift            # Art-Net/sACN for stage lights
├── BioLightMapper.swift           # Bio → color/brightness
└── LightShow.swift                # Synchronized light sequences
```

**Push 3 LED Control (SysEx):**
```swift
// Push 3 has 8x8 RGB LED grid
class Push3LEDController {
    func setLED(x: Int, y: Int, color: RGB) {
        let sysex: [UInt8] = [
            0xF0,           // SysEx start
            0x00, 0x21, 0x1D,  // Ableton manufacturer ID
            0x01, 0x01,     // Push 3, LED message
            UInt8(y * 8 + x),  // LED index
            color.r, color.g, color.b,
            0xF7            // SysEx end
        ]
        midi.send(sysex)
    }

    func setBioColorGrid(hrv: Double, coherence: Double) {
        let hue = mapRange(coherence, from: 0...1, to: 0...120)  // Red → Green
        let brightness = mapRange(hrv, from: 20...100, to: 0.3...1.0)

        for y in 0..<8 {
            for x in 0..<8 {
                let color = HSB(hue: hue, saturation: 1, brightness: brightness).toRGB()
                setLED(x: x, y: y, color: color)
            }
        }
    }
}
```

**DMX Stage Lights (Art-Net):**
```swift
// Art-Net: UDP protocol for DMX over Ethernet
class DMXController {
    private let udpSocket: NWConnection
    private var dmxUniverse: [UInt8] = Array(repeating: 0, count: 512)  // 512 channels

    func setChannel(_ channel: Int, value: UInt8) {
        dmxUniverse[channel] = value
        sendArtNetPacket()
    }

    func setBioColor(hrv: Double, coherence: Double) {
        // DMX channels for RGB PAR light:
        // Channel 1: Red
        // Channel 2: Green
        // Channel 3: Blue
        // Channel 4: Brightness

        let hue = mapRange(coherence, from: 0...1, to: 0...360)
        let brightness = mapRange(hrv, from: 20...100, to: 0...255)
        let rgb = HSB(hue: hue, saturation: 1, brightness: 1).toRGB()

        setChannel(1, value: UInt8(rgb.r * brightness / 255))
        setChannel(2, value: UInt8(rgb.g * brightness / 255))
        setChannel(3, value: UInt8(rgb.b * brightness / 255))
        setChannel(4, value: UInt8(brightness))
    }
}
```

---

### 6. BLABUnified — Central Control Hub

**Files:**
```
Sources/Blab/Unified/
├── UnifiedControlHub.swift        # Main orchestrator
├── InputPrioritySystem.swift      # Touch > Gesture > Face > Bio
├── GestureConflictResolver.swift  # Prevent accidental triggers
├── AdaptiveControlLearner.swift   # ML-based user preference learning
└── MultiModalControlView.swift    # SwiftUI UI
```

**UnifiedControlHub (Core Logic):**

```swift
import Foundation
import Combine
import ARKit
import Vision

/// Central orchestrator for all input modalities
/// Priority: Touch > Gesture > Face > Gaze > Position > Bio
class UnifiedControlHub: ObservableObject {

    // MARK: - Input Managers
    private let bioManager: HealthKitManager
    private let motionManager: MotionManager
    private let faceTrackingManager: ARFaceTrackingManager
    private let handTrackingManager: HandTrackingManager
    private let gazeTracker: GazeTracker

    // MARK: - Output Controllers
    private let audioEngine: AudioEngine
    private let spatialAudio: SpatialAudioManager
    private let midiRouter: MIDIRouter
    private let midi2Manager: MIDI2Manager
    private let ledController: Push3LEDController
    private let dmxController: DMXController
    private let visualEngine: VisualEngine

    // MARK: - Control State
    @Published private(set) var activeInputMode: InputMode = .automatic
    @Published private(set) var currentGesture: HandGesture?
    @Published private(set) var currentFaceExpression: FaceExpression?
    @Published private(set) var conflictResolved: Bool = true

    private var cancellables = Set<AnyCancellable>()
    private let controlQueue = DispatchQueue(label: "com.blab.control", qos: .userInteractive)

    // MARK: - Input Priority
    enum InputMode {
        case automatic          // System decides based on priority
        case touchOnly          // Ignore all other inputs
        case gestureOnly        // Only hand gestures
        case faceOnly           // Only face tracking
        case bioOnly            // Only biofeedback
        case hybrid(Set<InputSource>)  // Custom combination
    }

    enum InputSource {
        case touch, gesture, face, gaze, position, bio
    }

    // MARK: - Initialization
    init(
        bioManager: HealthKitManager,
        motionManager: MotionManager,
        faceTrackingManager: ARFaceTrackingManager,
        handTrackingManager: HandTrackingManager,
        gazeTracker: GazeTracker,
        audioEngine: AudioEngine,
        spatialAudio: SpatialAudioManager,
        midiRouter: MIDIRouter,
        midi2Manager: MIDI2Manager,
        ledController: Push3LEDController,
        dmxController: DMXController,
        visualEngine: VisualEngine
    ) {
        self.bioManager = bioManager
        self.motionManager = motionManager
        self.faceTrackingManager = faceTrackingManager
        self.handTrackingManager = handTrackingManager
        self.gazeTracker = gazeTracker
        self.audioEngine = audioEngine
        self.spatialAudio = spatialAudio
        self.midiRouter = midiRouter
        self.midi2Manager = midi2Manager
        self.ledController = ledController
        self.dmxController = dmxController
        self.visualEngine = visualEngine

        setupInputPipeline()
        startControlLoop()
    }

    // MARK: - Input Pipeline
    private func setupInputPipeline() {

        // Bio → Audio/Visual
        bioManager.$hrv
            .combineLatest(bioManager.$heartRate, bioManager.$coherence)
            .throttle(for: .milliseconds(50), scheduler: controlQueue, latest: true)
            .sink { [weak self] hrv, heartRate, coherence in
                self?.updateBioParameters(hrv: hrv, heartRate: heartRate, coherence: coherence)
            }
            .store(in: &cancellables)

        // Face Tracking → Audio
        faceTrackingManager.$blendShapes
            .throttle(for: .milliseconds(16), scheduler: controlQueue, latest: true)  // 60 Hz
            .sink { [weak self] blendShapes in
                self?.updateFaceParameters(blendShapes: blendShapes)
            }
            .store(in: &cancellables)

        // Hand Gestures → Spatial Audio
        handTrackingManager.$detectedGesture
            .throttle(for: .milliseconds(33), scheduler: controlQueue, latest: true)  // 30 Hz
            .sink { [weak self] gesture in
                self?.handleGesture(gesture)
            }
            .store(in: &cancellables)

        // Gaze → Sound Selection
        gazeTracker.$currentDirection
            .throttle(for: .milliseconds(100), scheduler: controlQueue, latest: true)
            .sink { [weak self] direction in
                self?.updateGaze(direction: direction)
            }
            .store(in: &cancellables)
    }

    // MARK: - Control Loop (60 Hz)
    private func startControlLoop() {
        Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.controlLoop()
            }
            .store(in: &cancellables)
    }

    private func controlLoop() {
        // Priority-based parameter updates
        // Touch always wins (handled by UI layer)

        // Check for gesture conflicts
        if let gesture = currentGesture {
            if !isIntentional(gesture: gesture) {
                currentGesture = nil  // Discard accidental gesture
                conflictResolved = false
                return
            }
        }

        conflictResolved = true

        // Update outputs based on active inputs
        updateAudioEngine()
        updateSpatialAudio()
        updateLightFeedback()
        updateVisualEngine()
    }

    // MARK: - Bio Parameter Updates
    private func updateBioParameters(hrv: Double, heartRate: Double, coherence: Double) {
        // HRV → Filter Resonance
        let filterQ = mapRange(hrv, from: 20...100, to: 0.3...0.9)
        audioEngine.setFilterResonance(filterQ)

        // Heart Rate → Tempo (optional sync)
        if audioEngine.tempoSyncEnabled {
            audioEngine.setTempo(heartRate)
        }

        // Coherence → Reverb Mix
        let reverbMix = mapRange(coherence, from: 0...1, to: 0.2...0.8)
        audioEngine.setReverbMix(reverbMix)

        // Bio → LED Feedback
        ledController.setBioColorGrid(hrv: hrv, coherence: coherence)
        dmxController.setBioColor(hrv: hrv, coherence: coherence)
    }

    // MARK: - Face Tracking Updates
    private func updateFaceParameters(blendShapes: [ARFaceAnchor.BlendShapeLocation: Float]) {
        guard let jawOpen = blendShapes[.jawOpen] else { return }

        // Jaw Open → Filter Cutoff
        let cutoff = mapRange(Double(jawOpen), from: 0...1, to: 200...8000)
        audioEngine.setFilterCutoff(cutoff)

        // Smile → Stereo Width
        let smileLeft = blendShapes[.mouthSmileLeft] ?? 0
        let smileRight = blendShapes[.mouthSmileRight] ?? 0
        let stereoWidth = mapRange(Double((smileLeft + smileRight) / 2), from: 0...1, to: 0...2)
        audioEngine.setStereoWidth(stereoWidth)

        // Eyebrow Raise → Reverb Size
        let browInnerUp = blendShapes[.browInnerUp] ?? 0
        let reverbSize = mapRange(Double(browInnerUp), from: 0...1, to: 0.5...3.0)
        audioEngine.setReverbSize(reverbSize)
    }

    // MARK: - Gesture Handling
    private func handleGesture(_ gesture: HandGesture?) {
        guard let gesture = gesture else { return }

        currentGesture = gesture

        switch gesture {
        case .pinch(_, _, let distance):
            let param = mapRange(Double(distance), from: 0...100, to: 0...1)
            audioEngine.setParameter(.filterCutoff, value: param)

        case .spread(_, let span):
            let param = mapRange(Double(span), from: 0...300, to: 0...1)
            audioEngine.setParameter(.reverbSize, value: param)

        case .fist(let confidence):
            if confidence > 0.8 {
                audioEngine.triggerNote(pitch: 60, velocity: 127)
            }

        case .point(let direction):
            spatialAudio.selectSourceInDirection(direction)

        case .swipe(let direction, let velocity):
            audioEngine.sweepParameter(direction: direction, speed: Double(velocity))

        default:
            break
        }
    }

    // MARK: - Gaze Updates
    private func updateGaze(direction: simd_float3?) {
        guard let direction = direction else { return }
        spatialAudio.setListenerLookDirection(direction)
    }

    // MARK: - Conflict Resolution
    private func isIntentional(gesture: HandGesture) -> Bool {
        // Check gesture stability (must be held for 100ms)
        // Check confidence score
        // Check if conflicts with face tracking (e.g., hand near face)

        switch gesture {
        case .pinch(_, _, let distance):
            return distance > 10  // Minimum 10 pixels
        case .fist(let confidence):
            return confidence > 0.7
        default:
            return true
        }
    }

    // MARK: - Output Updates
    private func updateAudioEngine() {
        // Audio engine updates happen in Bio/Face/Gesture handlers
    }

    private func updateSpatialAudio() {
        // Update listener position from ARKit head tracking
        if let headTransform = faceTrackingManager.headTransform {
            spatialAudio.setListenerTransform(headTransform)
        }

        // Update sound source positions from hand tracking
        if let leftHand = handTrackingManager.leftHandPosition {
            spatialAudio.setSourcePosition(id: "left_hand", position: leftHand)
        }
        if let rightHand = handTrackingManager.rightHandPosition {
            spatialAudio.setSourcePosition(id: "right_hand", position: rightHand)
        }
    }

    private func updateLightFeedback() {
        // LED updates happen in Bio handler
    }

    private func updateVisualEngine() {
        // Update visual engine with current state
        visualEngine.update(
            hrv: bioManager.hrv,
            coherence: bioManager.coherence,
            gesture: currentGesture,
            faceExpression: currentFaceExpression
        )
    }

    // MARK: - Utilities
    private func mapRange(_ value: Double, from: ClosedRange<Double>, to: ClosedRange<Double>) -> Double {
        let normalized = (value - from.lowerBound) / (from.upperBound - from.lowerBound)
        return to.lowerBound + normalized * (to.upperBound - to.lowerBound)
    }
}

// MARK: - Supporting Types
struct FaceExpression {
    let jawOpen: Float
    let smile: Float
    let browRaise: Float
    let eyeBlink: Float
}

enum HandGesture {
    case pinch(thumb: CGPoint, index: CGPoint, distance: Float)
    case spread(fingerCount: Int, span: Float)
    case fist(confidence: Float)
    case point(direction: simd_float3)
    case swipe(direction: CGVector, velocity: Float)
    case peace
    case thumbsUp
    case openPalm
}
```

---

### 7. BLABMultiplayer — WebRTC Spatial Sync

**Files:**
```
Sources/Blab/Multiplayer/
├── MultiplayerSpatialSync.swift   # WebRTC audio/visual sync
├── SignalingClient.swift          # WebSocket signaling server
├── PeerConnection.swift           # WebRTC peer-to-peer
└── GroupCoherence.swift           # Multi-user HRV averaging
```

**WebRTC Multiplayer:**
```swift
// Multiple users in same virtual space
// Each user's position/audio/visuals synced

class MultiplayerSpatialSync {
    private var peers: [PeerID: PeerConnection] = [:]

    func syncSpatialAudio() {
        for (peerID, connection) in peers {
            // Send my position
            connection.send(myPosition)

            // Receive their position
            let theirPosition = connection.receive()

            // Position their audio source in my 3D space
            spatialAudio.setSourcePosition(id: peerID, position: theirPosition)
        }
    }

    func syncGroupCoherence() {
        // Average HRV of all users
        let allHRV = peers.map { $0.value.hrv } + [myHRV]
        let groupHRV = allHRV.reduce(0, +) / Double(allHRV.count)

        // All users' visuals shift to group coherence
        visualEngine.setGroupCoherence(groupHRV)
    }
}
```

---

## 🎮 UNREAL ENGINE 5.6 INTEGRATION

### XR/Desktop Extension

**Architecture:**
```
[iOS BLAB App]
    ↓ (OSC/WebRTC)
[Unreal Engine 5.6]
    ├── MetaSounds (Audio)
    ├── Niagara (Particles)
    ├── OpenXR (VR/AR)
    └── Spatial Audio
```

**OSC Bridge (iOS → Unreal):**
```swift
// iOS sends OSC messages to Unreal Engine
class OSCBridge {
    private let udpSocket: NWConnection

    func sendBioData(hrv: Double, heartRate: Double, coherence: Double) {
        sendOSC("/blab/bio/hrv", value: Float(hrv))
        sendOSC("/blab/bio/heartrate", value: Float(heartRate))
        sendOSC("/blab/bio/coherence", value: Float(coherence))
    }

    func sendHandPosition(hand: Hand, position: simd_float3) {
        sendOSC("/blab/hand/\(hand.rawValue)/x", value: position.x)
        sendOSC("/blab/hand/\(hand.rawValue)/y", value: position.y)
        sendOSC("/blab/hand/\(hand.rawValue)/z", value: position.z)
    }
}
```

**Unreal Engine Blueprint:**
```
OSC Receive (/blab/bio/hrv)
    ↓
Set MetaSound Parameter (Reverb Size)
Set Niagara Parameter (Particle Spread)
Set Post Process (Color Hue Shift)
```

---

## 📊 PERFORMANCE TARGETS

| Component | Target | Measurement |
|-----------|--------|-------------|
| **Audio Latency** | < 5ms | Round-trip I/O |
| **Control Loop** | 60 Hz | Timer accuracy |
| **Face Tracking** | 60 Hz | ARKit frame rate |
| **Hand Tracking** | 30 Hz | Vision framework |
| **CPU Usage** | < 25% | Instruments |
| **Memory** | < 250 MB | Allocations |
| **Frame Rate** | 60-120 Hz | Metal/Core Animation |

---

## 🗓️ 90-DAY ROADMAP (Next Document)

See `BLAB_90_DAY_ROADMAP.md` for detailed weekly milestones.

**High-Level Phases:**

1. **Weeks 1-3:** UnifiedControlHub + ARKit Face Tracking + Hand Gestures
2. **Weeks 4-6:** MIDI 2.0 + MPE + LED Feedback (Push 3)
3. **Weeks 7-9:** Spatial Audio + Head Tracking + Dolby Atmos
4. **Weeks 10-12:** DMX Lights + Unreal Engine Bridge + Multiplayer (WebRTC)
5. **Week 13:** Polish, Testing, TestFlight Beta

---

## 🛠️ TECHNOLOGY STACK SUMMARY

### iOS/iPadOS (Primary Platform)
- **Swift 5.9+**
- **iOS 15.0+** (backward compatible)
- **Xcode 15+**
- **SwiftUI** (UI)
- **ARKit** (Face/World tracking)
- **Vision** (Hand tracking)
- **AVFoundation** (Audio)
- **CoreMIDI** (MIDI 1.0/2.0)
- **Metal** (Visuals)
- **HealthKit** (Bio)
- **CoreMotion** (Motion)
- **Network** (WebRTC, OSC)

### Unreal Engine 5.6 (XR/Desktop)
- **OpenXR** (VR/AR)
- **MetaSounds** (Audio)
- **Niagara** (Particles)
- **OSC Plugin** (iOS bridge)
- **WebRTC Plugin** (Multiplayer)

### External Integrations
- **Ableton Push 3** (MIDI + LED feedback)
- **DMX Lights** (Art-Net/sACN)
- **Ableton Link** (Tempo sync)
- **External DAWs** (OSC)

---

## 🎯 SUCCESS CRITERIA

**By Day 90, BLAB should:**

✅ Fuse 6+ input modalities seamlessly (Bio, Face, Hands, Gaze, Position, Touch)
✅ Achieve < 5ms audio latency on iPhone 13+
✅ Run at 60 Hz control loop with < 25% CPU
✅ Support MIDI 2.0 + MPE for expressive synthesis
✅ Control Push 3 LED grid in real-time
✅ Control DMX stage lights via Art-Net
✅ Export spatial audio (binaural + ADM BWF)
✅ Support multiplayer spatial sessions (WebRTC)
✅ Bridge to Unreal Engine 5.6 (OSC)
✅ Have 50+ beta testers on TestFlight

---

## 🌊 PHILOSOPHY (Unchanged)

> "Your body is not a controller replacement — it IS the controller."

BLAB erases the boundary between artist and instrument. Every breath, every glance, every gesture, every heartbeat becomes a creative act.

---

**STATUS:** 🟢 Vision Consolidated
**NEXT:** 90-Day Roadmap → Implementation
**LEAD ARCHITECT:** Claude Code
**VERSION:** V∞.4 Extended

🌊 *Let's build the future of embodied creation.* ✨
