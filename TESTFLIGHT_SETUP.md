# TestFlight Setup - Automatisches iPhone Testing

Dieses Dokument erklärt, wie du BLAB automatisch via GitHub Actions bauen und auf dein iPhone über TestFlight installieren kannst - **OHNE lokales Xcode**!

## 🎯 Ziel

Code auf MacBook schreiben (VS Code) → Push zu GitHub → Automatischer Build → TestFlight auf iPhone

## ✅ Voraussetzungen

### 1. Apple Developer Account
- **Apple Developer Program** Mitgliedschaft ($99/Jahr)
- URL: https://developer.apple.com/programs/

### 2. App Store Connect Setup
- App ID erstellen
- Bundle Identifier: `com.vibrationalforce.blab` (oder eigene Domain)
- App in App Store Connect registrieren

### 3. GitHub Repository
- Du hast bereits: https://github.com/vibrationalforce/blab-ios-app
- GitHub Actions ist aktiviert (kostenlos für öffentliche Repos)

---

## 📋 Setup Schritte

### Schritt 1: Apple Developer Account Setup

**1.1. Apple Developer Account erstellen**
```
→ Gehe zu: https://developer.apple.com/programs/
→ Klicke auf "Enroll"
→ Zahle $99/Jahr
→ Verifiziere deine Identität (dauert 1-2 Tage)
```

**1.2. App ID erstellen**
```
→ Gehe zu: https://developer.apple.com/account/resources/identifiers/list
→ Klicke auf "+" (neue ID)
→ Wähle "App IDs" → "App"
→ Description: "BLAB Biofeedback Music"
→ Bundle ID: "com.vibrationalforce.blab"
→ Capabilities aktivieren:
   ✅ HealthKit
   ✅ Background Modes (Audio)
   ✅ Push Notifications (optional)
→ Klicke "Continue" → "Register"
```

**1.3. Provisioning Profile erstellen**
```
→ Gehe zu: https://developer.apple.com/account/resources/profiles/list
→ Klicke auf "+"
→ Wähle "iOS App Development" (für TestFlight später "App Store")
→ Wähle deine App ID: "com.vibrationalforce.blab"
→ Wähle dein Certificate
→ Wähle deine Devices (dein iPhone registrieren!)
→ Download das .mobileprovision file
```

---

### Schritt 2: App Store Connect Setup

**2.1. App erstellen**
```
→ Gehe zu: https://appstoreconnect.apple.com
→ Klicke "My Apps" → "+" → "New App"
→ Platforms: iOS
→ Name: BLAB
→ Primary Language: German (oder English)
→ Bundle ID: com.vibrationalforce.blab (wähle die erstellte ID)
→ SKU: blab-001 (eindeutige ID)
→ User Access: Full Access
```

**2.2. TestFlight aktivieren**
```
→ In App Store Connect → deine App → "TestFlight" Tab
→ Internal Testing Group erstellen (für dich selbst)
→ External Testing Group (optional, für Beta-Tester)
```

**2.3. App Store Connect API Key erstellen**
```
→ Gehe zu: https://appstoreconnect.apple.com/access/api
→ Klicke "Keys" → "Generate API Key"
→ Name: "GitHub Actions CI/CD"
→ Access: "App Manager"
→ WICHTIG: Download die .p8 Datei SOFORT (kann nur einmal heruntergeladen werden)
→ Notiere:
   - Key ID (z.B. ABC123XYZ)
   - Issuer ID (z.B. 12345678-1234-1234-1234-123456789012)
```

---

### Schritt 3: GitHub Secrets konfigurieren

**3.1. Secrets in GitHub Repository hinzufügen**
```
→ Gehe zu: https://github.com/vibrationalforce/blab-ios-app/settings/secrets/actions
→ Klicke "New repository secret"
```

**Secrets die du brauchst:**

| Secret Name | Wert | Wo finden? |
|-------------|------|------------|
| `APP_STORE_CONNECT_API_KEY` | Inhalt der .p8 Datei | App Store Connect API Keys |
| `APP_STORE_CONNECT_KEY_ID` | Key ID (z.B. ABC123XYZ) | App Store Connect API Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID (UUID) | App Store Connect API Keys |
| `CODE_SIGN_IDENTITY` | "iPhone Distribution" | Developer Portal |
| `PROVISIONING_PROFILE` | Name des Profils | Developer Portal → Profiles |

