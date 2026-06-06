import AppKit
import SwiftUI

// MARK: - Sidebar

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case focusSession
    case permissions
    case dailyLimits

    var id: String { rawValue }
    var title: String {
        switch self {
        case .focusSession: return "Focus Session"
        case .permissions: return "Permissions"
        case .dailyLimits: return "Daily Limits"
        }
    }
    var systemImage: String {
        switch self {
        case .focusSession: return "timer"
        case .permissions: return "lock.shield"
        case .dailyLimits: return "hourglass"
        }
    }
}

// MARK: - Main container

struct SettingsView: View {
    @EnvironmentObject var manager: FocusManager
    @State private var selection: SidebarSection? = .focusSession

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Focus") {
                    ForEach(SidebarSection.allCases) { s in
                        NavigationLink(value: s) {
                            Label(s.title, systemImage: s.systemImage)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch selection ?? .focusSession {
                case .focusSession: FocusSessionPane()
                case .permissions:  PermissionsPane()
                case .dailyLimits:  DailyLimitsPane()
                }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

// MARK: - Focus Session pane

struct FocusSessionPane: View {
    @EnvironmentObject var manager: FocusManager

    @State private var mode: FocusMode = .block
    @State private var duration: FocusDuration = .timed(minutes: 25)
    @State private var targetInput: String = ""
    @State private var selectedBrowserID: String = BrowserInfo.anyBrowserID
    @State private var draftTargets: [FocusTarget] = []
    @State private var showEndPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let s = manager.currentSession {
                    runningCard(session: s)
                } else {
                    builderCard
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Focus Session")
        .sheet(isPresented: $showEndPrompt) {
            PasswordPromptView(title: "End Focus Session",
                               message: "Enter password to end the session.",
                               verify: { manager.verifyEndSessionPassword($0) },
                               onSuccess: { manager.endSession() })
        }
    }

    // Running

    @ViewBuilder
    private func runningCard(session: FocusSession) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Session active", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                    Spacer()
                    Text(modeLabel(session.mode)).font(.subheadline).foregroundStyle(.secondary)
                }
                if let remaining = session.remaining {
                    Text(formatRemaining(remaining))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("No limit").font(.title3).foregroundStyle(.secondary)
                }
                Divider()
                Text("Targets").font(.subheadline).foregroundStyle(.secondary)
                chips(for: session.targets, removable: false)
                Divider()
                Text("Usage").font(.subheadline).foregroundStyle(.secondary)
                ForEach(session.targets) { t in
                    HStack {
                        Text(t.displayName)
                        Spacer()
                        Text(formatRemaining(session.usageByTarget[t.id] ?? 0))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }.font(.callout)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        if manager.settings.endSessionPasswordHash != nil { showEndPrompt = true }
                        else { manager.endSession() }
                    } label: {
                        Label("End Session", systemImage: "stop.circle.fill")
                    }
                    .controlSize(.large)
                }
            }
            .padding(8)
        }
        .glassyIfAvailable()
    }

    // Builder

    private var builderCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("New Session").font(.headline)
                    Spacer()
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mode").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $mode) {
                            ForEach(FocusMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $duration) {
                            ForEach(FocusDuration.presets, id: \.self) { d in
                                Text(d.displayName).tag(d)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Target").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("App bundle id or website (e.g. twitter.com)", text: $targetInput)
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $selectedBrowserID) {
                            ForEach(manager.installedBrowsers) { b in
                                Text(b.name).tag(b.bundleIdentifier)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Button {
                            addTargetFromInput()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(targetInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            addFrontmostAppAsTarget()
                        } label: {
                            Label("Frontmost", systemImage: "macwindow.on.rectangle")
                        }
                    }
                }

                if !draftTargets.isEmpty {
                    chips(for: draftTargets, removable: true)
                }

                Divider()
                HStack {
                    Spacer()
                    Button {
                        manager.startSession(mode: mode, duration: duration, targets: draftTargets)
                        draftTargets.removeAll()
                        targetInput = ""
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(draftTargets.isEmpty)
                }
            }
            .padding(8)
        }
        .glassyIfAvailable()
    }

    private func addTargetFromInput() {
        let raw = targetInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let kind: FocusTargetKind = looksLikeDomain(raw) ? .website : .app
        let target: FocusTarget
        if kind == .website {
            let norm = manager.normalizeDomain(raw)
            target = FocusTarget(kind: .website, value: norm, displayName: norm,
                                 browserBundleID: selectedBrowserID)
        } else {
            target = FocusTarget(kind: .app, value: raw, displayName: raw)
        }
        draftTargets.append(target)
        targetInput = ""
    }

    private func addFrontmostAppAsTarget() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier, bid != "com.anaygoyal.focus" else { return }
        let name = app.localizedName ?? bid
        draftTargets.append(FocusTarget(kind: .app, value: bid, displayName: name))
    }

    private func looksLikeDomain(_ s: String) -> Bool {
        if s.contains("/") { return true }
        if s.contains(".") && !s.hasPrefix("com.") && !s.hasPrefix("org.") && !s.hasPrefix("net.") {
            return true
        }
        return false
    }

    @ViewBuilder
    private func chips(for targets: [FocusTarget], removable: Bool) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(targets) { t in
                HStack(spacing: 6) {
                    Image(systemName: t.kind == .website ? "globe" : "app.badge")
                    Text(t.displayName).lineLimit(1)
                    if t.kind == .website, let bid = t.browserBundleID,
                       let b = manager.installedBrowsers.first(where: { $0.bundleIdentifier == bid }) {
                        Text("·").foregroundStyle(.tertiary)
                        Text(b.name).foregroundStyle(.secondary).font(.caption)
                    }
                    if removable {
                        Button {
                            draftTargets.removeAll { $0.id == t.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2)))
            }
        }
    }

    private func modeLabel(_ m: FocusMode) -> String {
        m == .block ? "Block mode" : "Allow mode"
    }

    private func formatRemaining(_ s: TimeInterval) -> String {
        let i = Int(s)
        let h = i / 3600, m = (i % 3600) / 60, sec = i % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Permissions pane

struct PermissionsPane: View {
    @EnvironmentObject var manager: FocusManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    HStack {
                        Image(systemName: "accessibility")
                            .font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility").font(.headline)
                            Text(manager.accessibilityGranted ? "Granted" : "Needed to monitor the frontmost app.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.accessibilityGranted {
                            Label("Allowed", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                        } else {
                            Button("Request") { manager.requestAccessibility() }
                                .buttonStyle(.borderedProminent)
                        }
                    }.padding(6)
                }.glassyIfAvailable()

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Browser Automation").font(.headline)
                            Spacer()
                            Button {
                                manager.scanBrowsers()
                            } label: {
                                Label("Rescan", systemImage: "arrow.clockwise")
                            }
                            Button {
                                manager.openAutomationSettings()
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                            }
                            Button {
                                Task { await manager.resetAutomationTCC() }
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise.circle")
                            }
                            Button {
                                Task { await manager.resetAllAppleEventsTCC() }
                            } label: {
                                Label("Force Reset", systemImage: "exclamationmark.arrow.circlepath")
                            }
                            .help("Reset macOS Automation permissions for all apps (nuclear). Use only if normal reset doesn't take effect.")
                        }
                        Text("If a row stays at Denied after Request, click Open Settings and toggle Focus on under the browser, or click Force Reset and try again.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ForEach(manager.installedBrowsers.filter { $0.bundleIdentifier != BrowserInfo.anyBrowserID }) { b in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: b.path))
                                    .resizable().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.name).font(.callout)
                                    Text(b.bundleIdentifier).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusBadge(for: manager.automationStatus[b.bundleIdentifier] ?? .needsPermission)
                                Button {
                                    manager.scanBrowsers()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }.help("Refresh")
                                Button {
                                    manager.requestAutomation(for: b)
                                } label: {
                                    Text("Request")
                                }
                                .disabled(!b.supportsTabAutomation)
                            }
                            .padding(.vertical, 2)
                        }
                    }.padding(6)
                }.glassyIfAvailable()
            }
            .padding(20)
        }
        .navigationTitle("Permissions")
        .onAppear { manager.refreshAccessibility(); manager.scanBrowsers() }
    }

    @ViewBuilder
    private func statusBadge(for s: AutomationStatus) -> some View {
        let (icon, tint): (String, Color) = {
            switch s {
            case .allowed: return ("checkmark.seal.fill", .green)
            case .denied: return ("xmark.octagon.fill", .red)
            case .unsupported: return ("minus.circle", .secondary)
            case .opening, .waitingForPrompt, .resetting: return ("hourglass", .orange)
            case .failed: return ("exclamationmark.triangle.fill", .orange)
            case .needsPermission: return ("lock.fill", .secondary)
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(s.label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Daily limits pane

struct DailyLimitsPane: View {
    @EnvironmentObject var manager: FocusManager
    @State private var newBundleID: String = ""
    @State private var newName: String = ""
    @State private var newMinutes: Int = 30
    @State private var appSearchQuery: String = ""
    @State private var appSearchResults: [InstalledAppRecord] = []
    @State private var appSearchDebounce: Task<Void, Never>?
    @State private var appSearchBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add Limit").font(.headline)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Search installed apps").font(.caption).foregroundStyle(.secondary)
                            TextField("Type an app name…", text: $appSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: appSearchQuery) { _, newValue in
                                    scheduleAppSearch(newValue)
                                }
                            if appSearchBusy, !appSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Searching…").font(.caption).foregroundStyle(.secondary)
                                }
                            } else if !appSearchResults.isEmpty {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(appSearchResults) { app in
                                            Button {
                                                applySearchedApp(app)
                                            } label: {
                                                HStack(spacing: 10) {
                                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                                        .resizable()
                                                        .frame(width: 26, height: 26)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(app.displayName)
                                                            .foregroundStyle(.primary)
                                                            .multilineTextAlignment(.leading)
                                                        Text(app.bundleIdentifier)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                            .multilineTextAlignment(.leading)
                                                    }
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 4)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            Divider()
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        HStack {
                            TextField("App bundle id (e.g. com.tinyspeck.slackmacgap)", text: $newBundleID)
                                .textFieldStyle(.roundedBorder)
                            TextField("Display name", text: $newName)
                                .textFieldStyle(.roundedBorder).frame(width: 160)
                            Stepper(value: $newMinutes, in: 5...720, step: 5) {
                                Text("\(newMinutes) min").monospacedDigit().frame(width: 70, alignment: .leading)
                            }
                            Button {
                                let name = newName.isEmpty ? newBundleID : newName
                                manager.addDailyLimit(bundleID: newBundleID,
                                                      displayName: name,
                                                      seconds: TimeInterval(newMinutes * 60))
                                newBundleID = ""; newName = ""
                            } label: {
                                Label("Add", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        HStack {
                            Button {
                                manager.addFrontmostAppAsLimit(seconds: TimeInterval(newMinutes * 60))
                            } label: {
                                Label("Add Frontmost App", systemImage: "macwindow.on.rectangle")
                            }
                            Spacer()
                        }
                    }.padding(6)
                }.glassyIfAvailable()

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tracked Apps").font(.headline)
                        if manager.dailyLimits.isEmpty {
                            Text("No daily limits configured.").font(.caption).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(manager.dailyLimits) { l in
                                limitRow(l)
                            }
                        }
                    }.padding(6)
                }.glassyIfAvailable()
            }.padding(20)
        }
        .navigationTitle("Daily Limits")
    }

    private func scheduleAppSearch(_ raw: String) {
        appSearchDebounce?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            appSearchResults = []
            appSearchBusy = false
            return
        }
        appSearchBusy = true
        appSearchDebounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            let found = await InstalledAppCatalog.shared.search(trimmed)
            guard !Task.isCancelled else { return }
            appSearchResults = found
            appSearchBusy = false
        }
    }

    private func applySearchedApp(_ app: InstalledAppRecord) {
        appSearchDebounce?.cancel()
        newBundleID = app.bundleIdentifier
        newName = app.displayName
        appSearchQuery = ""
        appSearchResults = []
        appSearchBusy = false
    }

    @ViewBuilder
    private func limitRow(_ l: DailyLimit) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: pathForBundle(l.bundleIdentifier) ?? "/Applications"))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(l.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(l.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Int(l.dailyLimitSeconds/60)) min/day")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    
                    Stepper("", value: Binding(
                        get: { Int(l.dailyLimitSeconds / 60) },
                        set: { newMinutes in
                            manager.addDailyLimit(bundleID: l.bundleIdentifier, displayName: l.displayName, seconds: TimeInterval(newMinutes * 60))
                        }
                    ), in: 5...720, step: 5)
                    .labelsHidden()
                    .controlSize(.small)
                }
                
                Text("Remaining: \(Int(l.remaining/60)) min")
                    .font(.system(size: 11))
                    .foregroundStyle(l.remaining <= 300 ? Color.red : Color.secondary)
                    .monospacedDigit()
            }
            .padding(.trailing, 4)
            
            Button(role: .destructive) {
                withAnimation {
                    manager.removeDailyLimit(l.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }


    private func pathForBundle(_ bid: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid)?.path
    }
}

// MARK: - Helpers

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxWidth {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// Liquid Glass styling — soft fallback on older SDKs.
extension View {
    @ViewBuilder
    func glassyIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            self
        }
    }
}
