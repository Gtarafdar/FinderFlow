import SwiftUI
import Quartz

struct ContentView: View {
    @StateObject private var folderService = FolderCreationService()
    @StateObject private var searchEngine  = SearchEngine()
    @StateObject private var fileOps       = FileOperationsService()
    @StateObject private var tagService    = TagService()
    @EnvironmentObject  var  favorites:      FavoritesService

    @State private var currentPath:     URL       = FileManager.default.homeDirectoryForCurrentUser
    @State private var sidebarItem:     SidebarItem?
    @State private var viewMode:        ViewMode  = .list
    @State private var sortField:       SortField = .name
    @State private var sortAscending:   Bool      = true
    @State private var showHidden:      Bool      = false
    @State private var groupByDate:     Bool      = false
    @State private var showPreview:     Bool      = false
    @State private var selectedIDs:      Set<UUID> = []
    @State private var rawFiles:            [FileItem] = []
    @State private var searchDisplayFiles:  [FileItem] = []   // pre-computed search results (avoid reloading on every render)
    @State private var pendingSelectURL: URL?
    @State private var pendingRenameURL: URL?
    @State private var showColumnTree:   Bool = false
    @State private var activeTagFilter:  String? = nil
    @State private var tagDisplayFiles:  [FileItem] = []
    @State private var toastItem:        ToastPayload?
    @State private var errorMsg:         String?

    // Derived selected item for preview
    private var selectedItem: FileItem? {
        guard let id = selectedIDs.first else { return nil }
        return displayFiles.first { $0.id == id }
    }

    // Selected folder URL — used by IDE toolbar buttons to open the right folder
    private var selectedFolderURL: URL? {
        guard let item = selectedItem, item.isDirectory else { return nil }
        return item.url
    }

    // Active destination: used for both paste and new-item creation.
    // If exactly one folder is selected, target it; otherwise use currentPath.
    private var activeDestination: URL {
        if selectedIDs.count == 1,
           let item = displayFiles.first(where: { selectedIDs.contains($0.id) }),
           item.isDirectory {
            return item.url
        }
        return currentPath
    }

    private var pasteDestination: URL { activeDestination }

