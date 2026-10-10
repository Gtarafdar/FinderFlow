import Foundation

// MARK: - Compress

/// Arguments for `/usr/bin/zip`. macOS zip requires the archive path before `--`.
/// `--` then ends options so a file name is never read as a flag.
/// `-y` stores symlinks instead of following them. Returns nil when a name cannot be passed safely.
func zipArguments(archivePath: String, names: [String]) -> [String]? {
    guard !archivePath.isEmpty, !names.isEmpty else { return nil }
    guard names.allSatisfy(zipEntryNameIsSafe) else { return nil }
    return ["-r", "-y", archivePath, "--"] + names
}

func zipEntryNameIsSafe(_ name: String) -> Bool {
    if name.isEmpty || name == "." || name == ".." { return false }
    if name.contains("/") || name.contains("\\") { return false }
    if name.unicodeScalars.contains(where: { $0.value < 32 }) { return false }
    return true
}

// MARK: - Extract

/// Archive member paths that would escape the destination, or that are empty, are rejected.
func archiveEntryIsSafe(_ entry: String) -> Bool {
    var raw = entry
    while raw.hasSuffix("/") { raw.removeLast() }
    if raw.isEmpty { return false }
    if raw.hasPrefix("/") || raw.hasPrefix("\\") { return false }
    if raw.contains("\\") { return false }
    if raw.unicodeScalars.contains(where: { $0.value < 32 }) { return false }
    let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
    if parts.isEmpty { return false }
    for part in parts {
        if part.isEmpty || part == "." || part == ".." { return false }
    }
    return true
}

/// First path component of each archive member — the names that land in the destination folder.
func archiveTopLevelNames(_ entries: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for entry in entries where archiveEntryIsSafe(entry) {
        var raw = entry
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let first = raw.split(separator: "/").first else { continue }
        let name = String(first)
        if seen.insert(name).inserted { ordered.append(name) }
    }
    return ordered
}

/// True when a symlink's resolved target sits outside `root`.
func symlinkEscapesRoot(_ link: URL, root: URL) -> Bool {
    let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    let targetPath = link.resolvingSymlinksInPath().standardizedFileURL.path
    if targetPath == rootPath { return false }
    return !targetPath.hasPrefix(rootPath + "/")
}

// MARK: - finderflow:// links

enum ExternalOpenSource: Equatable {
    case fileURL
    case finderFlowLink
}

struct ExternalOpenFacts: Equatable {
    var isDirectory: Bool
    var isBrowsableFolder: Bool
    var isMarkdown: Bool
    var isEditableText: Bool
}

enum ExternalOpenDecision: Equatable {
    case navigate(path: String)
    case launchPackage(path: String)
    case openMarkdown(path: String)
    case openText(path: String)
    case revealParent(path: String)
    case ignore
}

/// Web-triggered `finderflow://` links may only navigate into a normal folder.
/// File URLs (Open With, `open -a`) keep the existing document behavior.
func externalOpenDecision(source: ExternalOpenSource, path: String, facts: ExternalOpenFacts) -> ExternalOpenDecision {
    guard !path.isEmpty else { return .ignore }
    switch source {
    case .finderFlowLink:
        if facts.isDirectory && facts.isBrowsableFolder {
            return .navigate(path: path)
        }
        return .ignore
    case .fileURL:
        if facts.isDirectory && facts.isBrowsableFolder {
            return .navigate(path: path)
        }
        if facts.isDirectory {
            return .launchPackage(path: path)
        }
        if facts.isMarkdown {
            return .openMarkdown(path: path)
        }
        if facts.isEditableText {
            return .openText(path: path)
        }
        return .revealParent(path: path)
    }
}