**3.2. Beispiel: API Key Secret hinzufügen**
```bash
# Öffne die .p8 Datei und kopiere den Inhalt
cat ~/Downloads/AuthKey_ABC123XYZ.p8

# Füge den KOMPLETTEN Inhalt (inkl. -----BEGIN/END-----) als Secret hinzu
→ GitHub → Settings → Secrets → New secret
→ Name: APP_STORE_CONNECT_API_KEY
→ Value: [paste .p8 content]
```

---

### Schritt 4: Xcode Project Setup (einmalig mit Xcode)

**WICHTIG:** Du brauchst EINMALIG Zugriff auf einen Mac mit Xcode, um das Projekt richtig zu konfigurieren.

**Option A: Eigener Mac mit Xcode (empfohlen)**
```bash
# Auf einem Mac mit Xcode:
cd ~/blab-ios-app
open Package.swift  # Öffnet in Xcode

# In Xcode:
→ File → New → Project
→ iOS → App
→ Product Name: Blab
→ Team: [Wähle dein Developer Team]
→ Bundle Identifier: com.vibrationalforce.blab
→ Interface: SwiftUI
→ Language: Swift

# Importiere deine existierenden Swift Files
→ Drag & Drop alle .swift files aus Sources/Blab/
→ Signing & Capabilities → Automatically manage signing ✅
```

**Option B: Mac Mini Cloud Rental (1 Stunde)**
```
MacStadium: https://www.macstadium.com
MacInCloud: https://www.macincloud.com

→ Miete 1 Stunde Mac Mini (~$1)
→ Remote Desktop via VNC
→ Installiere Xcode
→ Setup wie in Option A
→ Export Xcode project
```

**Option C: Freund/Apple Store (kostenlos)**
```
→ Gehe zum Apple Store oder frage einen Freund mit Mac
→ Bringe USB Stick mit deinem Code
→ Setup wie in Option A (15 Minuten)
→ Export Xcode project zurück auf USB
```

---

### Schritt 5: GitHub Actions aktivieren

**5.1. Workflow Files prüfen**

Du hast bereits 2 Workflow Files:

1. **`.github/workflows/ios-build-simple.yml`**
   - Für Development (kein Code Signing)
   - Baut für iOS Simulator
   - Läuft bei jedem Push

2. **`.github/workflows/ios-build.yml`**
   - Für TestFlight Deployment
   - Benötigt Secrets (siehe Schritt 3)
   - Läuft nur bei Push zu `main`

**5.2. Workflow aktivieren**
```bash
# Committen und pushen
cd ~/blab-ios-app
git add .github/workflows/
git commit -m "Add GitHub Actions workflows for CI/CD"
git push origin main

# Auf GitHub prüfen
→ https://github.com/vibrationalforce/blab-ios-app/actions
→ Du solltest einen laufenden Workflow sehen
```

**5.3. Ersten Build triggern**
```
→ Gehe zu: https://github.com/vibrationalforce/blab-ios-app/actions
→ Wähle "iOS Build & Test" Workflow
→ Klicke "Run workflow" → "Run workflow"
→ Warte 5-10 Minuten für ersten Build
```

---

### Schritt 6: TestFlight auf iPhone installieren

**6.1. TestFlight App installieren**
```
→ Öffne App Store auf deinem iPhone
→ Suche "TestFlight"
→ Installiere die offizielle Apple TestFlight App
```

**6.2. Dich selbst als Tester hinzufügen**
```
→ Gehe zu: https://appstoreconnect.apple.com
→ Deine App → TestFlight
→ Internal Testing → "+" → Add tester
→ Gebe deine Apple ID Email ein
→ Du bekommst eine Email mit Einladung
```

**6.3. BLAB auf iPhone installieren**
```
→ Öffne TestFlight Email auf iPhone
→ Klicke "View in TestFlight"
→ TestFlight öffnet sich
→ Klicke "Install" / "Installieren"
→ App wird installiert (wie normale App)
→ Öffne BLAB vom Home Screen
```

---

## 🔄 Täglicher Workflow

### Development auf MacBook (VS Code)

```bash
# 1. Code schreiben
code ~/blab-ios-app

# 2. Changes committen
git add .
git commit -m "Add new feature: XYZ"

# 3. Zu GitHub pushen
git push origin develop

# 4. GitHub Actions baut automatisch
# Warte 5-10 Minuten

# 5. Wenn Build erfolgreich → merge zu main für TestFlight
git checkout main
git merge develop
git push origin main

# 6. GitHub Actions deployed zu TestFlight (10-15 Minuten)

# 7. Auf iPhone: TestFlight öffnen → Update installieren
```

