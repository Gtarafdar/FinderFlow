import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Shared helpers so List / Icons / Columns can drag real files out to Finder,
/// Desktop, upload dialogs, browsers, and other apps — the same pasteboard
/// contract macOS uses for Finder → Finder file drags.
enum FileDragSupport {

    /// Build an `NSItemProvider` that carries one or more existing file URLs.
    /// Upload panels / Finder accept this for both single and multi-file drops.
    static func provider(for urls: [URL]) -> NSItemProvider {
        let unique = Self.dedupe(urls)
        guard !unique.isEmpty else { return NSItemProvider() }

        if unique.count == 1, let single = NSItemProvider(contentsOf: unique[0]) {
            return single
        }

        // Multi-file: advertise the classic filename-list type Finder / browsers
        // and upload panels understand, plus a primary file-URL for the first item.
        let provider = NSItemProvider(object: unique[0] as NSURL)
        provider.registerDataRepresentation(
            forTypeIdentifier: "NSFilenamesPboardType",
            visibility: .all
        ) { completion in
            do {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: unique.map(\.path),
                    format: .xml,
                    options: 0
                )
                completion(data, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        return provider
    }

    /// Resolve which URLs should ride along with a drag that starts on `item`.
    /// If the clicked item is part of the current selection, drag the whole
    /// selection; otherwise just that one item (Finder behaviour).
    static func urlsForDrag(item: FileItem, files: [FileItem], selectedIDs: Set<UUID>) -> [URL] {
        if selectedIDs.contains(item.id), selectedIDs.count > 1 {
            return files.filter { selectedIDs.contains($0.id) }.map(\.url)
        }
        return [item.url]
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for u in urls {
            let key = u.path
            if seen.insert(key).inserted { out.append(u) }
        }
        return out
    }
}

// MARK: - SwiftUI convenience

extension View {
    /// Attach Finder-style file drag-out to any row / icon / cell.
    func fileDragOut(item: FileItem, files: [FileItem], selectedIDs: Set<UUID>) -> some View {
        onDrag {
            let urls = FileDragSupport.urlsForDrag(item: item, files: files, selectedIDs: selectedIDs)
            return FileDragSupport.provider(for: urls)
        }
    }
}
