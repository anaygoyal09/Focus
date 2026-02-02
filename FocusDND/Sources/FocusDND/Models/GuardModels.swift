import Foundation

struct GuardedApp: Identifiable, Codable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let name: String
}

enum FilterMode: String, Codable, CaseIterable, Identifiable {
    case blockList = "Block list"
    case allowList = "Allow list"

    var id: String { rawValue }
}

struct FocusGuardConfig: Codable {
    var durationMinutes: Int
    var filterMode: FilterMode
    var apps: [GuardedApp]
    var enableDndShortcuts: Bool
    var dndStartShortcutName: String
    var dndEndShortcutName: String

    static let `default` = FocusGuardConfig(
        durationMinutes: 60,
        filterMode: .blockList,
        apps: [],
        enableDndShortcuts: false,
        dndStartShortcutName: "Enable Focus",
        dndEndShortcutName: "Disable Focus"
    )
}
