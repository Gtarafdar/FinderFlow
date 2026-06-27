import SwiftUI
import AppKit
import CoreServices
import UniformTypeIdentifiers

/// Manages whether FinderFlow is registered as the system's default handler for
/// folders. This is the closest macOS allows to a "default file manager":
/// Finder itself can never be replaced (it owns the Desktop, drive mounting,
/// Open/Save dialogs and the Dock icon), but folder-open requests from the
/// `open` command, other apps, and "Open With" can be routed to FinderFlow.
enum DefaultFolderHandler {

    static var bundleURL: URL { Bundle.main.bundleURL }
    static var bundleID: String? { Bundle.main.bundleIdentifier }

    private static let finderBundleID = "com.apple.finder"

    /// True when LaunchServices currently routes folders to FinderFlow.
    static var isDefault: Bool {
        guard let current = NSWorkspace.shared.urlForApplication(toOpen: .folder) else { return false }
        return current.standardizedFileURL == bundleURL.standardizedFileURL
    }

    /// Register FinderFlow as the default folder handler.
    static func makeDefault(_ completion: @escaping (Error?) -> Void) {
        apply(handlerBundleID: bundleID ?? "", fileViewer: bundleID, completion: completion)
    }

    /// Restore Finder as the default folder handler.
    static func restoreFinder(_ completion: @escaping (Error?) -> Void) {
        apply(handlerBundleID: finderBundleID, fileViewer: nil, completion: completion)
    }

    private static func apply(handlerBundleID: String,
                              fileViewer: String?,
                              completion: @escaping (Error?) -> Void) {
        // The modern NSWorkspace setter only targets a single file URL; setting the
        // default for an entire content type (every folder) still goes through
        // LaunchServices' role-handler API.
        let status = LSSetDefaultRoleHandlerForContentType("public.folder" as CFString,
                                                           .all,
                                                           handlerBundleID as CFString)
        setGlobalFileViewer(fileViewer)
        let error: Error? = (status == noErr)
            ? nil
            : NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        completion(error)
    }

    /// The global `NSFileViewer` preference is what some apps consult for
    /// "Reveal/Show in Finder". Passing `nil` removes the override.
    private static func setGlobalFileViewer(_ bundleID: String?) {
        let key = "NSFileViewer" as CFString
        CFPreferencesSetValue(key,
                              bundleID as CFString?,
                              kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)
    }
}

struct SettingsView: View {
    @State private var isDefault = DefaultFolderHandler.isDefault
    @State private var working = false
    @State private var statusMessage: String?

    @AppStorage("ffEditorSniffUnknown") private var sniffUnknown = true

    var body: some View {
        Form {
            Section("Text editor") {
                Toggle(isOn: $sniffUnknown) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open unknown file types in the editor")
                        Text("When on, files without a known code extension open in FinderFlow’s editor if they look like text. When off, only known text/code files do.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { isDefault },
                    set: { applyDefault($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open folders in FinderFlow")
                            .font(.headline)
                        Text("Routes folder-open actions (the `open` command, other apps, and “Open With”) to FinderFlow instead of Finder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(working)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("What this can and can't do") {
                Label("FinderFlow opens when you open a folder from Terminal, other apps, or “Open With”.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Label("Finder can't be fully replaced. The Desktop, drive mounting, Open/Save dialogs and the Dock’s Finder icon always stay Finder.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Label("Some changes only take effect after you log out and back in (or restart).",
                      systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { isDefault = DefaultFolderHandler.isDefault }
    }

    private func applyDefault(_ enable: Bool) {
        working = true
        statusMessage = nil
        let onDone: (Error?) -> Void = { error in
            working = false
            isDefault = DefaultFolderHandler.isDefault
            if let error {
                statusMessage = "Couldn’t update the setting: \(error.localizedDescription)"
            } else if enable {
                statusMessage = "FinderFlow is now the default for folders. Log out and back in if some apps still open Finder."
            } else {
                statusMessage = "Finder restored as the default for folders."
            }
        }
        if enable {
            DefaultFolderHandler.makeDefault(onDone)
        } else {
            DefaultFolderHandler.restoreFinder(onDone)
        }
    }
}
