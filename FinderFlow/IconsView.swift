import SwiftUI

struct IconsView: View {
    let files:       [FileItem]
    @Binding var selectedIDs: Set<UUID>
    let currentPath: URL
    let groupBy:     GroupBy
    let onNavigate:  (URL) -> Void
    let onReload:    () -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var iconSize: CGFloat = 64

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
                                    IconCell(item: item, iconSize: iconSize, isSelected: selectedIDs.contains(item.id))
                                        .fileDragOut(item: item, files: files, selectedIDs: selectedIDs)
                                        .onTapGesture(count: 2) { onNavigate(item.url) }
                                        .onTapGesture         { selectedIDs = [item.id] }
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

        Button("Open") { onNavigate(item.url) }
        if item.isDirectory {
            Button("Open in New Window") { NSWorkspace.shared.open(item.url) }
            if NSWorkspace.shared.isFilePackage(atPath: item.url.path) {
                Button("Show Package Contents") { onNavigate(item.url) }
            }
        }
        Divider()
        Button("Quick Look") { QuickLookController.shared.show(urls) }
        Button("Get Info")   { showGetInfo(for: targets) }
        Divider()
        Button("Rename…")  { promptRename(item: item) }
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

    private func promptRename(item: FileItem) {
        let alert = NSAlert()
        alert.messageText     = "Rename \"\(item.name)\""
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tf.stringValue = item.name; tf.selectText(nil)
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return }
        fileOps.rename(item.url, to: name, reload: onReload)
    }

    private func showGetInfo(for items: [FileItem]) {
        showGetInfoInFinder(items.map(\.url))
    }
}

struct IconCell: View {
    let item: FileItem; let iconSize: CGFloat; let isSelected: Bool
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                if !item.tagColors.isEmpty {
                    TagDotsView(colors: item.tagColors, size: 10)
                        .offset(x: 2, y: 2)
                }
            }
            Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .padding(6).frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
