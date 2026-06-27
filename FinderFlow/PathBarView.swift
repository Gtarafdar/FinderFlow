import SwiftUI
import AppKit

struct PathBarView: View {
    @Binding var currentPath: URL
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.caption)

            if isEditing {
                TextField("Path", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .resetsCursorOnExit()
                    .onSubmit { commitEdit() }
                    .onExitCommand { isEditing = false }
            } else {
                breadcrumbs
            }

            Spacer()

            Button { copyPathToClipboard() } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Copy full path")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(pathComponents, id: \.path) { component in
                    Button {
                        currentPath = component
                    } label: {
                        Text(component.lastPathComponent.isEmpty ? "/" : component.lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundStyle(component == currentPath ? .primary : .secondary)
                    }
                    .buttonStyle(.borderless)

                    if component != pathComponents.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onTapGesture(count: 2) {
            editText = currentPath.path
            isEditing = true
        }
    }

    private var pathComponents: [URL] {
        var components: [URL] = []
        var url = currentPath
        components.append(url)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            components.insert(url, at: 0)
        }
        return components
    }

    private func commitEdit() {
        let expanded = NSString(string: editText).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            currentPath = url
        }
        isEditing = false
    }

    private func copyPathToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentPath.path, forType: .string)
        // Fire the same feedback notification the toolbar / context-menu "Copy Path"
        // actions use, so this button shows the "Path copied" toast too.
        NotificationCenter.default.post(name: .ffCopyPathFeedback, object: nil)
    }
}
