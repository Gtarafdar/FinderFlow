import SwiftUI
import ServiceManagement

@main
struct FinderFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var favorites = FavoritesService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(favorites)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            FinderFlowCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Folder requested while launching before any window is ready (cold launch).
    /// ContentView consumes this on first appear.
    static var pendingNavigationURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Sync stored toggle with actual SMAppService registration state
        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Open folders / finderflow:// links

    /// Handles both file URLs (folder/file opened with FinderFlow, e.g. "Open With",
    /// `open -a`, or being the default folder handler) and the custom `finderflow://`
    /// scheme posted by the Finder Sync extension's "Open in FinderFlow" item.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleOpen(url) }
    }

    private func handleOpen(_ url: URL) {
        let targetPath: String?
        if url.isFileURL {
            targetPath = url.path
        } else if url.scheme == "finderflow" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            targetPath = comps?.queryItems?
                .first(where: { $0.name == "path" })?.value
        } else {
            targetPath = nil
        }

        guard let path = targetPath, !path.isEmpty else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }

        let url = URL(fileURLWithPath: path)

        DispatchQueue.main.async {
            if isDir.boolValue {
                AppDelegate.pendingNavigationURL = url
                NotificationCenter.default.post(name: .navigateToPath, object: url)
            } else if TextFileDetector.isEditableText(url) {
                // A text/code file opened with FinderFlow → open it in the editor window.
                EditorWindowManager.shared.open(url)
            } else {
                // Other files: reveal the enclosing folder.
                let parent = url.deletingLastPathComponent()
                AppDelegate.pendingNavigationURL = parent
                NotificationCenter.default.post(name: .navigateToPath, object: parent)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct FinderFlowCommands: Commands {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some Commands {
        CommandMenu("FinderFlow") {
            Button("New Folder") {
                NotificationCenter.default.post(name: .createNewFolder, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Toggle Hidden Files") {
                NotificationCenter.default.post(name: .toggleHiddenFiles, object: nil)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    if #available(macOS 13.0, *) {
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                }
            ))
        }
    }
}

extension Notification.Name {
    static let createNewFolder   = Notification.Name("createNewFolder")
    static let toggleHiddenFiles = Notification.Name("toggleHiddenFiles")
    static let navigateToPath    = Notification.Name("navigateToPath")
    static let refreshDirectory  = Notification.Name("FinderFlow.refreshDirectory")
    static let ffCopyPathFeedback = Notification.Name("FF.copyPathFeedback")
}
