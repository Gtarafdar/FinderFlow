# FinderFlow — Feature History & Changelog

A complete record of what FinderFlow does and how it was built. Dates are
relative to the 1.0 release.

---

## 1.1 — Markdown reader in its own window

- **Draggable & resizable Markdown reader** — the Markdown reader/editor now
  opens in a real macOS window (drag by the titlebar, resize, zoom, minimise)
  instead of a fixed modal sheet, matching the built-in code editor. The window
  is reused for subsequent Markdown files and remembers its size/position.
- **"Open in editor" now uses FinderFlow's own editor** — the reader's toolbar
  link button previously launched an external app (Obsidian / TextEdit / etc.);
  it now opens the file in FinderFlow's built-in code editor. Unsaved Markdown
  edits are auto-saved first so the editor shows the latest content.
- **Consistent Markdown handling** — opening a `.md` file *with* FinderFlow
  (from Finder or the command line) now shows the rendered reader, matching what
  double-clicking a `.md` inside the app already did.

---

## 1.0 — First public release

The first shippable build: a fast, native macOS file manager and Finder
alternative, distributed free as a Universal app (Apple Silicon + Intel).

### Core file browsing
- **Three view modes**
  - **List view** — sortable columns (Name, Date Modified, Date Created, Size,
    Kind, Extension), inline rename, optional **Group by Date** sections
    (Today / Yesterday / Previous 7 Days / Previous 30 Days / Earlier).
  - **Icon view** — resizable icon grid (32–128 pt slider).
  - **Column view** — macOS-style miller columns with an inline preview pane,
    optional full ancestor "tree" mode, and resizable column dividers.
- **Sidebar** — system locations (Home, Desktop, Documents, Downloads),
  user-pinned folders, recent folders, and a Tags section.
- **Path bar** — clickable breadcrumbs, double-click to edit the path directly,
  and a one-click **Copy Path** button.
- **Status bar** — item count, selection size, and free disk space.
- **Native Quick Look** (Space bar) and a built-in **preview panel**
  (QLPreviewView, the same engine Finder uses).

### Search
- **Scopes**: This Folder, This Folder & Subfolders (recursive), Desktop,
  Documents, Downloads, Home, and **Entire Mac** (Spotlight-powered).
- Name search and **extension search** (e.g. type `.pdf`).
- Live result count, background execution (never blocks the UI).

### Finder-compatible color tags
- Add/remove the 7 standard macOS colors (Red, Orange, Yellow, Green, Blue,
  Purple, Gray) from any view's right-click **Tags** menu — toggles exactly like
  Finder, multiple colors per file preserved.
- Tags written in macOS's real format so they appear in Finder too.
- Tag dots render in list/icon/column/preview, and tapping a tag in the sidebar
  filters **Mac-wide** via Spotlight (unioned with local color-label matches).

### File operations (with Undo/Redo)
- Copy / Cut / Paste, Duplicate, inline Rename, Make Alias (symlink).
- Move to Trash and **Delete Permanently** (with confirmation).
- **Compress** to `.zip`; **Extract** `.zip / .tar / .gz / .tgz / .bz2 / .xz`
  (uses The Unarchiver if installed, else macOS's built-in tools).
- Share / AirDrop, Show in Finder, Get Info, Copy Path.
- Multi-select aware; partial-failure-safe paste/move with correct undo.

### Built-in code editor (Ace, bundled & offline)
- Double-click a text/code file to open it in FinderFlow's editor.
- Syntax highlighting for dozens of languages; **multiple files as tabs**.
- **Fuzzy command palette** (⌘⇧P), Ace settings menu, Sublime keybindings.
- **Open** (⌘O) / **Close tab** (⌘W).
- **Sublime-style minimap** (theme-aware, click/drag to scroll).
- Runs in a **real, standalone macOS window** — drag, minimize, resize,
  fit — and does **not** block the main browser window.
- Setting to open unknown file types in the editor when they look like text.

### Markdown reader / editor
- Rendered preview (GitHub/Obsidian-style, dark + light) with internal `.md`
  link navigation, plus an **Edit** mode with ⌘S save and auto-save on close.

### Developer integrations (shown only if installed)
- One-click **Open in Terminal**, **VS Code**, **Cursor**, **Claude Code**,
  **Codex** for the current/selected folder. Detection is cached for speed.

### System integration
- **Finder Sync extension** — right-click menu in Finder: New Folder Here,
  Copy Path, Open in Terminal, **Open in FinderFlow**.
- **Set FinderFlow as the default folder handler** (Settings) — routes the
  `open` command, "Open With", and other apps' folder-opens to FinderFlow.
  (Finder itself can't be fully replaced by macOS design — clearly explained
  in-app.)
- `finderflow://` URL scheme and "Open With" handling for folders & text files.
- **Launch at Login** toggle.
- In-app toast notifications for actions (copied, moved, tagged, etc.).

---

## Development history (how 1.0 came together)

1. **Foundation** — list/icon/column views, sidebar, search, file operations,
   path/status bars, Quick Look, Markdown reader, Finder Sync extension, and the
   developer-tool toolbar.
2. **Cursor polish** — fixed the resize/I-beam cursor "sticking" after using the
   sidebar divider, search field, table column dividers, and column handles
   (geometry-based `NSTrackingArea` enter/exit resets + a rewritten resize
   handle).
3. **Tags overhaul** — rewrote tagging to use macOS's real color-tag encoding so
   tags show correctly across all views and are searchable via Spotlight;
   fixed the crash and the "empty results" bug.
4. **Copy-path toast** — wired the path-bar copy button into the toast system.
5. **Default folder handler** — added the Settings option to route folder opens
   to FinderFlow (via LaunchServices), with honest in-app caveats.
6. **Code editor, Phase 1** — extended the text viewer into a full Ace editor;
   double-click to edit.
7. **Code editor, Phase 2** — tabs, command palette (⌘⇧P), settings menu,
   Open/Close shortcuts, unknown-file-type sniffing toggle.
8. **Code editor, Phase 3** — moved the editor into a real, draggable,
   resizable, non-blocking macOS window.
9. **Minimap** — added a theme-aware, Sublime-style minimap.
10. **Senior-QA & security pass** — fixed an **AppleScript-injection**
    vulnerability via crafted filenames (Get Info / Open-in-Terminal), wired up
    the dead **Toggle Hidden Files** (⌘⇧.) command, fixed **unsaved-Markdown
    data loss** on close, and made **paste/move partial failures** undo-safe.
11. **Release engineering** — Universal (Intel + Apple Silicon) build, a
    one-command DMG packager (`release.sh`), README + in-DMG install/permission
    guide, a modern flat app icon, and removal of a deprecated API call.

---

## Known limitations (by design)

- **Not notarized** (free distribution, no paid Apple Developer account) — a
  one-time Gatekeeper "Open Anyway" is required on first launch. See the README.
- **Finder cannot be fully replaced** — the Desktop, drive mounting, Open/Save
  dialogs, and the Dock's Finder icon always remain Finder (a macOS limitation).
- **Requires macOS 14 (Sonoma) or newer.**
