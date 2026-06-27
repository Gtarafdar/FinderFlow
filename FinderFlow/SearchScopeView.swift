import SwiftUI
import AppKit

enum SearchScope: String, CaseIterable {
    case thisFolder          = "This Folder"
    case thisFolderRecursive = "This Folder & Subfolders"
    case desktop             = "Desktop"
    case documents           = "Documents"
    case downloads           = "Downloads"
    case home                = "Home Folder"
    case entireMac           = "Entire Mac"

    var icon: String {
        switch self {
        case .thisFolder:          "folder"
        case .thisFolderRecursive: "folder.fill.badge.plus"
        case .desktop:             "desktopcomputer"
        case .documents:           "doc"
        case .downloads:           "arrow.down.circle"
        case .home:                "house"
        case .entireMac:           "magnifyingglass"
        }
    }

    func baseURL(currentPath: URL) -> URL {
        let fm = FileManager.default
        switch self {
        case .thisFolder, .thisFolderRecursive:
            return currentPath
        case .desktop:
            return fm.urls(for: .desktopDirectory,  in: .userDomainMask).first ?? currentPath
        case .documents:
            return fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? currentPath
        case .downloads:
            return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? currentPath
        case .home:
            return fm.homeDirectoryForCurrentUser
        case .entireMac:
            return fm.homeDirectoryForCurrentUser   // unused; Spotlight uses its own scope constant
        }
    }
}

struct SearchScopeView: View {
    let currentPath: URL
    @ObservedObject var searchEngine: SearchEngine
    var body: some View {
        HStack(spacing: 8) {

            // ── Scope picker ──────────────────────────────────────────────
            Picker("Scope", selection: $searchEngine.selectedScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            // Re-run search immediately when scope changes
            .onChange(of: searchEngine.selectedScope) { _, _ in
                guard !searchEngine.query.isEmpty else { return }
                searchEngine.search(
                    in: searchEngine.selectedScope.baseURL(currentPath: currentPath))
            }

            // ── Search field ──────────────────────────────────────────────
            HStack(spacing: 4) {
                if searchEngine.isSearching {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                TextField("Name or .ext (e.g. .pdf)…", text: $searchEngine.query)
                    .textFieldStyle(.plain)
                    .resetsCursorOnExit()
                    .onSubmit {
                        searchEngine.search(
                            in: searchEngine.selectedScope.baseURL(currentPath: currentPath))
                    }
                    .onChange(of: searchEngine.query) { _, newValue in
                        if newValue.isEmpty {
                            searchEngine.results    = []
                            searchEngine.isSearching = false
                        } else {
                            searchEngine.search(
                                in: searchEngine.selectedScope.baseURL(currentPath: currentPath))
                        }
                    }

                if !searchEngine.query.isEmpty {
                    Button {
                        searchEngine.query      = ""
                        searchEngine.results    = []
                        searchEngine.isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            // ── Result count badge ────────────────────────────────────────
            if !searchEngine.query.isEmpty && !searchEngine.isSearching {
                Text("\(searchEngine.results.count) found")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        // Re-run "This Folder" search when user navigates to a different folder
        .onChange(of: currentPath) { _, newPath in
            guard !searchEngine.query.isEmpty,
                  searchEngine.selectedScope == .thisFolder ||
                  searchEngine.selectedScope == .thisFolderRecursive
            else { return }
            searchEngine.search(
                in: searchEngine.selectedScope.baseURL(currentPath: newPath))
        }
    }
}
