import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var manager: FocusGuardManager

    @State private var newAppName: String = ""
    @State private var newAppBundleId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("FocusDND Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            GroupBox(label: Text("Session")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Stepper(value: $manager.config.durationMinutes, in: 5...240, step: 5) {
                            Text("\(manager.config.durationMinutes) minutes")
                                .frame(width: 140, alignment: .trailing)
                        }
                    }

                    Picker("Filter Mode", selection: $manager.config.filterMode) {
                        ForEach(FilterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }

            GroupBox(label: Text("Apps")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("App name", text: $newAppName)
                        TextField("Bundle ID", text: $newAppBundleId)
                        Button("Add") {
                            addManualApp()
                        }
                        .disabled(newAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    RunningAppPicker { app in
                        manager.addApp(app)
                    }

                    if manager.config.apps.isEmpty {
                        Text("No apps added yet")
                            .foregroundColor(.secondary)
                    } else {
                        List {
                            ForEach(manager.config.apps) { app in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(app.name)
                                        Text(app.bundleIdentifier)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Remove") {
                                        manager.removeApp(app)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox(label: Text("Do Not Disturb Integration")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Run Shortcuts when focus starts/ends", isOn: $manager.config.enableDndShortcuts)

                    HStack {
                        Text("Start Shortcut")
                        TextField("Enable Focus", text: $manager.config.dndStartShortcutName)
                    }

                    HStack {
                        Text("End Shortcut")
                        TextField("Disable Focus", text: $manager.config.dndEndShortcutName)
                    }

                    Text("Create two Shortcuts named above that enable/disable macOS Focus (Do Not Disturb). FocusDND will run them automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Button("Save") {
                    manager.saveConfig()
                }
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .onDisappear {
            manager.saveConfig()
        }
    }

    private func addManualApp() {
        let name = newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleId = newAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleId.isEmpty else { return }

        let app = GuardedApp(bundleIdentifier: bundleId, name: name.isEmpty ? bundleId : name)
        manager.addApp(app)

        newAppName = ""
        newAppBundleId = ""
    }
}
