import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var manager: FocusManager
    @Environment(\.openWindow) private var openWindow

    private var hasActiveFocus: Bool {
        manager.currentSession != nil || !manager.dailyLimits.isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                header

                DayTrackerView()
                    .environmentObject(manager)
                    .glassPopoverPanel()

                if let session = manager.currentSession {
                    activeSessionSection(session)
                } else {
                    emptySessionSection
                }

                actionsSection
            }
            .padding(10)
        }
        .frame(width: 300)
        .background(VisualEffectBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: hasActiveFocus ? "timer.circle.fill" : "timer")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(hasActiveFocus ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasActiveFocus ? "Focus Active" : "Focus Inactive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(manager.currentSession == nil ? "No timed session" : "Session running")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(12)
        .glassPopoverPanel(interactive: false)
    }

    private func activeSessionSection(_ session: FocusSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(session.mode.label) Session",
                      systemImage: session.mode == .block ? "hand.raised.fill" : "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(sessionTimeText(session))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if session.targets.isEmpty {
                Text("No targets added")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ForEach(session.targets) { target in
                    SessionTargetRow(target: target,
                                     seconds: session.usageByTarget[target.id, default: 0],
                                     browserName: browserName(for: target))
                }
            }
        }
        .glassPopoverPanel()
    }

    private var emptySessionSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.6))

            Text("No active focus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text("Open Focus to start a session")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassPopoverPanel()
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            MenuButton(title: "Open Focus", icon: "macwindow", shortcut: "⌘,") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(role: .destructive) {
                QuitController.shared.requestQuit()
            } label: {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("Quit")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .glassPopoverPanel()
    }

    private func sessionTimeText(_ session: FocusSession) -> String {
        guard let remaining = session.remaining else { return "No limit" }
        let totalSeconds = max(0, Int(remaining))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func browserName(for target: FocusTarget) -> String? {
        guard target.kind == .website,
              let browserID = target.browserBundleID,
              browserID != BrowserInfo.anyBrowserID else { return nil }
        return manager.installedBrowsers.first(where: { $0.bundleIdentifier == browserID })?.name
    }
}

struct SessionTargetRow: View {
    let target: FocusTarget
    let seconds: TimeInterval
    let browserName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.kind == .app ? "app.dashed" : "globe")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.tint(.accentColor.opacity(0.14)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(target.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(target.kind == .app ? "App" : "Website")
                    if let browserName {
                        Text("·")
                        Text(browserName)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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

struct AppLimitRow: View {
    let limit: DailyLimit

    private var remainingMinutes: Int {
        Int(limit.remaining / 60)
    }

    private var progress: Double {
        guard limit.dailyLimitSeconds > 0 else { return 0 }
        return min(1, limit.usedToday / limit.dailyLimitSeconds)
    }

    private var statusColor: Color {
        if remainingMinutes <= 5 { return .red }
        if remainingMinutes <= 15 { return .orange }
        return .green
    }

    private var timeBadgeFill: Color {
        if remainingMinutes <= 5 { return Color.red.opacity(0.14) }
        if remainingMinutes <= 15 { return Color.orange.opacity(0.14) }
        return Color.green.opacity(0.14)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(limit.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

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

            Text("\(remainingMinutes)m")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(timeBadgeFill)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var icon: NSImage {
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: limit.bundleIdentifier)?.path else {
            return NSWorkspace.shared.icon(forFile: "/Applications")
        }
        return NSWorkspace.shared.icon(forFile: path)
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private extension View {
    func glassPopoverPanel(interactive: Bool = true) -> some View {
        self
            .glassEffect(interactive ? .regular.interactive() : .regular,
                         in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
