import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

// MARK: - Text/binary detection + editor eligibility

enum TextFileDetector {

    /// Extensions we always treat as editable text (fast path, no disk sniff).
    static let knownTextExtensions: Set<String> = [
        "txt","text","log","md","markdown","mdown","rtf",
        "json","json5","jsonc","yaml","yml","toml","ini","conf","cfg","properties","env",
        "xml","plist","svg","html","htm","xhtml","css","scss","sass","less",
        "js","jsx","mjs","cjs","ts","tsx","swift","m","mm","h","hpp","c","cc","cpp","cxx",
        "java","kt","kts","go","rs","rb","php","py","pyw","pl","pm","lua","r","dart","scala",
        "sh","bash","zsh","fish","ps1","bat","cmd","sql","graphql","gql",
        "vue","svelte","astro","tex","bib","csv","tsv","diff","patch","gitignore",
        "gitattributes","editorconfig","dockerfile","makefile","mk","cmake","gradle",
        "asm","s","vim","el","clj","ex","exs","erl","hs","ml","fs","groovy","nim","zig"
    ]

    /// Filenames (no extension) commonly used for text/config files.
    static let knownTextFilenames: Set<String> = [
        "makefile","dockerfile","readme","license","changelog","authors",
        ".gitignore",".gitattributes",".editorconfig",".env",".zshrc",".bashrc",".bash_profile",
        ".profile",".vimrc","podfile","gemfile","rakefile",".npmrc",".prettierrc",".eslintrc"
    ]

    /// When true (default), unknown file types are sniffed and opened in the editor
    /// if they look like text. When false, only known text types open in the editor.
    static var sniffUnknown: Bool {
        UserDefaults.standard.object(forKey: "ffEditorSniffUnknown") as? Bool ?? true
    }

    /// Decide whether a file should open in the in-app code editor.
    static func isEditableText(_ url: URL) -> Bool {
        let ext  = url.pathExtension.lowercased()
        if !ext.isEmpty && knownTextExtensions.contains(ext) { return true }
        let name = url.lastPathComponent.lowercased()
        if knownTextFilenames.contains(name) { return true }
        guard sniffUnknown else { return false }
        return sniffIsText(url)
    }

    private static func sniffIsText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8192)
        if data.isEmpty { return true }
        if data.contains(0) { return false }
        if String(data: data, encoding: .utf8) != nil { return true }
        if String(data: data, encoding: .isoLatin1) != nil { return true }
        return false
    }
}

// MARK: - Open document model

struct OpenDoc: Identifiable, Equatable {
    let id: String
    let url: URL
    var modified: Bool = false
}

// MARK: - Standalone editor window manager (real macOS window, non-blocking)

@MainActor
final class EditorWindowManager: NSObject, NSWindowDelegate {
    static let shared = EditorWindowManager()

    private var window: NSWindow?
    private var controller: AceEditorController?

    /// Open a file in the editor window — creating the window on first use,
    /// otherwise adding the file as a new tab in the existing window.
    func open(_ url: URL) {
        if let controller, let window {
            controller.open(urls: [url])
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = AceEditorController(urls: [url])
        self.controller = controller

        let hosting = NSHostingController(rootView: CodeEditorView(controller: controller))
        let window  = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = url.lastPathComponent
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("FinderFlowEditorWindow")
        self.window = window

        controller.onTitleChange = { [weak window] title in window?.title = title }
        controller.onRequestClose = { [weak self] in self?.window?.performClose(nil) }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        controller = nil
        window = nil
    }
}

// MARK: - Controller bridging WKWebView (Ace) and SwiftUI

final class AceEditorController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {

    let webView: WKWebView

    @Published var docs: [OpenDoc] = []
    @Published var activeID: String?
    @Published var statusFlash: String?
    @Published var isReady = false

    /// Callbacks owned by the window manager.
    var onTitleChange: ((String) -> Void)?
    var onRequestClose: (() -> Void)?

    // Mirrored from @AppStorage by the view.
    var wrap        = false
    var fontSize    = 14
    var sublimeKeys = false
    var minimapOn   = true

    private var pendingURLs: [URL]
    private let handlerName = "bridge"

