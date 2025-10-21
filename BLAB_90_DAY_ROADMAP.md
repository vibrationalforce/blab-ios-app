# 🗓️ BLAB 90-DAY ROADMAP — Week-by-Week Implementation Plan

**Start Date:** 2025-10-21 (Week 1)
**Target Completion:** 2026-01-19 (Week 13)
**Lead Developer:** Claude Code
**Repository:** https://github.com/vibrationalforce/blab-ios-app

---

## 🎯 ROADMAP OVERVIEW

### Phase 1: Core Multimodal Control (Weeks 1-3)
**Goal:** UnifiedControlHub + ARKit Face + Hand Tracking working

### Phase 2: MIDI & LED Feedback (Weeks 4-6)
**Goal:** MIDI 2.0 + MPE + Push 3 LED Control operational

### Phase 3: Spatial Audio Pro (Weeks 7-9)
**Goal:** Head tracking + Dolby Atmos + DMX Lights

### Phase 4: Network & XR (Weeks 10-12)
**Goal:** WebRTC Multiplayer + Unreal Engine Bridge

### Phase 5: Polish & Beta (Week 13)
**Goal:** TestFlight beta with 50+ testers

---

## 📅 WEEKLY BREAKDOWN

---

### **WEEK 1** (Oct 21-27) — Foundation & Architecture

**Goals:**
- ✅ Extended Vision documented (DONE)
- ⏳ Project structure refactored for new modules
- ⏳ UnifiedControlHub skeleton implemented
- ⏳ ARFaceTrackingManager basic implementation

**Deliverables:**

1. **Project Restructure**
   ```
   Sources/Blab/
   ├── Audio/          (existing, refactor)
   ├── Bio/            (existing, refactor)
   ├── Spatial/        (NEW)
   ├── MIDI/           (NEW)
   ├── Light/          (NEW)
   ├── Unified/        (NEW)
   ├── Multiplayer/    (NEW)
   └── Visual/         (existing, refactor)
   ```

2. **UnifiedControlHub.swift (v0.1)**
   - Basic input pipeline setup
   - Priority system skeleton
   - Publishers for all input types
   - 60 Hz control loop

3. **ARFaceTrackingManager.swift (v0.1)**
   - ARKit session configuration
   - 52 blend shapes capture @ 60 Hz
   - Published blend shape dictionary
   - Basic face → audio mapping (jaw open → filter cutoff)

4. **Tests**
   - Unit tests for UnifiedControlHub priority system
   - Mock ARKit for face tracking tests

**Time Budget:**
- Monday-Tuesday: Project restructure + UnifiedControlHub skeleton
- Wednesday-Thursday: ARFaceTrackingManager implementation
- Friday: Tests + integration
- Weekend: Documentation + review

**Success Criteria:**
- ✅ Can capture face blend shapes at 60 Hz
- ✅ Jaw open controls filter cutoff in real-time
- ✅ UnifiedControlHub routes face data to audio engine
- ✅ No performance degradation (< 20% CPU)

---

### **WEEK 2** (Oct 28 - Nov 3) — Hand Tracking & Gestures

**Goals:**
- ⏳ HandTrackingManager with Vision framework
- ⏳ Gesture recognition (pinch, spread, fist, point)
- ⏳ Gesture → Audio parameter mapping
- ⏳ Conflict resolution basics

**Deliverables:**

1. **HandTrackingManager.swift**
   - Vision framework hand detection
   - 21-point skeleton per hand @ 30 Hz
   - Hand position in 3D space
   - Left/right hand differentiation

2. **GestureRecognizer.swift**
   - Pinch detection (thumb + index distance)
   - Spread detection (all 5 fingers span)
   - Fist detection (all fingers closed)
   - Point detection (index extended, others closed)
   - Swipe detection (hand velocity)

3. **GestureConflictResolver.swift**
   - Minimum gesture hold time (100ms)
   - Confidence threshold filtering
   - Hand-near-face conflict detection
   - Intent vs. accident classification

