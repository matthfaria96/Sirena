import SwiftUI

/// Shown when tap creation failed — almost always missing the
/// System Audio Recording permission.
struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Precisa de acesso ao áudio")
                    .font(.system(size: 11, weight: .semibold))
                Text("Permita que o Sirena grave o áudio do sistema em Privacidade e Segurança, para controlar o volume de cada app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                if let settingsURL = URL(string: url) {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
