import Foundation

/// Lightweight index of `.app` bundles under common install locations, used for name search in settings.
actor InstalledAppCatalog {
    static let shared = InstalledAppCatalog()

    private var records: [InstalledAppRecord]?

    func search(_ rawQuery: String, limit: Int = 24) async -> [InstalledAppRecord] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { return [] }
        if records == nil {
            records = await Self.scanInstalledApplications()
        }
        let needle = q.lowercased()
        let matches = records!.filter { r in
            r.displayName.lowercased().contains(needle) || r.bundleIdentifier.lowercased().contains(needle)
        }
        if matches.count <= limit { return matches }
        return Array(matches.prefix(limit))
    }

    /// Call after long idle if you need fresh results (optional).
    func invalidate() { records = nil }

    private nonisolated static func scanInstalledApplications() async -> [InstalledAppRecord] {
        await Task.detached(priority: .utility) {
            scanSync()
        }.value
    }

    private nonisolated static func scanSync() -> [InstalledAppRecord] {
        let fm = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        var seen = Set<String>()
        var out: [InstalledAppRecord] = []
        out.reserveCapacity(400)

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension.lowercased() == "app" else { continue }
                guard let bundle = Bundle(url: item),
                      let bid = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bid.isEmpty else { continue }
                if bid == "com.anaygoyal.focus" { continue }
                guard seen.insert(bid).inserted else { continue }

                let name = displayName(for: bundle, fallbackURL: item)
                out.append(InstalledAppRecord(bundleIdentifier: bid, displayName: name, url: item))
            }
        }

        out.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return out
    }

    private nonisolated static func displayName(for bundle: Bundle, fallbackURL: URL) -> String {
        let loc = bundle.localizedInfoDictionary
        let info = bundle.infoDictionary
        let candidates: [String?] = [
            loc?["CFBundleDisplayName"] as? String,
            loc?["CFBundleName"] as? String,
            info?["CFBundleDisplayName"] as? String,
            info?["CFBundleName"] as? String,
        ]
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        }
        return fallbackURL.deletingPathExtension().lastPathComponent
    }
}

struct InstalledAppRecord: Identifiable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let url: URL
}
