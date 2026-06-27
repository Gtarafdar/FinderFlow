import SwiftUI
import AppKit

private let kDefaultColWidth: CGFloat = 230
private let kMinColWidth:     CGFloat = 120
private let kPreviewWidth:    CGFloat = 260

// MARK: - Columns view (macOS Finder-style)

struct ColumnsView: View {
    @Binding var currentPath: URL
    let showHidden:     Bool
    let showColumnTree: Bool
    let groupByDate:    Bool
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService
    // Search support — when isSearchActive the column browser is replaced by a flat results list
    let searchResults:  [FileItem]
    let isSearchActive: Bool

    @State private var columns:         [URL]          = []
    @State private var colWidths:       [Int: CGFloat] = [:]
    @State private var selectedFileURL: URL?
    @State private var previewWidth:    CGFloat        = kPreviewWidth

    var body: some View {
        if isSearchActive {
            searchResultsView
        } else {
            columnBrowserView
        }
    }

    // MARK: - Search results flat list

    private var searchResultsView: some View {
        List(searchResults) { item in
            HStack(spacing: 8) {
                Image(nsImage: item.icon)
                    .resizable().frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        TagDotsView(colors: item.tagColors, size: 9)
                    }
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDir)
                if exists && isDir.boolValue {
                    currentPath = item.url
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
            .contextMenu { columnContextMenu(item: item, directory: item.url.deletingLastPathComponent()) }
        }
        .listStyle(.plain)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Normal column browser

    private var columnBrowserView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { idx, dir in
                        paneAndHandle(idx: idx, dir: dir)
                    }
                    // Preview column — auto-shown when a file is selected, just like macOS Finder
                    if let fileURL = selectedFileURL {
                        ResizeHandle { delta in
                            previewWidth = max(180, previewWidth + delta)
                        }
                        ColumnPreviewPane(url: fileURL)
                            .frame(width: previewWidth)
                            .id("preview")
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
            .onChange(of: columns) { _, cols in
                if let last = cols.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .trailing) }
                }
            }
            .onChange(of: selectedFileURL) { _, url in
                if url != nil {
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo("preview", anchor: .trailing) }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear       { buildColumns() }
        .onChange(of: currentPath)    { _, newPath in
            // Only rebuild if the new path isn't already in our column list.
            // If it IS already there, the user clicked within the column view and
            // the onSelect handler already updated `columns` — don't overwrite it.
            if !columns.contains(newPath) { buildColumns() }
        }
        .onChange(of: showColumnTree) { _, _ in buildColumns() }
    }

    @ViewBuilder
    private func paneAndHandle(idx: Int, dir: URL) -> some View {
        // The last column highlights the selected file; other columns highlight the next dir.
        let highlighted: URL? = {
            if idx + 1 < columns.count { return columns[idx + 1] }
            if idx == columns.count - 1 { return selectedFileURL }
            return nil
        }()

        ColumnPane(
            directory:      dir,
            highlightedURL: highlighted,
            showHidden:     showHidden,
            groupByDate:    groupByDate,
            onSelect: { selected in
                if selected.hasDirectoryPath {
                    columns = Array(columns.prefix(idx + 1)) + [selected]
                    currentPath = selected
                    selectedFileURL = nil
                } else {
                    // File selected: trim columns back to this level, show preview
                    columns = Array(columns.prefix(idx + 1))
                    selectedFileURL = selected
                }
            },
            fileOps:   fileOps,
            favorites: favorites
        )
        .frame(width: colWidths[idx, default: kDefaultColWidth], alignment: .topLeading)
        .id(idx)

        ResizeHandle { delta in
            let current = colWidths[idx, default: kDefaultColWidth]
            colWidths[idx] = max(kMinColWidth, current + delta)
        }
    }

    // MARK: - Context menu for search result rows

    @ViewBuilder
    private func columnContextMenu(item: FileItem, directory: URL) -> some View {
        Button("Open") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDir), isDir.boolValue {
                currentPath = item.url
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
        if item.isDirectory {
            Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
        }
        Divider()
        Button("Quick Look") { QuickLookController.shared.show([item.url]) }
        Button("Get Info") { showGetInfoInFinder([item.url]) }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
        }
        Button("Copy Path") { fileOps.copyPath(item.url.path) }
        Divider()
        Button("Move to Trash", role: .destructive) {
            fileOps.trash([item.url], reload: {})
        }
    }

    private func buildColumns() {
        selectedFileURL = nil
        guard showColumnTree else {
            // Default: show only the current folder, no ancestor tree
            columns = [currentPath]
            return
        }
        // Full ancestor chain up to root
        var path  = currentPath
        var paths = [path]
        while path.pathComponents.count > 1 {
            path = path.deletingLastPathComponent()
            paths.insert(path, at: 0)
        }
        columns = paths
    }
}

