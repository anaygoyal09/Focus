import Foundation
import AppKit
import UserNotifications
import Combine
import SwiftUI
import ApplicationServices

private struct BrowserSnapshot {
    let bundleIdentifier: String
    let browserName: String
    let url: URL?
    let domain: String?
}

class FocusManager: NSObject, ObservableObject, NSWindowDelegate {
    @Published var appState: AppState
    private var timer: Timer?
    private var workspace = NSWorkspace.shared
    private var cancellables = Set<AnyCancellable>()
    private var blockerWindow: NSWindow?
    private let monitoringInterval: TimeInterval = 2.0
    private let permissionRefreshInterval: TimeInterval = 30.0
    private let browserURLRefreshInterval: TimeInterval = 3.0
    
    // Track last notification sent to avoid spamming
    private var lastNotificationTime: Date = Date.distantPast
    // Track which thresholds we've already notified for each app
    private var notifiedThresholds: [String: Set<TimeInterval>] = [:]
    // Track the last frontmost app to detect switches
    private var lastFrontmostBundleId: String?
    private var lastPermissionRefresh: Date = .distantPast
    private var browserSnapshotCache: [String: (snapshot: BrowserSnapshot, checkedAt: Date)] = [:]
    private let supportedBrowserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "org.mozilla.firefox"
    ]
    
    init(appState: AppState) {
        self.appState = appState
        super.init()
        startMonitoring()
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            self?.checkCurrentActivity()
        }
    }
    
    private func checkCurrentActivity() {
        // Check for daily reset (in case app runs past midnight)
        appState.checkDailyReset()
        refreshPermissionStatusIfNeeded()
        checkActiveSession()
        
        guard let activeModeIndex = appState.focusModes.firstIndex(where: { $0.id == appState.activeModeId }) else {
            // No active mode, nothing to track
            return
        }
        
        guard let frontApp = workspace.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            return
        }
        
        if bundleId == Bundle.main.bundleIdentifier { return } // Don't block ourselves
        
        // Find if this app is in the current mode
        if let appIndex = appState.focusModes[activeModeIndex].apps.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            var trackedApp = appState.focusModes[activeModeIndex].apps[appIndex]
            
            // Notify when switching to a tracked app
            if bundleId != lastFrontmostBundleId {
                lastFrontmostBundleId = bundleId
                let minutes = Int(trackedApp.timeRemaining / 60)
                sendNotification(
                    title: "⏱ \(trackedApp.name) is tracked",
                    body: "You have \(minutes) min left. Check your time and close if not needed."
                )
            }
            
            // Increment usage
            trackedApp.timeUsedToday += monitoringInterval
            
            // Update State
            appState.focusModes[activeModeIndex].apps[appIndex] = trackedApp
            
            // Check Limits
            checkTimeLimit(for: trackedApp, appObject: frontApp)
            
            // Save periodically
            if Int(trackedApp.timeUsedToday) % 60 < Int(monitoringInterval) {
                 appState.saveData()
            }
        } else {
            // Switched to an untracked app — reset so next switch to a tracked app triggers notification
            lastFrontmostBundleId = bundleId
        }
    }

    private func checkActiveSession() {
        guard var session = appState.activeSession else { return }

        if session.isRunning == false {
            stopSession()
            sendNotification(title: "Focus complete", body: "Your focus session has ended.")
            return
        }

        guard let frontApp = workspace.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else {
            return
        }

        let browser = browserSnapshot(for: frontApp)
        let matchingTarget = session.targets.first { target in
            targetMatches(target, bundleId: bundleId, browser: browser)
        }
        let matchingTargetKey = matchingTarget.map(targetUsageKey(for:))

        if let matchingTarget {
            session.usageByTarget[targetUsageKey(for: matchingTarget), default: 0] += monitoringInterval
        }

        var shouldBlock: Bool
        let blockedName: String
        let blockedKey: String

        switch session.mode {
        case .block:
            shouldBlock = matchingTarget != nil
            blockedName = matchingTarget?.displayName ?? frontApp.localizedName ?? "This app"
            blockedKey = matchingTargetKey ?? blockedActivityKey(bundleId: bundleId, browser: browser, fallbackName: blockedName)
        case .allow:
            shouldBlock = !session.targets.isEmpty && matchingTarget == nil
            blockedName = browser?.domain ?? frontApp.localizedName ?? "This app"
            blockedKey = blockedActivityKey(bundleId: bundleId, browser: browser, fallbackName: blockedName)
        }

        if let snoozedUntil = session.snoozedUntilByTarget[blockedKey], snoozedUntil > Date() {
            shouldBlock = false
        }

        if shouldBlock {
            session.lastBlockedTargetName = blockedName
            session.lastBlockedTargetKey = blockedKey
            appState.activeSession = session
            appState.saveSessionData()
            handleSessionBlock(name: blockedName, key: blockedKey, appObject: frontApp, browser: browser)
        } else {
            appState.activeSession = session
            if Int(session.usageByTarget.values.reduce(0, +)) % 30 == 0 {
                appState.saveSessionData()
            }
        }
    }

    func startSession(duration: TimeInterval?, mode: FocusSessionMode, targets: [FocusTarget]) {
        let now = Date()
        appState.activeSession = FocusSession(
            mode: mode,
            duration: duration,
            startedAt: now,
            endsAt: duration.map { now.addingTimeInterval($0) },
            targets: targets,
            usageByTarget: [:],
            snoozedUntilByTarget: [:]
        )
        appState.saveSessionData()
    }

    func stopSession() {
        appState.activeSession = nil
        appState.saveSessionData()
        dismissBlocker()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        var status = PermissionStatus()
        status.accessibility = AXIsProcessTrusted()
        status.browserAutomation = appState.permissionStatus.browserAutomation

        appState.permissionStatus = status
        lastPermissionRefresh = Date()
    }

    private func refreshPermissionStatusIfNeeded() {
        guard Date().timeIntervalSince(lastPermissionRefresh) >= permissionRefreshInterval else { return }
        refreshPermissionStatus()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "focusapp", url.host == "snooze" else { return }
        snoozeCurrentBlock(minutes: 3)
    }

    func snoozeCurrentBlock(minutes: Double) {
        guard var session = appState.activeSession,
              let blockedKey = session.lastBlockedTargetKey else {
            dismissBlocker()
            return
        }

        session.snoozedUntilByTarget[blockedKey] = Date().addingTimeInterval(minutes * 60)
        appState.activeSession = session
        appState.isBlocking = false
        appState.currentBlockedApp = nil
        appState.saveSessionData()

        blockerWindow?.close()
        blockerWindow = nil
    }

    private func handleSessionBlock(name: String, key: String, appObject: NSRunningApplication, browser: BrowserSnapshot?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let blockedApp = TrackedApp(
                bundleIdentifier: appObject.bundleIdentifier ?? name,
                name: name,
                dailyTimeLimit: 0,
                timeUsedToday: 0,
                lastUsageCheck: nil
            )

            self.appState.currentBlockedApp = blockedApp
            self.appState.isBlocking = true

            if let browser {
                self.showBrowserBlockPage(appObject, blockedName: name, blockedKey: key, browser: browser)
            } else {
                appObject.terminate()
            }
        }
    }

    private func targetMatches(_ target: FocusTarget, bundleId: String, browser: BrowserSnapshot?) -> Bool {
        switch target.kind {
        case .app:
            return target.bundleIdentifier == bundleId
        case .website:
            guard let browser,
                  let domain = browser.domain,
                  let targetDomain = target.domain?.lowercased() else {
                return false
            }

            if let browserBundleIdentifier = target.browserBundleIdentifier,
               browserBundleIdentifier != browser.bundleIdentifier {
                return false
            }

            return domain == targetDomain || domain.hasSuffix(".\(targetDomain)")
        }
    }

    private func targetUsageKey(for target: FocusTarget) -> String {
        switch target.kind {
        case .app:
            return "app:\(target.bundleIdentifier ?? target.name)"
        case .website:
            return "website:\(target.browserBundleIdentifier ?? "any"):\(target.domain ?? target.name)"
        }
    }

    private func blockedActivityKey(bundleId: String, browser: BrowserSnapshot?, fallbackName: String) -> String {
        if let browser {
            return "blocked:website:\(browser.bundleIdentifier):\(browser.domain ?? fallbackName)"
        }
        return "blocked:app:\(bundleId)"
    }

    private func browserSnapshot(for app: NSRunningApplication) -> BrowserSnapshot? {
        guard let bundleId = app.bundleIdentifier,
              supportedBrowserBundleIds.contains(bundleId) else {
            return nil
        }

        if let cached = browserSnapshotCache[bundleId],
           Date().timeIntervalSince(cached.checkedAt) < browserURLRefreshInterval {
            return cached.snapshot
        }

        let browserName = app.localizedName ?? browserDisplayName(bundleId)
        let urlString = frontmostBrowserURL(bundleIdentifier: bundleId)
        let url = urlString.flatMap(URL.init(string:))
        let domain = url?.host?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        appState.permissionStatus.browserAutomation[bundleId] = url != nil

        let snapshot = BrowserSnapshot(bundleIdentifier: bundleId, browserName: browserName, url: url, domain: domain)
        browserSnapshotCache[bundleId] = (snapshot, Date())
        return snapshot
    }

    private func frontmostBrowserURL(bundleIdentifier: String) -> String? {
        let scriptBody: String

        switch bundleIdentifier {
        case "com.apple.Safari":
            scriptBody = "tell application id \"\(bundleIdentifier)\" to if (count of windows) > 0 then return URL of current tab of front window"
        case "org.mozilla.firefox":
            return nil
        default:
            scriptBody = "tell application id \"\(bundleIdentifier)\" to if (count of windows) > 0 then return URL of active tab of front window"
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptBody) else { return nil }
        let descriptor = script.executeAndReturnError(&error)

        if let error {
            print("[Browser] Failed to read URL for \(bundleIdentifier): \(error)")
            return nil
        }

        return descriptor.stringValue
    }

    private func showBrowserBlockPage(_ app: NSRunningApplication, blockedName: String, blockedKey: String, browser: BrowserSnapshot) {
        guard let bundleId = app.bundleIdentifier else {
            app.terminate()
            return
        }

        let pageURL = browserBlockPageURL(blockedName: blockedName, blockedKey: blockedKey)

        let scriptBody: String
        switch bundleId {
        case "com.apple.Safari":
            scriptBody = "tell application id \"\(bundleId)\" to if (count of windows) > 0 then set URL of current tab of front window to \"\(pageURL)\""
        case "org.mozilla.firefox":
            app.terminate()
            return
        default:
            scriptBody = "tell application id \"\(bundleId)\" to if (count of windows) > 0 then set URL of active tab of front window to \"\(pageURL)\""
        }

        var error: NSDictionary?
        NSAppleScript(source: scriptBody)?.executeAndReturnError(&error)
        browserSnapshotCache[bundleId] = nil
        if let error {
            print("[Browser] Failed to blank tab for \(bundleId): \(error)")
            app.terminate()
        }
    }

    private func browserBlockPageURL(blockedName: String, blockedKey: String) -> String {
        let cleanName = blockedName.replacingOccurrences(of: " in Safari", with: "")
            .replacingOccurrences(of: " in Chrome", with: "")
            .replacingOccurrences(of: " in Arc", with: "")
            .replacingOccurrences(of: " in Microsoft Edge", with: "")
            .replacingOccurrences(of: " in Brave", with: "")

        let escapedName = htmlEscaped(cleanName)
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedName) blocked by Focus</title>
        <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        html, body { width: 100%; height: 100%; margin: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif;
          background:
            radial-gradient(circle at 50% 48%, rgba(255,255,255,.08), transparent 27rem),
            linear-gradient(135deg, #040404 0%, #181818 45%, #050505 100%);
          color: rgba(255,255,255,.9);
          overflow: hidden;
        }
        main {
          min-height: 100%;
          display: grid;
          grid-template-rows: 1fr auto 1fr;
          align-items: center;
          justify-items: center;
          padding: 64px 32px;
        }
        .center { text-align: center; align-self: end; }
        .icon {
          width: 52px; height: 52px; border-radius: 14px; margin: 0 auto 28px;
          display: grid; place-items: center;
          background: linear-gradient(145deg, #20a063, #0f603d);
          box-shadow: 0 14px 40px rgba(0,0,0,.35), inset 0 1px rgba(255,255,255,.22);
        }
        .icon span { font-size: 28px; transform: translateY(-1px); }
        h1 {
          margin: 0;
          font-size: clamp(28px, 3vw, 44px);
          line-height: 1.15;
          letter-spacing: 0;
          font-weight: 700;
          color: rgba(255,255,255,.86);
        }
        a.snooze {
          margin-top: 44px;
          display: inline-flex;
          align-items: center;
          gap: 10px;
          padding: 11px 18px;
          border-radius: 8px;
          background: rgba(255,255,255,.14);
          color: rgba(255,255,255,.9);
          text-decoration: none;
          font-size: 17px;
          font-weight: 600;
        }
        .hint {
          align-self: end;
          color: rgba(255,255,255,.28);
          font-size: 16px;
          font-weight: 500;
          padding-bottom: 22px;
          text-align: center;
        }
        </style>
        </head>
        <body>
        <main>
          <div></div>
          <section class="center">
            <div class="icon"><span>✓</span></div>
            <h1>\(escapedName) has been blocked by Focus</h1>
            <a class="snooze" href="focusapp://snooze?target=\(urlEscaped(blockedKey))">↺ Snooze for 3 minutes</a>
          </section>
          <p class="hint">End your focus session to access this page.</p>
        </main>
        </body>
        </html>
        """

        return "data:text/html;charset=utf-8,\(urlEscaped(html))"
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func urlEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func browserDisplayName(_ bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome", "com.google.Chrome.canary": return "Chrome"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        case "org.mozilla.firefox": return "Firefox"
        default: return "Browser"
        }
    }
    
    private func checkTimeLimit(for app: TrackedApp, appObject: NSRunningApplication) {
        let remaining = app.timeRemaining
        
        // 1. Check for Blocking
        if remaining <= 0 {
            // Trigger Block
            handleBlocking(for: app, appObject: appObject)
        } else {
            // 2. Check for Notifications
            checkAndSendNotification(remaining: remaining, appName: app.name)
        }
    }
    
    private func handleBlocking(for app: TrackedApp, appObject: NSRunningApplication) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set state
            self.appState.currentBlockedApp = app
            self.appState.isBlocking = true
            
            // Force quit the blocked app
            appObject.terminate()
        }
    }
    
    private func showBlockerWindow() {
        let promptView = PasswordPromptView()
            .environmentObject(self)
        
        let hostingController = NSHostingController(rootView: promptView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .fullSizeContentView] // Standard style
        window.title = "Time's Up"
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.level = .floating // Keep on top
        window.center()
        window.isReleasedWhenClosed = false
        
        // Enable close button
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        window.delegate = self

        self.blockerWindow = window
        window.orderFrontRegardless()
    }
    
    private func checkAndSendNotification(remaining: TimeInterval, appName: String) {
        for threshold in appState.warningThresholds {
            // Check if we're at this threshold (within 1 second)
            if abs(remaining - threshold) <= monitoringInterval {
                // Check if we already notified for this threshold for this app
                if notifiedThresholds[appName]?.contains(threshold) == true {
                    return
                }
                
                // Mark as notified
                if notifiedThresholds[appName] == nil {
                    notifiedThresholds[appName] = []
                }
                notifiedThresholds[appName]?.insert(threshold)
                
                let message: String
                if threshold >= 60 {
                    let minutes = Int(threshold / 60)
                    message = "\(minutes) minute\(minutes == 1 ? "" : "s") remaining for \(appName)"
                } else {
                    message = "\(Int(threshold)) seconds remaining for \(appName)!"
                }
                
                let urgency = threshold <= 60 ? "⚠️ " : ""
                sendNotification(title: "\(urgency)Time Alert", body: message)
                break
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        print("[Notification] Sending: \(title) - \(body)")
        
        // Use NSUserNotification - works for unsigned apps, no authorization needed
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.hasActionButton = false
            
            NSUserNotificationCenter.default.deliver(notification)
            print("[Notification] NSUserNotification delivered")
        }
    }
    
    // For testing/debugging
    func sendTestNotification() {
        print("[Test] Sending test notification...")
        
        // Use NSUserNotification directly - no authorization needed
        DispatchQueue.main.async { [weak self] in
            let notification = NSUserNotification()
            notification.title = "Focus Test"
            notification.informativeText = "Notifications are working! 🎉"
            notification.soundName = NSUserNotificationDefaultSoundName
            
            NSUserNotificationCenter.default.deliver(notification)
            print("[Test] Notification delivered via NSUserNotificationCenter")
            
            // Also show in-app alert as confirmation
            self?.showInAppNotification(title: "Focus Test", body: "Notification sent! Check your screen.")
        }
    }
    
    private func showInAppNotification(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func extendTime(minutes: Double) {
        guard let activeModeIndex = appState.focusModes.firstIndex(where: { $0.id == appState.activeModeId }),
              let blockedApp = appState.currentBlockedApp,
              let appIndex = appState.focusModes[activeModeIndex].apps.firstIndex(where: { $0.id == blockedApp.id }) else {
            return
        }
        
        // Add time
        appState.focusModes[activeModeIndex].apps[appIndex].dailyTimeLimit += (minutes * 60)
        
        // Reset notified thresholds for this app so they can be notified again
        notifiedThresholds[blockedApp.name] = nil
        
        // Clear blocking state
        appState.isBlocking = false
        appState.currentBlockedApp = nil
        
        appState.saveData()
        
        // Close window
        blockerWindow?.close()
        blockerWindow = nil
    }
    
    func dismissBlocker() {
        // Clear blocking state
        appState.isBlocking = false
        appState.currentBlockedApp = nil

        // Close window
        if let window = blockerWindow {
            blockerWindow = nil
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Ensure state is cleared if the window is closed via the title bar.
        appState.isBlocking = false
        appState.currentBlockedApp = nil
        blockerWindow = nil
    }

    func dismissQuitPrompt() {
        // Close the quit prompt window
        NSApp.keyWindow?.close()
    }

    func performQuit() {
        NSApp.terminate(nil)
    }
}
