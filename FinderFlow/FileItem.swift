import Foundation
import AppKit
import SwiftUI

// MARK: - Date category (Finder-style Recent / Older grouping)

/// Matches Finder's "Group by Date" buckets — including the "Previous 90 Days"
/// band Finder added after the old 30-day / Earlier split.
enum DateCategory: String, CaseIterable, Identifiable {
    case today        = "Today"
    case yesterday    = "Yesterday"
    case previous7    = "Previous 7 Days"
    case previous30   = "Previous 30 Days"
    case previous90   = "Previous 90 Days"
    case earlier      = "Earlier"

    var id: String { rawValue }

    static func of(_ date: Date) -> DateCategory {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 7  { return .previous7 }
        if days <= 30 { return .previous30 }
        if days <= 90 { return .previous90 }
        return .earlier
    }
}

// MARK: - Grouping & folder order

/// How items are visually sectioned. Sort field still applies *inside* each group.
enum GroupBy: String, CaseIterable, Identifiable {
    case none = "None"
    case dateModified = "Date Modified"
    case dateCreated  = "Date Created"
    case kind         = "Kind"
    case extension_   = "Extension"
    case size         = "Size"
    case nameInitial  = "Name"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .none:         return "None"
        case .dateModified: return "Date Modified"
        case .dateCreated:  return "Date Created"
        case .kind:         return "Kind"
        case .extension_:   return "Extension"
        case .size:         return "Size"
        case .nameInitial:  return "Name"
        }
    }
}

/// Whether folders float above files, sink below, or mix with the sort.
enum FolderOrder: String, CaseIterable, Identifiable {
    case foldersFirst = "Folders on Top"
    case filesFirst   = "Files on Top"
    case mixed        = "Mixed (Sort Only)"

    var id: String { rawValue }
}

/// A labeled section of already-sorted items used by list / icon / column views.
struct FileGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [FileItem]
}

/// Bucket absolute file sizes into Finder / Explorer-like bands.
enum SizeBand: String, CaseIterable, Identifiable {
    case folders     = "Folders"
    case zero        = "Zero KB"
    case tiny        = "1 KB – 100 KB"
    case small       = "100 KB – 1 MB"
    case medium      = "1 MB – 100 MB"
    case large       = "100 MB – 1 GB"
    case huge        = "Over 1 GB"

    var id: String { rawValue }

    static func of(_ item: FileItem) -> SizeBand {
        if item.isBrowsableFolder { return .folders }
        let s = item.size
        if s <= 0          { return .zero }
        if s < 100_000     { return .tiny }
        if s < 1_000_000   { return .small }
        if s < 100_000_000 { return .medium }
        if s < 1_000_000_000 { return .large }
        return .huge
    }
}

// MARK: - FileItem

struct FileItem: Identifiable, Hashable {
    let id           = UUID()
    let url:           URL
    let name:          String
    let isDirectory:   Bool
    let isPackage:     Bool      // opaque bundle (.app, .pages, …) — open, don't browse
    let isHidden:      Bool
    let size:          Int64
    let dateModified:  Date
    let dateCreated:   Date
    let kind:          String
    let fileExtension: String

