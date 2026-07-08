import SwiftUI
import AppKit

// MARK: - Detected IDE/tool state

struct InstalledApps {
    var vscode:     NSImage? = nil   // nil → not installed, don't show button
    var vscodePath: String?  = nil   // resolved app path for VS Code
    var claude:     NSImage? = nil
    var claudeCLI:  String?  = nil   // path to `claude` CLI
    var cursor:     NSImage? = nil
    var cursorPath: String?  = nil   // resolved app path for Cursor
    var codex:      NSImage? = nil
    var codexPath:  String?  = nil
}

// MARK: - Toolbar

struct QuickActionsToolbar: View {
    @Binding var currentPath:    URL
    let selectedURL:             URL?   // selected folder, nil → use currentPath for IDEs
    let selectedCount:           Int    // enables delete button
    let onCreateFolder:          () -> Void
    let onCreateFile:            () -> Void
    let onDelete:                () -> Void
    @ObservedObject var fileOps: FileOperationsService
    @Binding var viewMode:       ViewMode
    @Binding var sortField:      SortField
    @Binding var sortAscending:  Bool
    @Binding var showHidden:     Bool
    @Binding var groupBy:        GroupBy
    @Binding var folderOrder:    FolderOrder
    @Binding var showPreview:    Bool
    @Binding var showColumnTree: Bool
    let onReload: () -> Void

    @State private var apps = InstalledApps()

    private var openTarget: URL { selectedURL ?? currentPath }