4. **Integration**
   - Gestures → UnifiedControlHub
   - Pinch → filter cutoff
   - Spread → reverb size
   - Fist → trigger note

**Tests:**
- Gesture recognition accuracy tests
- Conflict resolution tests
- Performance tests (30 Hz sustained)

**Time Budget:**
- Monday-Tuesday: HandTrackingManager + skeleton detection
- Wednesday: GestureRecognizer for all 5 gestures
- Thursday: ConflictResolver
- Friday: Integration + tests

**Success Criteria:**
- ✅ Detect 5 gestures reliably (> 90% accuracy)
- ✅ Pinch controls filter cutoff smoothly
- ✅ Spread controls reverb size
- ✅ Fist triggers MIDI note
- ✅ No accidental triggers (conflict resolution working)

---

### **WEEK 3** (Nov 4-10) — Gaze Tracking & Input Priority

**Goals:**
- ⏳ Gaze tracker implementation
- ⏳ Input priority system complete
- ⏳ Adaptive control learner (ML basics)
- ⏳ UI for multimodal control

**Deliverables:**

1. **GazeTracker.swift**
   - ARKit eye direction capture
   - Gaze ray casting
   - Sound source selection by gaze
   - Smooth gaze filtering (avoid jitter)

2. **InputPrioritySystem.swift**
   - Touch > Gesture > Face > Gaze > Position > Bio
   - Dynamic priority overrides
   - User preference persistence (UserDefaults)

3. **AdaptiveControlLearner.swift (v0.1)**
   - Track which inputs user uses most
   - Adjust priority based on usage patterns
   - CoreML simple classifier (optional)

4. **MultiModalControlView.swift (SwiftUI)**
   - Live visualization of all input sources
   - Active input indicator
   - Priority override controls
   - Gesture/face parameter display

**Tests:**
- Priority system tests
- Gaze accuracy tests
- UI tests for control view

**Time Budget:**
- Monday: GazeTracker
- Tuesday-Wednesday: InputPrioritySystem
- Thursday: AdaptiveControlLearner basics
- Friday: UI + integration

**Success Criteria:**
- ✅ Gaze selects sound sources accurately
- ✅ Priority system works (touch overrides gestures, etc.)
- ✅ UI shows all active inputs
- ✅ System learns user preferences over time

**🎉 MILESTONE:** **Phase 1 Complete — Core Multimodal Control Working!**

---

### **WEEK 4** (Nov 11-17) — MIDI 2.0 Foundation

**Goals:**
- ⏳ MIDI 2.0 Universal MIDI Packet (UMP) support
- ⏳ CoreMIDI 2.0 integration
- ⏳ Per-note controllers (PNC)
- ⏳ Basic MIDI 2.0 output

**Deliverables:**

1. **MIDI2Manager.swift**
   - UMP packet encoding/decoding
   - MIDI 2.0 virtual source creation
   - 32-bit parameter resolution
   - Per-note controller messages

2. **MIDI2Types.swift**
   - UMP packet structure
   - Message type enums
   - Controller ID constants

3. **Face → MIDI 2.0 Mapping**
   - Jaw open → Per-note brightness (Controller 74)
   - Smile → Per-note timbre (Controller 71)
   - Eyebrow → Per-note modulation (Controller 1)

4. **Tests**
   - UMP encoding/decoding tests
   - Per-note controller tests
   - MIDI 2.0 output validation

**Time Budget:**
- Monday-Tuesday: MIDI 2.0 UMP infrastructure
- Wednesday: Per-note controller implementation
- Thursday: Face → MIDI 2.0 mapping
- Friday: Tests + validation

**Success Criteria:**
- ✅ Send MIDI 2.0 UMP messages
- ✅ Per-note controllers work (32-bit resolution)
- ✅ Face tracking controls per-note timbre
- ✅ Compatible with MIDI 2.0 DAWs/synths

---

