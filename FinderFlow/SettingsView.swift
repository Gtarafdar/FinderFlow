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
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var locale = LocaleState.shared
    @State private var isDefault = DefaultFolderHandler.isDefault
    @State private var working = false
    @State private var statusMessage: String?
    @AppStorage("ffEditorSniffUnknown") private var sniffUnknown = true
    @AppStorage(UserPreferences.viewModeKey)       private var viewModeRaw    = UserPreferences.defaultViewMode.rawValue
    @AppStorage(UserPreferences.sortFieldKey)      private var sortFieldRaw   = UserPreferences.defaultSortField.rawValue
    @AppStorage(UserPreferences.sortAscendingKey)  private var sortAscending  = UserPreferences.defaultSortAscending
    @AppStorage(UserPreferences.groupByKey)        private var groupByRaw     = UserPreferences.defaultGroupBy.rawValue
    @AppStorage(UserPreferences.folderOrderKey)    private var folderOrderRaw = UserPreferences.defaultFolderOrder.rawValue

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { updateManager.autoCheckEnabled },
            set: { updateManager.autoCheckEnabled = $0 }
        )
    }

    var body: some View {
        Form {
            Section(L10n.s("Language")) {
                Picker(L10n.s("Interface language"), selection: Binding(
                    get: { locale.language },
                    set: { locale.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section(L10n.s("Updates")) {
                LabeledContent(L10n.s("Version"), value: updateManager.currentVersion)
                Toggle(L10n.s("Check for updates automatically"), isOn: autoCheckBinding)
                Button(L10n.s("Check for Updates…")) {
                    updateManager.checkForUpdates()
                }
                Text(L10n.s("Sparkle installs an update only when it carries the maintainer's signature. Version 1.5.2 and earlier need one manual download from GitHub."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.s("Browse defaults")) {
                Text(L10n.s("New installs start with Finder-like settings: list view, date-modified groups sorted newest first, folders on top. Reset restores those defaults."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.s("Reset to Finder defaults")) {
                    UserPreferences.applyFactoryBrowseDefaults()
                    viewModeRaw    = UserPreferences.defaultViewMode.rawValue
                    sortFieldRaw   = UserPreferences.defaultSortField.rawValue
                    sortAscending  = UserPreferences.defaultSortAscending
                    groupByRaw     = UserPreferences.defaultGroupBy.rawValue
                    folderOrderRaw = UserPreferences.defaultFolderOrder.rawValue
                }
            }

            Section(L10n.s("Text editor")) {
                Toggle(isOn: $sniffUnknown) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s("Open unknown file types in the editor"))
                        Text(L10n.s("When on, files without a known code extension open in FinderFlow’s editor if they look like text. When off, only known text/code files do."))
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
                        Text(L10n.s("Open folders in FinderFlow"))
                            .font(.headline)
                        Text(L10n.s("Routes folder-open actions (the `open` command, other apps, and “Open With”) to FinderFlow instead of Finder."))
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

            Section(L10n.s("What this can and can't do")) {
                Label(L10n.s("FinderFlow opens when you open a folder from Terminal, other apps, or “Open With”."),
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Label(L10n.s("Finder can't be fully replaced. The Desktop, drive mounting, Open/Save dialogs and the Dock’s Finder icon always stay Finder."),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Label(L10n.s("Some changes only take effect after you log out and back in (or restart)."),
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
                statusMessage = L10n.sf("Couldn't update the setting: %@", error.localizedDescription)
            } else if enable {
                statusMessage = L10n.s("FinderFlow is now the default for folders. Log out and back in if some apps still open Finder.")
            } else {
                statusMessage = L10n.s("Finder restored as the default for folders.")
            }
        }
        if enable {
            DefaultFolderHandler.makeDefault(onDone)
        } else {
            DefaultFolderHandler.restoreFinder(onDone)
        }
    }
}
