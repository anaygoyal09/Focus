import Foundation
import AppKit
import SwiftUI

@MainActor
final class FocusGuardManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var config: FocusGuardConfig = .default

    private var timer: Timer?
    private let workspace = NSWorkspace.shared

    private let alwaysAllowedBundleIds: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.systempreferences",
        "com.apple.systemsettings"
    ]

    init() {
        loadConfig()
    }

    func startFocus() {
        if isActive { return }
        remainingSeconds = max(1, config.durationMinutes * 60)
        isActive = true
        startTimer()
        if config.enableDndShortcuts {
            runShortcut(named: config.dndStartShortcutName)
        }
    }

    func stopFocus() {
        guard isActive else { return }
        isActive = false
        stopTimer()
        if config.enableDndShortcuts {
            runShortcut(named: config.dndEndShortcutName)
        }
    }

    func saveConfig() {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL())
        } catch {
            print("Failed to save config: \(error)")
        }
    }

    func loadConfig() {
        do {
            let data = try Data(contentsOf: configURL())
            config = try JSONDecoder().decode(FocusGuardConfig.self, from: data)
        } catch {
            config = .default
        }
    }

    func addApp(_ app: GuardedApp) {
        if config.apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) { return }
        config.apps.append(app)
        saveConfig()
    }

    func removeApp(_ app: GuardedApp) {
        config.apps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        saveConfig()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isActive else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            checkFrontmostApp()
        } else {
            stopFocus()
        }
    }

    private func checkFrontmostApp() {
        guard let frontApp = workspace.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return }

        if bundleId == Bundle.main.bundleIdentifier { return }
        if alwaysAllowedBundleIds.contains(bundleId) { return }

        let isListed = config.apps.contains { $0.bundleIdentifier == bundleId }

        switch config.filterMode {
        case .blockList:
            if isListed {
                frontApp.terminate()
            }
        case .allowList:
            if !isListed {
                frontApp.terminate()
            }
        }
    }

    private func runShortcut(named name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        do {
            try process.run()
        } catch {
            print("Failed to run shortcut \(name): \(error)")
        }
    }

    private func configURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FocusDND", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }
}