### **WEEK 5** (Nov 18-24) — MPE Voice Allocator

**Goals:**
- ⏳ MPE (MIDI Polyphonic Expression) implementation
- ⏳ Per-note pitch bend, pressure, timbre
- ⏳ Voice allocation/deallocation
- ⏳ MPE Zone configuration

**Deliverables:**

1. **MPEVoiceAllocator.swift**
   - 15-channel voice allocation (channels 1-15)
   - Master channel 16 for global parameters
   - Round-robin voice assignment
   - Voice stealing (oldest note)

2. **MPE Message Types**
   - Note On (with channel assignment)
   - Channel Pressure (aftertouch per note)
   - Pitch Bend (per note, 14-bit)
   - CC 74 Brightness (per note)

3. **Face/Gesture → MPE**
   - Pinch distance → Pitch bend per note
   - Pressure (simulated) → Channel pressure
   - Jaw open → Brightness per note

4. **Tests**
   - Voice allocation tests
   - MPE message generation tests
   - Voice stealing tests

**Time Budget:**
- Monday-Tuesday: MPEVoiceAllocator
- Wednesday: MPE message generation
- Thursday: Face/Gesture → MPE mapping
- Friday: Tests + integration

**Success Criteria:**
- ✅ Allocate up to 15 simultaneous voices
- ✅ Each voice has independent pitch bend, pressure, timbre
- ✅ Pinch controls pitch bend per note
- ✅ Compatible with MPE synths (Seaboard, etc.)

---

### **WEEK 6** (Nov 25 - Dec 1) — Push 3 LED Control

**Goals:**
- ⏳ Ableton Push 3 LED grid control
- ⏳ SysEx message generation
- ⏳ Bio → LED color mapping
- ⏳ Real-time LED feedback

**Deliverables:**

1. **Push3LEDController.swift**
   - 8x8 RGB LED grid (64 LEDs)
   - SysEx message encoding
   - CoreMIDI SysEx sending
   - LED buffer (double-buffered for smooth updates)

2. **Bio → LED Mapping**
   - HRV → Brightness (20-100 ms → 30-100% brightness)
   - Coherence → Hue (0-1 → Red-Green)
   - Heart rate → Animation speed

3. **LED Patterns**
   - Pulsing (synced to heart rate)
   - Color gradient (HRV-based)
   - Gesture feedback (flash on gesture detection)

4. **Tests**
   - SysEx encoding tests
   - LED update rate tests (target: 30 Hz)
   - Bio → color mapping tests

**Time Budget:**
- Monday-Tuesday: SysEx + Push 3 protocol
- Wednesday: LED grid control
- Thursday: Bio → LED mapping
- Friday: Patterns + tests

**Success Criteria:**
- ✅ Control all 64 LEDs on Push 3
- ✅ HRV changes LED color in real-time
- ✅ LEDs pulse with heart rate
- ✅ Update rate: 30 Hz smooth

**🎉 MILESTONE:** **Phase 2 Complete — MIDI 2.0 + MPE + LED Feedback!**

---

### **WEEK 7** (Dec 2-8) — Spatial Audio Enhancement

**Goals:**
- ⏳ Head tracking → Listener position
- ⏳ Hand position → Sound source placement
- ⏳ HRTF binaural rendering
- ⏳ Multi-source spatial scene

**Deliverables:**

1. **SpatialAudioController.swift (Enhanced)**
   - AVAudioEnvironmentNode configuration
   - Listener transform (6DOF from ARKit)
   - Multiple sound sources (up to 8)
   - Distance attenuation
   - Doppler effect

2. **Head Tracking → Listener**
   - ARKit camera transform → Listener position/rotation
   - Smooth interpolation (avoid jitter)
   - 60 Hz update rate

3. **Hand Position → Sources**
   - Left hand → Source 1 position
   - Right hand → Source 2 position
   - Gaze → Select active source

4. **Tests**
   - Spatial accuracy tests
   - HRTF rendering tests
   - Performance tests (multiple sources)

