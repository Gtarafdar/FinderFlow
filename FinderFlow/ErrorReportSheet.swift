import SwiftUI
import AppKit

/// Compact, scrollable error dialog — never overflows the screen.
/// Copy and Contact Support are user-initiated only (no silent upload).
struct ErrorReportSheet: View {
    let message: String
    let onDismiss: () -> Void

    private var summary: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 240 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 240)
        return String(trimmed[..<idx]) + "…"
    }

    private var diagnosticBlob: String {
        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build  = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os     = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        FinderFlow \(appVer) (\(build))
        macOS \(os)

        \(message)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.headline)
                Spacer()
            }

            Text(summary)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if message.count > 240 {
                GroupBox("Details") {
                    ScrollView {
                        Text(message)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack(spacing: 10) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnosticBlob, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Contact Support") { openSupport() }
                    .help("Copies diagnostics, then opens GitHub Issues")

                Spacer()

                Button("OK", role: .cancel, action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func openSupport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticBlob, forType: .string)
        // Prefer GitHub Issues (public repo). Diagnostics are already on the clipboard to paste.
        if let issues = URL(string: "https://github.com/Gtarafdar/FinderFlow/issues/new?title=Error%20report") {
            NSWorkspace.shared.open(issues)
        }
    }
}
