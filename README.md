# Focus

Focus is a macOS menu bar app for protecting deep work time. It helps you start focus sessions, limit distracting apps, track how your day is being spent, and enforce boundaries with native macOS permissions.

The app is built with SwiftUI and AppKit, and runs as a lightweight menu bar utility.

## Download and try it

[Download Focus.dmg](https://raw.githubusercontent.com/anaygoyal09/Focus/main/dist/Focus.dmg)

When the link works, your browser should download a file named `Focus.dmg`. Open the DMG, then open `Focus.app`. Because this build is not codesigned, macOS may ask you to right-click the app and choose Open.

## What the app contains

### Menu bar focus control

- A menu bar extra with a compact Focus status view.
- A live indication of whether a timed focus session is active.
- A quick action to open the main Focus window.
- A quit action routed through the app's quit controller.

### Focus sessions

- Timed sessions with presets for 15, 25, 45, 60, 90, and 120 minutes.
- No-limit sessions for open-ended focus blocks.
- Block mode, where selected apps or websites are blocked.
- Allow mode, where selected apps or websites are allowed and other configured activity is restricted.
- A session builder for adding targets before starting.
- Active session details, including remaining time, targets, and tracked usage.
- Frontmost-app targeting, so the current app can be added without manually finding its bundle identifier.

### App blocking

- App targets are stored by bundle identifier.
- When a blocked app becomes frontmost during a focus session, Focus terminates it.
- Allow-list sessions can restrict non-browser apps that are not part of the allowed target list.

### Website blocking

- Website targets are normalized by domain.
- Domains match subdomains, so a target such as `example.com` also covers subdomains.
- Website rules can apply to any supported browser or to a specific browser.
- Supported browsers are detected from installed apps that declare HTTP/HTTPS handling and AppleScript support.
- Focus reads the active browser tab URL through macOS Automation.
- Blocked websites are redirected to a local "Blocked by Focus" page.
- Blocked pages include a five-minute snooze link using the app's `focusapp://snooze` URL scheme.

### Permissions

- Accessibility permission is requested so Focus can monitor the frontmost app.
- Browser Automation permission is requested per supported browser.
- The Permissions pane shows browser support and current Automation status.
- Built-in controls rescan browsers, open macOS Automation settings, reset Focus Automation permission, or force-reset AppleEvents permission when macOS gets stuck.
- Notification permission is requested for focus and limit alerts.

### Day Tracker

- Tracks today's app usage based on frontmost application time.
- Tracks today's website usage when a supported browser has Automation permission.
- Shows daily app limits in the menu bar popover.
- Shows usage stats for apps and websites.
- Groups lower-usage items into an "Others" row.
- Provides detail views for all apps and all websites.
- Includes search inside the detail views.
- Displays app icons and website favicons when available.
- Resets day usage at local midnight.

### Daily app limits

- Add app limits by searching installed apps.
- Add a limit manually with a bundle identifier and display name.
- Add the current frontmost app as a limit.
- Configure limits in five-minute increments from 5 minutes to 12 hours.
- Edit an existing limit from the tracked-apps list.
- Remove tracked app limits.
- Tracks remaining time for each limited app.
- Resets used time at local midnight.
- When a limit is reached, Focus shows a screen-edge warning overlay, posts a notification, and closes the limited app.

### Persistence

- Focus saves sessions, daily limits, settings, app usage, website usage, and the day-tracking anchor date.
- State is stored in the user's Application Support directory under `Focus/state.json`.

### App bundle tooling

- `Package.swift` defines the Swift package and `FocusApp` executable product.
- `create_app.sh` builds the release binary and assembles `Focus.app`.
- The bundle uses `Sources/Info.plist`.
- `Focus.iconset` contains the app icon sources.
- Codesigning is optional through `FOCUS_SIGN=1`.

## What has been verified

The project has been checked against the implemented Swift source so the README only describes features that exist in the app.

The release product builds successfully:

```sh
swift build --configuration release --product FocusApp
```

Verified result:

```text
Build of product 'FocusApp' complete
```

Runtime behavior that depends on macOS permissions, frontmost-app state, installed browsers, and AppleScript support still depends on the user's local system configuration. Website tracking and website blocking require Automation permission for the browser being used.

## Requirements

- macOS 26.0 or newer
- Swift 6.2 or newer
- Accessibility permission for app monitoring and enforcement
- Automation permission for supported browser tab URL reading
- Notification permission for alerts

## Build

Build the Swift package:

```sh
swift build --configuration release --product FocusApp
```

Create the `.app` bundle:

```sh
./create_app.sh
```

The bundled app is written to `Focus.app`.

To enable codesigning during bundling:

```sh
FOCUS_SIGN=1 ./create_app.sh
```

## Development notes

This project was built as a collaboration between Anay Goyal and AI-assisted development.

Anay worked on the app framework and the daily app limits. The rest of the implementation was produced with AI assistance, then checked against the codebase before publishing.
