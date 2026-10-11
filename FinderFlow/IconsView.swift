import SwiftUI

struct IconsView: View {
    let files:       [FileItem]
    @Binding var selectedIDs: Set<String>
    let currentPath: URL
    let groupBy:     GroupBy
    let onNavigate:  (FileItem) -> Void
    let onBrowseInto:(URL) -> Void
    let onReload:    () -> Void
    @ObservedObject var fileOps:   FileOperationsService
    @ObservedObject var favorites: FavoritesService

    @State private var iconSize: CGFloat = 64
    @EnvironmentObject private var locale: LocaleState

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
                                            .onTapGesture(count: 2) { onNavigate(item) }
                                            .onTapGesture { selectedIDs = [item.id] }
                                        IconCell(item: item, iconSize: iconSize, isSelected: selectedIDs.contains(item.id))
                                            .allowsHitTesting(false)
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

        Button(L10n.s("Open")) { onNavigate(item) }
        if item.isBrowsableFolder {
            Button(L10n.s("Open in New Window")) { NSWorkspace.shared.open(item.url) }
        } else if item.isPackage {
            Button(L10n.s("Show Package Contents")) { onBrowseInto(item.url) }
        }
        Divider()
        Button(L10n.s("Quick Look")) { QuickLookController.shared.show(urls) }
        Button(L10n.s("Get Info"))   { showGetInfo(for: targets) }
        Divider()
        Button(L10n.s("Rename…"))  { promptRename(item: item) }
        Button(targets.count > 1 ? L10n.sf("Duplicate %d Items", targets.count) : L10n.s("Duplicate")) {
            fileOps.duplicate(urls, reload: onReload)
        }
        Button(targets.count > 1 ? L10n.sf("Make %d Aliases", targets.count) : L10n.s("Make Alias")) {
            urls.forEach { fileOps.makeAlias(for: $0, reload: onReload) }
        }
        Button(targets.count > 1 ? L10n.sf("Compress %d Items", targets.count) : L10n.sf("Compress \"%\"", item.name)) {
            fileOps.compress(urls, reload: onReload)
        }
        if targets.count == 1 && item.isArchive {
            Button(L10n.s("Extract Here")) { fileOps.extract(item.url, reload: onReload) }
        }
        Divider()
        Button(L10n.s("Cut"))   { fileOps.cut(urls) }
        Button(L10n.s("Copy"))  { fileOps.copy(urls) }
        Button(L10n.s("Paste")) {
            let dest = (targets.count == 1 && item.isDirectory) ? item.url : currentPath
            fileOps.paste(to: dest, reload: onReload)
        }
        .disabled(fileOps.pasteboardURLs.isEmpty)
        Divider()
        Menu(L10n.s("Share")) {
            Button(L10n.s("AirDrop")) { fileOps.shareViaAirDrop(urls) }
            Divider()
            Button(L10n.s("Share…")) { fileOps.showShareSheet(for: urls) }
        }
        Divider()
        Menu(L10n.s("Tags")) {
            TagMenuContent(targets: targets, fileOps: fileOps, onReload: onReload)
        }
        Divider()
        if item.isBrowsableFolder {
            if favorites.isPinned(item.url) {
                Button(L10n.s("Remove from Sidebar")) { favorites.unpin(item.url) }
            } else {
                Button(L10n.s("Add to Sidebar")) { favorites.pin(item.url) }
            }
        }
        Button(L10n.s("Show in Finder")) {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
        }
        Button(targets.count > 1 ? L10n.sf("Copy %d Paths", targets.count) : L10n.s("Copy Path")) {
            fileOps.copyPath(urls.map(\.path).joined(separator: "\n"))
        }
        Divider()
        Button(L10n.s("Move to Trash"), role: .destructive) {
            fileOps.trash(urls, reload: onReload)
        }
        Button(L10n.s("Delete Permanently…"), role: .destructive) {
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
        alert.messageText     = L10n.sf("Rename \"%\"", item.name)
        alert.informativeText = L10n.s("Enter a new name:")
        alert.addButton(withTitle: L10n.s("Rename"))
        alert.addButton(withTitle: L10n.s("Cancel"))
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
                    .allowsHitTesting(false)
                if !item.tagColors.isEmpty {
                    TagDotsView(colors: item.tagColors, size: 10)
                        .offset(x: 2, y: 2)
                        .allowsHitTesting(false)
                }
            }
            Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? .white : .primary)
                .allowsHitTesting(false)
        }
        .padding(6).frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
