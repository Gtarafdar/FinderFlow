import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {

    override init() {
        super.init()
        let fm = FileManager.default
        FIFinderSyncController.default().directoryURLs = Set([
            fm.homeDirectoryForCurrentUser,
            fm.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        ].compactMap { $0 })
    }

    // MARK: - Toolbar

    override var toolbarItemName: String { "FinderFlow" }

    override var toolbarItemToolTip: String { "FinderFlow: Enhanced file management" }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "FinderFlow")
            ?? NSImage(named: NSImage.folderName)!
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(withTitle: "New Folder Here",  action: #selector(createFolderHere), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Path",         action: #selector(copyPath),         keyEquivalent: "")
        menu.addItem(withTitle: "Open in Terminal",  action: #selector(openInTerminal),   keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open in FinderFlow", action: #selector(openInFinderFlow), keyEquivalent: "")
        return menu
    }

    @objc private func createFolderHere() {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        let folder = uniqueURL(for: target.appendingPathComponent("New Folder"))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @objc private func copyPath() {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target.path, forType: .string)
    }

    @objc private func openInTerminal() {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        // Shell-quote the path, then wrap the whole command as a safe AppleScript
        // string literal so a path containing " or \ can't break out / inject.
        let shellQuoted = "'" + target.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let cmd = "cd \(shellQuoted)"
        let cmdLiteral = "\"" + cmd.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        let script = """
        tell application "Terminal"
            activate
            do script \(cmdLiteral)
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    @objc private func openInFinderFlow() {
        guard let target = FIFinderSyncController.default().targetedURL(),
              let encoded = target.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "finderflow://open?path=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func uniqueURL(for base: URL) -> URL {
        var url = base
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent) \(counter)")
            counter += 1
        }
        return url
    }
}
