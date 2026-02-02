import SwiftUI
import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification delegate EARLY - this is critical
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                print("Notification permission granted: \(granted)")
                if let error = error {
                    print("Notification error: \(error)")
                }
            }
        }
    }
    
    // Show notifications even when app is in foreground - REQUIRED for menu bar apps
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appState = AppState()
    @StateObject var focusManager: FocusManager
    
    // We need to keep a reference to the blocker window to show/hide it
    @State var blockerWindow: NSWindow?
    
    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        _focusManager = StateObject(wrappedValue: FocusManager(appState: state))
    }
    
    var body: some Scene {
        // Menu Bar
        MenuBarExtra("Focus", systemImage: "timer") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(focusManager)
        }
        .menuBarExtraStyle(.window) // Uses the MenuBarView as a popover
        
        // Settings Window
        Window("Focus Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(focusManager)
                .onAppear {
                    // Show in Dock when Settings opens
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    // Hide from Dock when Settings closes
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { } // Remove New
        }
    }
}

// Extension to handle the Blocker Window logic via AppState changes
extension FocusApp {
    // This is a bit of a hack in SwiftUI App lifecycle to hook into state changes for window management
    // But since we have FocusManager as an Object, we can let IT handle the window creation using NSKit
    // So we don't need to do it here.
    // I put the logic in FocusManager.displayBlocker()
}

// We need to ensuring FocusManager can open a window.
// I will update FocusManager to manage the NSWindow directly.
