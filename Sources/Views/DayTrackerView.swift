import AppKit
import SwiftUI

enum DayTrackerMode: String, CaseIterable {
    case now = "Now"
    case stats = "Stats"
}

struct DayTrackerView: View {
    @EnvironmentObject private var manager: FocusManager
    @State private var mode: DayTrackerMode = .now
    @State private var detailMode: DayTrackerDetailMode = .main
    @State private var searchText = ""
    @Namespace private var tabNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Day Tracker", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            dayTrackerModeBar
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .onChange(of: mode) { _, _ in
                    withAnimation {
                        detailMode = .main
                        searchText = ""
                    }
                }

            Group {
                switch mode {
                case .now:
                    dayTrackerNowContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .stats:
                    dayTrackerStatsContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.snappy(duration: 0.25), value: mode)
            .padding(.bottom, 10)
        }
    }

    private var dayTrackerModeBar: some View {
        HStack(spacing: 0) {
            ForEach(DayTrackerMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.snappy(duration: 0.25, extraBounce: 0.05)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if mode == m {
                                Capsule()
                                    .fill(Color.primary.opacity(0.09))
                                    .matchedGeometryEffect(id: "activeTabIndicator", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.45)))
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var dayTrackerNowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Daily App Limits", systemImage: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            if manager.dailyLimits.isEmpty {
                dayTrackerEmptyRow("No limits yet — add apps in Daily Limits from the Focus window.")
            } else {
                ForEach(manager.dailyLimits) { limit in
                    AppLimitRow(limit: limit)
                }
            }
        }
    }

    private var dayTrackerStatsContent: some View {
        ZStack {
            if detailMode == .main {
                ScreenTimeStatsCard(
                    appRows: Self.topUsageRows(from: manager.dayAppUsage, excluding: "com.anaygoyal.focus") { id in
                        manager.displayNameForBundle(id)
                    },
                    websiteRows: Self.topUsageRows(from: manager.dayWebsiteUsage, excluding: nil) { $0 },
                    appIcon: nsImage(forBundle:),
                    formatDuration: Self.formatShort,
                    onAppsOthersTapped: {
                        searchText = ""
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            detailMode = .allApps
                        }
                    },
                    onWebsitesOthersTapped: {
                        searchText = ""
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            detailMode = .allWebsites
                        }
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                .zIndex(0)
            } else {
                UsageDetailView(
                    title: detailMode == .allApps ? "All Apps" : "All Websites",
                    rows: detailMode == .allApps ?
                        Self.allUsageRows(from: manager.dayAppUsage, excluding: "com.anaygoyal.focus") { id in
                            manager.displayNameForBundle(id)
                        } :
                        Self.allUsageRows(from: manager.dayWebsiteUsage, excluding: nil) { $0 },
                    website: detailMode == .allWebsites,
                    searchText: $searchText,
                    appIcon: nsImage(forBundle:),
                    formatDuration: Self.formatShort,
                    onBack: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            detailMode = .main
                        }
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                .zIndex(1)
            }
        }
        .frame(height: 270)
        .compositingGroup()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func dayTrackerEmptyRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    fileprivate struct UsageRowModel: Identifiable, Equatable {
        var id: String
        var bundleOrDomainKey: String
        var title: String
        var seconds: TimeInterval
        var isOthers: Bool
    }

    private static func topUsageRows(
        from map: [String: TimeInterval],
        excluding: String?,
        titleForKey: (String) -> String
    ) -> [UsageRowModel] {
        let sorted = map
            .filter { key, sec in
                guard sec > 0 else { return false }
                if let ex = excluding, key == ex { return false }
                return true
            }
            .sorted { $0.value > $1.value }

        guard !sorted.isEmpty else { return [] }

        let top = Array(sorted.prefix(4))
        let tail = sorted.dropFirst(4)
        let othersTotal = tail.reduce(0.0) { $0 + $1.value }

        var rows: [UsageRowModel] = top.map {
            UsageRowModel(id: $0.key, bundleOrDomainKey: $0.key, title: titleForKey($0.key), seconds: $0.value, isOthers: false)
        }
        if othersTotal > 0 {
            rows.append(UsageRowModel(id: "__others__", bundleOrDomainKey: "", title: "Others", seconds: othersTotal, isOthers: true))
        }
        return rows
    }

    private static func allUsageRows(
        from map: [String: TimeInterval],
        excluding: String?,
        titleForKey: (String) -> String
    ) -> [UsageRowModel] {
        let sorted = map
            .filter { key, sec in
                guard sec > 0 else { return false }
                if let ex = excluding, key == ex { return false }
                return true
            }
            .sorted { $0.value > $1.value }

        return sorted.map {
            UsageRowModel(id: $0.key, bundleOrDomainKey: $0.key, title: titleForKey($0.key), seconds: $0.value, isOthers: false)
        }
    }

    private static func formatShort(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m <= 0 { return "<1m" }
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return mm > 0 ? "\(h)h \(mm)m" : "\(h)h"
        }
        return "\(m)m"
    }

    private func nsImage(forBundle bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path else {
            return NSWorkspace.shared.icon(forFile: "/Applications")
        }
        return NSWorkspace.shared.icon(forFile: url)
    }
}

