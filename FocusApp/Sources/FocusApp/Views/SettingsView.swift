import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModeId: UUID?
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Focus Modes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Button(action: addNewMode) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add new focus mode")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // Mode List
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.focusModes) { mode in
                            ModeRowView(
                                mode: mode,
                                isSelected: selectedModeId == mode.id,
                                isActive: appState.activeModeId == mode.id
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedModeId = mode.id
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteMode(mode)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 200)
            .background(Color(NSColor.controlBackgroundColor))
            
        } detail: {
            // Detail View
            if let modeId = selectedModeId,
               let modeIndex = appState.focusModes.firstIndex(where: { $0.id == modeId }) {
                FocusModeDetailView(mode: $appState.focusModes[modeIndex])
                    .environmentObject(appState)
            } else {
                EmptyDetailView()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            if selectedModeId == nil, let first = appState.focusModes.first {
                selectedModeId = first.id
            }
        }
    }
    
    private func addNewMode() {
        let newMode = FocusMode(name: "New Mode")
        appState.focusModes.append(newMode)
        selectedModeId = newMode.id
        appState.saveData()
    }
    
    private func deleteMode(_ mode: FocusMode) {
        if appState.activeModeId == mode.id {
            appState.activeModeId = nil
        }
        appState.focusModes.removeAll { $0.id == mode.id }
        if selectedModeId == mode.id {
            selectedModeId = appState.focusModes.first?.id
        }
        appState.saveData()
    }
}

struct ModeRowView: View {
    let mode: FocusMode
    let isSelected: Bool
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? .green : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("\(mode.apps.count) app\(mode.apps.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isActive {
                Text("Active")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Select a Focus Mode")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Choose a mode from the sidebar to view and edit its settings")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FocusModeDetailView: View {
    @Binding var mode: FocusMode
    @EnvironmentObject var appState: AppState
    @State private var isEditing = false
    
    var isActive: Bool {
        appState.activeModeId == mode.id
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if isEditing {
                                TextField("Mode Name", text: $mode.name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 24, weight: .bold))
                                    .onSubmit { isEditing = false }
                            } else {
                                Text(mode.name)
                                    .font(.system(size: 24, weight: .bold))
                                    .onTapGesture { isEditing = true }
                            }
                            
                            Text("\(mode.apps.count) tracked application\(mode.apps.count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Activate Toggle
                        Button(action: toggleActive) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(isActive ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                
                                Text(isActive ? "Active" : "Inactive")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Apps Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Tracked Apps")
                            .font(.system(size: 15, weight: .semibold))
                        
                        Spacer()
                        
                        Button(action: selectApp) {
                            Label("Add App", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    if mode.apps.isEmpty {
                        EmptyAppsView(onAdd: selectApp)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($mode.apps) { $app in
                                AppRowCard(app: $app, onDelete: {
                                    mode.apps.removeAll { $0.id == app.id }
                                    appState.saveData()
                                })
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func toggleActive() {
        if isActive {
            appState.activeModeId = nil
        } else {
            appState.activeModeId = mode.id
        }
        appState.saveData()
    }
    
    private func selectApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                let name = url.deletingPathExtension().lastPathComponent
                let newApp = TrackedApp(
                    bundleIdentifier: bundleId,
                    name: name,
                    dailyTimeLimit: 1800
                )
                if !mode.apps.contains(where: { $0.id == newApp.id }) {
                    mode.apps.append(newApp)
                    appState.saveData()
                }
            }
        }
    }
}

struct EmptyAppsView: View {
    let onAdd: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No apps tracked yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Button("Add Your First App", action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppRowCard: View {
    @Binding var app: TrackedApp
    let onDelete: () -> Void
    
    @State private var timeLimit: Double
    
    init(app: Binding<TrackedApp>, onDelete: @escaping () -> Void) {
        self._app = app
        self.onDelete = onDelete
        self._timeLimit = State(initialValue: app.wrappedValue.dailyTimeLimit / 60)
    }
    
    private var progress: Double {
        guard app.dailyTimeLimit > 0 else { return 0 }
        return min(1, app.timeUsedToday / app.dailyTimeLimit)
    }
    
    private var remaining: Int {
        Int(app.timeRemaining / 60)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // App Icon
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(app.name.prefix(1)))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name)
                    .font(.system(size: 14, weight: .medium))
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                        
                        Capsule()
                            .fill(remaining <= 5 ? Color.red : (remaining <= 15 ? Color.orange : Color.green))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(app.timeUsedToday / 60))m used of \(Int(app.dailyTimeLimit / 60))m")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Time Limit Control
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Button(action: { adjustTime(-5) }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(timeLimit))m")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 40)
                    
                    Button(action: { adjustTime(5) }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("daily limit")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func adjustTime(_ amount: Double) {
        timeLimit = max(5, timeLimit + amount)
        app.dailyTimeLimit = timeLimit * 60
    }
}