    // Split out of `body` so each chained expression stays within the Swift
    // type-checker's complexity budget (adding more modifiers to one giant
    // expression triggers "unable to type-check in reasonable time").
    private var splitView: some View {
        NavigationSplitView {
            SidebarView(currentPath: $currentPath, selection: $sidebarItem,
                        activeTagFilter: $activeTagFilter, usedTagNames: usedTagNames)
                .frame(minWidth: 180, idealWidth: 220)
                .background(ArrowCursorArea())   // resets cursor when leaving the sidebar divider
                .resetsCursorOnEnter()           // clears the divider's stuck resize cursor on entry
        } detail: {
            VStack(spacing: 0) {
                PathBarView(currentPath: $currentPath)
                    .resetsCursorOnEnter()   // clear a stuck resize cursor when moving up from the file list
                SearchScopeView(currentPath: currentPath, searchEngine: searchEngine)
                    .resetsCursorOnEnter()
                QuickActionsToolbar(
                    currentPath:    $currentPath,
                    selectedURL:    selectedFolderURL,
                    selectedCount:  selectedIDs.count,
                    onCreateFolder: promptAndCreateFolder,
                    onCreateFile:   promptAndCreateFile,
                    onDelete:       confirmAndDeleteSelected,
                    fileOps:        fileOps,
                    viewMode:       $viewMode,
                    sortField:      $sortField,
                    sortAscending:  $sortAscending,
                    showHidden:     $showHidden,
                    groupByDate:    $groupByDate,
                    showPreview:    $showPreview,
                    showColumnTree: $showColumnTree,
                    onReload:       reload
                )
                .resetsCursorOnEnter()

                // Right preview panel — list/icon views only (column view has inline preview)
                HStack(spacing: 0) {
                    fileBrowser
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showPreview && viewMode != .columns {
                        Divider()
                        FilePreviewPanel(item: selectedItem)
                            .frame(width: 260)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBarView(files: displayFiles, selectedIDs: selectedIDs, currentPath: currentPath)
            }
            .background(ArrowCursorArea())   // resets IBeam / resize cursor leaving search bar or column handles
            .resetsCursorOnEnter()           // clears the divider's stuck resize cursor on entry
            .overlay(alignment: .bottom) {
                if let toast = toastItem {
                    InAppToast(icon: toast.icon, message: toast.message)
                        .padding(.bottom, 42)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .opacity
                        ))
                        .allowsHitTesting(false)
                        .id(toast.id)
                        .onAppear {
                            let captured = toast.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    if toastItem?.id == captured { toastItem = nil }
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastItem?.id)
        }
        .frame(minWidth: 860, minHeight: 520)
        .background(QLResponderSetup())

        // ── Keyboard shortcuts ──────────────────────────────────────────
        .background(keyboardShortcuts)
    }

    private var splitWithChanges: some View {
        splitView
        // ── Lifecycle ───────────────────────────────────────────────────
        .onAppear {
            reload()
            // Cold launch via "Open in FinderFlow" / default folder handler:
            // the open request may arrive before this view is listening.
            if let pending = AppDelegate.pendingNavigationURL {
                AppDelegate.pendingNavigationURL = nil
                if pending != currentPath { currentPath = pending }
            }
        }
        // Don't clear the icon cache on every navigation — NSCache evicts under
        // memory pressure automatically; keeping icons warm makes navigation fast.
        .onChange(of: currentPath)   { _, _  in reload(); selectedIDs = []; activeTagFilter = nil }
        .onChange(of: sortField)     { _, _  in
            rawFiles = sortedItems(rawFiles, by: sortField, ascending: sortAscending)
            resortSearchFiles()
        }
        .onChange(of: sortAscending) { _, _  in
            rawFiles = sortedItems(rawFiles, by: sortField, ascending: sortAscending)
            resortSearchFiles()
        }
        .onChange(of: showHidden)    { _, _  in reload() }
        // Recompute Spotlight search results in background (never on the render thread)
        .onChange(of: searchEngine.results) { _, results in
            if results.isEmpty { searchDisplayFiles = []; return }
            let field = sortField; let asc = sortAscending
            DispatchQueue.global(qos: .userInitiated).async {
                let files = sortedItems(results.compactMap { FileItem.load(from: $0) },
                                        by: field, ascending: asc)
                DispatchQueue.main.async { searchDisplayFiles = files }
            }
        }
        // Select an item after paste/duplicate (no rename dialog needed)
        .onChange(of: rawFiles) { _, newFiles in
            guard let url = pendingSelectURL,
                  let item = newFiles.first(where: { $0.url == url }) else { return }
            selectedIDs    = [item.id]
            pendingSelectURL = nil
            DispatchQueue.main.async {
                scrollTableView(toRow: displayFiles.firstIndex(where: { $0.id == item.id }) ?? 0)
            }
        }
    }

    var body: some View {
        splitWithChanges
        .onReceive(NotificationCenter.default.publisher(for: .createNewFolder)) { _ in
            promptAndCreateFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleHiddenFiles)) { _ in
            showHidden.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPath)) { n in
            AppDelegate.pendingNavigationURL = nil
            if let url = n.object as? URL, url != currentPath { currentPath = url }
        }
        // Folder/file created → navigate to destination if needed, then select & scroll.
        .onReceive(folderService.$lastCreatedURL.compactMap { $0 }) { url in
            let parent = url.deletingLastPathComponent()
            if parent != currentPath {
                // Created inside a subfolder — navigate there so the item is visible.
                pendingSelectURL = url
                currentPath = parent            // triggers onChange → reload → select via pendingSelectURL
            } else {
                _reload {
                    guard let item = rawFiles.first(where: { $0.url == url }) else { return }
                    selectedIDs = [item.id]
                    scrollTableView(toRow: displayFiles.firstIndex(where: { $0.id == item.id }) ?? 0)
                }
            }
            // Notify any column pane showing the parent to reload
            NotificationCenter.default.post(name: .refreshDirectory, object: parent)
        }
        .onReceive(fileOps.$lastOpURL.compactMap { $0 }) { url in
            pendingSelectURL = url
            NotificationCenter.default.post(name: .refreshDirectory,
                                            object: url.deletingLastPathComponent())
        }
        .onReceive(folderService.$errorMessage.compactMap      { $0 }) { msg in errorMsg = msg }
        .onReceive(fileOps.$errorMessage.compactMap            { $0 }) { msg in errorMsg = msg }
        .onReceive(fileOps.$lastActionFeedback.compactMap      { $0 }) { f in showToast(f) }
        .onReceive(folderService.$lastActionFeedback.compactMap { $0 }) { f in showToast(f) }
        .onReceive(NotificationCenter.default.publisher(for: .ffCopyPathFeedback)) { _ in
            showToast(ActionFeedback(icon: "doc.on.clipboard.fill", message: "Path copied"))
        }
        // When a tag is selected, search Mac-wide; when cleared, reset tagged results
        .onChange(of: activeTagFilter) { _, tag in
            if let tag {
                tagService.searchFiles(forTag: tag)
            } else {
                tagService.stopSearch()
                tagDisplayFiles = []
            }
        }
        // Convert Spotlight tag results to FileItems in background
        .onChange(of: tagService.taggedFileURLs) { _, urls in
            let field = sortField; let asc = sortAscending
            DispatchQueue.global(qos: .userInitiated).async {
                let files = sortedItems(urls.compactMap { FileItem.load(from: $0) },
                                        by: field, ascending: asc)
                DispatchQueue.main.async { tagDisplayFiles = files }
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMsg != nil },
            set: { if !$0 { errorMsg = nil; folderService.errorMessage = nil; fileOps.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
    }

    // MARK: - Keyboard shortcuts (hidden buttons)
    // Extracted from `body` to keep the main view expression within the Swift
    // type-checker's complexity budget.

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Button("") { fileOps.undo() }
                .keyboardShortcut("z", modifiers: .command).hidden()
            Button("") { fileOps.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).hidden()
            Button("") {
                let sel = displayFiles.filter { selectedIDs.contains($0.id) }
                if !sel.isEmpty { fileOps.copy(sel.map(\.url)) }
            }.keyboardShortcut("c", modifiers: .command).hidden()
            Button("") {
                let sel = displayFiles.filter { selectedIDs.contains($0.id) }
                if !sel.isEmpty { fileOps.cut(sel.map(\.url)) }
            }.keyboardShortcut("x", modifiers: .command).hidden()
            Button("") { fileOps.paste(to: pasteDestination, reload: reload) }
                .keyboardShortcut("v", modifiers: .command).hidden()
        }
    }

    // MARK: - Pre-named creation dialogs

    // Show a name dialog BEFORE creating, so the item appears with the correct name immediately.
    // Respects the active destination (selected folder or currentPath).

    func promptAndCreateFolder() {
        let dest = activeDestination
        let alert = NSAlert()
        alert.messageText     = "New Folder in \"\(dest.lastPathComponent)\""
        alert.informativeText = "Enter a name for the new folder:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tf.stringValue = "New Folder"; tf.selectText(nil)
        alert.accessoryView = tf; alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        folderService.createFolder(at: dest, name: name)
    }

    func promptAndCreateFile() {
        let dest = activeDestination
        let alert = NSAlert()
        alert.messageText     = "New File in \"\(dest.lastPathComponent)\""
        alert.informativeText = "Enter a name for the new file (include extension, e.g. notes.txt):"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tf.stringValue = "untitled.txt"; tf.selectText(nil)
        alert.accessoryView = tf; alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        folderService.createFile(at: dest, name: name)
    }

    // MARK: - Permanent delete with confirmation

    func confirmAndDeleteSelected() {
        let items = displayFiles.filter { selectedIDs.contains($0.id) }
        guard !items.isEmpty else { return }

        let names = items.map(\.name)
        let label = items.count == 1 ? "\"\(names[0])\"" : "\(items.count) items"

        let alert = NSAlert()
        alert.messageText     = "Permanently delete \(label)?"
        alert.informativeText = "This cannot be undone. The \(items.count == 1 ? "item" : "items") will be permanently deleted and cannot be recovered from Trash."
        alert.alertStyle      = .warning
        let deleteBtn = alert.addButton(withTitle: "Delete Permanently")
        deleteBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selectedIDs = []
        fileOps.permanentlyDelete(items.map(\.url), reload: reload)
    }

    // MARK: - File browser

    @ViewBuilder
    private var fileBrowser: some View {
        switch viewMode {
        case .list:
            ListView(
                files:            displayFiles,
                selectedIDs:      $selectedIDs,
                pendingRenameURL: $pendingRenameURL,
                currentPath:      currentPath,
                sortField:        $sortField,
                sortAscending:    $sortAscending,
                groupByDate:      groupByDate,
                onNavigate:       navigate,
                onReload:         reload,
                fileOps:          fileOps,
                favorites:        favorites
            )
        case .icons:
            IconsView(
                files:       displayFiles,
                selectedIDs: $selectedIDs,
                currentPath: currentPath,
                onNavigate:  navigate,
                onReload:    reload,
                fileOps:     fileOps,
                favorites:   favorites
            )
        case .columns:
            ColumnsView(
                currentPath:    $currentPath,
                showHidden:     showHidden,
                showColumnTree: showColumnTree,
                groupByDate:    groupByDate,
                fileOps:        fileOps,
                favorites:      favorites,
                searchResults:  displayFiles,
                isSearchActive: !searchEngine.query.isEmpty || activeTagFilter != nil
            )
        }
    }

    // Tags used by items in the current folder — shown in the sidebar Tags section.
    // Only shows tags that actually exist here, so the sidebar stays clean.
    // When a tag is tapped, TagService searches Mac-wide via Spotlight.
    private var usedTagNames: [String] {
        Array(Set(rawFiles.flatMap(\.tagNames))).sorted()
    }

    // MARK: - Display list

    private var displayFiles: [FileItem] {
        // Tag filter: Mac-wide Spotlight matches UNION current-folder items carrying
        // the color. The local pass is what guarantees correctness — Spotlight only
        // finds files with a real kMDItemUserTags value, while the local match also
        // catches files that only have the legacy color label (kMDItemFSLabel), which
        // Spotlight cannot search. So tagged items in the folder you're viewing always
        // appear, regardless of how they were tagged.
        if let tag = activeTagFilter {
            let merged = mergedTagResults(for: tag)
            guard !searchEngine.query.isEmpty else { return merged }
            return merged.filter { $0.name.localizedCaseInsensitiveContains(searchEngine.query) }
        }
        // Spotlight results are pre-computed into searchDisplayFiles to avoid
        // calling FileItem.load(from:) on every SwiftUI re-render.
        if !searchEngine.results.isEmpty { return searchDisplayFiles }
        if !searchEngine.query.isEmpty {
            return rawFiles.filter { $0.name.localizedCaseInsensitiveContains(searchEngine.query) }
        }
        return rawFiles
    }

    // Spotlight (Mac-wide) results unioned with current-folder color matches, deduped
    // by path and sorted. The local match covers items that only carry the legacy
    // color label, which Spotlight can't find.
    private func mergedTagResults(for tag: String) -> [FileItem] {
        let colorNumber = FileItem.colorNameToLabel[tag.lowercased()]
        let local = rawFiles.filter { item in
            item.tagNames.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                || (colorNumber != nil && colorNumber == item.labelNumber)
        }
        var seen = Set<String>()
        var merged: [FileItem] = []
        for f in tagDisplayFiles + local where seen.insert(f.url.path).inserted {
            merged.append(f)
        }
        return sortedItems(merged, by: sortField, ascending: sortAscending)
    }

    // MARK: - Helpers

    private func navigate(_ url: URL) {
        // Use FileManager to reliably detect directories — URL.hasDirectoryPath
        // only returns true when the path ends with "/" which FileManager results
        // do NOT do, so folders from search results would silently fall through.
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            currentPath = url
        } else if url.pathExtension.lowercased() == "md" {
            MarkdownWindowManager.shared.open(url)
        } else if TextFileDetector.isEditableText(url) {
            EditorWindowManager.shared.open(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func scrollTableView(toRow row: Int) {
        guard row >= 0 else { return }
        func find(_ v: NSView) -> NSTableView? {
            if let tv = v as? NSTableView { return tv }
            return v.subviews.lazy.compactMap { find($0) }.first
        }
        if let tv = find(NSApp.keyWindow?.contentView ?? NSView()) {
            tv.scrollRowToVisible(row)
        }
    }

    // MARK: - Toast

    private func showToast(_ feedback: ActionFeedback) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastItem = ToastPayload(icon: feedback.icon, message: feedback.message)
        }
    }

    private func resortSearchFiles() {
        guard !searchDisplayFiles.isEmpty else { return }
        let field = sortField; let asc = sortAscending
        DispatchQueue.global(qos: .userInitiated).async {
            let sorted = sortedItems(searchDisplayFiles, by: field, ascending: asc)
            DispatchQueue.main.async { searchDisplayFiles = sorted }
        }
    }

    func reload() { _reload(then: nil) }

    private func _reload(then: (() -> Void)?) {
        let path   = currentPath
        let hidden = showHidden
        let field  = sortField
        let asc    = sortAscending
        DispatchQueue.global(qos: .userInitiated).async {
            let items = sortedItems(loadItems(at: path, showHidden: hidden), by: field, ascending: asc)
            DispatchQueue.main.async {
                rawFiles = items
                then?()
            }
        }
    }
}

// MARK: - Toast payload

struct ToastPayload: Equatable {
    let id      = UUID()
    let icon:    String
    let message: String
    static func == (l: ToastPayload, r: ToastPayload) -> Bool { l.id == r.id }
}

// MARK: - In-app toast view

struct InAppToast: View {
    let icon:    String
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

// MARK: - File preview panel (right sidebar)
// Uses native QLPreviewView (same engine as macOS Finder's preview column)

struct FilePreviewPanel: View {
    let item: FileItem?

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                QLSidebarPreview(url: item.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(nsImage: item.icon).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            TagDotsView(colors: item.tagColors, size: 10)
                        }
                    }
                    Divider()
                    detailRow("Kind",     item.kind)
                    if !item.isDirectory { detailRow("Size", item.formattedSize) }
                    detailRow("Modified", item.formattedDateModified)
                    detailRow("Created",  item.formattedDateCreated)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.magnifyingglass")
                        .font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Select a file\nto preview")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value).font(.caption).lineLimit(2)
        }
    }
}

