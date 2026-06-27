import Foundation
import AppKit

// MARK: - Permanent delete confirmation (shared across all views)

func confirmPermanentDelete(names: [String], onConfirm: @escaping () -> Void) {
    let label = names.count == 1 ? "\"\(names[0])\"" : "\(names.count) items"
    let alert = NSAlert()
    alert.messageText     = "Permanently delete \(label)?"
    alert.informativeText = "This cannot be undone. \(names.count == 1 ? "The item" : "The items") will be permanently deleted and cannot be recovered."
    alert.alertStyle      = .warning
    let deleteBtn = alert.addButton(withTitle: "Delete Permanently")
    deleteBtn.hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn { onConfirm() }
}

// MARK: - Action feedback (drives the in-app toast)

struct ActionFeedback {
    let icon: String
    let message: String
}

// MARK: - Safe AppleScript helpers
//
// Filenames on macOS may legally contain double quotes and backslashes. Building
// an AppleScript source string by interpolating a raw path lets a crafted file
// name break out of the string literal and inject arbitrary AppleScript (which
// can run shell commands) — a real code-execution risk when the user merely
// right-clicks a downloaded file. Always wrap untrusted text with this helper so
// it becomes a single, properly escaped AppleScript string literal.

/// Escapes `s` and wraps it in double quotes so it is a safe AppleScript string
/// literal — backslashes first, then quotes.
func appleScriptStringLiteral(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// Opens the native Finder "Get Info" window for each URL, with the path safely
/// escaped against AppleScript injection.
func showGetInfoInFinder(_ urls: [URL]) {
    for url in urls {
        let pathLiteral = appleScriptStringLiteral(url.path)
        let src = """
        tell application "Finder"
            activate
            open information window of (POSIX file \(pathLiteral) as alias)
        end tell
        """
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }
}

// MARK: - Folder / File creation

class FolderCreationService: ObservableObject {
    @Published var lastCreatedURL:     URL?
    @Published var errorMessage:       String?
    @Published var lastActionFeedback: ActionFeedback?

    func createFolder(at path: URL, name: String = "New Folder") {
        let target = uniqueURL(for: path.appendingPathComponent(name))
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                self.lastActionFeedback = ActionFeedback(
                    icon: "folder.badge.plus",
                    message: "Created \"\(target.lastPathComponent)\""
                )
                self.lastCreatedURL = target
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }

    func createFile(at path: URL, name: String = "untitled.txt") {
        let target = uniqueURL(for: path.appendingPathComponent(name))
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            DispatchQueue.main.async {
                self.errorMessage = "Could not create file at \(target.path)"
            }
            return
        }
        DispatchQueue.main.async {
            self.lastActionFeedback = ActionFeedback(
                icon: "doc.badge.plus",
                message: "Created \"\(target.lastPathComponent)\""
            )
            self.lastCreatedURL = target
        }
    }

    func uniqueURL(for base: URL) -> URL {
        var url = base
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let ext  = base.pathExtension
            let stem = base.deletingPathExtension().lastPathComponent
            let name = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            url = base.deletingLastPathComponent().appendingPathComponent(name)
            counter += 1
        }
        return url
    }
}

// MARK: - File operations (cut / copy / paste / rename / duplicate / undo)

class FileOperationsService: ObservableObject {
    @Published var clipboardURLs:      [URL]           = []
    @Published var isCut:              Bool            = false
    @Published var lastOpURL:          URL?
    @Published var errorMessage:       String?
    @Published var lastActionFeedback: ActionFeedback?

    private let undoMgr = UndoManager()

    var canUndo: Bool { undoMgr.canUndo }
    var canRedo: Bool { undoMgr.canRedo }

    // MARK: Clipboard

    func copy(_ urls: [URL]) {
        clipboardURLs = urls; isCut = false
        writeToPasteboard(urls)
        let label = urls.count == 1 ? "\"\(urls[0].lastPathComponent)\"" : "\(urls.count) items"
        lastActionFeedback = ActionFeedback(icon: "doc.on.doc", message: "Copied \(label)")
    }

