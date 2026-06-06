import AppKit
import ApplicationServices
import Carbon
import Combine
import CryptoKit
import Foundation
import OSLog
import SwiftUI
import UserNotifications

private let focusLog = Logger(subsystem: "com.anaygoyal.focus", category: "automation")

// MARK: - Automation status

public enum AutomationStatus: String, Sendable {
    case needsPermission
    case opening
    case waitingForPrompt
    case resetting
    case allowed
    case denied
    case unsupported
    case failed

    public var label: String {
        switch self {
        case .needsPermission: return "Needs permission"
        case .opening: return "Opening browser"
        case .waitingForPrompt: return "Waiting for macOS prompt"
        case .resetting: return "Resetting"
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .unsupported: return "Unsupported"
        case .failed: return "Failed"
        }
    }
}

// MARK: - FocusManager

@MainActor
public final class FocusManager: ObservableObject {
    public static let shared = FocusManager()

    // Published state
    @Published public private(set) var installedBrowsers: [BrowserInfo] = []
    @Published public private(set) var defaultBrowserID: String? = nil
    @Published public var currentSession: FocusSession? = nil
    @Published public var dailyLimits: [DailyLimit] = []
    @Published public private(set) var automationStatus: [String: AutomationStatus] = [:]
    @Published public private(set) var accessibilityGranted: Bool = false
    @Published public var settings: FocusSettings = FocusSettings()

    // Snooze: domain -> until-date
    @Published public private(set) var snoozedDomains: [String: Date] = [:]

    /// Screen-time style totals for today (all apps except Focus), keyed by bundle id.
    @Published public private(set) var dayAppUsage: [String: TimeInterval] = [:]
    /// Totals for today, keyed by normalized domain (requires Automation permission for the front browser).
    @Published public private(set) var dayWebsiteUsage: [String: TimeInterval] = [:]
    /// Active domain in the frontmost browser when URL can be read; drives the Day Tracker “Now” tab.
    @Published public private(set) var liveFrontDomain: String?

    private var dayUsageRecordedForDay: Date = Calendar.current.startOfDay(for: Date())

    private var monitorTimer: Timer?
    private var usageTickTimer: Timer?
    private var lastFrontmostBundleID: String?
    private var lastTickDate: Date = Date()

    private let storageURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Focus", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }()

    // MARK: Lifecycle

    private init() {}

    public func bootstrap() {
        load()
        scanBrowsers()
        refreshAccessibility()
        startMonitorTimer()
        Task { await preflightAutomationForRunningBrowsers() }
    }

    // MARK: Persistence

    private struct PersistedState: Codable {
        var session: FocusSession?
        var dailyLimits: [DailyLimit]
        var settings: FocusSettings
        var dayAppUsage: [String: TimeInterval]?
        var dayWebsiteUsage: [String: TimeInterval]?
        var dayUsageRecordedForDay: Date?
    }

    public func save() {
        let state = PersistedState(session: currentSession, dailyLimits: dailyLimits, settings: settings,
                                   dayAppUsage: dayAppUsage, dayWebsiteUsage: dayWebsiteUsage,
                                   dayUsageRecordedForDay: dayUsageRecordedForDay)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        currentSession = state.session
        dailyLimits = state.dailyLimits
        settings = state.settings
        dayAppUsage = state.dayAppUsage ?? [:]
        dayWebsiteUsage = state.dayWebsiteUsage ?? [:]
        if let anchor = state.dayUsageRecordedForDay {
            dayUsageRecordedForDay = Calendar.current.startOfDay(for: anchor)
        }
        rolloverDailyLimitsIfNeeded()
        rolloverDayUsageIfNeeded()
    }

    // MARK: Browser scanning