    var body: some View {
        HStack(spacing: 6) {

            // ── Create ────────────────────────────────────────────────────
            ToolbarActionButton(icon: "folder.badge.plus", label: "New Folder") { onCreateFolder() }
            ToolbarActionButton(icon: "doc.badge.plus",    label: "New Text File") { onCreateFile() }

            Divider().frame(height: 20)

            // ── Undo / Redo ───────────────────────────────────────────────
            ToolbarActionButton(icon: "arrow.uturn.backward", label: "Undo") { fileOps.undo() }
                .disabled(!fileOps.canUndo)
            ToolbarActionButton(icon: "arrow.uturn.forward", label: "Redo") { fileOps.redo() }
                .disabled(!fileOps.canRedo)

            Divider().frame(height: 20)

            // ── Paste / Copy Path ─────────────────────────────────────────
            ToolbarActionButton(icon: "doc.on.clipboard", label: "Paste") {
                fileOps.paste(to: currentPath, reload: onReload)
            }
            .disabled(fileOps.pasteboardURLs.isEmpty)

            ToolbarActionButton(icon: "doc.on.clipboard.fill", label: "Copy Path") {
                fileOps.copyPath(currentPath.path)
            }

            // ── Delete ────────────────────────────────────────────────────
            ToolbarActionButton(icon: "trash", label: "Delete Permanently…") { onDelete() }
                .disabled(selectedCount == 0)

            Divider().frame(height: 20)

            // ── Terminal (always visible) ─────────────────────────────────
            ToolbarActionButton(icon: "terminal", label: "Open Terminal") {
                openInTerminal(openTarget)
            }

            // ── IDEs: only shown when detected ────────────────────────────
            if let icon = apps.vscode {
                AppIconToolbarButton(appIcon: icon, label: "Open in VS Code") {
                    openInVSCode(openTarget)
                }
            }

            if let icon = apps.claude {
                AppIconToolbarButton(appIcon: icon, label: "Open in Claude Code (opens Terminal)") {
                    openInClaudeCode(openTarget)
                }
            }

            if let icon = apps.cursor {
                AppIconToolbarButton(appIcon: icon, label: "Open in Cursor") {
                    openInCursor(openTarget)
                }
            }

            if let icon = apps.codex {
                AppIconToolbarButton(appIcon: icon, label: "Open in Codex") {
                    openInCodex(openTarget)
                }
            }

            Divider().frame(height: 20)

            // ── Toggles ───────────────────────────────────────────────────
            Toggle(isOn: $showHidden) {
                Label("Hidden Files", systemImage: showHidden ? "eye" : "eye.slash")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button).buttonStyle(.borderless)
            .help(showHidden ? "Hide hidden files" : "Show hidden files")

            Menu {
                Picker("Group By", selection: $groupBy) {
                    ForEach(GroupBy.allCases) { g in
                        Text(g.menuTitle).tag(g)
                    }
                }
            } label: {
                Image(systemName: groupBy == .none ? "rectangle.3.group" : "rectangle.3.group.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(groupBy == .none ? Color.primary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help(groupBy == .none ? "Group By" : "Grouped by \(groupBy.menuTitle)")

            Toggle(isOn: $showPreview) {
                Label("File Preview", systemImage: showPreview ? "doc.richtext.fill" : "doc.richtext")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button).buttonStyle(.borderless)
            .help(showPreview ? "Hide preview panel" : "Show file preview panel")

            if viewMode == .columns {
                Toggle(isOn: $showColumnTree) {
                    Label("Show Tree", systemImage: showColumnTree ? "sidebar.left" : "rectangle.split.1x2")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button).buttonStyle(.borderless)
                .help(showColumnTree ? "Hide folder tree — show current folder only"
                                     : "Show full folder tree from root")
            }

            ToolbarActionButton(icon: "arrow.clockwise", label: "Refresh") { onReload() }

            Divider().frame(height: 20)

            // ── Go Up ─────────────────────────────────────────────────────
            ToolbarActionButton(icon: "arrow.up", label: "Go Up") {
                let p = currentPath.deletingLastPathComponent()
                if p != currentPath { currentPath = p }
            }

            Spacer()

            // ── Sort / folder order ───────────────────────────────────────
            HStack(spacing: 2) {
                Picker("Sort", selection: $sortField) {
                    ForEach(SortField.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.menu).frame(maxWidth: 138).help("Sort by")

                Button { sortAscending.toggle() } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down").font(.caption)
                }
                .buttonStyle(.borderless)
                .help(sortAscending ? "Ascending" : "Descending")

                Menu {
                    Picker("Folders", selection: $folderOrder) {
                        ForEach(FolderOrder.allCases) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }
                } label: {
                    Image(systemName: folderOrder == .foldersFirst ? "folder.fill"
                          : (folderOrder == .filesFirst ? "doc.fill" : "arrow.up.arrow.down"))
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Folder / file order: \(folderOrder.rawValue)")
            }

            Divider().frame(height: 20)

            // ── View mode ─────────────────────────────────────────────────
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented).frame(width: 96).help("Switch view")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
        // Show IDE buttons instantly from last-known-good cache,
        // then re-detect in background in case anything changed.
        loadCachedApps()
        detectInstalledApps()
    }
    }

    // MARK: - App detection cache (UserDefaults, 6-hour TTL)

    private struct AppCache: Codable {
        let timestamp:  Double   // timeIntervalSince1970
        let vscodePath: String?
        let claudeCLI:  String?
        let claudeApp:  String?
        let cursorPath: String?
        let codexPath:  String?
        let codexCLI:   String?
    }
    private static let kCacheKey = "FF.appDetectionCache.v2"
    private static let kCacheTTL: Double = 6 * 3600   // 6 hours

    private func loadCachedApps() {
        guard let data = UserDefaults.standard.data(forKey: Self.kCacheKey),
              let c    = try? JSONDecoder().decode(AppCache.self, from: data),
              Date().timeIntervalSince1970 - c.timestamp < Self.kCacheTTL
        else { return }

        let fm = FileManager.default
        var a  = InstalledApps()

        if let p = c.vscodePath, fm.fileExists(atPath: p) {
            a.vscodePath = p
            a.vscode     = NSWorkspace.shared.icon(forFile: p)
        }
        if let cli = c.claudeCLI, fm.fileExists(atPath: cli) {
            a.claudeCLI = cli
            if let app = c.claudeApp, fm.fileExists(atPath: app) {
                a.claude = NSWorkspace.shared.icon(forFile: app)
            } else {
                a.claude = NSImage(systemSymbolName: "brain.head.profile",
                                   accessibilityDescription: "Claude Code")
            }
        }
        if let p = c.cursorPath, fm.fileExists(atPath: p) {
            a.cursorPath = p
            a.cursor     = NSWorkspace.shared.icon(forFile: p)
        }
        if let p = c.codexPath, fm.fileExists(atPath: p) {
            a.codexPath = p
            a.codex     = NSWorkspace.shared.icon(forFile: p)
        } else if let cli = c.codexCLI, fm.fileExists(atPath: cli) {
            a.codex = NSImage(systemSymbolName: "terminal",
                              accessibilityDescription: "Codex")
        }
        apps = a
    }

    private func saveCachedApps(_ detected: InstalledApps, claudeApp: String?) {
        let c = AppCache(
            timestamp:  Date().timeIntervalSince1970,
            vscodePath: detected.vscodePath,
            claudeCLI:  detected.claudeCLI,
            claudeApp:  claudeApp,
            cursorPath: detected.cursorPath,
            codexPath:  detected.codexPath,
            codexCLI:   nil
        )
        if let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: Self.kCacheKey)
        }
    }

