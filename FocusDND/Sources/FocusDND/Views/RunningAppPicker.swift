import SwiftUI
import AppKit

struct RunningAppPicker: View {
    let onPick: (GuardedApp) -> Void

    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        Menu("Add Running App") {
            ForEach(runningApps, id: \.bundleIdentifier) { app in
                if let bundleId = app.bundleIdentifier {
                    Button(app.localizedName ?? bundleId) {
                        let name = app.localizedName ?? bundleId
                        onPick(GuardedApp(bundleIdentifier: bundleId, name: name))
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