// MARK: - Preview column (mirrors Finder's rightmost preview pane)

struct ColumnPreviewPane: View {
    let url: URL
    @State private var item: FileItem?

    var body: some View {
        VStack(spacing: 0) {
            QLSidebarPreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let item {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: item.icon)
                            .resizable().frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(3)
                            TagDotsView(colors: item.tagColors, size: 10)
                        }
                    }
                    Divider()
                    detailRow("Kind",     item.kind)
                    detailRow("Size",     item.formattedSize)
                    detailRow("Modified", item.formattedDateModified)
                    detailRow("Created",  item.formattedDateCreated)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear   { item = FileItem.load(from: url) }
        .onChange(of: url) { _, u in item = FileItem.load(from: u) }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value).font(.caption).lineLimit(2)
        }
    }
}

// MARK: - Drag handle between column panes
//
// Cursor is managed explicitly via NSTrackingArea enter/exit + the SwiftUI drag
// lifecycle — NOT via addCursorRect. Cursor rects are SUPPRESSED by AppKit during
// a drag, so a rect-based handle leaves the resize cursor "stuck" after you grab,
// drag, and release over a non-rect area (the file list). Managing the cursor
// directly on enter/exit/drag-end guarantees it is released the instant there is
// nothing left to drag.
//
// The flow:
//   • pointer enters handle      → resizeLeftRight
//   • pointer leaves (no drag)   → arrow
//   • drag in progress           → resizeLeftRight re-asserted every change
//   • drag ends                  → arrow, unless still hovering the handle
// During a drag we keep `hovering` accurate (the tracking area uses
// .enabledDuringMouseDrag) but suppress the arrow reset, so the resize cursor
// stays put while you actually resize.

private struct ResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    @State private var hovering:  Bool    = false
    @State private var dragging:  Bool    = false
    @State private var lastDelta: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(width: 8)
            .overlay(
                Rectangle()
                    .fill(hovering
                          ? Color.accentColor.opacity(0.7)
                          : Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(width: 1)
            )
            .overlay(ResizeCursorTracker(isHovering: $hovering, isDragging: $dragging))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        dragging = true
                        NSCursor.resizeLeftRight.set()   // keep resize cursor for the whole drag
                        let delta = v.translation.width - lastDelta
                        lastDelta  = v.translation.width
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        lastDelta = 0
                        dragging  = false
                        // Release immediately unless the pointer is still on the handle.
                        if hovering { NSCursor.resizeLeftRight.set() }
                        else        { NSCursor.arrow.set() }
                    }
            )
    }
}

// Transparent overlay NSView that manages the resize cursor and hover state via
// geometry-based NSTrackingArea enter/exit events (instant, no cursor-rect lag).
// hitTest returns nil so SwiftUI gestures on the parent still fire normally.
private struct ResizeCursorTracker: NSViewRepresentable {
    @Binding var isHovering: Bool
    @Binding var isDragging: Bool
    func makeNSView(context: Context) -> _ResizeCursorTrackerView {
        _ResizeCursorTrackerView(isHovering: $isHovering, isDragging: $isDragging)
    }
    func updateNSView(_ v: _ResizeCursorTrackerView, context: Context) {}
}

private final class _ResizeCursorTrackerView: NSView {
    private var _isHovering: Binding<Bool>
    private var _isDragging: Binding<Bool>
    private var trackingArea: NSTrackingArea?

    init(isHovering: Binding<Bool>, isDragging: Binding<Bool>) {
        self._isHovering = isHovering
        self._isDragging = isDragging
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        guard !bounds.isEmpty else { return }
        // .enabledDuringMouseDrag keeps `hovering` accurate while resizing so the
        // drag-end handler knows whether to release the cursor.
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        _isHovering.wrappedValue = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        _isHovering.wrappedValue = false
        // Only release when not actively resizing — otherwise the cursor would
        // flicker to arrow the moment the pointer slips past the 8-pt handle.
        if !_isDragging.wrappedValue { NSCursor.arrow.set() }
    }
}

// MARK: - Column pane

struct ColumnPane: View {
    let directory:      URL
    let highlightedURL: URL?
    let showHidden:     Bool
    let groupByDate:    Bool
    let onSelect:       (URL) -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var items: [FileItem] = []

    private var dateGroups: [(DateCategory, [FileItem])] {
        DateCategory.allCases.compactMap { cat in
            let g = items.filter { $0.dateCategory == cat }
            return g.isEmpty ? nil : (cat, g)
        }
    }

