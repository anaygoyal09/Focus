import Foundation

enum FocusSessionMode: String, Codable, CaseIterable, Identifiable {
    case block
    case allow

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum FocusTargetKind: String, Codable {
    case app
    case website
}

struct FocusTarget: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: FocusTargetKind
    var name: String
    var bundleIdentifier: String?
    var browserBundleIdentifier: String?
    var browserName: String?
    var domain: String?

    var displayName: String {
        switch kind {
        case .app:
            return name
        case .website:
            let site = domain ?? name
            if let browserName {
                return "\(site) in \(browserName)"
            }
            return site
        }
    }
}

struct FocusSession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var mode: FocusSessionMode = .block
    var duration: TimeInterval?
    var startedAt: Date = Date()
    var endsAt: Date?
    var targets: [FocusTarget] = []
    var usageByTarget: [String: TimeInterval] = [:]
    var lastBlockedTargetName: String?
    var lastBlockedTargetKey: String?
    var snoozedUntilByTarget: [String: Date] = [:]

    var isRunning: Bool {
        guard let endsAt else { return true }
        return Date() < endsAt
    }

    var timeRemaining: TimeInterval? {
        guard let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }
}

struct TrackedApp: Identifiable, Codable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
    var dailyTimeLimit: TimeInterval // in seconds
    var timeUsedToday: TimeInterval = 0 // in seconds
    var lastUsageCheck: Date?
    
    // Display helper
    var timeRemaining: TimeInterval {
        max(0, dailyTimeLimit - timeUsedToday)
    }
}

struct FocusMode: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var apps: [TrackedApp] = []
    var isActive: Bool = false
}

class AppState: ObservableObject {
    @Published var focusModes: [FocusMode] = []
    @Published var activeModeId: UUID?
    @Published var activeSession: FocusSession?
    @Published var permissionStatus: PermissionStatus = PermissionStatus()
    @Published var isBlocking: Bool = false
    @Published var currentBlockedApp: TrackedApp?
    @Published var lastResetDate: Date = Date()
    
    // Notifications Configuration - more frequent as time runs out
    // 30m, 25m, 15m, 10m, 5m, 4m, 3m, 2m, 1m, 30s, 10s, 5s
    @Published var warningThresholds: [TimeInterval] = [1800, 1500, 900, 600, 300, 240, 180, 120, 60, 30, 10, 5]
    
    init() {
        loadData()
        loadSessionData()
        checkDailyReset()
    }
    
    /// Check if we need to reset daily usage (new day started)
    func checkDailyReset() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            print("[Reset] New day detected! Resetting all usage...")
            resetAllUsage()
            lastResetDate = Date()
            saveData()
        }
    }
    
    /// Reset timeUsedToday for all apps in all modes
    private func resetAllUsage() {
        for modeIndex in focusModes.indices {
            for appIndex in focusModes[modeIndex].apps.indices {
                focusModes[modeIndex].apps[appIndex].timeUsedToday = 0
            }
        }
    }
    
    func appDataPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("FocusAppData.json")
    }
    
    private func resetDatePath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("FocusLastReset.txt")
    }
    
    func saveData() {
        do {
            let data = try JSONEncoder().encode(focusModes)
            try data.write(to: appDataPath())
            // Save reset date
            let dateString = ISO8601DateFormatter().string(from: lastResetDate)
            try dateString.write(to: resetDatePath(), atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save data: \(error)")
        }
    }

    private func sessionDataPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("FocusSessionData.json")
    }

    func saveSessionData() {
        do {
            let data = try JSONEncoder().encode(activeSession)
            try data.write(to: sessionDataPath())
        } catch {
            print("Failed to save session data: \(error)")
        }
    }

    func loadSessionData() {
        do {
            let data = try Data(contentsOf: sessionDataPath())
            activeSession = try JSONDecoder().decode(FocusSession?.self, from: data)
            if activeSession?.isRunning == false {
                activeSession = nil
                saveSessionData()
            }
        } catch {
            activeSession = nil
        }
    }
    
    func loadData() {
        do {
            let data = try Data(contentsOf: appDataPath())
            focusModes = try JSONDecoder().decode([FocusMode].self, from: data)
            // Load reset date
            if let dateString = try? String(contentsOf: resetDatePath(), encoding: .utf8),
               let date = ISO8601DateFormatter().date(from: dateString) {
                lastResetDate = date
            }
        } catch {
            // Default data if none exists
            print("No existing data or failed to load. Starting fresh.")
            focusModes = [
                FocusMode(name: "Work", apps: []),
                FocusMode(name: "Social Media", apps: [])
            ]
        }
    }
}

struct PermissionStatus: Equatable {
    var accessibility: Bool = false
    var browserAutomation: [String: Bool] = [:]
}
