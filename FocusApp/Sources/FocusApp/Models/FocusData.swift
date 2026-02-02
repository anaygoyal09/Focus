import Foundation

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
    @Published var isBlocking: Bool = false
    @Published var currentBlockedApp: TrackedApp?
    @Published var menuBarIcon: String = "pawprint.fill"
    @Published var menuBarText: String = ""
    
    // Notifications Configuration - more frequent as time runs out
    // 30m, 25m, 15m, 10m, 5m, 4m, 3m, 2m, 1m, 30s, 10s, 5s
    @Published var warningThresholds: [TimeInterval] = [1800, 1500, 900, 600, 300, 240, 180, 120, 60, 30, 10, 5]
    
    init() {
        loadData()
    }
    
    func appDataPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("FocusAppData.json")
    }
    
    func saveData() {
        do {
            let data = try JSONEncoder().encode(focusModes)
            try data.write(to: appDataPath())
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    func loadData() {
        do {
            let data = try Data(contentsOf: appDataPath())
            focusModes = try JSONDecoder().decode([FocusMode].self, from: data)
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
