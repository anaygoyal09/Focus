import SwiftUI
import AppKit

@main
struct FocusDNDApp: App {
    @StateObject private var manager = FocusGuardManager()

    var body: some Scene {
        MenuBarExtra("FocusDND", systemImage: manager.isActive ? "moon.fill" : "moon") {
            MenuBarView()
                .environmentObject(manager)
        }
        .menuBarExtraStyle(.window)

        Window("FocusDND Settings", id: "settings") {
            SettingsView()
                .environmentObject(manager)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