    func cut(_ urls: [URL]) {
        clipboardURLs = urls; isCut = true
        writeToPasteboard(urls)
        let label = urls.count == 1 ? "\"\(urls[0].lastPathComponent)\"" : "\(urls.count) items"
        lastActionFeedback = ActionFeedback(icon: "scissors", message: "Cut \(label)")
    }

    private func writeToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    var pasteboardURLs: [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? clipboardURLs
    }

    // MARK: Paste

    func paste(to destination: URL, reload: @escaping () -> Void) {
        let sources = pasteboardURLs
        guard !sources.isEmpty else { return }
        let wasCut = isCut

        var pasted: [URL] = []
        for src in sources {
            let dest = uniqueURL(for: destination.appendingPathComponent(src.lastPathComponent))
            do {
                if wasCut { try FileManager.default.moveItem(at: src, to: dest) }
                else       { try FileManager.default.copyItem(at: src, to: dest) }
                pasted.append(dest)
            } catch {
                // Stop on the first failure but still register undo for whatever
                // already succeeded — otherwise a partial move would strand files
                // at the destination with no way to undo them.
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                break
            }
        }

        // Nothing got pasted (e.g. the very first item failed) — the error is
        // already surfaced; don't register an empty undo or show a success toast.
        guard !pasted.isEmpty else { return }

        if wasCut { clipboardURLs = []; isCut = false }

        if wasCut {
            // Move: undo by moving items back to their original locations
            let pairs = zip(sources, pasted).map { ($0, $1) }
            undoMgr.registerUndo(withTarget: self) { _ in
                for (orig, dest) in pairs {
                    try? FileManager.default.moveItem(at: dest, to: orig)
                }
                reload()
            }
        } else {
            // Copy: undo by removing the copies
            undoMgr.registerUndo(withTarget: self) { _ in
                pasted.forEach { try? FileManager.default.removeItem(at: $0) }
                reload()
            }
        }
        undoMgr.setActionName(wasCut ? "Move" : "Paste")
        objectWillChange.send()

        let count = pasted.count
        let label = count == 1 ? "\"\(pasted[0].lastPathComponent)\"" : "\(count) items"
        DispatchQueue.main.async {
            self.lastActionFeedback = ActionFeedback(
                icon: "doc.on.clipboard",
                message: (wasCut ? "Moved " : "Pasted ") + label
            )
            self.lastOpURL = pasted.first
            reload()
        }
    }

    // MARK: Rename

