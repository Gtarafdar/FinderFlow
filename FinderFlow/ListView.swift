import SwiftUI
import AppKit

// Approximate height of the Table's column header row. Below this strip the pointer
// is over the rows, where the cursor must always be the plain arrow. Erring slightly
// tall keeps us from ever clobbering the header divider's resize cursor.
private let kTableHeaderStripHeight: CGFloat = 30

struct ListView: View {
    let files:         [FileItem]
    @Binding var selectedIDs:      Set<UUID>
    @Binding var pendingRenameURL: URL?
    let currentPath:   URL
    @Binding var sortField:     SortField
    @Binding var sortAscending: Bool
    let groupBy:       GroupBy
    let onNavigate:    (URL) -> Void
    let onBrowseInto:  (URL) -> Void
    let onReload:      () -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var sortOrder:       [KeyPathComparator<FileItem>] = [.init(\.name, order: .forward)]
    @State private var renamingID:      UUID?
    @State private var renameText:      String = ""
    @State private var renameCancelled: Bool   = false
    @FocusState private var renameActive: Bool

    var body: some View {
        if groupBy != .none {
            GroupedListView(
                files:            files,
                selectedIDs:      $selectedIDs,
                pendingRenameURL: $pendingRenameURL,
                currentPath:      currentPath,
                groupBy:          groupBy,
                onNavigate:       onNavigate,
                onBrowseInto:     onBrowseInto,
                onReload:         onReload,
                fileOps:          fileOps,
                favorites:        favorites
            )
        } else {
            tableView
                .onChange(of: pendingRenameURL) { _, url in
                    guard let url, let item = files.first(where: { $0.url == url }) else { return }
                    startRename(item: item)
                    pendingRenameURL = nil
                }
        }
    }

    // MARK: - Table (non-grouped)

    private var tableView: some View {
        Table(files, selection: $selectedIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(nsImage: item.icon).resizable().frame(width: 16, height: 16)
                    if renamingID == item.id {
                        TextField("", text: $renameText)
                            .textFieldStyle(.plain)
                            .resetsCursorOnExit()
                            .focused($renameActive)
                            .onSubmit {
                                if let it = files.first(where: { $0.id == renamingID }) {
                                    commitRename(for: it)
                                }
                            }
                            .onExitCommand { cancelRename() }
                    } else {
                        Text(item.name).lineLimit(1)
                            .foregroundStyle(fileOps.isCut && fileOps.clipboardURLs.contains(item.url)
                                             ? Color.secondary : Color.primary)
                    }
                    TagDotsView(colors: item.tagColors, size: 10)
                }
                .fileDragOut(item: item, files: files, selectedIDs: selectedIDs)
            }
            .width(min: 140, ideal: 280, max: 600)

            TableColumn("Date Modified", value: \.dateModified) { item in
                Text(item.formattedDateModified).foregroundStyle(.secondary)
            }.width(min: 100, ideal: 148, max: 240)

            TableColumn("Date Created", value: \.dateCreated) { item in
                Text(item.formattedDateCreated).foregroundStyle(.secondary)
            }.width(min: 100, ideal: 148, max: 240)

