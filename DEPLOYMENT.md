# 📱 BLAB - Deployment Guide

**VS Code First Development Workflow**

This guide explains how to develop BLAB in VS Code and deploy to your iPhone.

---

## 🎯 Development Philosophy: 95% VS Code + 5% Xcode

```
┌─────────────────────────────────┐
│  VS CODE (95% der Zeit)         │
│  • Code schreiben               │
│  • Features implementieren      │
│  • Tests schreiben              │
│  • Git operations               │
└─────────────────────────────────┘
              │
              ▼ (nur für Device Deploy)
┌─────────────────────────────────┐
│  XCODE (5% der Zeit)            │
│  • Code Signing Setup           │
│  • Build & Run auf iPhone       │
│  • Zurück zu VS Code!           │
└─────────────────────────────────┘
```

---

## 🚀 Quick Start

### Daily Development (in VS Code)

```bash
# Build the project
./build.sh

# Run tests
./test.sh

# Make changes, repeat
```

### Deploy to iPhone (once per week)

```bash
# Generate Xcode project and get instructions
./deploy.sh
```

---

## 📋 Detailed Workflow

### Phase 1: Setup (One-Time)

**1. Clone Repository**
```bash
git clone https://github.com/vibrationalforce/blab-ios-app.git
cd blab-ios-app
```

**2. Verify Swift Installation**
```bash
swift --version
# Should be Swift 5.7+
```

**3. Build in VS Code**
```bash
./build.sh
```

**4. Run Tests**
```bash
./test.sh
```

---

### Phase 2: Daily Development (VS Code)

**Write Code in VS Code:**
- Edit Swift files in `Sources/Blab/`
- Modern syntax highlighting
- IntelliSense (with SourceKit-LSP)
- Git integration

**Build & Test:**
```bash
# Quick build
./build.sh

# Clean build
./build.sh clean

# Release build
./build.sh release

# Run tests
./test.sh

# Verbose tests
./test.sh --verbose
```

**Commit Changes:**
```bash
git add .
git commit -m "Add new feature"
git push
```

---

### Phase 3: Deploy to iPhone (Xcode Touch)

**When to Deploy:**
- New features complete
- Major changes
- Testing on real device
- ~Once per week

**Step 1: Run Deploy Script**
```bash
./deploy.sh
```

This will:
1. ✅ Build the project
2. ✅ Generate Xcode project (`Blab.xcodeproj`)
3. ✅ Open Xcode automatically
4. ✅ Show deployment instructions

**Step 2: In Xcode (5 minutes)**

1. **Select Target:** Click "Blab" in project navigator
2. **Signing & Capabilities Tab:**
   - Team: Select your Apple ID
   - Bundle ID: `com.vibrationalforce.blab`
3. **Connect iPhone:** USB cable
4. **Select Device:** Product → Destination → iPhone 16 Pro Max
5. **Build & Run:** Press `Cmd+R`

**Step 3: On iPhone**

Grant permissions when prompted:
- ✅ Microphone (required)
- ✅ HealthKit (optional, for HRV)
- ✅ Motion (optional, for head tracking)

**Step 4: Return to VS Code**

Close Xcode, continue developing in VS Code!

---

## 🛠️ Build Scripts Reference

### `build.sh`

Standard build:
```bash
./build.sh
```

Clean build:
```bash
./build.sh clean
```

Release build:
```bash
./build.sh release
```

### `test.sh`

Run all tests:
```bash
./test.sh
```

Verbose output:
```bash
./test.sh --verbose
```

### `deploy.sh`

Generate Xcode project and deploy:
```bash
./deploy.sh
```

---

## 📁 Project Structure

```
blab-ios-app/
├── Package.swift              # Swift Package Manager config
├── Resources/
│   └── Info.plist            # iOS permissions & config
├── Sources/
│   └── Blab/
│       ├── BlabApp.swift     # App entry point
│       ├── ContentView.swift # Main UI
│       ├── MicrophoneManager.swift
│       ├── Audio/
│       │   ├── AudioEngine.swift
│       │   ├── DSP/
│       │   │   └── PitchDetector.swift
│       │   └── Effects/
│       │       └── BinauralBeatGenerator.swift
│       ├── Biofeedback/
│       │   └── HealthKitManager.swift
│       └── Views/
│           └── Components/
│               └── BioMetricsView.swift
├── Tests/
│   └── BlabTests/
├── build.sh                  # Build script
├── test.sh                   # Test script
├── deploy.sh                 # Deploy script
└── DEPLOYMENT.md            # This file
```

