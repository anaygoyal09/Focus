# Focus

<p align="center">
  <img src="FocusApp/Focus.app/Contents/Resources/AppIcon.icns" alt="Focus App Icon" width="128" height="128">
</p>

<p align="center">
  <strong>A lightweight macOS menu bar app to help you stay focused by tracking and limiting app usage.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#requirements">Requirements</a> •
  <a href="#building-from-source">Building from Source</a>
</p>

---

## Features

- **🎯 Focus Modes** — Create custom focus modes for different contexts (Work, Study, Social Media detox, etc.)
- **⏱️ Time Tracking** — Automatically tracks how long you spend in each configured app
- **⏰ Time Limits** — Set daily time limits for distracting apps
- **🔔 Smart Notifications** — Get warned at multiple intervals as you approach your limit (30min, 15min, 5min, 1min, etc.)
- **🚫 App Blocking** — When time's up, the app is force-quit and a blocker screen appears
- **🔒 Password Protection** — Optional password to prevent bypassing the blocker
- **📊 Menu Bar Widget** — See your remaining time at a glance from the menu bar
- **🌙 Lightweight** — Lives quietly in your menu bar, hidden from the Dock

## Installation

### Download

1. Download the latest `Focus.dmg` from the [Releases](https://github.com/anaygoyal/Focus/releases) page
2. Open the DMG file
3. Drag **Focus.app** to your **Applications** folder
4. Launch Focus from your Applications folder or Spotlight

> **Note:** On first launch, you may need to right-click the app and select "Open" to bypass Gatekeeper, as the app is not notarized.

### Granting Permissions

Focus needs permission to monitor running applications:

1. Go to **System Preferences** → **Privacy & Security** → **Accessibility**
2. Click the lock icon to make changes
3. Add **Focus** to the list and enable it

## Usage

### Getting Started

1. Click the **timer icon** in your menu bar to open Focus
2. Click **Settings** to open the configuration window
3. Create or edit a **Focus Mode** (e.g., "Work")
4. Add apps you want to track by clicking the **+** button
5. Set a daily time limit for each app
6. **Activate** the focus mode to start tracking

### Menu Bar

The menu bar icon shows:
- **Green dot** — Focus mode is active
- **Gray dot** — No focus mode active

Click the icon to see:
- Current focus mode status
- Time remaining for each tracked app
- Quick access to Settings

### When Time Runs Out

When you exceed your time limit for an app:
1. The app is automatically closed
2. A blocker window appears
3. If you set a password, you'll need to enter it to dismiss the blocker
4. The app remains blocked until the next day (usage resets at midnight)

## Requirements

- **macOS 13.0** (Ventura) or later
- Apple Silicon or Intel Mac

## Building from Source

### Prerequisites

- Xcode 15.0 or later
- Swift 5.9 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/anaygoyal/Focus.git
cd Focus/FocusApp

# Build with Swift Package Manager
swift build -c release

# The built executable will be in .build/release/FocusApp
```

### Creating the App Bundle

The pre-built `Focus.app` bundle is located in `FocusApp/Focus.app`. To update it with a new build:

```bash
# Build release
swift build -c release

# Copy executable to app bundle
cp .build/release/FocusApp Focus.app/Contents/MacOS/FocusApp
```

### Release DMG Automation

- Pushing a tag that starts with `v` (for example, `v1.2.3`) runs `.github/workflows/release-dmg.yml`.
- That workflow builds the app, packages `Focus.app` into `Focus.dmg`, and uploads the DMG to the matching GitHub Release.
- You can also run the workflow manually with **Run workflow** and provide an existing tag.
- The DMG is unsigned/not notarized unless signing credentials are configured separately.

## Privacy

Focus runs entirely locally on your Mac. No data is sent to any external servers. Your usage data is stored locally in your Documents folder.

## License

This project is open source. You are free to use, modify, and distribute this software without restriction.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

<p align="center">
  Made with ❤️ for productivity
</p>
