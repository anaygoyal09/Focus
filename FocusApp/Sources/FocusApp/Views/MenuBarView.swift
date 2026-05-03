import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var focusManager: FocusManager
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill((appState.activeModeId != nil || appState.activeSession != nil) ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                
                Text((appState.activeModeId != nil || appState.activeSession != nil) ? "Focus Active" : "Focus Inactive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Active Session Content
            if let session = appState.activeSession {
                VStack(spacing: 0) {
                    HStack {
                        Label("\(session.mode.title) Session", systemImage: session.mode == .block ? "hand.raised.fill" : "checkmark.shield.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(sessionTimeText(session))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(session.targets) { target in
                        SessionTargetRow(target: target, seconds: session.usageByTarget[usageKey(for: target), default: 0])
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
                    
                    Text("Open settings to start a session")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 24)
            }

            dailyAppLimitsSection
            
            Divider()
                .padding(.top, 8)
            
            // Actions
            VStack(spacing: 2) {
                // Test Notification Button - prominent orange
                Button(action: {
                    focusManager.sendTestNotification()
                }) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .frame(width: 16)
                        
                        Text("Test Notification")
                            .font(.system(size: 13))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                
                MenuButton(title: "Settings", icon: "gearshape", shortcut: "⌘,") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .background(VisualEffectBackground())
    }

    @ViewBuilder
    private var dailyAppLimitsSection: some View {
        if !appState.focusModes.isEmpty {
            VStack(spacing: 0) {
                Divider()
                    .padding(.top, appState.activeSession == nil ? 0 : 8)

                HStack {
                    Label("Daily App Limits", systemImage: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                ForEach(appState.focusModes) { mode in
                    DailyModeMenuRow(
                        mode: mode,
                        isActive: appState.activeModeId == mode.id,
                        toggle: {
                            appState.activeModeId = appState.activeModeId == mode.id ? nil : mode.id
                            appState.saveData()
                        }
                    )
                }

                if let activeId = appState.activeModeId,
                   let mode = appState.focusModes.first(where: { $0.id == activeId }) {
                    if mode.apps.isEmpty {
                        Text("No apps added to \(mode.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(mode.apps) { app in
                                AppTimeRow(app: app)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func sessionTimeText(_ session: FocusSession) -> String {
        guard let remaining = session.timeRemaining else { return "No limit" }
        let totalSeconds = max(0, Int(remaining))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func usageKey(for target: FocusTarget) -> String {
        switch target.kind {
        case .app:
            return "app:\(target.bundleIdentifier ?? target.name)"
        case .website:
            return "website:\(target.browserBundleIdentifier ?? "any"):\(target.domain ?? target.name)"
        }
    }
}

struct DailyModeMenuRow: View {
    let mode: FocusMode
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? .green : .secondary.opacity(0.65))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("\(mode.apps.count) app\(mode.apps.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(isActive ? "On" : "Off")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isActive ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((isActive ? Color.green : Color.gray).opacity(0.13))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? Color.green.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

struct SessionTargetRow: View {
    let target: FocusTarget
    let seconds: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.kind == .app ? "app.dashed" : "globe")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(target.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(target.kind == .app ? "App" : "Website")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(Int(seconds / 60))m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