    public func scanBrowsers() {
        let fm = FileManager.default
        var found: [BrowserInfo] = [BrowserInfo.anyBrowser]
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for entry in apps where entry.hasSuffix(".app") {
            let path = "/Applications/\(entry)"
            guard let bundle = Bundle(path: path),
                  let bid = bundle.bundleIdentifier else { continue }
            guard declaresHTTPScheme(bundle: bundle) else { continue }
            let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (entry as NSString).deletingPathExtension
            let supports = supportsTabAutomation(bundle: bundle)
            found.append(BrowserInfo(bundleIdentifier: bid, name: name, path: path, supportsTabAutomation: supports))
        }
        // Stable sort by name, keep Any Browser first.
        let head = found.first!
        let rest = found.dropFirst().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        installedBrowsers = [head] + rest
        defaultBrowserID = detectDefaultBrowserID()
        // Initialize automation status for new browsers.
        for b in installedBrowsers where b.bundleIdentifier != BrowserInfo.anyBrowserID {
            if automationStatus[b.bundleIdentifier] == nil {
                automationStatus[b.bundleIdentifier] = b.supportsTabAutomation ? .needsPermission : .unsupported
            } else if !b.supportsTabAutomation {
                automationStatus[b.bundleIdentifier] = .unsupported
            }
        }
    }

    private func declaresHTTPScheme(bundle: Bundle) -> Bool {
        guard let types = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        for t in types {
            if let schemes = t["CFBundleURLSchemes"] as? [String] {
                for s in schemes {
                    let lower = s.lowercased()
                    if lower == "http" || lower == "https" { return true }
                }
            }
        }
        return false
    }

    private func supportsTabAutomation(bundle: Bundle) -> Bool {
        let info = bundle.infoDictionary ?? [:]
        // Explicitly exclude Firefox.
        if let bid = bundle.bundleIdentifier?.lowercased(), bid.contains("firefox") { return false }
        let scriptable = (info["NSAppleScriptEnabled"] as? Bool) ?? false
            || ((info["NSAppleScriptEnabled"] as? String)?.lowercased() == "yes")
        let hasSDef = info["OSAScriptingDefinition"] != nil
        return scriptable && hasSDef
    }

