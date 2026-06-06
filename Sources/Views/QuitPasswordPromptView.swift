import AppKit
import SwiftUI

/// Quit-gating controller. Presents a password sheet if a quit password is set,
/// otherwise quits immediately. Uses a hosted window so it works from the menu bar.
@MainActor
final class QuitController {
    static let shared = QuitController()
    private var window: NSWindow?

    func requestQuit() {
        let manager = FocusManager.shared
        if manager.settings.quitPasswordHash == nil {
            NSApp.terminate(nil)
            return
        }
        if window != nil { window?.makeKeyAndOrderFront(nil); return }
        let view = QuitPasswordPromptView(
            verify: { manager.verifyQuitPassword($0) },
            onSuccess: { [weak self] in
                self?.window?.close()
                self?.window = nil
                NSApp.terminate(nil)
            },
            onCancel: { [weak self] in
                self?.window?.close()
                self?.window = nil
            }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable]
        w.title = "Quit Focus"
        w.level = .modalPanel
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct QuitPasswordPromptView: View {
    let verify: (String) -> Bool
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "power").font(.title2).foregroundStyle(.red)
                Text("Quit Focus").font(.headline)
            }
            Text("Enter password to quit Focus.").font(.callout).foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let e = error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Quit", role: .destructive, action: submit).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func submit() {
        if verify(password) { onSuccess() }
        else { error = "Incorrect password."; password = "" }
    }
}
