import AppKit
import SwiftUI

// MARK: - Terminal app choice (persisted, editable in Settings)

/// Which terminal FinderFlow opens. Persisted as a raw string under
/// `ffTerminalApp`; the "Other app" path under `ffCustomTerminalApp`.
enum TerminalChoice: String, CaseIterable, Identifiable {
    case terminal
    case iterm
    case alacritty
    case kitty
    case wezterm
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal:  return "Terminal"
        case .iterm:     return "iTerm2"
        case .alacritty: return "Alacritty"
        case .kitty:     return "kitty"
        case .wezterm:   return "WezTerm"
        case .custom:    return "Other app…"
        }
    }

    /// Only these can run arbitrary commands through AppleScript — the only
    /// way to launch a TUI (Claude Code, Codex) in a new window.
    var isScriptable: Bool { self == .terminal || self == .iterm }

    static let choiceKey    = "ffTerminalApp"
    static let customAppKey = "ffCustomTerminalApp"

    static var current: TerminalChoice {
        let raw = UserDefaults.standard.string(forKey: choiceKey) ?? terminal.rawValue
        return TerminalChoice(rawValue: raw) ?? .terminal
    }

    /// The app for the "Other app" choice — nil when unset or the app is gone.
    static var customAppPath: String? {
        guard let p = UserDefaults.standard.string(forKey: customAppKey), !p.isEmpty,
              FileManager.default.fileExists(atPath: p) else { return nil }
        return p
    }

    /// Settings action: pick an app, save it, and select "Other app".
    @discardableResult
    static func chooseCustomApp() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the terminal app FinderFlow opens"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        UserDefaults.standard.set(url.path, forKey: customAppKey)
        UserDefaults.standard.set(custom.rawValue, forKey: choiceKey)
        return true
    }
}

// MARK: - Launcher

/// Opens the user's configured terminal in a given directory, or runs a
/// command in a scriptable one. Anything missing (iTerm not installed, a CLI
/// not on PATH, a custom app deleted) falls back to the system Terminal so an
/// action never silently does nothing.
enum TerminalLauncher {

    /// New terminal session whose working directory is `dir`.
    static func openTerminal(workingDirectory dir: URL) {
        let command = "cd \(shellQuoted(dir.path))"
        let choice = TerminalChoice.current
        switch choice {
        case .terminal:
            openInTerminalApp(command: command)
        case .iterm:
            isInstalled("com.googlecode.iterm2")
                ? openInITerm(command: command)
                : openInTerminalApp(command: command)
        case .alacritty:
            openViaCLI("alacritty", args: ["--working-directory", dir.path]) {
                openInTerminalApp(command: command)
            }
        case .kitty:
            openViaCLI("kitty", args: ["--start-directory", dir.path]) {
                openInTerminalApp(command: command)
            }
        case .wezterm:
            openViaCLI("wezterm", args: ["cli", "spawn", "--dir", dir.path]) {
                openInTerminalApp(command: command)
            }
        case .custom:
            if let app = TerminalChoice.customAppPath {
                openCustomApp(app: app, working: dir)
            } else {
                openInTerminalApp(command: command)
            }
        }
    }

    /// Runs `command` in a new session of a scriptable terminal. Returns
    /// false when the configured terminal can't take commands — callers should
    /// then open a plain terminal and tell the user what to run.
    @discardableResult
    static func runCommand(_ command: String) -> Bool {
        switch TerminalChoice.current {
        case .terminal where isInstalled("com.apple.Terminal"):
            openInTerminalApp(command: command)
            return true
        case .iterm where isInstalled("com.googlecode.iterm2"):
            openInITerm(command: command)
            return true
        default:
            return false
        }
    }

    // MARK: Per-app launchers

    private static func openInTerminalApp(command: String) {
        runAppleScript("""
        tell application "Terminal"
            activate
            do script \(appleScriptStringLiteral(command))
        end tell
        """)
    }

    private static func openInITerm(command: String) {
        // Never reuse an existing session: fresh window when there's none,
        // fresh tab otherwise. The new session is a login shell, so PATH is
        // fully configured (nvm, homebrew, npm, …).
        // iTerm2's dictionary has no `do script` — `write text` sends the
        // line and its trailing newline (default), which runs it.
        let cmdLiteral = appleScriptStringLiteral(command)
        runAppleScript("""
        tell application "iTerm"
            activate
            if (count of windows) is 0 then
                set w to create window with default profile
                tell w
                    tell current session
                        write text \(cmdLiteral)
                    end tell
                end tell
            else
                tell current window
                    create tab with default profile
                    tell current session
                        write text \(cmdLiteral)
                    end tell
                end tell
            end if
        end tell
        """)
    }

    private static func openCustomApp(app: String, working dir: URL) {
        // Generic contract: hand the folder to the app as an argument.
        // Terminal-like apps that accept a directory path will start there.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", app, dir.path]
        try? p.run()
    }

    private static func openViaCLI(_ name: String, args: [String], fallback: () -> Void) {
        guard let cli = findCLI(name) else {
            fallback()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args
        try? p.run()
    }

    // MARK: Lookup helpers

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Locate a CLI: common install dirs first (fast), then a login-shell
    /// `which` to pick up nvm/asdf-managed shells.
    private static func findCLI(_ name: String) -> String? {
        let home = NSHomeDirectory()
        for dir in ["/opt/homebrew/bin", "/usr/local/bin",
                    "\(home)/.local/bin", "\(home)/.cargo/bin",
                    "\(home)/.nix-profile/bin"] {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-c", "which \(name) 2>/dev/null"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    /// Single-quote a path for shell embedding — safe against $, `, !, spaces, etc.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAppleScript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
    }
}
