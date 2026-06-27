import Foundation
import Combine

// Extract file URLs from a finished NSMetadataQuery.
//
// IMPORTANT: NSMetadataItemURLKey ("kMDItemURL") frequently comes back nil for
// Spotlight results (verified on this system), which silently dropped every match
// when used with compactMap. kMDItemPath is reliably populated, so prefer it and
// fall back to the URL key only if the path is somehow missing.
func metadataQueryURLs(_ q: NSMetadataQuery) -> [URL] {
    (0..<q.resultCount).compactMap { i -> URL? in
        guard let item = q.result(at: i) as? NSMetadataItem else { return nil }
        if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
            return URL(fileURLWithPath: path)
        }
        return item.value(forAttribute: NSMetadataItemURLKey) as? URL
    }
}

class SearchEngine: ObservableObject {
    @Published var query          = ""
    @Published var results:   [URL] = []
    @Published var selectedScope: SearchScope = .thisFolder
    @Published var showHidden = false
    @Published var isSearching    = false

    private var metadataQuery:      NSMetadataQuery?
    private var spotlightObservers: [NSObjectProtocol] = []
    private var searchTask:         Task<Void, Never>?

    func search(in directory: URL) {
        guard !query.isEmpty else {
            results = []; isSearching = false; return
        }

        searchTask?.cancel()
        isSearching = true

        switch selectedScope {
        case .thisFolder:
            searchFlat(in: directory)
        case .thisFolderRecursive:
            searchRecursive(in: directory)
        default:
            searchWithSpotlight(scope: selectedScope, fallbackDir: directory)
        }
    }

    // MARK: - Flat local search (current folder only)

    private func searchFlat(in directory: URL) {
        let q       = query
        let hidden  = showHidden
        searchTask  = Task {
            let opts: FileManager.DirectoryEnumerationOptions = hidden ? [] : [.skipsHiddenFiles]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: opts
            )) ?? []
            let filtered = urls.filter { matches(url: $0, query: q) }
            await MainActor.run { self.results = filtered; self.isSearching = false }
        }
    }

    // MARK: - Recursive local search (folder + all subfolders, no Spotlight)

    private func searchRecursive(in directory: URL) {
        let q       = query
        let hidden  = showHidden
        searchTask  = Task {
            var found: [URL] = []
            let opts: FileManager.DirectoryEnumerationOptions = hidden
                ? []
                : [.skipsHiddenFiles, .skipsPackageDescendants]
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: opts
            )
            while let url = enumerator?.nextObject() as? URL {
                if Task.isCancelled { break }
                if matches(url: url, query: q) { found.append(url) }
                if found.count >= 5_000 { break }   // safety cap
            }
            await MainActor.run { self.results = found; self.isSearching = false }
        }
    }

    // MARK: - Spotlight search (Desktop / Documents / Downloads / Home / Entire Mac)

    private func searchWithSpotlight(scope: SearchScope, fallbackDir: URL) {
        stopSpotlight()

        let q = NSMetadataQuery()

        // Map scope → correct NSMetadataQuery search scope
        switch scope {
        case .entireMac:
            q.searchScopes = [NSMetadataQueryLocalComputerScope]
        default:
            let url = scope.baseURL(currentPath: fallbackDir)
            q.searchScopes = [url as NSURL]
        }

        q.predicate = buildSpotlightPredicate()
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]

        // Collect results on finish AND on each incremental update
        let collect: (Notification) -> Void = { [weak self, weak q] _ in
            self?.collectSpotlightResults(from: q)
        }
        spotlightObservers = [
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main, using: collect),
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: q, queue: .main, using: collect),
        ]

        q.start()
        metadataQuery = q
    }

    private func collectSpotlightResults(from q: NSMetadataQuery?) {
        guard let q else { return }
        q.disableUpdates()
        let urls = metadataQueryURLs(q)
        q.enableUpdates()
        results    = urls
        isSearching = false
    }

    private func stopSpotlight() {
        metadataQuery?.stop()
        spotlightObservers.forEach { NotificationCenter.default.removeObserver($0) }
        spotlightObservers = []
        metadataQuery      = nil
    }

    // MARK: - Query helpers

    /// Extension prefix: ".pdf" → match by extension; otherwise match by name.
    private func matches(url: URL, query: String) -> Bool {
        if query.hasPrefix(".") {
            let ext = String(query.dropFirst()).lowercased()
            return ext.isEmpty ? false : url.pathExtension.lowercased() == ext
        }
        return url.lastPathComponent.localizedCaseInsensitiveContains(query)
    }

    /// Build an NSPredicate that mirrors the local `matches` logic for Spotlight.
    private func buildSpotlightPredicate() -> NSPredicate {
        if query.hasPrefix(".") {
            let ext = String(query.dropFirst())
            guard !ext.isEmpty else {
                return NSPredicate(value: false)
            }
            return NSPredicate(format: "kMDItemFSExtension ==[cd] %@", ext)
        }
        return NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, query)
    }

    deinit {
        stopSpotlight()
        searchTask?.cancel()
    }
}

// MARK: - Mac-wide tag-based Spotlight search

class TagService: NSObject, ObservableObject {
    @Published var taggedFileURLs:  [URL] = []
    @Published var isSearchingTags: Bool  = false

    private var searchQuery:     NSMetadataQuery?
    private var searchObservers: [NSObjectProtocol] = []

    // Search Mac-wide for all files tagged with `tag`.
    // Uses ==[cd] so "Red" matches "red", "RED", etc.
    func searchFiles(forTag tag: String) {
        stopSearch()
        isSearchingTags = true
        let q = NSMetadataQuery()
        q.searchScopes    = [NSMetadataQueryLocalComputerScope]
        // Match the modern user tag by name AND, for the 7 standard colors, the
        // legacy color label (kMDItemFSLabel). Finder's color sidebar matches the
        // label too, so this also surfaces files tagged by Finder or older builds
        // that carry the color label but no kMDItemUserTags value.
        let tagPredicate = NSPredicate(format: "kMDItemUserTags ==[cd] %@", tag)
        if let colorNumber = FileItem.colorNameToLabel[tag.lowercased()] {
            let labelPredicate = NSPredicate(format: "kMDItemFSLabel == %d", colorNumber)
            q.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [tagPredicate, labelPredicate])
        } else {
            q.predicate = tagPredicate
        }
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]

        let handle: (Notification) -> Void = { [weak self, weak q] _ in
            self?.collectTaggedFiles(from: q)
        }
        searchObservers = [
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main, using: handle),
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: q, queue: .main, using: handle),
        ]
        q.start()
        searchQuery = q
    }

    private func collectTaggedFiles(from q: NSMetadataQuery?) {
        guard let q else { return }
        q.disableUpdates()
        let urls = metadataQueryURLs(q)
        q.enableUpdates()
        taggedFileURLs  = urls
        isSearchingTags = false
    }

    func stopSearch() {
        searchQuery?.stop()
        searchObservers.forEach { NotificationCenter.default.removeObserver($0) }
        searchObservers = []
        searchQuery     = nil
        taggedFileURLs  = []
        isSearchingTags = false
    }

    deinit { stopSearch() }
}
