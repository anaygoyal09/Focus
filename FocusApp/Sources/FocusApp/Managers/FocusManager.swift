import Foundation
import AppKit
import UserNotifications
import Combine
import SwiftUI

class FocusManager: ObservableObject {
    @Published var appState: AppState
    private var timer: Timer?
    private var workspace = NSWorkspace.shared
    private var cancellables = Set<AnyCancellable>()
    private var blockerWindow: NSWindow?
    // Delegate moved to AppDelegate
    
    // Track last notification sent to avoid spamming
    private var lastNotificationTime: Date = Date.distantPast
    // Track which thresholds we've already notified for each app
    private var notifiedThresholds: [String: Set<TimeInterval>] = [:]
    
    init(appState: AppState) {
        self.appState = appState
        // Delegate setup handled in AppDelegate
        startMonitoring()
    }
    
    // Legacy support kept for reference or re-request
    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    private func startMonitoring() {
        // Run loop every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCurrentActivity()
            self?.updateMenuBar()
        }
    }

    private func updateMenuBar() {
        guard let activeMode = appState.focusModes.first(where: { $0.id == appState.activeModeId }) else {
            DispatchQueue.main.async {
                if self.appState.menuBarText != "" { self.appState.menuBarText = "" }
                if self.appState.menuBarIcon != "pawprint.fill" { self.appState.menuBarIcon = "pawprint.fill" }
            }
            return
        }

        // Look for Arc specifically as requested
        if let arcApp = activeMode.apps.first(where: { $0.name.localizedCaseInsensitiveContains("Arc") || $0.bundleIdentifier == "company.thebrowser.Browser" }) {
             let remaining = Int(arcApp.timeRemaining)
             let minutes = remaining / 60
             let seconds = remaining % 60
             
             let newText = String(format: "Arc: %d:%02d", minutes, seconds)
             DispatchQueue.main.async {
                 if self.appState.menuBarText != newText { self.appState.menuBarText = newText }
                 self.appState.menuBarIcon = "timer"
             }
        } else {
             // Fallback if Arc is not tracked but we are active
             DispatchQueue.main.async {
                 self.appState.menuBarText = ""
                 self.appState.menuBarIcon = "target"
             }
        }
    }
    
    private func checkCurrentActivity() {
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
            
            // Increment usage
            trackedApp.timeUsedToday += 1.0
            
            // Update State
            appState.focusModes[activeModeIndex].apps[appIndex] = trackedApp
            
            // Check Limits
            checkTimeLimit(for: trackedApp, appObject: frontApp)
            
            // Save periodically
            if Int(trackedApp.timeUsedToday) % 60 == 0 {
                 appState.saveData()
            }
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
            
            // Show Window if not already shown
            if self.blockerWindow == nil {
                self.showBlockerWindow()
            }
            
            // Bring Block Window to Front
            self.blockerWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showBlockerWindow() {
        let promptView = PasswordPromptView()
            .environmentObject(self)
        
        let hostingController = NSHostingController(rootView: promptView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .fullSizeContentView] // Minimal style
        window.title = "Time's Up"
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.level = .floating // Keep on top
        window.center()
        
        // Make it hard to close
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.blockerWindow = window
        window.orderFrontRegardless()
    }
    
    private func checkAndSendNotification(remaining: TimeInterval, appName: String) {
        for threshold in appState.warningThresholds {
            // Check if we're at this threshold (within 1 second)
            if abs(remaining - threshold) < 1.5 {
                // Check if we already notified for this threshold for this app
                let key = "\(appName)_\(Int(threshold))"
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
        print("Attempting to send notification: \(title) - \(body)")
        
        // 1. Try NSUserNotifications (Older API, often more reliable for non-notarized apps)
        let nsNotification = NSUserNotification()
        nsNotification.title = title
        nsNotification.informativeText = body
        // Suppress warning: 'NSUserNotificationDefaultSoundName' was deprecated in macOS 11.0
        nsNotification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(nsNotification)
        
        // 2. Try UNUserNotificationCenter (Newer API)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active 
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("UNNotification error: \(error)")
            } else {
                print("UNNotification scheduled successfully")
            }
        }
    }
    
    // For testing/debugging
    func sendTestNotification() {
        print("Sending test notification...")
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            print("Notification settings: \(settings)")
        }
        sendNotification(title: "Focus Test", body: "This is a test notification from Focus.")
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
}
