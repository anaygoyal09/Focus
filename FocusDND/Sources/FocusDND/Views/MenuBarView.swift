import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var manager: FocusGuardManager
    @Environment(\.openWindow) var openWindow

    private var remainingText: String {
        let minutes = max(0, manager.remainingSeconds) / 60
        let seconds = max(0, manager.remainingSeconds) % 60
        return String(format: "%02dm %02ds", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(manager.isActive ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(manager.isActive ? "Focus Active" : "Focus Inactive")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mode:")
                        .foregroundColor(.secondary)
                    Text(manager.config.filterMode.rawValue)
                    Spacer()
                }

                if manager.isActive {
                    HStack {
                        Text("Remaining:")
                            .foregroundColor(.secondary)
                        Text(remainingText)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(spacing: 6) {
                Button(manager.isActive ? "Stop Focus" : "Start Focus") {
                    manager.isActive ? manager.stopFocus() : manager.startFocus()
                }
                .buttonStyle(.borderedProminent)

                Button("Settings") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 10)

            Divider()
                .padding(.top, 8)

            Button("Quit") {
                manager.saveConfig()
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 10)
        }
        .frame(width: 280)
    }
}