    init(urls: [URL]) {
        self.pendingURLs = urls

        let config = WKWebViewConfiguration()
        let ucc    = WKUserContentController()
        config.userContentController = ucc
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        ucc.add(WeakScriptMessageProxy(self), name: handlerName)
        webView.navigationDelegate = self

        if let html = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "AceEditor") {
            webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    var activeDoc: OpenDoc? { docs.first { $0.id == activeID } }

    private var currentTitle: String {
        guard let d = activeDoc else { return "Editor" }
        return (d.modified ? "• " : "") + d.url.lastPathComponent
    }

    private func notifyTitle() { onTitleChange?(currentTitle) }

    private var themeForAppearance: String {
        let dark = webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? "ace/theme/monokai" : "ace/theme/github"
    }

    // MARK: JS → Swift

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any] ?? [:]
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let queued = pendingURLs
            pendingURLs = []
            for url in queued { openOne(url) }
        case "changed":
            if let id = body["id"] as? String { setModified(id, true) }
        case "save":
            if let id = body["id"] as? String {
                write(id: id, content: body["content"] as? String ?? "")
            }
        case "open":
            presentOpenPanel()
        case "closeTab":
            if let id = body["id"] as? String { closeTab(id) }
        case "minimap":
            if let on = body["on"] as? Bool {
                minimapOn = on
                UserDefaults.standard.set(on, forKey: "ffEditorMinimap")
            }
        default:
            break
        }
    }

    // MARK: Tabs

    func open(urls: [URL]) {
        guard isReady else { pendingURLs.append(contentsOf: urls); return }
        for url in urls { openOne(url) }
    }

    private func openOne(_ url: URL) {
        if let existing = docs.first(where: { $0.url == url }) {
            switchTo(existing.id)
            return
        }
        let id = UUID().uuidString
        let content = readFile(url)
        docs.append(OpenDoc(id: id, url: url))
        activeID = id
        let enc = JSONEncoder()
        guard let textJSON = String(data: (try? enc.encode(content)) ?? Data(), encoding: .utf8),
              let nameJSON = String(data: (try? enc.encode(url.lastPathComponent)) ?? Data(), encoding: .utf8)
        else { return }
        let keymap = sublimeKeys ? "\"ace/keyboard/sublime\"" : "null"
        let js = "FF.openDoc(\"\(id)\", \(textJSON), \(nameJSON), \"\(themeForAppearance)\", \(wrap), \(keymap), \(fontSize));"
        run(js)
        run("FF.setMinimap(\(minimapOn));")
        notifyTitle()
    }

    func switchTo(_ id: String) {
        activeID = id
        run("FF.switchDoc(\"\(id)\");")
        notifyTitle()
    }

    func closeTab(_ id: String) {
        run("FF.closeDoc(\"\(id)\");")
        docs.removeAll { $0.id == id }
        if activeID == id { activeID = docs.last?.id }
        if let a = activeID { run("FF.switchDoc(\"\(a)\");") }
        if docs.isEmpty { onRequestClose?() } else { notifyTitle() }
    }

    // MARK: Save

    func saveActive() {
        guard let id = activeID else { return }
        webView.evaluateJavaScript("FF.getDocContent(\"\(id)\");") { [weak self] result, _ in
            self?.write(id: id, content: result as? String ?? "")
        }
    }

    private func write(id: String, content: String) {
        guard let doc = docs.first(where: { $0.id == id }) else { return }
        do {
            try content.write(to: doc.url, atomically: true, encoding: .utf8)
            setModified(id, false)
            flash("Saved \(doc.url.lastPathComponent)")
        } catch {
            flash("Save failed")
        }
    }

    private func setModified(_ id: String, _ value: Bool) {
        guard let idx = docs.firstIndex(where: { $0.id == id }), docs[idx].modified != value else { return }
        docs[idx].modified = value
        notifyTitle()
    }

    // MARK: Open panel

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let editable = panel.urls.filter { TextFileDetector.isEditableText($0) }
            if !editable.isEmpty { self.open(urls: editable) }
        }
    }

    // MARK: Editor commands (toolbar)

    func setMinimap(_ on: Bool) { minimapOn = on; run("FF.setMinimap(\(on));") }
    func toggleWrap()        { wrap.toggle(); run("FF.setWrapAll(\(wrap));") }
    func setFontSize(_ n: Int) { fontSize = max(8, min(36, n)); run("FF.setFontSize(\(fontSize));") }
    func toggleSublime()     { sublimeKeys.toggle(); run("FF.setKeymap(\(sublimeKeys ? "\"ace/keyboard/sublime\"" : "null"));") }
    func find()              { run("FF.find();") }
    func gotoLine()          { run("FF.gotoLine();") }
    func palette()           { run("FF.palette();") }
    func settings()          { run("FF.settings();") }

    private func run(_ js: String) { webView.evaluateJavaScript(js, completionHandler: nil) }

    private func readFile(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            ?? ""
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { statusFlash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.statusFlash = nil }
        }
    }
}

