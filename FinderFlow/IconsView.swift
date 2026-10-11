import SwiftUI

struct IconsView: View {
    let files:       [FileItem]
    @Binding var selectedIDs: Set<String>
    @Binding var pendingInlineEdit: InlineEditTarget?
    let currentPath: URL
    let groupBy:     GroupBy
    let onNavigate:  (FileItem) -> Void
    let onBrowseInto:(URL) -> Void
    let onReload:    () -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var iconSize: CGFloat = 64
    @State private var renamingID: String?
    @State private var editKind:   InlineEditKind = .rename

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: iconSize + 20, maximum: iconSize + 40), spacing: 8)]
    }

    private var groups: [FileGroup] { groupedItems(files, by: groupBy) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.items) { item in
                                    ZStack {
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .onTapGesture(count: 2) {
                                                guard renamingID == nil else { return }
                                                onNavigate(item)
                                            }
                                            .onTapGesture {
                                                guard renamingID == nil else { return }
                                                selectedIDs = [item.id]
                                            }
                                        if renamingID == item.id {
                                            IconCell(item: item, iconSize: iconSize,
                                                      isSelected: selectedIDs.contains(item.id),
                                                      hidesName: true)
                                                .overlay(alignment: .bottom) {
                                                    RenameField(
                                                        initialValue:     item.name,
                                                        initialSelection: inlineEditSelectionRange(for: item.name),
                                                        font:             .systemFont(ofSize: 11),
                                                        textColor:        selectedIDs.contains(item.id) ? .white : .labelColor,
                                                        onCommit:         { commitEdit($0, item: item) },
                                                        onCancel:         { cancelEdit(item: item) }
                                                    )
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.horizontal, 4)
                                                    .padding(.bottom, 6)
                                                }
                                        } else {
                                            IconCell(item: item, iconSize: iconSize, isSelected: selectedIDs.contains(item.id))
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .fileDragOut(item: item, files: files, selectedIDs: selectedIDs)
                                    .contextMenu { iconContextMenu(item: item) }
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            if groupBy != .none, !group.title.isEmpty {
                                DateSectionHeader(title: group.title, count: group.items.count)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .contextMenu { FolderBackgroundMenu() }
            .onAppear { applyPendingInlineEdit(files) }
            .onChange(of: pendingInlineEdit) { _, _ in applyPendingInlineEdit(files) }
            .onChange(of: files) { _, newFiles in
                if let id = renamingID, !newFiles.contains(where: { $0.id == id }) {
                    renamingID = nil
                }
                applyPendingInlineEdit(newFiles)
            }
            .background(
                Button("") { quickLook() }
                    .keyboardShortcut(.space, modifiers: [])
                    .hidden()
            )

            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $iconSize, in: 32...128, step: 8).frame(width: 100)
                Image(systemName: "square.grid.2x2").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private func iconContextMenu(item: FileItem) -> some View {
        let sel  = files.filter { selectedIDs.contains($0.id) }
        let targets = sel.isEmpty ? [item] : sel
        let urls    = targets.map(\.url)

        Button("Open") { onNavigate(item) }
        if item.isBrowsableFolder {
            Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
        } else if item.isPackage {
            Button("Show Package Contents") { onBrowseInto(item.url) }
        }
        Divider()
        Button("Quick Look") { QuickLookController.shared.show(urls) }
        Button("Get Info")   { showGetInfo(for: targets) }
        Divider()
        Button("Rename…")  { pendingInlineEdit = InlineEditTarget(kind: .rename, url: item.url) }
        Button(targets.count > 1 ? "Duplicate \(targets.count) Items" : "Duplicate") {
            fileOps.duplicate(urls, reload: onReload)
        }
        Button(targets.count > 1 ? "Make \(targets.count) Aliases" : "Make Alias") {
            urls.forEach { fileOps.makeAlias(for: $0, reload: onReload) }
        }
        Button(targets.count > 1 ? "Compress \(targets.count) Items" : "Compress \"\(item.name)\"") {
            fileOps.compress(urls, reload: onReload)
        }
        if targets.count == 1 && item.isArchive {
            Button("Extract Here") { fileOps.extract(item.url, reload: onReload) }
        }
        Divider()
        Button("Cut")   { fileOps.cut(urls) }
        Button("Copy")  { fileOps.copy(urls) }
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

    private func quickLook() {
        let urls = files.filter { selectedIDs.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        QuickLookController.shared.show(urls)
    }

    // MARK: - Inline edit (Finder-style)

    private func startEdit(item: FileItem, kind: InlineEditKind) {
        editKind   = kind
        renamingID = item.id
    }

    private func applyPendingInlineEdit(_ newFiles: [FileItem]) {
        guard let target = pendingInlineEdit,
              let item = newFiles.first(where: { $0.url == target.url }) else { return }
        pendingInlineEdit = nil
        startEdit(item: item, kind: target.kind)
    }

    private func commitEdit(_ typed: String, item: FileItem) {
        let kind = editKind
        renamingID = nil
        let name = committedRenameName(typed, original: item.name)
        guard !name.isEmpty else {
            if kind != .rename { removeJustCreated(item.url) }
            return
        }
        guard name != item.name else { return }
        fileOps.rename(item.url, to: name, reload: onReload)
    }

    private func cancelEdit(item: FileItem) {
        let kind = editKind
        renamingID = nil
        if kind != .rename { removeJustCreated(item.url) }
    }

    private func removeJustCreated(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        onReload()
    }

    private func showGetInfo(for items: [FileItem]) {
        showGetInfoInFinder(items.map(\.url))
    }
}

struct IconCell: View {
    let item: FileItem; let iconSize: CGFloat; let isSelected: Bool
    /// When true the name row is left empty — an inline rename field is
    /// overlaid there instead (the cell keeps its size so the grid doesn't jump).
    var hidesName: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .allowsHitTesting(false)
                if !item.tagColors.isEmpty {
                    TagDotsView(colors: item.tagColors, size: 10)
                        .offset(x: 2, y: 2)
                        .allowsHitTesting(false)
                }
            }
            if hidesName {
                Color.clear.frame(height: 14)
            } else {
                Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .allowsHitTesting(false)
            }
        }
        .padding(6).frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
