import Foundation

// MARK: - Mode

public enum FocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case block
    case allow

    public var id: String { rawValue }
    public var label: String { self == .block ? "Block" : "Allow" }
}

// MARK: - Duration

public enum FocusDuration: Codable, Hashable, Sendable {
    case noLimit
    case timed(minutes: Int)

    public var minutes: Int? {
        if case .timed(let m) = self { return m }
        return nil
    }

    public var isTimed: Bool { minutes != nil }

    public var displayName: String {
        switch self {
        case .noLimit: return "No limit"
        case .timed(let m):
            if m % 60 == 0 { return "\(m/60)h" }
            return "\(m)m"
        }
    }

    public static let presets: [FocusDuration] = [
        .timed(minutes: 15),
        .timed(minutes: 25),
        .timed(minutes: 45),
        .timed(minutes: 60),
        .timed(minutes: 90),
        .timed(minutes: 120),
        .noLimit
    ]
}

// MARK: - Browser

public struct BrowserInfo: Codable, Hashable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var path: String
    public var supportsTabAutomation: Bool

    public var id: String { bundleIdentifier }

    public static let anyBrowserID = "__any__"
    public static let anyBrowser = BrowserInfo(
        bundleIdentifier: anyBrowserID,
        name: "Any Browser",
        path: "",
        supportsTabAutomation: false
    )
}

// MARK: - Target

public enum FocusTargetKind: String, Codable, Sendable {
    case app
    case website
}

public struct FocusTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var kind: FocusTargetKind
    /// App bundle id when kind == .app; normalized domain when kind == .website.
    public var value: String
    /// Human readable label.
    public var displayName: String
    /// For website targets: bundle id of a specific browser, or BrowserInfo.anyBrowserID.
    public var browserBundleID: String?

    public init(kind: FocusTargetKind, value: String, displayName: String, browserBundleID: String? = nil) {
        self.kind = kind
        self.value = value
        self.displayName = displayName
        self.browserBundleID = browserBundleID
    }
}

// MARK: - Session

public struct FocusSession: Codable, Sendable {
    public var id: UUID = UUID()
    public var mode: FocusMode
    public var duration: FocusDuration
    public var targets: [FocusTarget]
    public var startedAt: Date
    public var endsAt: Date?
    /// Usage tracked per target id (seconds).
    public var usageByTarget: [UUID: TimeInterval] = [:]

    public var isExpired: Bool {
        guard let e = endsAt else { return false }
        return Date() >= e
    }

    public var remaining: TimeInterval? {
        guard let e = endsAt else { return nil }
        return max(0, e.timeIntervalSinceNow)
    }
}

// MARK: - Daily Limits

public struct DailyLimit: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var bundleIdentifier: String
    public var displayName: String
    /// Daily limit in seconds.
    public var dailyLimitSeconds: TimeInterval
    /// Used today (seconds), reset at local midnight.
    public var usedToday: TimeInterval = 0
    public var lastReset: Date = Date()

    public var remaining: TimeInterval {
        max(0, dailyLimitSeconds - usedToday)
    }
}

// MARK: - Settings

public struct FocusSettings: Codable, Sendable {
    public var quitPasswordHash: String? = nil
    public var endSessionPasswordHash: String? = nil
}