---

## 🔧 Troubleshooting

### Build Fails in VS Code

**Error: "Cannot find module"**
```bash
swift package resolve
./build.sh clean
./build.sh
```

**Error: "No such file or directory: Package.swift"**
```bash
# Make sure you're in the project root
cd blab-ios-app
./build.sh
```

### Xcode Issues

**Error: "No signing identity found"**
- Go to Xcode → Settings → Accounts
- Add your Apple ID
- Download certificates

**Error: "Untrusted Developer"**
- On iPhone: Settings → General → VPN & Device Management
- Trust your developer certificate

**Error: "Failed to prepare device for development"**
- Disconnect and reconnect iPhone
- Unlock iPhone
- Trust computer

### iPhone Issues

**App crashes on launch**
- Check Xcode console for errors
- Verify all permissions are granted
- Check Info.plist has required permissions

**No audio detected**
- Grant microphone permission
- Check microphone works in other apps
- Restart app

---

## 🎯 Best Practices

### DO ✅

- **Develop in VS Code** (95% of the time)
- **Use build scripts** (`./build.sh`, `./test.sh`)
- **Commit often** with meaningful messages
- **Test on real device** once per week
- **Keep Xcode project regenerated** (don't edit manually)

### DON'T ❌

- **Don't edit code in Xcode** (use VS Code!)
- **Don't commit Xcode project files** (.xcodeproj is gitignored)
- **Don't use Storyboards** (we use SwiftUI)
- **Don't rely on Xcode-specific features**

---

## 📱 Permissions Required

### Microphone (Required)
**Why:** Capture voice and breath for audio processing
**Key:** `NSMicrophoneUsageDescription`
**File:** `Resources/Info.plist`

### HealthKit (Optional)
**Why:** Read HRV for biofeedback-driven music
**Keys:** `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`
**File:** `Resources/Info.plist`

### Motion (Optional)
**Why:** Head tracking for 3D spatial audio
**Key:** `NSMotionUsageDescription`
**File:** `Resources/Info.plist`

### Bluetooth (Optional)
**Why:** Detect AirPods for spatial audio features
**Key:** `NSBluetoothAlwaysUsageDescription`
**File:** `Resources/Info.plist`

---

## 🔄 Update Workflow

### Scenario 1: New Swift File Added

**In VS Code:**
1. Create new file in `Sources/Blab/`
2. Write code
3. `./build.sh` (automatically includes new file)
4. `git commit -m "Add new feature"`

**No Xcode needed!** SPM auto-discovers source files.

### Scenario 2: New Dependency Added

**In VS Code:**
1. Edit `Package.swift`
2. Add dependency to `dependencies: []`
3. `swift package resolve`
4. `./build.sh`
5. Next Xcode deployment will include it

### Scenario 3: New Resource Added

**In VS Code:**
1. Add file to `Resources/`
2. SPM auto-processes it
3. `./build.sh`
4. Next Xcode deployment will include it

---

## 🎵 Development Tips

### Fast Iteration

1. **Make changes in VS Code**
2. **Build:** `./build.sh` (~5 seconds)
3. **Test:** `./test.sh` (~10 seconds)
4. **Repeat!**

### iPhone Testing

Only deploy to iPhone when:
- ✅ Feature is complete
- ✅ Tests pass
- ✅ Need device-specific testing
- ✅ Testing spatial audio / HRV

### Git Workflow

```bash
# Feature branch
git checkout -b feature/new-audio-effect

# Develop in VS Code
# ... make changes ...

# Build & test
./build.sh && ./test.sh

# Commit
git add .
git commit -m "Add reverb audio effect"

# Push
git push origin feature/new-audio-effect

# Create PR on GitHub
# Merge to main
```

---

## 📞 Support

**Issues:** https://github.com/vibrationalforce/blab-ios-app/issues

**Questions:**
- Check existing issues
- Create new issue with [Question] tag

---

## 🎉 Summary

**VS Code Development:**
```bash
./build.sh    # Build
./test.sh     # Test
git commit    # Save
```

**iPhone Deployment (weekly):**
```bash
./deploy.sh   # Generate Xcode project
# Open Xcode → Build & Run → Close Xcode
# Back to VS Code!
```

**That's it! 🚀**

Keep developing in VS Code, deploy to iPhone occasionally for testing.

---

**Built with** SwiftUI, AVFoundation, and ❤️ in VS Code.