    func rename(_ url: URL, to newName: String, reload: @escaping () -> Void) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            undoMgr.registerUndo(withTarget: self) { _ in
                try? FileManager.default.moveItem(at: newURL, to: url)
                reload()
            }
            undoMgr.setActionName("Rename")
            objectWillChange.send()
            DispatchQueue.main.async {
                self.lastActionFeedback = ActionFeedback(
                    icon: "pencil",
                    message: "Renamed to \"\(newName)\""
                )
                self.lastOpURL = newURL
                reload()
            }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }

    // MARK: Duplicate

    func duplicate(_ urls: [URL], reload: @escaping () -> Void) {
        var created: [URL] = []
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext  = url.pathExtension
            let name = ext.isEmpty ? "\(stem) copy" : "\(stem) copy.\(ext)"
            let dest = uniqueURL(for: url.deletingLastPathComponent().appendingPathComponent(name))
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                created.append(dest)
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
        guard !created.isEmpty else { return }
        undoMgr.registerUndo(withTarget: self) { _ in
            created.forEach { try? FileManager.default.removeItem(at: $0) }
            reload()
        }
        undoMgr.setActionName("Duplicate")
        objectWillChange.send()
        let count = created.count
        let label = count == 1 ? "\"\(created[0].lastPathComponent)\"" : "\(count) items"
        DispatchQueue.main.async {
            self.lastActionFeedback = ActionFeedback(icon: "plus.square.on.square", message: "Duplicated \(label)")
            self.lastOpURL = created.first
            reload()
        }
    }

    // MARK: Trash

    func trash(_ urls: [URL], reload: @escaping () -> Void) {
        var pairs: [(orig: URL, trash: URL)] = []
        for url in urls {
            var trashURL: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
                if let t = trashURL as? URL { pairs.append((url, t)) }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
        guard !pairs.isEmpty else { return }
        undoMgr.registerUndo(withTarget: self) { _ in
            pairs.forEach { try? FileManager.default.moveItem(at: $0.trash, to: $0.orig) }
            reload()
        }
        undoMgr.setActionName("Move to Trash")
        objectWillChange.send()
        let count = pairs.count
        let label = count == 1 ? "\"\(pairs[0].orig.lastPathComponent)\"" : "\(count) items"
        DispatchQueue.main.async {
            self.lastActionFeedback = ActionFeedback(icon: "trash", message: "Trashed \(label)")
            reload()
        }
    }

    // MARK: - Extract archive

    func extract(_ url: URL, reload: @escaping () -> Void) {
        let dest = url.deletingLastPathComponent()
        let ext  = url.pathExtension.lowercased()

        // Prefer The Unarchiver when installed (modern bundle-id lookup; the old
        // fullPath(forApplication:) name-based API is deprecated).
        let unarchiverIDs = ["cx.c3.theunarchiver", "com.macpaw.site.theunarchiver"]
        if let unaURL = unarchiverIDs.lazy
            .compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
            .first {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: unaURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in DispatchQueue.main.async { reload() } }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            switch ext {
            case "zip":
                p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                p.arguments     = ["-o", url.path, "-d", dest.path]
            case "tar":
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                p.arguments     = ["-xf", url.path, "-C", dest.path]
            case "gz", "tgz":
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                p.arguments     = ["-xzf", url.path, "-C", dest.path]
            case "bz2":
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                p.arguments     = ["-xjf", url.path, "-C", dest.path]
            case "xz":
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                p.arguments     = ["-xJf", url.path, "-C", dest.path]
            default:
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                return
            }
            do { try p.run(); p.waitUntilExit(); DispatchQueue.main.async { reload() } }
            catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
        }
    }

    // MARK: - Compress (zip)

    func compress(_ urls: [URL], reload: @escaping () -> Void) {
        guard let first = urls.first else { return }
        let base    = first.deletingLastPathComponent()
        let zipName = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent + ".zip"
            : "Archive.zip"
        let dest = uniqueURL(for: base.appendingPathComponent(zipName))
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL      = URL(fileURLWithPath: "/usr/bin/zip")
            p.currentDirectoryURL = base
            p.arguments = ["-r", dest.path] + urls.map { $0.lastPathComponent }
            do { try p.run(); p.waitUntilExit(); DispatchQueue.main.async { reload() } }
            catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
        }
    }

    // MARK: - Make Alias (symlink)

    func makeAlias(for url: URL, reload: @escaping () -> Void) {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        let name = ext.isEmpty ? "\(stem) alias" : "\(stem) alias.\(ext)"
        let dest = uniqueURL(for: url.deletingLastPathComponent().appendingPathComponent(name))
        do {
            try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: url)
            DispatchQueue.main.async { reload() }
        } catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
    }

    // MARK: - Tags (Finder-compatible: real color tags, multiple per file, toggle)

    /// Toggle a standard Finder color tag on the given files, mirroring Finder:
    /// if EVERY file already has the color it is removed from all; otherwise it is
    /// added to all. Other tags on the file (additional colors, custom text tags)
    /// are always preserved.
    func toggleColorTag(_ colorName: String, on urls: [URL], reload: @escaping () -> Void) {
        guard !urls.isEmpty,
              let number = FileItem.colorNameToLabel[colorName.lowercased()] else { return }
        let canonical = FileItem.labelToColorName[number] ?? colorName
        let target    = canonical.lowercased()

        DispatchQueue.global(qos: .userInitiated).async {
            let allHave = urls.allSatisfy { url in
                self.readTagNames(url).contains { $0.lowercased() == target }
            }
            for url in urls {
                var names = self.readTagNames(url)
                names.removeAll { $0.lowercased() == target }   // de-dupe / remove existing
                if !allHave { names.append(canonical) }          // add unless we're toggling off
                self.writeTags(names, to: url)
            }
            DispatchQueue.main.async {
                self.lastActionFeedback = ActionFeedback(
                    icon:    allHave ? "tag.slash" : "tag.fill",
                    message: allHave ? "Removed \(canonical) tag" : "Tagged \(canonical)"
                )
                reload()
            }
        }
    }

    /// Remove every tag (colors + custom) from the given files.
    func clearTags(on urls: [URL], reload: @escaping () -> Void) {
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls { self.writeTags([], to: url) }
            DispatchQueue.main.async {
                self.lastActionFeedback = ActionFeedback(icon: "tag.slash", message: "Cleared tags")
                reload()
            }
        }
    }

    /// Current tag names. The system returns plain display names (e.g. "Red",
    /// "Work") with any color-index suffix already stripped.
    private func readTagNames(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Write tags, encoding each of the 7 standard colors as "Name\nNumber" so
    /// macOS registers a REAL color tag (verified: a plain "Red" string is stored
    /// as a colorless custom tag, while "Red\n6" sets the red swatch / labelNumber
    /// 6). Custom (non-color) tags are written through unchanged.
    private func writeTags(_ names: [String], to url: URL) {
        let encoded: [String] = names.map { name in
            if let num = FileItem.colorNameToLabel[name.lowercased()] {
                let canonical = FileItem.labelToColorName[num] ?? name
                return "\(canonical)\n\(num)"
            }
            return name
        }
        try? (url as NSURL).setResourceValue(encoded as NSArray, forKey: .tagNamesKey)
    }

    // MARK: - Copy path to clipboard

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        // Post with object:nil — Swift structs don't bridge through NSNotification.object
        // (id in ObjC), so the receiver can't cast them back. ContentView hardcodes the toast.
        NotificationCenter.default.post(name: .ffCopyPathFeedback, object: nil)
    }

    // MARK: - Share

    func showShareSheet(for urls: [URL]) {
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async {
            guard let win = NSApp.keyWindow, let view = win.contentView else { return }
            NSSharingServicePicker(items: urls.map { $0 as NSURL })
                .show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    func shareViaAirDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls.map { $0 as NSURL })
    }

    // MARK: - Permanent delete (no undo — caller must confirm first)

    func permanentlyDelete(_ urls: [URL], reload: @escaping () -> Void) {
        var deleted: [URL] = []
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                deleted.append(url)
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
        guard !deleted.isEmpty else { return }
        let count = deleted.count
        let label = count == 1 ? "\"\(deleted[0].lastPathComponent)\"" : "\(count) items"
        DispatchQueue.main.async {
            self.lastActionFeedback = ActionFeedback(icon: "trash.fill", message: "Permanently deleted \(label)")
            reload()
        }
    }

    // MARK: Undo / Redo

    func undo() {
        let name = undoMgr.undoActionName
        undoMgr.undo()
        objectWillChange.send()
        let msg = name.isEmpty ? "Undone" : "Undone: \(name)"
        lastActionFeedback = ActionFeedback(icon: "arrow.uturn.backward", message: msg)
    }

    func redo() {
        let name = undoMgr.redoActionName
        undoMgr.redo()
        objectWillChange.send()
        let msg = name.isEmpty ? "Redone" : "Redone: \(name)"
        lastActionFeedback = ActionFeedback(icon: "arrow.uturn.forward", message: msg)
    }

    // MARK: Helpers

    private func uniqueURL(for base: URL) -> URL {
        var url = base; var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let ext  = base.pathExtension
            let stem = base.deletingPathExtension().lastPathComponent
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            url = base.deletingLastPathComponent().appendingPathComponent(name)
            n += 1
        }
        return url
    }
}

// MARK: - Quick Look bridge

import Quartz

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private(set) var urls: [URL] = []

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate   = self
        panel.isVisible ? panel.reloadData() : panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        (urls.indices.contains(index) ? urls[index] : urls[0]) as NSURL
    }
}

// MARK: - QL responder chain shim

import SwiftUI

struct QLResponderSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> _QLResponderView { _QLResponderView() }
    func updateNSView(_ nsView: _QLResponderView, context: Context) {}
}

final class _QLResponderView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let w = window else { return }
        if !(w.nextResponder is _QLResponderView) {
            nextResponder   = w.nextResponder
            w.nextResponder = self
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate   = QuickLookController.shared
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}
