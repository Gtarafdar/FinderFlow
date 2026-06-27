import SwiftUI

struct StatusBarView: View {
    let files: [FileItem]
    let selectedIDs: Set<UUID>
    let currentPath: URL

    var body: some View {
        HStack(spacing: 16) {
            Text(itemCountText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !selectedIDs.isEmpty {
                Text(selectionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let free = freeDiskSpace {
                Text("\(free) available")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var itemCountText: String {
        "\(files.count) \(files.count == 1 ? "item" : "items")"
    }

    private var selectionText: String {
        let sel = files.filter { selectedIDs.contains($0.id) }
        let totalBytes = sel.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
        let countStr = "\(sel.count) selected"
        guard totalBytes > 0 else { return countStr }
        return "\(countStr) — \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }

    private var freeDiskSpace: String? {
        guard let v = try? currentPath.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = v.volumeAvailableCapacity else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
