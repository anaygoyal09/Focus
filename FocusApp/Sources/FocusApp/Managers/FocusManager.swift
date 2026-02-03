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
    
    // Track last notification sent to avoid spamming
    private var lastNotificationTime: Date = Date.distantPast
    // Track which thresholds we've already notified for each app
    private var notifiedThresholds: [String: Set<TimeInterval>] = [:]
    
    init(appState: AppState) {
        self.appState = appState
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Run loop every 1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCurrentActivity()
        }
    }
    
    private func checkCurrentActivity() {
        // Check for daily reset (in case app runs past midnight)
        appState.checkDailyReset()
        
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
        blockerWindow?.close()
        blockerWindow = nil
    }
}
