import SwiftUI

enum SidebarItem: Hashable {
    case location(URL)
    case pinned(URL)
    case recent(URL)
}

// MARK: - Favorites service (pinned folders)

class FavoritesService: ObservableObject {
    @Published var pinnedURLs: [URL] = []

    init() { load() }

    func load() {
        pinnedURLs = (UserDefaults.standard.stringArray(forKey: "pinnedFolders") ?? [])
            .compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func pin(_ url: URL) {
        guard url.hasDirectoryPath, !pinnedURLs.contains(url) else { return }
        pinnedURLs.insert(url, at: 0)
        save()
    }

    func unpin(_ url: URL) {
        pinnedURLs.removeAll { $0 == url }
        save()
    }

    func isPinned(_ url: URL) -> Bool { pinnedURLs.contains(url) }

    private func save() {
        UserDefaults.standard.set(pinnedURLs.map(\.path), forKey: "pinnedFolders")
    }
}

// MARK: - Sidebar view

struct SidebarView: View {
    @Binding var currentPath:     URL
    @Binding var selection:       SidebarItem?
    @Binding var activeTagFilter: String?
    let usedTagNames: [String]
    @EnvironmentObject var favorites: FavoritesService
    @State private var recentFolders: [URL] = []

    var body: some View {
        List(selection: $selection) {

            // ── System locations ──────────────────────────────────────────
            Section("Favorites") {
                ForEach(systemLocations, id: \.self) { url in
                    SidebarRow(url: url)
                        .tag(SidebarItem.location(url))
                        .onTapGesture { currentPath = url }
                }
            }

            // ── User-pinned folders ───────────────────────────────────────
            if !favorites.pinnedURLs.isEmpty {
                Section("Pinned") {
                    ForEach(favorites.pinnedURLs, id: \.self) { url in
                        SidebarRow(url: url)
                            .tag(SidebarItem.pinned(url))
                            .onTapGesture { currentPath = url }
                            .contextMenu {
                                Button("Remove from Pinned") { favorites.unpin(url) }
                            }
                    }
                    .onDelete { idx in
                        idx.forEach { favorites.unpin(favorites.pinnedURLs[$0]) }
                    }
                }
            }

            // ── Recent ────────────────────────────────────────────────────
            if !recentFolders.isEmpty {
                Section("Recent") {
                    ForEach(recentFolders.prefix(8), id: \.self) { url in
                        SidebarRow(url: url)
                            .tag(SidebarItem.recent(url))
                            .onTapGesture { currentPath = url }
                    }
                }
            }

            // ── Tags (only when files in current folder are tagged) ────────
            if !usedTagNames.isEmpty {
                Section("Tags") {
                    ForEach(usedTagNames, id: \.self) { tag in
                        tagRow(tag: tag)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { loadRecent() }
        .onChange(of: currentPath) { _, path in
            if path.hasDirectoryPath { addToRecent(path) }
        }
    }

    private var systemLocations: [URL] {
        let fm = FileManager.default
        return [
            fm.homeDirectoryForCurrentUser,
            fm.urls(for: .desktopDirectory,  in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
    }

    private func loadRecent() {
        recentFolders = (UserDefaults.standard.stringArray(forKey: "recentFolders") ?? [])
            .compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addToRecent(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(20)), forKey: "recentFolders")
        recentFolders = Array(paths.prefix(8)).compactMap { URL(fileURLWithPath: $0) }
    }

    @ViewBuilder
    private func tagRow(tag: String) -> some View {
        let isActive = activeTagFilter == tag
        let dotColor = FileItem.colorForTagName(tag) ?? Color(nsColor: .systemGray)
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            Text(tag)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .listRowBackground(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture {
            activeTagFilter = isActive ? nil : tag
        }
    }
}

struct SidebarRow: View {
    let url: URL
    private var displayName: String {
        url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent
    }
    var body: some View {
        Label {
            Text(displayName).lineLimit(1)
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 16, height: 16)
        }
    }
}