/// Breaks the retain cycle WKUserContentController → handler → controller.
private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(uc, didReceive: message)
    }
}

// MARK: - NSViewRepresentable host

private struct AceWebView: NSViewRepresentable {
    let controller: AceEditorController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Editor view (hosted inside the standalone window)

struct CodeEditorView: View {
    @ObservedObject var ctrl: AceEditorController

    @AppStorage("ffEditorWrap")        private var wrap        = false
    @AppStorage("ffEditorFontSize")    private var fontSize    = 14
    @AppStorage("ffEditorSublimeKeys") private var sublimeKeys = false
    @AppStorage("ffEditorMinimap")     private var minimap     = true

    init(controller: AceEditorController) { self.ctrl = controller }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if ctrl.docs.count > 1 { tabBar; Divider() }
            AceWebView(controller: ctrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            ctrl.wrap        = wrap
            ctrl.fontSize    = fontSize
            ctrl.sublimeKeys = sublimeKeys
            ctrl.minimapOn   = minimap
        }
        .background(
            Button("") { ctrl.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        )
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            if let flash = ctrl.statusFlash {
                Text(flash).font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }

            Spacer(minLength: 0)

            Button { ctrl.palette() } label: { Image(systemName: "command") }
                .buttonStyle(.borderless).help("Command Palette  ⌘⇧P")
            Button { ctrl.find() } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Find / Replace  ⌘F")
            Button { ctrl.gotoLine() } label: { Image(systemName: "arrow.right.to.line") }
                .buttonStyle(.borderless).help("Go to Line  ⌘L")
            Button { ctrl.presentOpenPanel() } label: { Image(systemName: "doc.badge.plus") }
                .buttonStyle(.borderless).help("Open File in New Tab  ⌘O")
            Button { ctrl.toggleWrap(); wrap = ctrl.wrap } label: {
                Image(systemName: wrap ? "text.alignleft" : "text.append")
            }
            .buttonStyle(.borderless).help(wrap ? "Wrap: on" : "Wrap: off")

            Button { minimap.toggle(); ctrl.setMinimap(minimap) } label: {
                Image(systemName: minimap ? "rectangle.righthalf.inset.filled" : "rectangle.righthalf.inset.filled")
                    .foregroundStyle(minimap ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless).help(minimap ? "Minimap: on  ⌘⇧M" : "Minimap: off  ⌘⇧M")

            Menu {
                Button("Settings…")     { ctrl.settings() }
                Divider()
                Button("Increase Font") { ctrl.setFontSize(fontSize + 1); fontSize = ctrl.fontSize }
                Button("Decrease Font") { ctrl.setFontSize(fontSize - 1); fontSize = ctrl.fontSize }
                Divider()
                Toggle("Sublime Keybindings", isOn: Binding(
                    get: { sublimeKeys },
                    set: { _ in ctrl.toggleSublime(); sublimeKeys = ctrl.sublimeKeys }
                ))
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton).frame(width: 34).help("Editor options")

            Button(action: { ctrl.saveActive() }) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(ctrl.activeDoc?.modified != true)
            .help("Save  ⌘S")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(ctrl.docs) { doc in
                    tabChip(doc)
                    Divider().frame(height: 22)
                }
            }
        }
        .background(.bar)
    }

    private func tabChip(_ doc: OpenDoc) -> some View {
        let isActive = doc.id == ctrl.activeID
        return HStack(spacing: 6) {
            Text((doc.modified ? "• " : "") + doc.url.lastPathComponent)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Button { ctrl.closeTab(doc.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Close Tab  ⌘W")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { ctrl.switchTo(doc.id) }
    }
}
