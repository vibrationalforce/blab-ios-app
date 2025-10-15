# BLAB - Biofeedback Music Creation App

A revolutionary iOS app that transforms your voice and biofeedback into musical art using real-time audio processing and visualization.

## Project Overview

Blab is designed for **iPhone 16 Pro Max** (iOS 16+) and uses SwiftUI for the interface and AVFoundation for audio processing.

### Current Features (v0.1)

- Real-time microphone input capture
- Audio level visualization
- Beautiful particle visualization system
- Dark-themed modern UI
- Microphone permission handling

### Planned Features

- Advanced particle systems responding to audio frequency
- Music generation from voice patterns
- Biofeedback integration (heart rate, motion sensors)
- Audio effects and filters
- Recording and playback
- Export to audio files
- Social sharing

## Project Structure

```
BlabStudio/
├── Package.swift                    # Swift Package Manager configuration
├── Sources/
│   └── Blab/
│       ├── BlabApp.swift           # App entry point
│       ├── ContentView.swift       # Main UI interface
│       ├── MicrophoneManager.swift # Audio capture manager
│       └── ParticleView.swift      # Visualization component
├── .gitignore                       # Git ignore rules
└── README.md                        # This file
```

## File Descriptions

### BlabApp.swift
The main entry point of the app. Initializes the app, creates the MicrophoneManager, and sets up the dark theme.

### ContentView.swift
The main user interface. Contains:
- Beautiful gradient background
- Particle visualization
- Audio level meter
- Start/Stop recording button
- Status indicators

### MicrophoneManager.swift
Handles all audio-related functionality:
- Microphone permission requests
- Audio session configuration
- Real-time audio capture
- Audio level calculation (RMS)
- Audio buffer processing

### ParticleView.swift
Visual effects and animations:
- Pulsing center dot
- Rotating rings
- Particle system placeholder
- Smooth animations using SwiftUI

## How to Build

### Option 1: Xcode (Recommended)

1. **Open Terminal** and navigate to the BlabStudio folder
2. **Generate Xcode project:**
   ```bash
   swift package generate-xcodeproj
   ```
3. **Open the project:**
   ```bash
   open Blab.xcodeproj
   ```
4. **Select your iPhone 16 Pro Max** (or simulator) in Xcode
5. **Click the Play button** to build and run

### Option 2: Swift Package Manager

Build from command line:
```bash
cd BlabStudio
swift build
```

## Important: Info.plist Configuration

To run on a real device, you need to add microphone permissions to your Info.plist:

1. In Xcode, select your target
2. Go to the "Info" tab
3. Add this entry:
   - **Key:** `Privacy - Microphone Usage Description`
   - **Value:** `Blab needs microphone access to create music from your voice`

Or add this to your Info.plist file:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Blab needs microphone access to create music from your voice</string>
```

## How to Use the App

1. **Launch the app** on your iPhone
2. **Grant microphone permission** when prompted
3. **Tap the green button** to start recording
4. **Speak or make sounds** - watch the visualization react
5. **Tap the red button** to stop

## Technical Details

### Audio Processing
- **Sample Rate:** 48 kHz (default for iPhone)
- **Buffer Size:** 1024 samples
- **Level Calculation:** Root Mean Square (RMS)
- **Update Rate:** 20 Hz (50ms intervals)

### Requirements
- **iOS:** 16.0+
- **Swift:** 5.9+
- **Device:** iPhone 16 Pro Max (or any iPhone running iOS 16+)

## Future Development Roadmap

### Phase 1: Audio Enhancement (Current)
- [x] Basic microphone capture
- [x] Audio level visualization
- [ ] Frequency analysis (FFT)
- [ ] Pitch detection

### Phase 2: Music Generation
- [ ] MIDI note generation from voice
- [ ] Scale/key selection
- [ ] Rhythm detection
- [ ] Audio effects (reverb, delay, etc.)

### Phase 3: Biofeedback Integration
- [ ] Heart rate sensor integration
- [ ] Motion/accelerometer data
- [ ] Combine multiple biometric inputs
- [ ] Adaptive music generation

### Phase 4: Recording & Sharing
- [ ] Record sessions
- [ ] Export to audio files
- [ ] Share on social media
- [ ] Cloud storage integration

## Troubleshooting

### "Microphone permission denied"
- Go to Settings → Privacy → Microphone
- Enable permission for Blab

### "No audio detected"
- Check if your microphone is working in other apps
- Make sure you're speaking close to the microphone
- Try restarting the app

### Build errors
- Make sure you have Xcode 14+ installed
- Clean build folder: Product → Clean Build Folder
- Delete DerivedData folder

## Contributing

This is a personal project, but suggestions and feedback are welcome!

## License

Copyright © 2025 Blab Studio. All rights reserved.

---

**Built with** SwiftUI, AVFoundation, and creativity.