// MARK: - Day Tracker Detail Navigation Mode

enum DayTrackerDetailMode {
    case main
    case allApps
    case allWebsites
}

// MARK: - Screen Time Stats card

private struct ScreenTimeStatsCard: View {
    let appRows: [DayTrackerView.UsageRowModel]
    let websiteRows: [DayTrackerView.UsageRowModel]
    let appIcon: (String) -> NSImage
    let formatDuration: (TimeInterval) -> String
    let onAppsOthersTapped: () -> Void
    let onWebsitesOthersTapped: () -> Void

    private var appMaxSeconds: TimeInterval {
        appRows.map(\.seconds).max() ?? 0
    }

    private var websiteMaxSeconds: TimeInterval {
        websiteRows.map(\.seconds).max() ?? 0
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                statsSubsectionHeader("Apps")
                    .padding(.top, 4)
                if appRows.isEmpty {
                    statsEmptyHint("No app time recorded yet today.")
                } else {
                    ForEach(appRows, id: \.id) { row in
                        StatsRowView(
                            row: row,
                            maxSeconds: appMaxSeconds,
                            leading: AnyView(rowLeading(for: row, website: false)),
                            formatDuration: formatDuration,
                            action: row.isOthers ? onAppsOthersTapped : nil
                        )
                    }
                }

                if !websiteRows.isEmpty {
                    statsSubsectionHeader("Websites")
                    ForEach(websiteRows, id: \.id) { row in
                        StatsRowView(
                            row: row,
                            maxSeconds: websiteMaxSeconds,
                            leading: AnyView(rowLeading(for: row, website: true)),
                            formatDuration: formatDuration,
                            action: row.isOthers ? onWebsitesOthersTapped : nil
                        )
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func statsSubsectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func statsEmptyHint(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func rowLeading(for row: DayTrackerView.UsageRowModel, website: Bool) -> some View {
        if row.isOthers {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.08))
        } else if website {
            WebsiteFaviconView(domain: row.bundleOrDomainKey)
        } else {
            Image(nsImage: appIcon(row.bundleOrDomainKey))
                .resizable()
                .interpolation(.high)
        }
    }
}

// MARK: - Interactive Stats Row View

fileprivate struct StatsRowView: View {
    let row: DayTrackerView.UsageRowModel
    let maxSeconds: TimeInterval
    let leading: AnyView
    let formatDuration: (TimeInterval) -> String
    let action: (() -> Void)?

    @State private var isHovered = false
    @State private var animateProgress = false

    private var fraction: Double {
        maxSeconds > 0 ? min(1, row.seconds / maxSeconds) : 0
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(row.isOthers ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08))
                        .frame(width: max(geo.size.width * CGFloat(animateProgress ? fraction : 0.0), 24), height: 20)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)

                    HStack(spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if row.isOthers {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 20, alignment: .leading)
                }
            }
            .frame(height: 20)

            Text(formatDuration(row.seconds))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(row.isOthers && isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if row.isOthers {
                withAnimation(.snappy(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .onTapGesture {
            if row.isOthers {
                action?()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                animateProgress = true
            }
        }
    }
}

// MARK: - Usage Detail View

private struct UsageDetailView: View {
    let title: String
    let rows: [DayTrackerView.UsageRowModel]
    let website: Bool
    @Binding var searchText: String
    let appIcon: (String) -> NSImage
    let formatDuration: (TimeInterval) -> String
    let onBack: () -> Void

    @State private var isBackHovered = false

    private var filteredRows: [DayTrackerView.UsageRowModel] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rows
        }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var maxSeconds: TimeInterval {
        filteredRows.map(\.seconds).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isBackHovered ? Color.primary.opacity(0.08) : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isBackHovered = hovering
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                // Item count badge
                Text("\(filteredRows.count) \(website ? "sites" : "apps")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
                .background(Color.primary.opacity(0.1))

            // Scrollable List
            if filteredRows.isEmpty {
                VStack {
                    Spacer()
                    Text("No results found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                .frame(height: 185)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredRows, id: \.id) { row in
                            StatsRowView(
                                row: row,
                                maxSeconds: maxSeconds,
                                leading: AnyView(rowLeading(for: row, website: website)),
                                formatDuration: formatDuration,
                                action: nil
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.snappy(duration: 0.28), value: filteredRows)
                }
                .frame(height: 185)
            }
        }
    }

    @ViewBuilder
    private func rowLeading(for row: DayTrackerView.UsageRowModel, website: Bool) -> some View {
        if website {
            WebsiteFaviconView(domain: row.bundleOrDomainKey)
        } else {
            Image(nsImage: appIcon(row.bundleOrDomainKey))
                .resizable()
                .interpolation(.high)
        }
    }
}

// MARK: - Rows

private struct WebsiteFaviconView: View {
    let domain: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: domain) {
            image = await FaviconLoader.shared.image(forDomain: domain)
        }
    }
}

