import AppKit
import SwiftUI
import UserNotifications

@main
struct FocusAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = FocusManager.shared

    var body: some Scene {
        Window("Focus", id: "main") {
            SettingsView()
                .environmentObject(manager)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Focus") { QuitController.shared.requestQuit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(manager)
        } label: {
            Image(systemName: "scope")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        FocusManager.shared.bootstrap()
        FocusManager.shared.requestNotificationAuthorization()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            FocusManager.shared.handleSnoozeURL(url)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
