import SwiftUI

struct PasswordPromptView: View {
    @EnvironmentObject var focusManager: FocusManager

    private var blockedName: String {
        focusManager.appState.currentBlockedApp?.name ?? "This page"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.10, green: 0.10, blue: 0.10),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 16,
                    endRadius: 420
                )
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                colors: [Color.green.opacity(0.95), Color.green.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

                        Image(systemName: "target")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white.opacity(0.92))
                    }

                    Text("\(blockedName) has been blocked by Focus")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundColor(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 760)

                    Button(action: {
                        focusManager.snoozeCurrentBlock(minutes: 3)
                    }) {
                        Label("Snooze for 3 minutes", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }

                Spacer()

                Text("End your focus session to access this page.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.bottom, 44)
            }
            .padding(36)
        }
        .frame(minWidth: 920, minHeight: 620)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
