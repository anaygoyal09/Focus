import SwiftUI

struct PasswordPromptView: View {
    @EnvironmentObject var focusManager: FocusManager
    @State private var passwordInput: String = ""
    @State private var showWrongPassword: Bool = false
    @State private var shake: Bool = false
    
    var body: some View {
        ZStack {
            // Blurred background
            VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Main content card
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 32) {
                        // Icon with pulse animation
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 120, height: 120)
                            
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 88, height: 88)
                            
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                        }
                        
                        // Title and description
                        VStack(spacing: 12) {
                            Text("Time's Up")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.primary)
                            
                            if let blockedApp = focusManager.appState.currentBlockedApp {
                                Text("You've reached your limit for **\(blockedApp.name)**")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // Password section
                        VStack(spacing: 16) {
                            VStack(spacing: 8) {
                                Text("Want 5 more minutes?")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text("Type the passphrase to extend")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            SecureField("Enter passphrase...", text: $passwordInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(showWrongPassword ? Color.red.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .frame(width: 280)
                                .offset(x: shake ? -10 : 0)
                                .animation(.interpolatingSpring(stiffness: 500, damping: 10), value: shake)
                                .onSubmit {
                                    checkPassword()
                                }
                            
                            if showWrongPassword {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Incorrect passphrase")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.red)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        
                        // Action buttons
                        VStack(spacing: 10) {
                            Button(action: checkPassword) {
                                Text("Extend Time")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 200)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.defaultAction)

                            Button(action: {
                                focusManager.dismissBlocker()
                            }) {
                                Text("Close")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 200)
                                    .padding(.vertical, 10)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                    
                    Button(action: {
                        focusManager.dismissBlocker()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
                .padding(48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 40, y: 20)
                )
                
                Spacer()
                
                // Bottom hint
                VStack(spacing: 4) {
                    Text("Take a moment to reflect.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("Do you really need more time?")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func checkPassword() {
        if passwordInput == "iamthinkingtwice" {
            withAnimation {
                focusManager.extendTime(minutes: 5)
                passwordInput = ""
                showWrongPassword = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                showWrongPassword = true
                shake = true
            }
            passwordInput = ""
            
            // Reset shake
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shake = false
            }
        }
    }
}

// Background blur helper
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