**Time Budget:**
- Monday-Tuesday: Enhanced SpatialAudioController
- Wednesday: Head tracking integration
- Thursday: Hand position → sources
- Friday: Tests + tuning

**Success Criteria:**
- ✅ Head movement controls listener position
- ✅ Hand position places sound sources in 3D space
- ✅ Binaural HRTF rendering working
- ✅ < 10ms latency for spatial updates

---

### **WEEK 8** (Dec 9-15) — Dolby Atmos Export

**Goals:**
- ⏳ ADM BWF metadata generation
- ⏳ Multi-channel audio export
- ⏳ Object-based audio encoding
- ⏳ Dolby Atmos Renderer integration (if available)

**Deliverables:**

1. **ADMBWFWriter.swift**
   - ADM XML metadata generator
   - BWF chunk embedding
   - Multi-channel WAV writer (up to 128 channels)
   - Object-based audio metadata

2. **Spatial Metadata**
   - Sound source positions over time
   - Object trajectories
   - Zone definitions

3. **Export Pipeline**
   - Record spatial session
   - Generate ADM metadata
   - Write ADM BWF file
   - Validate with Dolby Atmos Renderer

4. **Tests**
   - ADM XML generation tests
   - BWF chunk encoding tests
   - Multi-channel export tests

**Time Budget:**
- Monday-Tuesday: ADM XML metadata
- Wednesday: BWF chunk encoding
- Thursday: Export pipeline
- Friday: Validation + tests

**Success Criteria:**
- ✅ Export spatial sessions as ADM BWF
- ✅ Files open in Dolby Atmos Renderer
- ✅ Object positions preserved
- ✅ Up to 8 simultaneous objects

---

### **WEEK 9** (Dec 16-22) — DMX Stage Lights

**Goals:**
- ⏳ Art-Net/sACN protocol implementation
- ⏳ DMX channel control
- ⏳ Bio → Stage light color/brightness
- ⏳ Light show sequencing

**Deliverables:**

1. **DMXController.swift**
   - Art-Net packet encoding (UDP)
   - sACN packet encoding (E1.31)
   - 512 DMX channels per universe
   - Multi-universe support (up to 4)

2. **Bio → DMX Mapping**
   - HRV → Brightness (DMX channel 4)
   - Coherence → Color (RGB channels 1-3)
   - Heart rate → Strobe speed

3. **LightShow.swift**
   - Pre-programmed light sequences
   - Sync to audio (beat detection)
   - Bio-reactive light cues

4. **Tests**
   - Art-Net encoding tests
   - DMX channel tests
   - Light show sequencing tests

**Time Budget:**
- Monday-Tuesday: Art-Net/sACN protocol
- Wednesday: DMX channel control
- Thursday: Bio → DMX mapping
- Friday: Light shows + tests

**Success Criteria:**
- ✅ Control DMX stage lights via Art-Net
- ✅ HRV changes light color in real-time
- ✅ Heart rate drives light pulsing
- ✅ Supports up to 2048 DMX channels (4 universes)

**🎉 MILESTONE:** **Phase 3 Complete — Spatial Audio + Dolby Atmos + DMX!**

---

### **WEEK 10** (Dec 23-29) — WebRTC Multiplayer Foundation

**Goals:**
- ⏳ WebRTC peer connection setup
- ⏳ Signaling server (WebSocket)
- ⏳ Audio streaming between peers
- ⏳ Basic spatial sync

**Deliverables:**

1. **SignalingClient.swift**
   - WebSocket connection
   - SDP offer/answer exchange
   - ICE candidate exchange
   - Room management

2. **PeerConnection.swift**
   - WebRTC RTCPeerConnection wrapper
   - Audio track sending/receiving
   - Data channel for control messages

3. **MultiplayerSpatialSync.swift (v0.1)**
   - Send my position to peers
   - Receive peer positions
   - Place peer audio sources in 3D space