// MARK: - Native QL preview (mirrors Finder's preview panel)
// QLPreviewView must be created after the view enters the window hierarchy —
// creating it with a zero frame or before a window exists silently produces nothing.

struct QLSidebarPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> _QLSidebarHost { _QLSidebarHost() }
    func updateNSView(_ host: _QLSidebarHost, context: Context) { host.show(url) }
}

final class _QLSidebarHost: NSView {
    private var qlView: QLPreviewView?
    private var pendingURL: URL?

    func show(_ url: URL) {
        pendingURL = url
        if let ql = qlView {
            ql.previewItem = url as NSURL
        } else {
            setupQL()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { setupQL() }
    }

    override func layout() {
        super.layout()
        qlView?.frame = bounds
    }

    private func setupQL() {
        guard window != nil, qlView == nil else { return }
        // Use a concrete initial frame; zero frame produces a blank view.
        let frame = bounds.isEmpty ? NSRect(x: 0, y: 0, width: 260, height: 300) : bounds
        guard let ql = QLPreviewView(frame: frame, style: .normal) else { return }
        ql.autoresizingMask = [.width, .height]
        ql.autostarts = true
        ql.shouldCloseWithWindow = false
        addSubview(ql)
        qlView = ql
        if let url = pendingURL {
            ql.previewItem = url as NSURL
        }
    }
}

// MARK: - Arrow cursor catch-all
//
// Place this as .background() on any region that should show the default arrow cursor
// when nothing else has claimed it (file list, sidebar list, toolbar, etc.).
//
// Uses NSTrackingArea with .cursorUpdate. AppKit's rule: if a cursor rect is active
// at the mouse position (text field → IBeam, resize handle → resizeLeftRight, the
// NavigationSplitView divider → resizeLeftRight), that cursor rect takes priority and
// cursorUpdate(with:) is NOT called. In every other area the tracking area fires
// cursorUpdate(with:) and we reset to arrow — which clears any IBeam or resize cursor
// that the previous area set via NSCursor.set() rather than via a cursor rect.
//
// hitTest returns nil so this transparent layer never intercepts clicks or drags.

struct ArrowCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> _ArrowCursorAreaView { _ArrowCursorAreaView() }
    func updateNSView(_ v: _ArrowCursorAreaView, context: Context) {}
}

