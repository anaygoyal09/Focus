# Focus

Focus is a macOS menu bar app for protecting deep work time. It can run timed focus sessions, block or allow selected apps and websites, track daily usage, and enforce daily limits.

## Features

- Menu bar status popover with the current focus state.
- Timed focus sessions with block-list or allow-list modes.
- App and website targets, including browser-aware website tracking.
- Daily app and website usage totals.
- Daily limits with reset and rollover behavior.
- Optional password prompt for ending sessions or quitting.
- macOS Accessibility, Automation, and notification permission checks.

## Requirements

- macOS 26.0 or newer
- Swift 6.2 or newer

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

## Permissions

Focus needs macOS permissions to enforce limits and inspect browser tab URLs:

- Accessibility, for monitoring and controlling active apps.
- Automation, for reading supported browser tabs.
- Notifications, for focus and limit alerts.

These permissions are requested from inside the app when needed.
