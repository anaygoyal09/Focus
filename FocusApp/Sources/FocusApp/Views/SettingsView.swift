import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var focusManager: FocusManager

    @State private var selectedDuration: SessionDuration = .noLimit
    @State private var selectedMode: FocusSessionMode = .block
    @State private var inputText: String = ""
    @State private var draftTargets: [FocusTarget] = []
    @State private var selectedBrowserBundleId: String = "com.apple.Safari"
    @State private var selectedDailyModeId: UUID?

    private let browsers: [(name: String, bundleId: String)] = [
        ("Safari", "com.apple.Safari"),
        ("Chrome", "com.google.Chrome"),
        ("Arc", "company.thebrowser.Browser"),
        ("Edge", "com.microsoft.edgemac"),
        ("Brave", "com.brave.Browser"),
        ("Firefox", "org.mozilla.firefox")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    activeSessionSummary
                    sessionBuilder
                    permissionsPanel
                    legacyModesPanel
                }
                .padding(24)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onAppear {
            focusManager.refreshPermissionStatus()
            if selectedDailyModeId == nil {
                selectedDailyModeId = appState.focusModes.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus")
                    .font(.system(size: 22, weight: .bold))
                Text("Start a timed app and website blocking session.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    @ViewBuilder
    private var activeSessionSummary: some View {
        if let session = appState.activeSession {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("\(session.mode.title) session running", systemImage: "timer")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(timeText(session.timeRemaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                    Button("End") {
                        focusManager.stopSession()
                    }
                    .buttonStyle(.bordered)
                }

                if !session.targets.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(session.targets) { target in
                            TargetChip(target: target) {}
                        }
                    }
                }
            }
            .panelStyle()
        }
    }

    private var sessionBuilder: some View {
        VStack(alignment: .leading, spacing: 18) {
            FormRow(title: "Duration") {
                Picker("", selection: $selectedDuration) {
                    ForEach(SessionDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FormRow(title: "Mode") {
                Picker("", selection: $selectedMode) {
                    ForEach(FocusSessionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: 8) {
                FormRow(title: selectedMode == .block ? "Block" : "Allow") {
                    HStack(spacing: 8) {
                        TextField(selectedMode == .block ? "What apps or websites do you want to block?" : "What apps or websites do you want to allow?", text: $inputText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addWebsiteTarget)

                        Picker("", selection: $selectedBrowserBundleId) {
                            ForEach(browsers, id: \.bundleId) { browser in
                                Text(browser.name).tag(browser.bundleId)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)

                        Button(action: addWebsiteTarget) {
                            Image(systemName: "globe.badge.chevron.backward")
                        }
                        .help("Add website")

                        Button(action: addFrontmostAppTarget) {
                            Image(systemName: "app.badge")
                        }
                        .help("Add frontmost app")
                    }
                }

                if !draftTargets.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(draftTargets) { target in
                            TargetChip(target: target) {
                                draftTargets.removeAll { $0.id == target.id }
                            }
                        }
                    }
                    .padding(.leading, 112)
                }
            }

            HStack {
                Spacer()
                Button("Start Focus Session") {
                    focusManager.startSession(
                        duration: selectedDuration.seconds,
                        mode: selectedMode,
                        targets: draftTargets
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftTargets.isEmpty)
            }
        }
        .panelStyle()
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.system(size: 15, weight: .semibold))

            PermissionRow(
                title: "Accessibility",
                detail: "Required to monitor the frontmost app and reliably enforce blocking.",
                isGranted: appState.permissionStatus.accessibility,
                actionTitle: "Request"
            ) {
                focusManager.requestAccessibilityPermission()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Browser Automation")
                    .font(.system(size: 13, weight: .medium))
                Text("Website blocking requires each browser to grant Focus permission the first time it reads or redirects the active tab.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ForEach(browsers, id: \.bundleId) { browser in
                    HStack {
                        Image(systemName: appState.permissionStatus.browserAutomation[browser.bundleId] == true ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(appState.permissionStatus.browserAutomation[browser.bundleId] == true ? .green : .orange)
                        Text(browser.name)
                            .font(.system(size: 12))
                        Spacer()
                    }
                }
            }
        }
        .panelStyle()
    }

    private var legacyModesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily App Limits")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Edit old app-limit modes, add apps, and set daily limits.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: addDailyMode) {
                    Label("Add Mode", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if appState.focusModes.isEmpty {
                Text("No daily modes yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                Picker("", selection: Binding(
                    get: { selectedDailyModeId ?? appState.focusModes.first?.id },
                    set: { selectedDailyModeId = $0 }
                )) {
                    ForEach(appState.focusModes) { mode in
                        Text(mode.name).tag(Optional(mode.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if let modeIndex = selectedDailyModeIndex {
                    DailyModeEditor(mode: $appState.focusModes[modeIndex])
                        .environmentObject(appState)
                }
            }
        }
        .panelStyle()
    }

    private var selectedDailyModeIndex: Int? {
        guard let selectedDailyModeId else { return appState.focusModes.indices.first }
        return appState.focusModes.firstIndex { $0.id == selectedDailyModeId }
    }

    private func addDailyMode() {
        let newMode = FocusMode(name: "New Mode")
        appState.focusModes.append(newMode)
        selectedDailyModeId = newMode.id
        appState.saveData()
    }

    private func addWebsiteTarget() {
        let normalized = normalizeDomain(inputText)
        guard !normalized.isEmpty else { return }
        let browser = browsers.first { $0.bundleId == selectedBrowserBundleId } ?? browsers[0]

        draftTargets.append(FocusTarget(
            kind: .website,
            name: normalized,
            bundleIdentifier: nil,
            browserBundleIdentifier: browser.bundleId,
            browserName: browser.name,
            domain: normalized
        ))
        inputText = ""
    }

    private func addFrontmostAppTarget() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier,
              bundleId != Bundle.main.bundleIdentifier else {
            return
        }

        draftTargets.append(FocusTarget(
            kind: .app,
            name: app.localizedName ?? bundleId,
            bundleIdentifier: bundleId,
            browserBundleIdentifier: nil,
            browserName: nil,
            domain: nil
        ))
    }

    private func normalizeDomain(_ value: String) -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return "" }

        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        if let host = URL(string: candidate)?.host {
            return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }

        return candidate
            .replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
    }

    private func timeText(_ interval: TimeInterval?) -> String {
        guard let interval else { return "No limit" }
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

struct DailyModeEditor: View {
    @Binding var mode: FocusMode
    @EnvironmentObject var appState: AppState

    @State private var modeName: String = ""
    @State private var showDeleteConfirmation = false

    private var isActive: Bool {
        appState.activeModeId == mode.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TextField("Mode name", text: $modeName)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        modeName = mode.name
                    }
                    .onChange(of: mode.id) { _ in
                        modeName = mode.name
                    }
                    .onSubmit(saveName)

                Button("Save Name", action: saveName)
                    .buttonStyle(.bordered)

                Button(isActive ? "Deactivate" : "Activate") {
                    appState.activeModeId = isActive ? nil : mode.id
                    appState.saveData()
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Delete this daily mode?", isPresented: $showDeleteConfirmation) {
                    Button("Delete Mode", role: .destructive, action: deleteMode)
                } message: {
                    Text("This removes the mode and its app limits from local Focus data.")
                }
            }

            HStack {
                Text("\(mode.apps.count) tracked app\(mode.apps.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: selectApp) {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if mode.apps.isEmpty {
                Text("Add an app to start tracking daily usage.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach($mode.apps) { $app in
                        DailyAppLimitRow(app: $app) {
                            mode.apps.removeAll { $0.id == app.id }
                            appState.saveData()
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func saveName() {
        let trimmed = modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mode.name = trimmed
        appState.saveData()
    }

    private func deleteMode() {
        if appState.activeModeId == mode.id {
            appState.activeModeId = nil
        }
        appState.focusModes.removeAll { $0.id == mode.id }
        appState.saveData()
    }

    private func selectApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleId = bundle.bundleIdentifier {
            let newApp = TrackedApp(
                bundleIdentifier: bundleId,
                name: url.deletingPathExtension().lastPathComponent,
                dailyTimeLimit: 1800
            )

            if !mode.apps.contains(where: { $0.id == newApp.id }) {
                mode.apps.append(newApp)
                appState.saveData()
            }
        }
    }
}

struct DailyAppLimitRow: View {
    @Binding var app: TrackedApp
    @EnvironmentObject var appState: AppState
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    private var limitMinutes: Int {
        max(5, Int(app.dailyTimeLimit / 60))
    }

    private var usedMinutes: Int {
        Int(app.timeUsedToday / 60)
    }

    private var progress: Double {
        guard app.dailyTimeLimit > 0 else { return 0 }
        return min(1, app.timeUsedToday / app.dailyTimeLimit)
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(String(app.name.prefix(1)))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))

                ProgressView(value: progress)
                    .frame(height: 4)

                Text("\(usedMinutes)m used of \(limitMinutes)m")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Stepper("\(limitMinutes)m", value: Binding(
                get: { limitMinutes },
                set: { newValue in
                    app.dailyTimeLimit = TimeInterval(max(5, newValue) * 60)
                    appState.saveData()
                }
            ), in: 5...480, step: 5)
            .frame(width: 110)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .confirmationDialog("Remove this app limit?", isPresented: $showDeleteConfirmation) {
                Button("Remove App", role: .destructive, action: onDelete)
            } message: {
                Text("This removes \(app.name) from the daily mode.")
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum SessionDuration: String, CaseIterable, Identifiable {
    case noLimit
    case fifteen
    case thirty
    case fortyFive
    case oneHour
    case twoHours
    case fourHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noLimit: return "No limit"
        case .fifteen: return "15 minutes"
        case .thirty: return "30 minutes"
        case .fortyFive: return "45 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .noLimit: return nil
        case .fifteen: return 15 * 60
        case .thirty: return 30 * 60
        case .fortyFive: return 45 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        }
    }
}

struct FormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .trailing)
            content
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct TargetChip: View {
    let target: FocusTarget
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: target.kind == .app ? "app.dashed" : "globe")
                .font(.system(size: 11))
            Text(target.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 600, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (items: [(index: Int, origin: CGPoint)], size: CGSize) {
        var items: [(Int, CGPoint)] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0 && cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }

            items.append((index, cursor))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, cursor.x)
        }

        return (items, CGSize(width: min(width, maxWidth), height: cursor.y + rowHeight))
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
