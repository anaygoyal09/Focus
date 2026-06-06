import SwiftUI

struct PasswordPromptView: View {
    let title: String
    let message: String
    let verify: (String) -> Bool
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(.tint)
                Text(title).font(.headline)
            }
            Text(message).font(.callout).foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let e = error {
                Text(e).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Confirm", action: submit).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func submit() {
        if verify(password) {
            onSuccess()
            dismiss()
        } else {
            error = "Incorrect password."
            password = ""
        }
    }
}
