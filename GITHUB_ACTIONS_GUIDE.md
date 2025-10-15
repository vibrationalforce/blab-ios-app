# 🚀 Blab - GitHub Actions Cloud Build Guide

Diese Anleitung zeigt dir, wie du deine iOS App **kostenlos in der Cloud** bauen lässt!

## ✅ Was ist bereits fertig:

- ✅ Git Repository initialisiert
- ✅ GitHub Actions Workflow erstellt (`.github/workflows/build-ios.yml`)
- ✅ Alle Quelldateien bereit
- ✅ Build-Konfiguration fertig

---

## 🎯 Nächste Schritte (5-10 Minuten)

### **Schritt 1: GitHub Account (falls noch keiner da ist)**

Gehe zu: https://github.com/signup

- Email eingeben
- Passwort wählen
- Username wählen
- Account bestätigen (Check email)

**✅ Kostenlos!**

---

### **Schritt 2: GitHub CLI installieren (optional aber einfacher)**

**Falls Homebrew fertig ist:**
```bash
brew install gh
gh auth login
```

**Oder manuell auf GitHub.com:**
- Weiter zu Schritt 3

---

### **Schritt 3: Repository auf GitHub erstellen**

#### **Option A: Mit GitHub CLI (einfacher):**

```bash
cd /Users/michpack/BlabStudio

# Bei GitHub anmelden
gh auth login

# Repository erstellen
gh repo create blab-ios-app --public --source=. --remote=origin --push
```

Das macht alles automatisch!

---

#### **Option B: Manuell auf GitHub.com:**

1. **Gehe zu:** https://github.com/new

2. **Fülle aus:**
   - Repository name: `blab-ios-app`
   - Description: `Biofeedback Music Creation App for iOS`
   - Visibility: **Public** (damit GitHub Actions kostenlos ist)
   - **NICHT** "Initialize with README" anklicken (haben wir schon!)

3. **Klicke:** "Create repository"

4. **GitHub zeigt dir Commands:**
   ```bash
   git remote add origin https://github.com/DEIN_USERNAME/blab-ios-app.git
   git branch -M main
   git push -u origin main
   ```

5. **Im Terminal (VS Code unten):**
   ```bash
   cd /Users/michpack/BlabStudio

   # Füge deine GitHub URL ein (ersetze DEIN_USERNAME!)
   git remote add origin https://github.com/DEIN_USERNAME/blab-ios-app.git
   git branch -M main
   git add .
   git commit -m "Initial commit - Blab iOS App"
   git push -u origin main
   ```

   **Wenn es nach Login fragt:**
   - Username: dein GitHub username
   - Password: **Personal Access Token** (nicht dein normales Passwort!)
     - Token erstellen: https://github.com/settings/tokens
     - Klicke "Generate new token (classic)"
     - Wähle: `repo` (alle Checkboxen)
     - Kopiere den Token (nur einmal sichtbar!)

---

### **Schritt 4: Build in der Cloud starten**

**Auf GitHub.com:**

1. **Gehe zu deinem Repository:**
   https://github.com/DEIN_USERNAME/blab-ios-app

2. **Klicke auf den Tab:** **"Actions"** (oben)

3. **Du siehst:** "Build iOS App" Workflow

4. **Klicke:** "Run workflow" → "Run workflow"

5. **Warte 5-10 Minuten**
   - Du siehst Live-Logs der Build-Schritte
   - Wird gelb (läuft) → dann grün (fertig) ✅

---

### **Schritt 5: IPA herunterladen**

**Wenn der Build fertig ist (grünes Häkchen):**

1. **Klicke auf den Build-Lauf** (z.B. "Build iOS App #1")

2. **Scrolle runter zu:** "Artifacts"

3. **Download:** `Blab-iOS-App.zip`

4. **Entpacke die Zip-Datei**
   - Du bekommst: `Blab-unsigned.ipa`

---

### **Schritt 6: IPA auf iPhone installieren**

#### **Methode 1: Mit Apple Configurator (kostenlos)**

1. **Download Apple Configurator:**
   - App Store → "Apple Configurator"

2. **iPhone per USB verbinden**

3. **Apple Configurator öffnen**

4. **Dein iPhone erscheint**

5. **Ziehe die IPA-Datei** auf dein iPhone-Symbol

**⚠️ Wichtig:** iPhone muss im **Developer Mode** sein!
- Settings → Privacy & Security → Developer Mode → ON

---

#### **Methode 2: Mit Sideloadly (einfacher)**

1. **Download Sideloadly:**
   - https://sideloadly.io/

2. **Installiere Sideloadly**