    private func detectDefaultBrowserID() -> String? {
        guard let url = URL(string: "https://apple.com") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)?.bundleIdentifier()
    }

    // MARK: Accessibility

    public func refreshAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    public func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibility()
        }
    }

    // MARK: Automation permission

    public func resetAutomationTCC() async {
        await MainActor.run { self.automationStatus = self.automationStatus.mapValues { _ in .resetting } }
        // 1. Bundle-id targeted reset.
        let bidResult = await Self.runTCCUtil(args: ["reset", "AppleEvents", "com.anaygoyal.focus"])
        focusLog.info("tccutil reset AppleEvents com.anaygoyal.focus -> exit=\(bidResult.exit) out=\(bidResult.out, privacy: .public) err=\(bidResult.err, privacy: .public)")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            for b in self.installedBrowsers where b.bundleIdentifier != BrowserInfo.anyBrowserID {
                self.automationStatus[b.bundleIdentifier] = b.supportsTabAutomation ? .needsPermission : .unsupported
            }
        }
    }

    /// Nuclear reset of the whole AppleEvents TCC table for the current user.
    /// We only call this from the explicit "Force Reset" button.
    public func resetAllAppleEventsTCC() async {
        let r = await Self.runTCCUtil(args: ["reset", "AppleEvents"])
        focusLog.info("tccutil reset AppleEvents (all) -> exit=\(r.exit) out=\(r.out, privacy: .public) err=\(r.err, privacy: .public)")
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            for b in self.installedBrowsers where b.bundleIdentifier != BrowserInfo.anyBrowserID {
                self.automationStatus[b.bundleIdentifier] = b.supportsTabAutomation ? .needsPermission : .unsupported
            }
        }
    }

    public func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private nonisolated static func runTCCUtil(args: [String]) async -> (exit: Int32, out: String, err: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = args
            let outPipe = Pipe(), errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            do { try p.run() } catch { return (-1, "", "\(error)") }
            p.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            return (p.terminationStatus,
                    String(data: outData, encoding: .utf8) ?? "",
                    String(data: errData, encoding: .utf8) ?? "")
        }.value
    }

    public func requestAutomation(for browser: BrowserInfo) {
        guard browser.bundleIdentifier != BrowserInfo.anyBrowserID else { return }
        guard browser.supportsTabAutomation else {
            automationStatus[browser.bundleIdentifier] = .unsupported
            return
        }
        Task { await performAutomationRequest(for: browser, allowReset: true) }
    }

    private func preflightAutomationForRunningBrowsers() async {
        for b in installedBrowsers where b.supportsTabAutomation {
            let running = NSWorkspace.shared.runningApplications
                .contains { $0.bundleIdentifier == b.bundleIdentifier }
            guard running else { continue }
            // On launch, only the wildcard preflight (no prompt). If the system
            // already has an entry, surface it; otherwise leave as "Needs permission"
            // so the user explicitly triggers the prompt via the Request button.
            let pid = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == b.bundleIdentifier })?.processIdentifier ?? 0
            guard pid > 0 else { continue }
            let preflight: AutomationPreflight = await Task.detached {
                return Self.determinePermission(pid: pid, prompt: false)
            }.value
            await MainActor.run {
                switch preflight {
                case .allowed: self.automationStatus[b.bundleIdentifier] = .allowed
                case .denied, .wouldNeedConsent, .failed:
                    // Don't mark as denied without user action — keep needsPermission.
                    if self.automationStatus[b.bundleIdentifier] != .allowed {
                        self.automationStatus[b.bundleIdentifier] = .needsPermission
                    }
                }
            }
        }
    }

    private func performAutomationRequest(for browser: BrowserInfo, allowReset: Bool, silent: Bool = false) async {
        let bid = browser.bundleIdentifier
        focusLog.info("[\(bid, privacy: .public)] request begin (allowReset=\(allowReset))")
        await MainActor.run { self.automationStatus[bid] = .opening }
        guard let pid = await ensureBrowserRunning(browser) else {
            focusLog.error("[\(bid, privacy: .public)] could not launch browser")
            await MainActor.run { self.automationStatus[bid] = .failed }
            return
        }
        await MainActor.run { self.automationStatus[bid] = .waitingForPrompt }

        // Bring Focus to the foreground so the TCC prompt has a UI context.
        // LSUIElement apps can fail to surface the Automation prompt otherwise.
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Wildcard preflight (informational; in practice does not always
        // surface a prompt for the wildcard event class).
        let preflight: AutomationPreflight = await Task.detached {
            return Self.determinePermission(pid: pid, prompt: true)
        }.value
        focusLog.info("[\(bid, privacy: .public)] preflight = \(String(describing: preflight), privacy: .public)")

        if preflight == .allowed {
            let probe = await runProbe(for: browser)
            focusLog.info("[\(bid, privacy: .public)] post-allow probe = \(String(describing: probe), privacy: .public)")
            await MainActor.run { self.automationStatus[bid] = probe.toStatus() }
            return
        }

        // Real probe — this is what actually makes the macOS prompt appear and
        // creates the Automation entry in System Settings.
        let probe = await runProbe(for: browser)
        focusLog.info("[\(bid, privacy: .public)] probe = \(String(describing: probe), privacy: .public)")

        switch probe {
        case .ok, .noWindows:
            await MainActor.run { self.automationStatus[bid] = .allowed }
        case .userDismissed:
            // User dismissed the prompt without answering — leave as
            // needsPermission so the next click re-prompts (no reset).
            await MainActor.run { self.automationStatus[bid] = .needsPermission }
        case .notPermitted:
            if allowReset {
                // First try the targeted reset.
                await MainActor.run { self.automationStatus[bid] = .resetting }
                await resetAutomationTCC()
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    self.automationStatus[bid] = .waitingForPrompt
                    NSApp.activate(ignoringOtherApps: true)
                }
                var retry = await runProbe(for: browser)
                focusLog.info("[\(bid, privacy: .public)] retry probe = \(String(describing: retry), privacy: .public)")

                // If targeted reset didn't take, try the full AppleEvents reset.
                if case .notPermitted = retry {
                    focusLog.info("[\(bid, privacy: .public)] targeted reset did not clear cache, falling back to full reset")
                    await MainActor.run { self.automationStatus[bid] = .resetting }
                    await resetAllAppleEventsTCC()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await MainActor.run {
                        self.automationStatus[bid] = .waitingForPrompt
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    retry = await runProbe(for: browser)
                    focusLog.info("[\(bid, privacy: .public)] retry-2 probe = \(String(describing: retry), privacy: .public)")
                }

                await MainActor.run { self.automationStatus[bid] = retry.toStatus() }
            } else {
                await MainActor.run { self.automationStatus[bid] = .denied }
            }
        case .failed(let code):
            focusLog.error("[\(bid, privacy: .public)] probe failed code=\(code)")
            await MainActor.run { self.automationStatus[bid] = .failed }
        }
        _ = silent
    }

    private enum AutomationPreflight {
        case allowed, denied, wouldNeedConsent, failed
    }

    private nonisolated static func determinePermission(pid: pid_t, prompt: Bool) -> AutomationPreflight {
        var pidValue = pid
        var addr = AEAddressDesc()
        let createErr = AECreateDesc(DescType(typeKernelProcessID), &pidValue, MemoryLayout.size(ofValue: pidValue), &addr)
        guard createErr == noErr else { return .failed }
        defer { AEDisposeDesc(&addr) }
        let result = AEDeterminePermissionToAutomateTarget(&addr,
                                                           DescType(typeWildCard),
                                                           DescType(typeWildCard),
                                                           prompt)
        switch result {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .wouldNeedConsent
        default: return .failed
        }
    }

    private enum ProbeResult {
        case ok
        case noWindows
        case userDismissed
        case notPermitted
        case failed(Int)

        func toStatus() -> AutomationStatus {
            switch self {
            case .ok, .noWindows: return .allowed
            case .userDismissed: return .needsPermission
            case .notPermitted: return .denied
            case .failed: return .failed
            }
        }
    }

    /// Runs a harmless real AppleScript that reads the front tab URL. This is
    /// what makes macOS show the Automation prompt and create the entry in
    /// System Settings → Privacy & Security → Automation.
    private func runProbe(for browser: BrowserInfo) async -> ProbeResult {
        let bid = browser.bundleIdentifier
        let script: String
        if bid.lowercased().contains("safari") {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return "__no_windows__"
                return URL of current tab of front window
            end tell
            """
        } else {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return "__no_windows__"
                return URL of active tab of front window
            end tell
            """
        }
        return await Task.detached {
            var errDict: NSDictionary?
            guard let s = NSAppleScript(source: script) else { return .failed(0) }
            let desc = s.executeAndReturnError(&errDict)
            if let err = errDict {
                let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
                let msg  = (err[NSAppleScript.errorMessage] as? String) ?? ""
                focusLog.error("AppleScript err code=\(code) msg=\(msg, privacy: .public)")
                switch code {
                case -1743: return .notPermitted        // errAEEventNotPermitted
                case -1744: return .userDismissed       // wouldRequireUserConsent / dismissed
                default:    return .failed(code)
                }
            }
            if desc.stringValue == "__no_windows__" { return .noWindows }
            return .ok
        }.value
    }

    private func ensureBrowserRunning(_ browser: BrowserInfo) async -> pid_t? {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == browser.bundleIdentifier }) {
            return running.processIdentifier
        }
        let url = URL(fileURLWithPath: browser.path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.hides = true
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            // Wait up to ~10s for it to be running.
            for _ in 0..<40 {
                if app.isFinishedLaunching { return app.processIdentifier }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            return app.processIdentifier
        } catch {
            return nil
        }
    }

    // MARK: AppleScript helpers

    @discardableResult
    public func readActiveTabURL(for browser: BrowserInfo) async -> String? {
        guard browser.supportsTabAutomation else { return nil }
        let bid = browser.bundleIdentifier
        let script: String
        if bid.lowercased().contains("safari") {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """
        } else {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """
        }
        return await runAppleScript(script)
    }

    public func setActiveTabURL(for browser: BrowserInfo, to urlString: String) async -> Bool {
        guard browser.supportsTabAutomation else { return false }
        let bid = browser.bundleIdentifier
        let escaped = urlString.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if bid.lowercased().contains("safari") {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return false
                set URL of current tab of front window to "\(escaped)"
                return true
            end tell
            """
        } else {
            script = """
            tell application id "\(bid)"
                if (count of windows) is 0 then return false
                set URL of active tab of front window to "\(escaped)"
                return true
            end tell
            """
        }
        let out = await runAppleScript(script)
        return out?.lowercased() == "true"
    }

    private func runAppleScript(_ source: String) async -> String? {
        return await Task.detached {
            var err: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return nil }
            let result = script.executeAndReturnError(&err)
            if err != nil { return nil }
            return result.stringValue
        }.value
    }

    // MARK: Sessions

    public func startSession(mode: FocusMode, duration: FocusDuration, targets: [FocusTarget]) {
        let now = Date()
        var endsAt: Date? = nil
        if case .timed(let m) = duration { endsAt = now.addingTimeInterval(TimeInterval(m * 60)) }
        currentSession = FocusSession(mode: mode, duration: duration, targets: targets,
                                      startedAt: now, endsAt: endsAt)
        save()
    }

    public func endSession() {
        currentSession = nil
        save()
    }

    public func addTarget(_ t: FocusTarget) {
        guard var s = currentSession else { return }
        s.targets.append(t)
        currentSession = s
        save()
    }

    public func removeTarget(_ id: UUID) {
        guard var s = currentSession else { return }
        s.targets.removeAll { $0.id == id }
        currentSession = s
        save()
    }

    // MARK: Snooze

    public func snooze(domain: String, minutes: Int = 5) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        snoozedDomains[normalizeDomain(domain)] = until
    }

    public func handleSnoozeURL(_ url: URL) {
        guard url.scheme == "focusapp", url.host == "snooze" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let domain = comps?.queryItems?.first(where: { $0.name == "domain" })?.value ?? ""
        let minutes = Int(comps?.queryItems?.first(where: { $0.name == "minutes" })?.value ?? "5") ?? 5
        if !domain.isEmpty { snooze(domain: domain, minutes: minutes) }
    }

    private func isSnoozed(_ domain: String) -> Bool {
        let key = normalizeDomain(domain)
        if let until = snoozedDomains[key], until > Date() { return true }
        if let until = snoozedDomains[key], until <= Date() { snoozedDomains.removeValue(forKey: key) }
        return false
    }

    // MARK: Monitor

    private func startMonitorTimer() {
        monitorTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        monitorTimer?.invalidate()
        RunLoop.main.add(t, forMode: .common)
        monitorTimer = t
    }

    private func tick() {
        rolloverDailyLimitsIfNeeded()
        rolloverDayUsageIfNeeded()
        let now = Date()
        let dt = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bid = front.bundleIdentifier else { return }

        // Never block self.
        if bid == "com.anaygoyal.focus" { return }

        if !isBrowser(bundleID: bid) {
            liveFrontDomain = nil
        }

        // Day tracker — frontmost app time (today).
        dayAppUsage[bid, default: 0] += dt

        // Daily limits accounting.
        if let idx = dailyLimits.firstIndex(where: { $0.bundleIdentifier == bid }) {
            dailyLimits[idx].usedToday += dt
            if dailyLimits[idx].remaining <= 0 {
                let appName = dailyLimits[idx].displayName
                DailyLimitEdgeOverlayPresenter.present(displayName: appName, bundleID: bid)
                let pid = front.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self else { return }
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        self.terminate(app: app)
                    }
                }
                postNotification(title: "Daily Limit Reached",
                                 body: "\(appName) is closed for today.")
            }
        }

        // Active session enforcement.
        if var session = currentSession {
            if session.isExpired {
                endSession()
                postNotification(title: "Focus Session Complete", body: "Great work.")
                return
            }
            let blocked = shouldBlock(bundleID: bid, session: session, frontApp: front)
            if blocked {
                handleBlock(bundleID: bid, frontApp: front, session: session)
            }
            // Track per-target usage.
            for t in session.targets where t.kind == .app && t.value == bid {
                session.usageByTarget[t.id, default: 0] += dt
            }
            currentSession = session
        }

        // Browser URL inspection for website rules + day tracker websites.
        if let session = currentSession, !session.targets.isEmpty {
            Task { await self.enforceBrowserRules(frontBundleID: bid, session: session, timeDelta: dt) }
        } else if isBrowser(bundleID: bid) {
            Task { await self.recordWebsiteDayUsageOnly(frontBundleID: bid, timeDelta: dt) }
        }

        save()
    }

    private func shouldBlock(bundleID: String, session: FocusSession, frontApp: NSRunningApplication) -> Bool {
        let appTargets = session.targets.filter { $0.kind == .app }
        let matches = appTargets.contains { $0.value == bundleID }
        switch session.mode {
        case .block:
            return matches
        case .allow:
            // If frontmost is a browser, defer to URL-level enforcement.
            if isBrowser(bundleID: bundleID) { return false }
            return !matches && !appTargets.isEmpty
        }
    }

    private func isBrowser(bundleID: String) -> Bool {
        installedBrowsers.contains { $0.bundleIdentifier == bundleID }
    }

    private func handleBlock(bundleID: String, frontApp: NSRunningApplication, session: FocusSession) {
        // Non-browser: terminate.
        terminate(app: frontApp)
    }

    private func terminate(app: NSRunningApplication) {
        app.terminate()
    }

    private func enforceBrowserRules(frontBundleID: String, session: FocusSession, timeDelta: TimeInterval) async {
        guard let browser = installedBrowsers.first(where: { $0.bundleIdentifier == frontBundleID }),
              browser.supportsTabAutomation,
              automationStatus[browser.bundleIdentifier] == .allowed else {
            liveFrontDomain = nil
            return
        }
        guard let urlString = await readActiveTabURL(for: browser),
              let url = URL(string: urlString),
              let host = url.host else {
            liveFrontDomain = nil
            return
        }
        let domain = normalizeDomain(host)
        liveFrontDomain = domain
        dayWebsiteUsage[domain, default: 0] += timeDelta

        if isSnoozed(domain) { return }

        let websiteTargets = session.targets.filter { $0.kind == .website }
        let appTargets = session.targets.filter { $0.kind == .app }

        let matchesTarget = websiteTargets.contains { tgt in
            guard targetAppliesToBrowser(tgt, browser: browser) else { return false }
            return domainMatches(domain, target: tgt.value)
        }

        let shouldRedirect: Bool
        switch session.mode {
        case .block:
            shouldRedirect = matchesTarget
        case .allow:
            // Allow website if it matches an allowed website target.
            // If only app allow-list and no website targets, leave browser tabs alone.
            if websiteTargets.isEmpty && !appTargets.isEmpty { return }
            shouldRedirect = !matchesTarget
        }

        if shouldRedirect {
            let page = blockedPageDataURL(forDomain: domain)
            _ = await setActiveTabURL(for: browser, to: page)
        }
    }

    private func recordWebsiteDayUsageOnly(frontBundleID: String, timeDelta: TimeInterval) async {
        guard let browser = installedBrowsers.first(where: { $0.bundleIdentifier == frontBundleID }),
              browser.supportsTabAutomation,
              automationStatus[browser.bundleIdentifier] == .allowed else {
            liveFrontDomain = nil
            return
        }
        guard let urlString = await readActiveTabURL(for: browser),
              let url = URL(string: urlString),
              let host = url.host else {
            liveFrontDomain = nil
            return
        }
        let domain = normalizeDomain(host)
        liveFrontDomain = domain
        dayWebsiteUsage[domain, default: 0] += timeDelta
    }

    private func targetAppliesToBrowser(_ t: FocusTarget, browser: BrowserInfo) -> Bool {
        guard let b = t.browserBundleID else { return true }
        if b == BrowserInfo.anyBrowserID { return true }
        return b == browser.bundleIdentifier
    }

    public func normalizeDomain(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: s), let h = u.host { s = h.lowercased() }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        // Strip path/scheme remnants.
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        return s
    }

    private func domainMatches(_ host: String, target: String) -> Bool {
        let h = normalizeDomain(host)
        let t = normalizeDomain(target)
        if h == t { return true }
        return h.hasSuffix("." + t)
    }

    private func blockedPageDataURL(forDomain domain: String) -> String {
        let snooze = "focusapp://snooze?domain=\(domain)&minutes=5"
        let html = """
        <!doctype html><html><head><meta charset='utf-8'><title>Blocked by Focus</title>
        <style>
        :root { color-scheme: dark light; }
        html,body { height:100%; margin:0; font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif; }
        body { display:flex; align-items:center; justify-content:center;
               background: radial-gradient(circle at 30% 20%, #5b4bdc, #181a2e 60%); color:#fff; }
        .card { backdrop-filter: blur(20px); background: rgba(255,255,255,0.08);
                border:1px solid rgba(255,255,255,0.15); border-radius:24px;
                padding:36px 44px; max-width:520px; text-align:center; }
        h1 { margin:0 0 10px; font-weight:600; font-size:28px; letter-spacing:-0.02em; }
        p  { margin:0 0 22px; opacity:0.85; line-height:1.45; }
        code { background: rgba(255,255,255,0.12); padding:2px 8px; border-radius:6px; }
        a.btn { display:inline-block; padding:10px 18px; border-radius:12px;
                background:#fff; color:#1d1b3a; text-decoration:none; font-weight:600; }
        small { display:block; margin-top:14px; opacity:0.55; }
        </style></head><body>
        <div class='card'>
          <h1>Focus is on</h1>
          <p><code>\(domain)</code> is blocked while your focus session is running.</p>
          <a class='btn' href='\(snooze)'>Snooze 5 min</a>
          <small>You can end the session in the Focus app.</small>
        </div></body></html>
        """
        let allowed = CharacterSet.urlQueryAllowed
        let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "data:text/html;charset=utf-8,\(encoded)"
    }

    // MARK: Daily limits

    public func addDailyLimit(bundleID: String, displayName: String, seconds: TimeInterval) {
        if let i = dailyLimits.firstIndex(where: { $0.bundleIdentifier == bundleID }) {
            dailyLimits[i].dailyLimitSeconds = seconds
        } else {
            dailyLimits.append(DailyLimit(bundleIdentifier: bundleID,
                                          displayName: displayName,
                                          dailyLimitSeconds: seconds))
        }
        save()
    }

    public func addFrontmostAppAsLimit(seconds: TimeInterval) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier, bid != "com.anaygoyal.focus" else { return }
        let name = app.localizedName ?? bid
        addDailyLimit(bundleID: bid, displayName: name, seconds: seconds)
    }

    public func removeDailyLimit(_ id: UUID) {
        dailyLimits.removeAll { $0.id == id }
        save()
    }

    private func rolloverDailyLimitsIfNeeded() {
        let cal = Calendar.current
        for i in dailyLimits.indices {
            if !cal.isDateInToday(dailyLimits[i].lastReset) {
                dailyLimits[i].usedToday = 0
                dailyLimits[i].lastReset = Date()
            }
        }
    }

    private func rolloverDayUsageIfNeeded() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if !cal.isDate(dayUsageRecordedForDay, inSameDayAs: Date()) {
            dayAppUsage = [:]
            dayWebsiteUsage = [:]
            liveFrontDomain = nil
            dayUsageRecordedForDay = today
            save()
        }
    }

    /// Human-readable app name for menu bar / day tracker rows.
    public func displayNameForBundle(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let n = FileManager.default.displayName(atPath: url.path)
            if !n.isEmpty { return n }
        }
        return bundleID
    }

    // MARK: Notifications

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    public func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Passwords

    public static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func verifyEndSessionPassword(_ password: String) -> Bool {
        guard let h = settings.endSessionPasswordHash, !h.isEmpty else { return true }
        return Self.hash(password) == h
    }

    public func verifyQuitPassword(_ password: String) -> Bool {
        guard let h = settings.quitPasswordHash, !h.isEmpty else { return true }
        return Self.hash(password) == h
    }
}

// MARK: - Bundle helper

private extension URL {
    func bundleIdentifier() -> String? {
        return Bundle(url: self)?.bundleIdentifier
    }
}
