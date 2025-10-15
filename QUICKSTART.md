# BLAB - Quick Start Guide

This guide will help you build and install the Blab app on your iPhone **without needing the full Xcode application**.

## ✅ Prerequisites (Already Done!)

- [x] macOS with Command Line Tools
- [x] Swift 5.7+ installed
- [x] VS Code with Claude Code extension

## 🚀 Quick Start (3 Easy Steps)

### Step 1: Check Homebrew Installation Status

Homebrew is currently installing in the background. Check status:

```bash
# Check if Homebrew is ready
brew --version
```

**If you see a version number:** ✅ Homebrew is ready!
**If not:** Wait a few more minutes for installation to complete.

---

### Step 2: Install Build Tools (5 minutes)

Once Homebrew is ready, run:

```bash
cd /Users/michpack/BlabStudio
make setup
```

This installs:
- `xcodegen` - Generates Xcode project from project.yml
- `ios-deploy` - Deploys apps to iPhone via USB
- `libimobiledevice` - Communicates with iOS devices

---

### Step 3: Build & Install (One Command!)

```bash
make run
```

This will:
1. Generate the Xcode project
2. Build the app
3. Install it on your connected iPhone

**Note:** Make sure your iPhone is:
- Connected via USB cable
- Unlocked
- Set to "Trust This Computer"

---

## 📋 All Available Commands

```bash
make help         # Show all available commands
make generate     # Generate Xcode project
make build        # Build the app only
make install      # Install on iPhone only
make run          # Build + Install
make clean        # Remove build files
make test         # Run unit tests
```

Or use the build script:

```bash
./build.sh        # Alternative build script
```

---

## 🔧 Troubleshooting

### Problem: "Command Line Tools not found"

```bash
xcode-select --install
```

---

### Problem: "No iPhone detected"

1. **Connect iPhone via USB**
2. **Unlock iPhone**
3. **Tap "Trust" on the prompt**
4. **Check connection:**

```bash
idevice_id -l
```

Should show your iPhone's UUID.

---

### Problem: "Code signing failed"

You need to set your Apple Developer Team ID:

1. **Get your Team ID:**
   - Go to: https://developer.apple.com/account
   - Sign in with your Apple ID (free account works!)
   - Go to "Membership" section
   - Copy your Team ID (looks like: ABCDE12345)

2. **Edit project.yml:**
   - Find line: `DEVELOPMENT_TEAM: ""`
   - Replace with: `DEVELOPMENT_TEAM: "YOUR_TEAM_ID"`

3. **Rebuild:**

```bash
make clean
make run
```

---

### Problem: "Developer Mode not enabled" (iOS 16+)

On your iPhone:
1. Settings → Privacy & Security
2. Developer Mode → **ON**
3. Restart iPhone

---

### Problem: "App crashes on launch"

Check microphone permissions:
1. iPhone Settings → Privacy → Microphone
2. Enable for "Blab"

---

## 📱 Testing the App

After installation, you should see:

1. **App Icon** - "Blab" on your home screen
2. **Permission Dialog** - "Allow microphone access?" → Tap **Allow**
3. **Main Screen:**
   - Dark purple/blue gradient background
   - "BLAB" title at top
   - Particle visualization in center
   - Large green "Start" button at bottom

4. **Try it:**
   - Tap the green button → turns red
   - Speak or make sounds
   - Watch the audio level bars react
   - See the particle animation respond
   - Tap red button to stop

---

## 🎯 Next Steps

Once the app is working, you can:

### 1. Customize Colors

Edit [ContentView.swift](Sources/Blab/ContentView.swift):

```swift
// Change background gradient (lines ~25-30)
Color(red: 0.05, green: 0.05, blue: 0.15),  // Your custom color here
```

### 2. Modify Particles

Edit [ParticleView.swift](Sources/Blab/ParticleView.swift):

```swift
// Change particle colors (lines ~35-40)
Color.cyan.opacity(0.6),  // Change to your preferred color
```

### 3. Adjust Audio Sensitivity

Edit [MicrophoneManager.swift](Sources/Blab/MicrophoneManager.swift):

```swift
// Line ~135 - adjust the multiplier (currently 20)
let normalizedLevel = min(rms * 20, 1.0)  // Try 10 or 30
```

After any changes, run:

```bash
make run
```

---

## 🆘 Need Help?

### Check logs during build:

```bash
make build 2>&1 | tee build.log
```

### Check device connection:

```bash
idevice_id -l              # List connected devices
ideviceinfo                # Show device info
idevicepair pair           # Re-pair device
```

### Clean everything and start fresh:

```bash
make clean
rm -rf Blab.xcodeproj
make run
```

---

## 📚 File Structure

```
BlabStudio/
├── Package.swift           # Swift package config
├── project.yml             # Xcode project template
├── Makefile                # Build automation
├── build.sh                # Alternative build script
├── README.md               # Full documentation
├── QUICKSTART.md           # This file
├── .gitignore              # Git ignore rules
└── Sources/Blab/
    ├── BlabApp.swift       # App entry point
    ├── ContentView.swift   # Main UI
    ├── MicrophoneManager.swift  # Audio capture
    └── ParticleView.swift  # Visualization
```

---

## 🎉 Success Checklist

- [ ] Homebrew installed
- [ ] Build tools installed (`make setup`)
- [ ] iPhone connected and trusted
- [ ] App builds successfully
- [ ] App installs on iPhone
- [ ] App launches without crashing
- [ ] Microphone permission granted
- [ ] Audio visualization works

---

**Ready to build? Start with:**

```bash
cd /Users/michpack/BlabStudio
make setup
```

Then:

```bash
make run
```

🚀 **Let's create some music!**