    var body: some View {
        List {
            if groupByDate {
                ForEach(dateGroups, id: \.0) { cat, groupItems in
                    Section {
                        ForEach(groupItems) { item in rowFor(item) }
                    } header: {
                        DateSectionHeader(title: cat.rawValue, count: groupItems.count)
                    }
                }
            } else {
                ForEach(items) { item in rowFor(item) }
            }
        }
        .listStyle(.plain)
        // Background right-click (empty space or empty folder)
        .contextMenu {
            Button("Paste") { fileOps.paste(to: directory, reload: reload) }
                .disabled(fileOps.pasteboardURLs.isEmpty)
            if fileOps.canUndo { Button("Undo") { fileOps.undo() } }
            if fileOps.canRedo { Button("Redo") { fileOps.redo() } }
            Divider()
            Button("Refresh") { reload() }
        }
        .onAppear    { reload() }
        .onChange(of: directory)  { _, _ in reload() }
        .onChange(of: showHidden) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDirectory)) { notif in
            if let url = notif.object as? URL, url == directory { reload() }
        }
    }

    @ViewBuilder
    private func rowFor(_ item: FileItem) -> some View {
        ColumnRow(item: item, isHighlighted: highlightedURL == item.url)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if !item.isDirectory { NSWorkspace.shared.open(item.url) }
            })
            .simultaneousGesture(TapGesture(count: 1).onEnded {
                onSelect(item.url)
            })
            .contextMenu { columnContextMenu(item: item) }
    }

    // MARK: - Full context menu

    @ViewBuilder
    private func columnContextMenu(item: FileItem) -> some View {
        Button("Open") { onSelect(item.url) }
        if item.isDirectory {
            Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
            if NSWorkspace.shared.isFilePackage(atPath: item.url.path) {
                Button("Show Package Contents") { onSelect(item.url) }
            }
        }
        Divider()
        Button("Quick Look") { QuickLookController.shared.show([item.url]) }
        Button("Get Info")   { showGetInfo(item: item) }
        Divider()
        Button("Rename…")    { promptRename(item: item) }
        Button("Duplicate")  { fileOps.duplicate([item.url], reload: reload) }
        Button("Make Alias") { fileOps.makeAlias(for: item.url, reload: reload) }
        Button("Compress \"\(item.name)\"") { fileOps.compress([item.url], reload: reload) }
        if item.isArchive {
            Button("Extract Here") { fileOps.extract(item.url, reload: reload) }
        }
        Divider()
        Button("Cut")   { fileOps.cut([item.url]) }
        Button("Copy")  { fileOps.copy([item.url]) }
        Button("Paste") {
            let dest = item.isDirectory ? item.url : directory
            fileOps.paste(to: dest, reload: reload)
        }
        .disabled(fileOps.pasteboardURLs.isEmpty)
        Divider()
        Menu("Share") {
            Button("AirDrop") { fileOps.shareViaAirDrop([item.url]) }
            Divider()
            Button("Share…")  { fileOps.showShareSheet(for: [item.url]) }
        }
        Divider()
        Menu("Tags") {
            TagMenuContent(targets: [item], fileOps: fileOps, onReload: reload)
        }
        Divider()
        if item.isDirectory {
            if favorites.isPinned(item.url) {
                Button("Remove from Sidebar") { favorites.unpin(item.url) }
            } else {
                Button("Add to Sidebar") { favorites.pin(item.url) }
            }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
        }
        Button("Copy Path") {
            fileOps.copyPath(item.url.path)
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            fileOps.trash([item.url], reload: reload)
        }
        Button("Delete Permanently…", role: .destructive) {
            confirmPermanentDelete(names: [item.name]) {
                fileOps.permanentlyDelete([item.url], reload: reload)
            }
        }
    }

    // MARK: - Helpers

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = sortedItems(loadItems(at: directory, showHidden: showHidden),
                                     by: .name, ascending: true)
            DispatchQueue.main.async { items = loaded }
        }
    }

    private func showGetInfo(item: FileItem) {
        showGetInfoInFinder([item.url])
    }

    private func promptRename(item: FileItem) {
        let alert = NSAlert()
        alert.messageText     = "Rename \"\(item.name)\""
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tf.stringValue = item.name; tf.selectText(nil)
        alert.accessoryView = tf; alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return }
        fileOps.rename(item.url, to: name, reload: reload)
    }
}

// MARK: - Column row

struct ColumnRow: View {
    let item:          FileItem
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: item.icon).resizable().frame(width: 16, height: 16)
            Text(item.name).font(.system(size: 12)).lineLimit(1)
            TagDotsView(colors: item.tagColors, size: 9)
            Spacer()
            if item.isDirectory {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