3. **iPhone verbinden**

4. **Sideloadly öffnen:**
   - IPA auswählen: `Blab-unsigned.ipa`
   - Apple ID eingeben (deine normale Apple ID)
   - Klicke "Start"

5. **Auf iPhone:**
   - Settings → General → VPN & Device Management
   - Vertraue deinem Zertifikat

---

#### **Methode 3: Mit AltStore (automatisch)**

1. **Download AltStore:**
   - https://altstore.io/

2. **Installiere AltStore auf Mac & iPhone**

3. **Ziehe IPA in AltStore**

---

### **Schritt 7: App testen!**

**Auf deinem iPhone:**

1. **Developer Mode aktivieren** (iOS 16+):
   - Settings → Privacy & Security → Developer Mode → ON
   - iPhone neu starten

2. **Blab App öffnen**

3. **Microphone Permission gewähren**

4. **Tap Start Button und sprich!** 🎤

---

## 🔄 Updates / Änderungen machen

**Wenn du Code änderst:**

```bash
cd /Users/michpack/BlabStudio

# Änderungen committen
git add .
git commit -m "Beschreibung deiner Änderung"
git push

# GitHub baut automatisch die neue Version!
```

**Auf GitHub Actions Tab** siehst du den neuen Build.

---

## 🎨 Was du anpassen kannst

### **Farben ändern:**

Edit: `Sources/Blab/ContentView.swift`

```swift
// Zeile ~25-30: Hintergrund Gradient
Color(red: 0.05, green: 0.05, blue: 0.15),  // Deine Farbe hier
Color(red: 0.1, green: 0.05, blue: 0.2)     // Deine Farbe hier
```

### **Partikel-Farben:**

Edit: `Sources/Blab/ParticleView.swift`

```swift
// Zeile ~35-40
Color.cyan.opacity(0.6),  // Ändere zu deiner Farbe
```

### **Audio-Empfindlichkeit:**

Edit: `Sources/Blab/MicrophoneManager.swift`

```swift
// Zeile ~135
let normalizedLevel = min(rms * 20, 1.0)  // Versuche 10 oder 30
```

**Nach Änderungen:**
```bash
git add .
git commit -m "Farben angepasst"
git push
```

→ Neue Version wird automatisch gebaut!

---

## 🆘 Troubleshooting

### **Build failed (rotes X auf GitHub)**

Klicke auf den Build → Lies die Logs → Kopiere den Fehler

**Häufige Probleme:**

1. **"No such file"** → Datei fehlt, check ob alle Files committed sind
2. **"Swift version mismatch"** → In `Package.swift` auf 5.7 setzen (bereits gemacht)
3. **"Code signing failed"** → Normal bei unsigned builds

### **IPA installiert nicht auf iPhone**

1. **Developer Mode aktiviert?**
   - Settings → Privacy & Security → Developer Mode → ON

2. **iPhone vertraut dem Zertifikat?**
   - Settings → General → VPN & Device Management → Vertraue

3. **iOS Version zu alt?**
   - Blab braucht iOS 16+

### **"No artifacts uploaded"**

Build ist fehlgeschlagen. Check die Logs auf GitHub Actions.

---

## 📊 Build-Status verstehen

**Auf GitHub Actions Tab:**

- 🟡 **Gelb/Orange:** Build läuft gerade
- ✅ **Grün:** Build erfolgreich! IPA verfügbar
- ❌ **Rot:** Build fehlgeschlagen, Logs checken

**Build dauert:** 5-10 Minuten

---

## 💰 Kosten

- **GitHub Actions:** 2000 Minuten/Monat kostenlos für öffentliche Repos
- **Private Repos:** 500 Minuten/Monat kostenlos
- **Blab Build:** ~10 Minuten pro Build
- **→ Du kannst 200 Builds/Monat kostenlos machen!**

---

## 🎉 Fertig!

Du hast jetzt:
- ✅ Code auf GitHub
- ✅ Automatische Cloud-Builds
- ✅ IPA zum Download
- ✅ App auf iPhone installierbar

**Keine Xcode Installation nötig!**
**Kein Speicherplatz auf deinem Mac nötig!**
**Alles läuft in der Cloud!** ☁️

---

## 📚 Nützliche Links

- **Dein GitHub Repo:** https://github.com/DEIN_USERNAME/blab-ios-app
- **GitHub Actions Docs:** https://docs.github.com/en/actions
- **Apple Developer:** https://developer.apple.com/
- **Sideloadly:** https://sideloadly.io/
- **AltStore:** https://altstore.io/

---

**Viel Erfolg mit Blab!** 🎤🎵