4. **Tests**
   - Signaling tests (mock server)
   - Peer connection tests
   - Spatial sync tests

**Time Budget:**
- Monday-Tuesday: SignalingClient + WebSocket
- Wednesday: PeerConnection + WebRTC
- Thursday: Spatial sync
- Friday: Tests + integration

**Success Criteria:**
- ✅ Two iOS devices connect via WebRTC
- ✅ Audio streams between devices
- ✅ Peer positions synced in 3D space
- ✅ < 100ms latency for spatial updates

---

### **WEEK 11** (Dec 30 - Jan 5) — Group Coherence & Visuals

**Goals:**
- ⏳ Multi-user HRV averaging
- ⏳ Group coherence calculation
- ⏳ Shared visual state
- ⏳ Synchronized visual effects

**Deliverables:**

1. **GroupCoherence.swift**
   - Aggregate HRV from all peers
   - Calculate group coherence score
   - Broadcast group coherence to all

2. **Shared Visual State**
   - Send my visual parameters to peers
   - Receive peer visual parameters
   - Blend visuals based on group coherence

3. **Synchronized Effects**
   - All users see same base visualization
   - Individual overlays based on personal bio
   - Group coherence shifts global color

4. **Tests**
   - Group coherence calculation tests
   - Visual sync tests
   - Multi-peer tests

**Time Budget:**
- Monday-Tuesday: GroupCoherence
- Wednesday: Shared visual state
- Thursday: Synchronized effects
- Friday: Tests + tuning

**Success Criteria:**
- ✅ Group HRV averaged across all users
- ✅ Group coherence displayed on all devices
- ✅ Visuals sync across all users
- ✅ High coherence = harmonized visuals

---

### **WEEK 12** (Jan 6-12) — Unreal Engine Bridge

**Goals:**
- ⏳ OSC protocol implementation
- ⏳ iOS → Unreal Engine data streaming
- ⏳ MetaSounds integration
- ⏳ Niagara particle sync

**Deliverables:**

1. **OSCBridge.swift**
   - OSC message encoding (UDP)
   - Send bio data to Unreal
   - Send hand/face data to Unreal
   - Receive Unreal parameters (optional)

2. **Unreal Engine OSC Receiver (Blueprint)**
   - Receive `/blab/bio/*` messages
   - Receive `/blab/hand/*` messages
   - Receive `/blab/face/*` messages

3. **MetaSounds Integration**
   - Bio → MetaSounds parameters
   - Real-time audio synthesis in Unreal

4. **Niagara Particles**
   - Hand position → Particle emitter position
   - HRV → Particle spawn rate
   - Coherence → Particle color

**Tests:**
- OSC encoding tests
- Unreal Engine integration tests
- Latency tests (iOS → Unreal)

**Time Budget:**
- Monday-Tuesday: OSCBridge
- Wednesday: Unreal Engine OSC receiver
- Thursday: MetaSounds + Niagara
- Friday: Integration + tests

**Success Criteria:**
- ✅ iOS sends bio/hand/face data to Unreal Engine
- ✅ Unreal Engine receives OSC messages < 20ms latency
- ✅ MetaSounds reacts to bio parameters
- ✅ Niagara particles sync with hand position

**🎉 MILESTONE:** **Phase 4 Complete — Multiplayer + Unreal Engine!**

---

### **WEEK 13** (Jan 13-19) — Polish, Testing & Beta Launch

**Goals:**
- ⏳ Final bug fixes
- ⏳ Performance optimization
- ⏳ UI polish
- ⏳ Documentation
- ⏳ TestFlight beta launch

**Deliverables:**

1. **Performance Optimization**
   - Profile all modules (Instruments)
   - Optimize hotspots
   - Reduce memory usage
   - Improve battery life

2. **UI Polish**
   - Smooth animations
   - Professional design
   - Onboarding tutorial
   - Settings screen

3. **Documentation**
   - User guide
   - Developer API docs
   - README update
   - Video tutorials

