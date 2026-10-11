import SwiftUI
import AppKit

/// Shown once after a successful first launch (Gatekeeper already passed).
struct FirstRunSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var locale: LocaleState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.s("You're all set"))
                        .font(.title2.weight(.semibold))
                    Text("FinderFlow \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(L10n.s("If macOS asked you to allow FinderFlow once under System Settings → Privacy & Security, that was expected. This is a free open-source app without a paid Apple Developer certificate — the one-time Open Anyway step is safe."))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.s("When you browse Desktop, Documents, or Downloads, macOS may ask for folder access — click Allow. You can enable the optional Finder right-click menu later under Login Items & Extensions."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("GitHub") {
                    if let u = URL(string: "https://github.com/Gtarafdar/FinderFlow") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .buttonStyle(.link)

                Spacer()

                Button(L10n.s("Continue")) {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