final class _ArrowCursorAreaView: NSView {
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        guard !bounds.isEmpty else { return }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

// MARK: - Cursor reset on exit
//
// A zero-cost transparent layer that forces the cursor back to the default arrow
// the instant the pointer LEAVES its bounds. Apply to any view that hands the
// cursor to a child which sets a non-default cursor (text fields → I-beam) so the
// cursor never "sticks" after the pointer moves on.
//
// Why this exists alongside ArrowCursorArea: the catch-all above resets via a
// .cursorUpdate tracking area placed as a .background(), which the front-most
// AppKit table/list views occlude — so leaving a text field onto the file list
// would not fire it and the I-beam would persist. This uses geometry-based
// .mouseEnteredAndExited on the field itself, which fires the moment the pointer
// crosses the field boundary regardless of what is in front of it.
//
// hitTest returns nil so it never intercepts clicks, drags, or text selection.

struct CursorResetOnExit: NSViewRepresentable {
    func makeNSView(context: Context) -> _CursorResetView { _CursorResetView() }
    func updateNSView(_ v: _CursorResetView, context: Context) {}
}

final class _CursorResetView: NSView {
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        guard !bounds.isEmpty else { return }
        // No .enabledDuringMouseDrag — we must not reset to arrow mid text-selection
        // drag; we only care about a plain pointer move leaving the field.
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

extension View {
    /// Forces the cursor back to the default arrow the moment the pointer leaves
    /// this view. Use on text fields so the I-beam never sticks after moving away.
    func resetsCursorOnExit() -> some View { background(CursorResetOnExit()) }
}

// MARK: - Cursor reset on enter
//
// Sibling of CursorResetOnExit, but fires on ENTER. This exists specifically for
// the NavigationSplitView divider: the divider sets a resize cursor while hovered,
// and when the pointer moves off it onto a pane the divider's cursor would stick.
// The existing .cursorUpdate catch-all (ArrowCursorArea) can't clear it because the
// pane's List/Table is painted in front and steals the cursorUpdate. A geometry
// based .mouseEntered fires the instant the pointer crosses into the pane regardless
// of what is in front, so the stale resize cursor is released immediately.
//
// We only reset on ENTER (not exit) so internal cursors — text-field I-beams, the
// column resize handles — are left untouched; those views manage their own cursor
// once the pointer is already inside the pane.

struct CursorResetOnEnter: NSViewRepresentable {
    func makeNSView(context: Context) -> _CursorResetOnEnterView { _CursorResetOnEnterView() }
    func updateNSView(_ v: _CursorResetOnEnterView, context: Context) {}
}

final class _CursorResetOnEnterView: NSView {
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        guard !bounds.isEmpty else { return }
        // No .enabledDuringMouseDrag — while the user is actively dragging the
        // divider we must keep the resize cursor; we only reset once the drag is
        // over and the pointer moves into the pane.
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

extension View {
    /// Forces the cursor back to the default arrow the moment the pointer enters
    /// this view. Use on split-view panes so the divider's resize cursor never
    /// sticks after the pointer moves off the divider onto the pane.
    func resetsCursorOnEnter() -> some View { background(CursorResetOnEnter()) }
}