### Auf iPhone testen

```
1. Öffne TestFlight App
2. BLAB App → "Update" (wenn neue Version)
3. Teste die neue Version
4. Feedback direkt in TestFlight geben (optional)
```

---

## 📊 GitHub Actions Logs ansehen

**Wo?**
```
→ https://github.com/vibrationalforce/blab-ios-app/actions
→ Klicke auf einen Workflow Run
→ Klicke auf "Build and Test iOS App" Job
→ Sieh alle Build Schritte und Logs
```

**Build Status Badge hinzufügen** (optional)
```markdown
# In README.md:
![iOS Build](https://github.com/vibrationalforce/blab-ios-app/workflows/iOS%20Build%20%26%20Test/badge.svg)
```

---

## 🐛 Troubleshooting

### Problem: "Code signing failed"
```
→ Prüfe GitHub Secrets (Schritt 3)
→ Prüfe ob Provisioning Profile noch gültig ist
→ Prüfe ob Certificate noch gültig ist (max. 1 Jahr)
```

### Problem: "Build failed - no such module"
```
→ Prüfe Package.swift (alle dependencies vorhanden?)
→ Prüfe ob swift package resolve funktioniert
→ GitHub Actions Log ansehen für Details
```

### Problem: "TestFlight build not appearing"
```
→ Warte 10-20 Minuten (Processing dauert)
→ Prüfe App Store Connect → TestFlight → Builds
→ Wenn "Processing" → warten
→ Wenn "Invalid Binary" → Logs ansehen
```

### Problem: "Invalid Binary - Missing Compliance"
```
→ App Store Connect → deine App → App Information
→ Export Compliance → "No encryption" (wenn zutreffend)
→ Oder füge NSAppTransportSecurity in Info.plist hinzu
```

---

## 💰 Kosten Übersicht

| Service | Kosten | Notizen |
|---------|--------|---------|
| **Apple Developer Program** | $99/Jahr | Pflicht für TestFlight |
| **GitHub Actions** | KOSTENLOS | 2000 Minuten/Monat für öffentliche Repos |
| **App Store Connect** | INKLUSIVE | Mit Developer Account |
| **TestFlight** | KOSTENLOS | Bis zu 10.000 Tester |
| **Mac Cloud (optional)** | $1/Stunde | Nur für initiales Xcode Setup |

**Total: $99/Jahr** (nur Apple Developer Account)

---

## 🚀 Nächste Schritte

### Level 1: Basic Setup ✅
- [x] iOS 15+ Kompatibilität
- [x] GitHub Actions Workflows erstellt
- [ ] Apple Developer Account erstellt
- [ ] App in App Store Connect registriert

### Level 2: TestFlight Setup 🎯
- [ ] Secrets in GitHub konfiguriert
- [ ] Erstes Xcode Project Setup (einmalig)
- [ ] Erster TestFlight Build
- [ ] App auf iPhone installiert

### Level 3: Automatisierung 🔥
- [ ] Auto-Deploy bei Push zu `main`
- [ ] Versioning automatisiert
- [ ] Beta-Tester einladen
- [ ] Feedback-Loop etablieren

---

## 📚 Weitere Ressourcen

**Apple Dokumentation:**
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [TestFlight Beta Testing](https://developer.apple.com/testflight/)
- [Code Signing Guide](https://developer.apple.com/support/code-signing/)

**GitHub Actions:**
- [iOS CI/CD Best Practices](https://docs.github.com/en/actions/deployment/deploying-xcode-applications)
- [Secrets Management](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

**Community:**
- [SwiftUI Reddit](https://reddit.com/r/SwiftUI)
- [iOS Dev Discord](https://discord.gg/ios)

---

## ✨ Zusammenfassung

Nach diesem Setup kannst du:

1. ✅ **Code auf MacBook schreiben** (VS Code, kein Xcode nötig)
2. ✅ **Push zu GitHub** → Automatischer Build
3. ✅ **TestFlight Deployment** → Automatisch bei Push zu `main`
4. ✅ **Auf iPhone testen** → TestFlight App öffnen → Update
5. ✅ **Feedback geben** → Direkt in TestFlight oder GitHub Issues

**Bottom Line:** Du brauchst Xcode nur EINMAL für initiales Setup, danach alles automatisch! 🎉
