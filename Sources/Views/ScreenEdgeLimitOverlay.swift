import AppKit
import SwiftUI

// MARK: - SwiftUI content

private struct ScreenEdgeGlowLayer: View {
    private let edgeThickness: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let glow = LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.45, blue: 0.12).opacity(0.95),
                    Color(red: 0.95, green: 0.18, blue: 0.08).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                Rectangle()
                    .strokeBorder(glow, lineWidth: edgeThickness)
                    .blur(radius: 22)
                    .padding(-edgeThickness / 2)

                Rectangle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.55),
                                Color.red.opacity(0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 5
                    )
                    .padding(10)
            }
            .frame(width: w, height: h)
            .allowsHitTesting(false)
        }
    }
}

private struct DailyLimitOverlayChrome: View {
    let displayName: String
    let appIcon: NSImage

    var body: some View {
        ZStack {
            Color.black.opacity(0.0001)
                .ignoresSafeArea()

            ScreenEdgeGlowLayer()
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(displayName) is blocked")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Daily limit reached for today")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 420)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
                }
                .padding(.top, 52)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Controller

@MainActor
enum DailyLimitEdgeOverlayPresenter {
    private static var hostingWindow: NSWindow?
    private static var hideWorkItem: DispatchWorkItem?

    /// Shows a non-interactive edge glow (and brief banner) when a daily-limited app hits its cap.
    static func present(displayName: String, bundleID: String, autoDismissAfter: TimeInterval = 3.2) {
        hideWorkItem?.cancel()

        let icon: NSImage = {
            if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
                return NSWorkspace.shared.icon(forFile: path)
            }
            return NSWorkspace.shared.icon(forFile: "/Applications")
        }()
        let root = DailyLimitOverlayChrome(displayName: displayName, appIcon: icon)
        let host = NSHostingView(rootView: root)

        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let window: NSWindow
        if let existing = hostingWindow {
            window = existing
            window.contentView = host
            window.level = .screenSaver
        } else {
            let w = NSWindow(
                contentRect: union,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.contentView = host
            hostingWindow = w
            window = w
        }

        window.setFrame(union, display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()

        let work = DispatchWorkItem {
            dismiss()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter, execute: work)
    }

    static func dismiss() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hostingWindow?.orderOut(nil)
    }
}