    // MARK: - App detection (background queue, no UI impact)

    private func detectInstalledApps() {
        DispatchQueue.global(qos: .background).async {
            var detected = InstalledApps()

            // Returns the first matching app URL from bundle IDs or direct paths
            func appURL(bundleIDs: [String], appPaths: [String] = []) -> URL? {
                for bid in bundleIDs {
                    if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                        return u
                    }
                }
                for path in appPaths where FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
                return nil
            }

            func iconForApp(_ url: URL) -> NSImage {
                NSWorkspace.shared.icon(forFile: url.path)
            }

            // Find a CLI via login shell `which` — handles nvm, homebrew, etc.
            func whichCLI(_ name: String) -> String? {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-l", "-c", "which \(name) 2>/dev/null"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError  = Pipe()
                guard (try? p.run()) != nil else { return nil }
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !result.isEmpty, FileManager.default.fileExists(atPath: result) else { return nil }
                return result
            }

            // Also check known fixed paths (fast, no shell spawn)
            func fixedCLI(_ paths: [String]) -> String? {
                paths.first { FileManager.default.fileExists(atPath: $0) }
            }

            // ── VS Code ───────────────────────────────────────────────────
            // Only show VS Code button when the VS Code *app* is installed (not CLI-only),
            // so we're sure we open VS Code and not Cursor's `code` shim.
            if let url = appURL(bundleIDs: ["com.microsoft.VSCode"],
                                appPaths: ["/Applications/Visual Studio Code.app"]) {
                detected.vscode     = iconForApp(url)
                detected.vscodePath = url.path
            }

            // ── Claude Code ───────────────────────────────────────────────
            // Only show the button when the `claude` CLI is actually installed.
            // Showing it without the CLI just confuses users (Terminal opens
            // but immediately shows "command not found").
            let claudeFixed = fixedCLI([
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude",
                "\(NSHomeDirectory())/.claude/local/claude",
                "\(NSHomeDirectory())/.volta/bin/claude",
            ])
            let claudeCLIPath = claudeFixed ?? whichCLI("claude")
            let claudeAppURL  = appURL(
                bundleIDs: ["com.anthropic.claudefordesktop",
                            "com.anthropic.claude-mac",
                            "com.anthropic.claude"],
                appPaths:  ["/Applications/Claude.app"]
            )
            if let cliPath = claudeCLIPath {
                detected.claudeCLI = cliPath
                // Use Desktop app icon when available, else brain SF-symbol
                detected.claude = claudeAppURL.map { iconForApp($0) }
                    ?? NSImage(systemSymbolName: "brain.head.profile",
                               accessibilityDescription: "Claude Code")
            }

            // ── Cursor ───────────────────────────────────────────────────
            if let url = appURL(bundleIDs: ["com.todesktop.230313mzl4w4u92",
                                            "com.cursor.macos",
                                            "com.cursor.cursor"],
                                appPaths: ["/Applications/Cursor.app"]) {
                detected.cursor     = iconForApp(url)
                detected.cursorPath = url.path
            }

            // ── OpenAI Codex ─────────────────────────────────────────────
            if let url = appURL(bundleIDs: ["com.openai.codex",
                                            "com.openai.codex-desktop"],
                                appPaths: ["/Applications/Codex.app",
                                           "/Applications/OpenAI Codex.app"]) {
                detected.codex     = iconForApp(url)
                detected.codexPath = url.path
            } else {
                // Codex may be CLI-only
                let codexCLI = fixedCLI(["/usr/local/bin/codex", "/opt/homebrew/bin/codex"])
                    ?? whichCLI("codex")
                if codexCLI != nil {
                    detected.codex = NSImage(systemSymbolName: "terminal",
                                             accessibilityDescription: "Codex")
                }
            }

            let claudeAppPath = claudeAppURL?.path
            DispatchQueue.main.async {
                apps = detected
                saveCachedApps(detected, claudeApp: claudeAppPath)
            }
        }
    }

    // MARK: - Open helpers

    private func openInTerminal(_ url: URL) {
        let cmd = "cd \(shellQuoted(url.path))"
        let script = """
tell application "Terminal"
    activate
    do script \(appleScriptStringLiteral(cmd))
end tell
"""
        runAppleScript(script)
    }

    private func openInVSCode(_ url: URL) {
        // Prefer opening via app bundle so we guarantee VS Code, not Cursor's `code` shim
        if let appPath = apps.vscodePath {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
    }

    private func openInClaudeCode(_ url: URL) {
        // Claude Code is a TUI — open a NEW Terminal window (which launches a
        // login shell, so PATH is fully configured including nvm / homebrew / npm).
        // Use the detected full CLI path when available, otherwise fall back to
        // the bare `claude` command which the login shell will resolve via PATH.
        let safe    = shellQuoted(url.path)
        let cliSafe = apps.claudeCLI.map { shellQuoted($0) } ?? "claude"
        // `do script` without "in front window" always opens a new window/tab.
        let cmd = "cd \(safe) && \(cliSafe) ."
        let script  = """
tell application "Terminal"
    activate
    do script \(appleScriptStringLiteral(cmd))
end tell
"""
        runAppleScript(script)
    }

    private func openInCursor(_ url: URL) {
        // Prefer app bundle — guarantees Cursor opens, not VS Code's code shim
        if let appPath = apps.cursorPath {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        // Fallback: known Cursor CLIs
        let cliCandidates = [
            "/usr/local/bin/cursor",
            "/opt/homebrew/bin/cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        ]
        if let cli = cliCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = [url.path]
            try? p.run()
        }
    }

    private func openInCodex(_ url: URL) {
        // App bundle takes priority
        if let appPath = apps.codexPath {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }
        // CLI (TUI) fallback — open in Terminal
        let cliCandidates = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        if let cli = cliCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let safe    = shellQuoted(url.path)
            let cliSafe = shellQuoted(cli)
            let cmd = "cd \(safe) && \(cliSafe)"
            let script  = """
tell application "Terminal"
    activate
    do script \(appleScriptStringLiteral(cmd))
end tell
"""
            runAppleScript(script)
        }
    }

    // MARK: - Shared helpers

    /// Single-quote a path for shell embedding — safe against $, `, !, spaces, etc.
    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runAppleScript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
    }
}

// MARK: - Toolbar button with SF Symbol icon

struct ToolbarActionButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) { Label(label, systemImage: icon).labelStyle(.iconOnly) }
            .buttonStyle(.borderless).help(label)
    }
}

// MARK: - Toolbar button with real app icon

struct AppIconToolbarButton: View {
    let appIcon: NSImage
    let label:   String
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
