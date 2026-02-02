import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(appState.activeModeId != nil ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                
                Text(appState.activeModeId != nil ? "Focus Active" : "Focus Inactive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Active Mode Content
            if let activeId = appState.activeModeId,
               let mode = appState.focusModes.first(where: { $0.id == activeId }) {
                
                VStack(spacing: 0) {
                    // Mode name badge and Stop button
                    HStack {
                        Label(mode.name, systemImage: "target")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Stop") {
                            appState.activeModeId = nil
                            appState.saveData()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    // App list
                    ForEach(mode.apps) { app in
                        AppTimeRow(app: app)
                    }
                }
                
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No active focus")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if let firstMode = appState.focusModes.first {
                        Button("Start \(firstMode.name)") {
                            appState.activeModeId = firstMode.id
                            appState.saveData()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    } else {
                        Text("Open settings to start a session")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 24)
            }
            
            Divider()
                .padding(.top, 8)
            
            // Actions
            VStack(spacing: 2) {
                MenuButton(title: "Settings", icon: "gearshape", shortcut: "⌘,") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                MenuButton(title: "Quit Focus", icon: "power", shortcut: "⌘Q") {
                    appState.saveData()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .background(VisualEffectBackground())
    }
}

struct AppTimeRow: View {
    let app: TrackedApp
    
    private var remaining: Int {
        Int(app.timeRemaining / 60)
    }
    
    private var progress: Double {
        guard app.dailyTimeLimit > 0 else { return 0 }
        return min(1, app.timeUsedToday / app.dailyTimeLimit)
    }
    
    private var statusColor: Color {
        if remaining <= 5 { return .red }
        if remaining <= 15 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(app.name.prefix(1)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(statusColor)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Spacer()
            
            // Time remaining
            Text("\(remaining)m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let shortcut: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
                
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