            TableColumn("Size", value: \.size) { item in
                Text(item.formattedSize).foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 50, ideal: 80, max: 140)

            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary)
            }.width(min: 60, ideal: 110, max: 200)

            TableColumn("Extension", value: \.fileExtension) { item in
                Text(item.fileExtension.isEmpty ? "—" : item.fileExtension.uppercased())
                    .foregroundStyle(.secondary)
            }.width(min: 40, ideal: 68, max: 120)
        }
        .onChange(of: sortOrder) { _, order in
            guard let first = order.first else { return }
            sortAscending = (first.order == .forward)
            switch first.keyPath {
            case \FileItem.name:          sortField = .name
            case \FileItem.dateModified:  sortField = .dateModified
            case \FileItem.dateCreated:   sortField = .dateCreated
            case \FileItem.size:          sortField = .size
            case \FileItem.kind:          sortField = .kind
            case \FileItem.fileExtension: sortField = .ext
            default: break
            }
        }
        .onChange(of: sortField)     { _, _ in syncSortOrder() }
        .onChange(of: sortAscending) { _, _ in syncSortOrder() }
        .onChange(of: renameActive)  { _, active in
            guard !active, let id = renamingID,
                  let item = files.first(where: { $0.id == id }) else { return }
            commitRename(for: item)
        }
        .onAppear { syncSortOrder() }
        .contextMenu(forSelectionType: UUID.self) { ids in contextMenu(for: ids) }
        primaryAction: { ids in
            guard renamingID == nil else { return }
            if let id = ids.first, let item = files.first(where: { $0.id == id }) {
                onNavigate(item.url)
            }
        }
        .background(
            Button("") { quickLook(ids: selectedIDs) }
                .keyboardShortcut(.space, modifiers: []).hidden()
        )
        // Release the column-resize cursor once the pointer moves into the rows.
        // The Table's NSTableView header sets a resize cursor on its column dividers
        // and (like every AppKit drag) leaves it stuck after a resize. The header and
        // rows are the same view, so there's no enter/exit boundary to hook — instead
        // we watch the live pointer position: anywhere below the header strip the
        // cursor must be the plain arrow, so force it there. We never touch the header
        // region (resize cursor still shows while hovering/dragging a divider) and skip
        // it during an inline rename so the text I-beam isn't disturbed.
        .onContinuousHover { phase in
            guard renamingID == nil else { return }
            if case .active(let point) = phase, point.y > kTableHeaderStripHeight {
                NSCursor.arrow.set()
            }
        }
    }

    private func syncSortOrder() {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortField {
        case .name:         sortOrder = [KeyPathComparator(\.name,          order: order)]
        case .dateModified: sortOrder = [KeyPathComparator(\.dateModified,  order: order)]
        case .dateCreated:  sortOrder = [KeyPathComparator(\.dateCreated,   order: order)]
        case .size:         sortOrder = [KeyPathComparator(\.size,          order: order)]
        case .kind:         sortOrder = [KeyPathComparator(\.kind,          order: order)]
        case .ext:          sortOrder = [KeyPathComparator(\.fileExtension, order: order)]
        }
    }

    // MARK: - Inline rename helpers

    func startRename(item: FileItem) {
        renameCancelled = false
        renamingID      = item.id
        renameText      = item.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { renameActive = true }
    }

    private func commitRename(for item: FileItem) {
        renamingID   = nil
        renameActive = false
        guard !renameCancelled else { renameCancelled = false; return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return }
        fileOps.rename(item.url, to: name, reload: onReload)
    }

    private func cancelRename() {
        renameCancelled = true
        renamingID      = nil
    }

    // MARK: - Full macOS context menu

    @ViewBuilder
    func contextMenu(for ids: Set<UUID>) -> some View {
        let sel  = files.filter { ids.contains($0.id) }
        if let item = sel.first {
            let urls = sel.map(\.url)

            Button("Open")               { onNavigate(item.url) }
            if item.isBrowsableFolder {
                Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
            } else if item.isPackage {
                Button("Show Package Contents") { onBrowseInto(item.url) }
            }
            Divider()
            Button("Quick Look")         { quickLook(ids: ids) }
            Button("Get Info")           { showGetInfo(for: sel) }
            Divider()
            Button("Rename…")            { pendingRenameURL = item.url }
            Button(sel.count > 1 ? "Duplicate \(sel.count) Items" : "Duplicate") {
                fileOps.duplicate(urls, reload: onReload)
            }
            Button(sel.count > 1 ? "Make \(sel.count) Aliases" : "Make Alias") {
                urls.forEach { fileOps.makeAlias(for: $0, reload: onReload) }
            }
            Button(sel.count > 1 ? "Compress \(sel.count) Items" : "Compress \"\(item.name)\"") {
                fileOps.compress(urls, reload: onReload)
            }
            if sel.count == 1 && item.isArchive {
                Button("Extract Here") { fileOps.extract(item.url, reload: onReload) }
            }
            Divider()
            Button("Cut")                { fileOps.cut(urls) }
            Button("Copy")               { fileOps.copy(urls) }
            Button("Paste") {
                let dest = (sel.count == 1 && item.isDirectory) ? item.url : currentPath
                fileOps.paste(to: dest, reload: onReload)
            }
            .disabled(fileOps.pasteboardURLs.isEmpty)
            Divider()
            Menu("Share") {
                Button("AirDrop")        { fileOps.shareViaAirDrop(urls) }
                Divider()
                Button("Share…")         { fileOps.showShareSheet(for: urls) }
            }
            Divider()
            Menu("Tags") {
                TagMenuContent(targets: sel, fileOps: fileOps, onReload: onReload)
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
            Button(sel.count > 1 ? "Copy \(sel.count) Paths" : "Copy Path") {
                fileOps.copyPath(urls.map(\.path).joined(separator: "\n"))
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                fileOps.trash(urls, reload: onReload)
            }
            Button("Delete Permanently…", role: .destructive) {
                confirmPermanentDelete(names: sel.map(\.name)) {
                    fileOps.permanentlyDelete(urls, reload: onReload)
                }
            }
        } else {
            Button("Paste") { fileOps.paste(to: currentPath, reload: onReload) }
                .disabled(fileOps.pasteboardURLs.isEmpty)
            if fileOps.canUndo { Button("Undo") { fileOps.undo() } }
            if fileOps.canRedo { Button("Redo") { fileOps.redo() } }
            Divider()
            Button("Refresh") { onReload() }
        }
    }

    // MARK: - Helpers

    private func quickLook(ids: Set<UUID>) {
        let urls = files.filter { ids.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        QuickLookController.shared.show(urls)
    }

    private func showGetInfo(for items: [FileItem]) {
        showGetInfoInFinder(items.map(\.url))
    }
}

// MARK: - Date-grouped list view

struct GroupedListView: View {
    let files:       [FileItem]
    @Binding var selectedIDs:      Set<UUID>
    @Binding var pendingRenameURL: URL?
    let currentPath: URL
    let groupBy:     GroupBy
    let onNavigate:  (URL) -> Void
    let onBrowseInto:(URL) -> Void
    let onReload:    () -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var renamingID:      UUID?
    @State private var renameText:      String = ""
    @State private var renameCancelled: Bool   = false
    @FocusState private var renameActive: Bool

    private var groups: [FileGroup] { groupedItems(files, by: groupBy) }

    var body: some View {
        ScrollViewReader { proxy in
        List(selection: $selectedIDs) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        ZStack(alignment: .leading) {
                            GroupedRow(item: item, isSelected: selectedIDs.contains(item.id))
                                .opacity(renamingID == item.id ? 0 : 1)
                            if renamingID == item.id {
                                HStack(spacing: 8) {
                                    Image(nsImage: item.icon).resizable().frame(width: 18, height: 18)
                                    TextField("", text: $renameText)
                                        .textFieldStyle(.plain)
                                        .resetsCursorOnExit()
                                        .focused($renameActive)
                                        .onSubmit {
                                            if let it = files.first(where: { $0.id == renamingID }) {
                                                commitGroupedRename(for: it)
                                            }
                                        }
                                        .onExitCommand { cancelGroupedRename() }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .tag(item.id)
                        .id(item.id)
                        .fileDragOut(item: item, files: files, selectedIDs: selectedIDs)
                        .onTapGesture(count: 2) { onNavigate(item.url) }
                        .onTapGesture {
                            selectedIDs = selectedIDs.contains(item.id)
                                ? [] : [item.id]
                        }
                        .contextMenu { listContextMenu(item: item) }
                    }
                } header: {
                    DateSectionHeader(title: group.title, count: group.items.count)
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: selectedIDs) { _, ids in
            if let id = ids.first {
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onChange(of: renameActive) { _, active in
            guard !active, let id = renamingID,
                  let item = files.first(where: { $0.id == id }) else { return }
            commitGroupedRename(for: item)
        }
        .onChange(of: pendingRenameURL) { _, url in
            guard let url, let item = files.first(where: { $0.url == url }) else { return }
            startGroupedRename(item: item)
            pendingRenameURL = nil
        }
        .background(
            Button("") {
                let urls = files.filter { selectedIDs.contains($0.id) }.map(\.url)
                if !urls.isEmpty { QuickLookController.shared.show(urls) }
            }
            .keyboardShortcut(.space, modifiers: []).hidden()
        )
        } // ScrollViewReader
    }

    // MARK: - Grouped inline rename helpers

    func startGroupedRename(item: FileItem) {
        renameCancelled = false
        renamingID      = item.id
        renameText      = item.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { renameActive = true }
    }

    private func commitGroupedRename(for item: FileItem) {
        renamingID   = nil
        renameActive = false
        guard !renameCancelled else { renameCancelled = false; return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return }
        fileOps.rename(item.url, to: name, reload: onReload)
    }

    private func cancelGroupedRename() {
        renameCancelled = true
        renamingID      = nil
    }

    @ViewBuilder
    private func listContextMenu(item: FileItem) -> some View {
        let sel     = files.filter { selectedIDs.contains($0.id) }
        let targets = sel.isEmpty ? [item] : sel
        let urls    = targets.map(\.url)

        Button("Open")       { onNavigate(item.url) }
        if item.isBrowsableFolder {
            Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
        } else if item.isPackage {
            Button("Show Package Contents") { onBrowseInto(item.url) }
        }
        Button("Quick Look") { QuickLookController.shared.show(urls) }
        Button("Get Info")   { showGetInfoInFinder([item.url]) }
        Divider()
        Button("Rename…")   { pendingRenameURL = item.url }
        Button("Duplicate") { fileOps.duplicate(urls, reload: onReload) }
        Button(targets.count > 1 ? "Make \(targets.count) Aliases" : "Make Alias") {
            urls.forEach { fileOps.makeAlias(for: $0, reload: onReload) }
        }
        Button(targets.count > 1 ? "Compress \(targets.count) Items" : "Compress \"\(item.name)\"") {
            fileOps.compress(urls, reload: onReload)
        }
        if targets.count == 1, item.isArchive {
            Button("Extract Here") { fileOps.extract(item.url, reload: onReload) }
        }
        Divider()
        Button("Cut")  { fileOps.cut(urls) }
        Button("Copy") { fileOps.copy(urls) }
        Button("Paste") {
            let dest = (targets.count == 1 && item.isDirectory) ? item.url : currentPath
            fileOps.paste(to: dest, reload: onReload)
        }
        .disabled(fileOps.pasteboardURLs.isEmpty)
        Divider()
        Menu("Share") {
            Button("AirDrop") { fileOps.shareViaAirDrop(urls) }
            Divider()
            Button("Share…") { fileOps.showShareSheet(for: urls) }
        }
        Divider()
        Menu("Tags") {
            TagMenuContent(targets: targets, fileOps: fileOps, onReload: onReload)
        }
        Divider()
        if item.isBrowsableFolder {
            if favorites.isPinned(item.url) {
                Button("Remove from Sidebar") { favorites.unpin(item.url) }
            } else {
                Button("Add to Sidebar") { favorites.pin(item.url) }
            }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
        }
        Button(targets.count > 1 ? "Copy \(targets.count) Paths" : "Copy Path") {
            fileOps.copyPath(urls.map(\.path).joined(separator: "\n"))
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            fileOps.trash(urls, reload: onReload)
        }
        Button("Delete Permanently…", role: .destructive) {
            confirmPermanentDelete(names: targets.map(\.name)) {
                fileOps.permanentlyDelete(urls, reload: onReload)
            }
        }
    }
}

struct GroupedRow: View {
    let item:       FileItem
    let isSelected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.name).font(.system(size: 13)).lineLimit(1)
                    TagDotsView(colors: item.tagColors, size: 9)
                }
                Text(item.kind + (item.isDirectory ? "" : " • \(item.formattedSize)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.formattedDateModified)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Date section header (Finder-style)

struct DateSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }
}