    let labelNumber: Int
    let tagNames:    [String]   // macOS modern tags (multiple per file)

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
        .creationDateKey, .localizedTypeDescriptionKey, .isHiddenKey,
        .labelNumberKey, .tagNamesKey,
    ]

    /// True when double-click should navigate into this item like a normal folder.
    /// Application bundles and other opaque packages launch instead (Finder behaviour).
    var isBrowsableFolder: Bool { isDirectory && !isPackage }

    /// URL-level check used before a `FileItem` exists (navigate / open handlers).
    static func isBrowsableFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        if url.pathExtension.lowercased() == "app" { return false }
        if let v = try? url.resourceValues(forKeys: [.isPackageKey]), v.isPackage == true {
            return false
        }
        return true
    }

    static func load(from url: URL) -> FileItem? {
        guard let v = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let ext = url.pathExtension.lowercased()
        let isPkg = v.isPackage ?? (ext == "app")
        return FileItem(
            url:           url,
            name:          url.lastPathComponent,
            isDirectory:   v.isDirectory ?? false,
            isPackage:     isPkg,
            isHidden:      v.isHidden ?? false,
            size:          Int64(v.fileSize ?? 0),
            dateModified:  v.contentModificationDate ?? .distantPast,
            dateCreated:   v.creationDate ?? .distantPast,
            kind:          v.localizedTypeDescription ?? (v.isDirectory == true ? "Folder" : "File"),
            fileExtension: ext,
            labelNumber:   v.labelNumber ?? 0,
            tagNames:      v.tagNames ?? []
        )
    }

    // Icon with NSCache — safe, thread-checked, and limits RAM to ~500 entries
    var icon: NSImage {
        let key = url.path as NSString
        if let hit = FileItem.iconCache.object(forKey: key) { return hit }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)   // cap RAM per image
        FileItem.iconCache.setObject(img, forKey: key)
        return img
    }

    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        c.totalCostLimit = 16 * 1024 * 1024
        return c
    }()

    static func clearIconCache() { iconCache.removeAllObjects() }

    // Convenience
    var formattedSize: String {
        isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    var formattedDateModified: String { Self.fmt.string(from: dateModified) }
    var formattedDateCreated:  String { Self.fmt.string(from: dateCreated) }

    var dateCategory: DateCategory { DateCategory.of(dateModified) }
    var dateCreatedCategory: DateCategory { DateCategory.of(dateCreated) }

    /// First letter (A–Z) used by "Group by Name"; everything else → "#".
    var nameGroupKey: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        let s = String(first).uppercased()
        if s.range(of: "^[A-Z]$", options: .regularExpression) != nil { return s }
        return "#"
    }

    // All tag colors for this item — uses modern tagNames first (multiple colors
    // per file), falls back to the legacy labelNumber if tagNames is empty.
    var tagColors: [Color] {
        let fromNames = tagNames.compactMap { FileItem.colorForTagName($0) }
        if !fromNames.isEmpty { return fromNames }
        return FileItem.colorForLabelNumber(labelNumber).map { [$0] } ?? []
    }

    // Single-color convenience kept for backward compat.
    var tagColor: Color? { tagColors.first }

    // macOS Finder exact system tag colors (matches Tag preferences in Finder).
    static func colorForTagName(_ name: String) -> Color? {
        switch name.lowercased() {
        case "red":          return Color(red: 1.00, green: 0.23, blue: 0.19)
        case "orange":       return Color(red: 1.00, green: 0.58, blue: 0.00)
        case "yellow":       return Color(red: 1.00, green: 0.80, blue: 0.00)
        case "green":        return Color(red: 0.20, green: 0.78, blue: 0.35)
        case "blue":         return Color(red: 0.00, green: 0.48, blue: 1.00)
        case "purple":       return Color(red: 0.69, green: 0.32, blue: 0.87)
        case "gray", "grey": return Color(nsColor: .systemGray)
        default:             return nil   // custom tag with no standard color
        }
    }

    static func colorForLabelNumber(_ n: Int) -> Color? {
        switch n {
        case 1: return Color(nsColor: .systemGray)
        case 2: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case 3: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case 4: return Color(red: 0.00, green: 0.48, blue: 1.00)
        case 5: return Color(red: 1.00, green: 0.80, blue: 0.00)
        case 6: return Color(red: 1.00, green: 0.23, blue: 0.19)
        case 7: return Color(red: 1.00, green: 0.58, blue: 0.00)
        default: return nil
        }
    }

    // Standard color name → label number, mirrors macOS Finder.
    static let colorNameToLabel: [String: Int] = [
        "gray": 1, "green": 2, "purple": 3, "blue": 4,
        "yellow": 5, "red": 6, "orange": 7
    ]
    static let labelToColorName: [Int: String] = [
        1: "Gray", 2: "Green", 3: "Purple", 4: "Blue",
        5: "Yellow", 6: "Red", 7: "Orange"
    ]

    // Order the 7 standard colors are presented in the Tags menu (matches Finder).
    static let colorMenuOrder = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    // True when this item carries the given standard color tag (case-insensitive).
    func hasColorTag(_ name: String) -> Bool {
        tagNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    var isArchive: Bool {
        ["zip","tar","gz","tgz","bz2","xz","7z","rar","pkg","dmg"].contains(fileExtension)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Tag dot(s) view — matches macOS Finder's colored-circle appearance

struct TagDotsView: View {
    let colors: [Color]
    var size: CGFloat = 10

    var body: some View {
        if !colors.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .overlay(
                            Circle().strokeBorder(color.opacity(0.4), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

// MARK: - Tags submenu (shared by list / grouped / icons / columns)
//
// Renders the 7 Finder colors as toggles (a checkmark shows when EVERY targeted
// item already carries that color) plus a "Clear Tags" action. Toggling adds the
// color when absent and removes it when present — exactly like Finder, and with
// multiple colors per file preserved.

struct TagMenuContent: View {
    let targets: [FileItem]
    @ObservedObject var fileOps: FileOperationsService
    let onReload: () -> Void

    private var urls: [URL] { targets.map(\.url) }

    private func applied(_ color: String) -> Bool {
        !targets.isEmpty && targets.allSatisfy { $0.hasColorTag(color) }
    }

    var body: some View {
        ForEach(FileItem.colorMenuOrder, id: \.self) { color in
            Toggle(color, isOn: Binding(
                get: { applied(color) },
                set: { _ in fileOps.toggleColorTag(color, on: urls, reload: onReload) }
            ))
        }
        Divider()
        Button("Clear Tags") { fileOps.clearTags(on: urls, reload: onReload) }
            .disabled(targets.allSatisfy { $0.tagNames.isEmpty })
    }
}

// MARK: - Sort

enum SortField: String, CaseIterable, Identifiable {
    case name         = "Name"
    case dateModified = "Date Modified"
    case dateCreated  = "Date Created"
    case size         = "Size"
    case kind         = "Kind"
    case ext          = "Extension"
    var id: String { rawValue }
}

enum ViewMode: String, CaseIterable {
    case list, icons, columns
    var icon: String {
        switch self {
        case .list:    "list.bullet"
        case .icons:   "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        }
    }
}

func sortedItems(_ items: [FileItem],
                 by field: SortField,
                 ascending: Bool,
                 folderOrder: FolderOrder = .foldersFirst) -> [FileItem] {
    items.sorted { a, b in
        switch folderOrder {
        case .foldersFirst:
            if a.isBrowsableFolder != b.isBrowsableFolder { return a.isBrowsableFolder }
        case .filesFirst:
            if a.isBrowsableFolder != b.isBrowsableFolder { return !a.isBrowsableFolder }
        case .mixed:
            break
        }
        let r: Bool
        switch field {
        case .name:         r = a.name.localizedCompare(b.name) == .orderedAscending
        case .dateModified: r = a.dateModified < b.dateModified
        case .dateCreated:  r = a.dateCreated  < b.dateCreated
        case .size:         r = a.size < b.size
        case .kind:         r = a.kind.localizedCompare(b.kind) == .orderedAscending
        case .ext:          r = a.fileExtension.localizedCompare(b.fileExtension) == .orderedAscending
        }
        return ascending ? r : !r
    }
}

/// Split an already-sorted list into visible section groups.
func groupedItems(_ items: [FileItem], by grouping: GroupBy) -> [FileGroup] {
    guard grouping != .none, !items.isEmpty else {
        return items.isEmpty ? [] : [FileGroup(id: "all", title: "", items: items)]
    }

    switch grouping {
    case .none:
        return [FileGroup(id: "all", title: "", items: items)]

    case .dateModified:
        return DateCategory.allCases.compactMap { cat in
            let g = items.filter { $0.dateCategory == cat }
            return g.isEmpty ? nil : FileGroup(id: "dm-\(cat.rawValue)", title: cat.rawValue, items: g)
        }

    case .dateCreated:
        return DateCategory.allCases.compactMap { cat in
            let g = items.filter { $0.dateCreatedCategory == cat }
            return g.isEmpty ? nil : FileGroup(id: "dc-\(cat.rawValue)", title: cat.rawValue, items: g)
        }

    case .kind:
        // Preserve encounter order from the sorted list so relative sort holds.
        var order: [String] = []
        var buckets: [String: [FileItem]] = [:]
        for item in items {
            let key = item.kind.isEmpty ? "Unknown" : item.kind
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { FileGroup(id: "kind-\($0)", title: $0, items: buckets[$0] ?? []) }

    case .extension_:
        var order: [String] = []
        var buckets: [String: [FileItem]] = [:]
        for item in items {
            let key: String
            if item.isBrowsableFolder {
                key = "Folders"
            } else if item.fileExtension.isEmpty {
                key = "Other"
            } else {
                key = item.fileExtension.uppercased()
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { FileGroup(id: "ext-\($0)", title: $0, items: buckets[$0] ?? []) }

    case .size:
        return SizeBand.allCases.compactMap { band in
            let g = items.filter { SizeBand.of($0) == band }
            return g.isEmpty ? nil : FileGroup(id: "sz-\(band.rawValue)", title: band.rawValue, items: g)
        }

    case .nameInitial:
        let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]
        return keys.compactMap { key in
            let g = items.filter { $0.nameGroupKey == key }
            return g.isEmpty ? nil : FileGroup(id: "nm-\(key)", title: key, items: g)
        }
    }
}

func loadItems(at url: URL, showHidden: Bool) -> [FileItem] {
    let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
    let keys = FileItem.resourceKeys
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: keys, options: opts
    ) else { return [] }
    var items: [FileItem] = []
    items.reserveCapacity(urls.count)
    for child in urls {
        if let item = FileItem.load(from: child) { items.append(item) }
    }
    return items
}