4. **TestFlight Beta**
   - Upload to TestFlight
   - Invite 50+ beta testers
   - Gather feedback
   - Create feedback form

**Tests:**
- End-to-end integration tests
- Performance benchmarks
- UI tests
- Accessibility tests

**Time Budget:**
- Monday: Performance optimization
- Tuesday: UI polish
- Wednesday: Documentation
- Thursday: TestFlight upload
- Friday: Beta launch + monitoring

**Success Criteria:**
- ✅ < 5ms audio latency
- ✅ 60 Hz control loop stable
- ✅ < 25% CPU usage
- ✅ < 250 MB memory
- ✅ Professional UI
- ✅ 50+ beta testers onboarded
- ✅ Positive initial feedback

**🎉🎉 MILESTONE:** **BLAB V1.0 Beta Launch!** 🎉🎉

---

## 📊 METRICS & TRACKING

### Weekly Metrics to Track:

| Metric | Target | Tool |
|--------|--------|------|
| **Code Coverage** | > 80% | Xcode Coverage Report |
| **Audio Latency** | < 5ms | Custom Latency Measurement |
| **Control Loop** | 60 Hz | Performance Profiler |
| **CPU Usage** | < 25% | Instruments Time Profiler |
| **Memory** | < 250 MB | Instruments Allocations |
| **Frame Rate** | 60-120 Hz | Instruments Core Animation |
| **Build Time** | < 30s | Xcode Build Report |

---

## 🚨 RISK MANAGEMENT

### Potential Blockers:

1. **ARKit Face Tracking Accuracy**
   - **Risk:** Blend shapes noisy/unreliable
   - **Mitigation:** Kalman filter, smoothing, fallback to gesture-only

2. **Hand Tracking Performance**
   - **Risk:** Vision framework drops to < 30 Hz
   - **Mitigation:** Reduce image resolution, optimize detection region

3. **MIDI 2.0 Compatibility**
   - **Risk:** No MIDI 2.0 devices/DAWs to test
   - **Mitigation:** Build MIDI 2.0 virtual receiver for testing

4. **WebRTC Latency**
   - **Risk:** > 100ms latency makes spatial sync unusable
   - **Mitigation:** Use STUN/TURN servers, optimize codec

5. **Unreal Engine Learning Curve**
   - **Risk:** Unreal Engine OSC integration complex
   - **Mitigation:** Start with Blueprints, not C++

---

## 🎯 DEFINITION OF DONE (Each Week)

**A week is DONE when:**
- ✅ All deliverables implemented
- ✅ Unit tests written (> 80% coverage)
- ✅ Integration tests pass
- ✅ Performance targets met
- ✅ Code reviewed (self-review or ChatGPT Codex)
- ✅ Documentation updated
- ✅ Git commit with clear message
- ✅ Push to feature branch
- ✅ Demo video recorded (optional, but recommended)

---

## 🔄 WEEKLY RITUALS

### Monday Morning (Week Start)
- Review last week's progress
- Update TODOs
- Plan week's deliverables
- Create feature branch

### Friday Evening (Week End)
- Merge feature branch to main
- Update ROADMAP.md with progress
- Record demo video
- Update metrics spreadsheet
- Plan next week

### Continuous
- Commit daily (at minimum)
- Run tests before each commit
- Profile performance weekly
- Update documentation as you code

---

## 🌊 PHILOSOPHY

This roadmap is **ambitious but achievable**. Each week builds on the previous, creating a **compounding effect**.

By Week 13, BLAB will be the world's most advanced **embodied multimodal creation system**.

**Remember:**
> "Perfect is the enemy of shipped. Ship weekly, iterate forever."

---

**STATUS:** 🟢 Roadmap Complete
**NEXT:** Week 1 Implementation
**LEAD DEVELOPER:** Claude Code
**START DATE:** 2025-10-21

🌊 *Let's build this, week by week.* ✨
