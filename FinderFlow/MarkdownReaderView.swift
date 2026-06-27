import SwiftUI
import WebKit

// MARK: - Wrapper so URL works with .sheet(item:)

struct MarkdownFileItem: Identifiable {
    let id  = UUID()
    let url: URL
}

// MARK: - Read / Edit mode

private enum MDMode: String, Hashable {
    case read = "Read"
    case edit = "Edit"
}

// MARK: - Full Markdown reader + editor sheet

struct MarkdownReaderView: View {
    let initialURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var navStack:   [URL]   = []
    @State private var current:    URL
    @State private var mode:       MDMode  = .read
    @State private var editText:   String  = ""
    @State private var isModified: Bool    = false
    @State private var saveFlash:  String? = nil
    @State private var refreshID:  UUID    = UUID()

    init(url: URL) {
        self.initialURL = url
        self._current   = State(initialValue: url)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 580)
        .onAppear        { loadFile() }
        .onChange(of: current) { _, _ in loadFile() }
        // Safety net: never lose edits if the sheet is dismissed another way.
        .onDisappear { if isModified { try? editText.write(to: current, atomically: true, encoding: .utf8) } }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Toolbar
    // ─────────────────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: 8) {

            // Back — only appears after the user has followed an internal .md link
            if !navStack.isEmpty {
                Button {
                    if isModified { commitSave() }
                    let prev = navStack.removeLast()
                    current  = prev
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(navStack.last?.deletingPathExtension().lastPathComponent ?? "Back")
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .help("Go back")

                Divider().frame(height: 16)
            }

            // File icon + name  (• prefix while there are unsaved changes)
            Image(systemName: "doc.text.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            Text((isModified ? "• " : "") + current.deletingPathExtension().lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Saved / Save-failed flash message
            if let flash = saveFlash {
                Text(flash)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Read / Edit segmented toggle
            Picker("", selection: $mode) {
                Text("Read").tag(MDMode.read)
                Text("Edit").tag(MDMode.edit)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .onChange(of: mode) { _, newMode in
                // Auto-save when switching back to reader so WebView shows fresh content
                if newMode == .read, isModified {
                    commitSave()
                    refreshID = UUID()
                }
            }

            // Save button — only in edit mode, enabled when dirty
            if mode == .edit {
                Button(action: commitSave) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!isModified)
                .help("Save  ⌘S")
                // Hidden button captures ⌘S keyboard shortcut
                .background(
                    Button("") { commitSave() }
                        .keyboardShortcut("s", modifiers: .command)
                        .hidden()
                )
            }

            Divider().frame(height: 16)

            // Open externally — tries real Markdown apps before falling back
            Button {
                openExternally()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open in external Markdown editor")

            Divider().frame(height: 16)

            Button("Done") { if isModified { commitSave() }; dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Content area
    // ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .read:
            MarkdownWebView(url: current, refreshID: refreshID) { dest in
                navStack.append(current)
                current = dest
            }
        case .edit:
            MarkdownEditorView(text: $editText, isModified: $isModified)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────

    private func loadFile() {
        editText = (try? String(contentsOf: current, encoding: .utf8))
                ?? (try? String(contentsOf: current, encoding: .isoLatin1))
                ?? ""
        isModified = false
    }

    private func commitSave() {
        guard isModified else { return }
        do {
            try editText.write(to: current, atomically: true, encoding: .utf8)
            isModified = false
            withAnimation(.easeOut(duration: 0.2)) { saveFlash = "Saved" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.3)) { saveFlash = nil }
            }
        } catch {
            saveFlash = "Save failed"
        }
    }

    /// Open the file in an external Markdown app — avoids Xcode by trying
    /// dedicated apps first, falling back to TextEdit (always installed).
    private func openExternally() {
        let candidates = [
            "md.obsidian",
            "abnerworks.Typora",
            "com.uranusjr.macdown",
            "net.shinyfrog.bear",
            "com.brettterpstra.marked2",
            "com.apple.TextEdit",          // guaranteed fallback
        ]
        for bundleID in candidates {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let cfg = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([current], withApplicationAt: appURL,
                                        configuration: cfg, completionHandler: nil)
                return
            }
        }
        // Last resort: let the system decide (may be Xcode on dev machines)
        NSWorkspace.shared.open(current)
    }
}

// MARK: - WKWebView representable

struct MarkdownWebView: NSViewRepresentable {
    let url:        URL
    let refreshID:  UUID          // bump to force reload of the same URL after a save
    let onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onNavigate: onNavigate) }

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero)
        wv.navigationDelegate = context.coordinator
        context.coordinator.render(url: url, refreshID: refreshID, in: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.render(url: url, refreshID: refreshID, in: wv)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: (URL) -> Void
        private var loadedURL:       URL?
        private var loadedRefreshID: UUID?

        init(onNavigate: @escaping (URL) -> Void) { self.onNavigate = onNavigate }

        func render(url: URL, refreshID: UUID, in wv: WKWebView) {
            guard url != loadedURL || refreshID != loadedRefreshID else { return }
            loadedURL       = url
            loadedRefreshID = refreshID
            let md   = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                    ?? "*Unable to read file.*"
            let html = MarkdownToHTML.render(md, title: url.deletingPathExtension().lastPathComponent)
            wv.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }

        func webView(_ wv: WKWebView, decidePolicyFor nav: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard nav.navigationType == .linkActivated,
                  let target = nav.request.url else { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if target.isFileURL && target.pathExtension.lowercased() == "md" {
                onNavigate(target)
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }
}

// MARK: - In-app Markdown editor (NSTextView-based, Obsidian-styled)

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text:       String
    @Binding var isModified: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isModified: $isModified)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.delegate                             = context.coordinator
        tv.isEditable                           = true
        tv.isRichText                           = false
        tv.allowsUndo                           = true
        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled    = false
        tv.isAutomaticLinkDetectionEnabled      = false
        tv.isContinuousSpellCheckingEnabled     = false
        tv.font                                 = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textContainerInset                   = NSSize(width: 36, height: 28)
        tv.isVerticallyResizable                = true
        tv.isHorizontallyResizable              = false
        tv.textContainer?.widthTracksTextView   = true
        tv.insertionPointColor                  = .controlAccentColor

        // Obsidian-inspired background — adapts to macOS dark / light mode
        tv.backgroundColor = Self.editorBackground()

        // Line spacing & paragraph style
        let para = NSMutableParagraphStyle()
        para.lineSpacing        = 5
        para.paragraphSpacing   = 4
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [
            .font:            NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle:  para,
        ]

        tv.string = text
        context.coordinator.textView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Only update the backing store when the text changed externally
        // (e.g. file reload after navigation) — avoids cursor/scroll reset while typing.
        guard tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        let safeLoc = min(sel.location, (text as NSString).length)
        tv.setSelectedRange(NSRange(location: safeLoc, length: 0))
    }

    /// Dynamic background: Obsidian #1e1e2e in dark mode, near-white in light mode.
    private static func editorBackground() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1)  // #1e1e2e
                : NSColor(srgbRed: 0.980, green: 0.980, blue: 0.984, alpha: 1)  // #fafafa
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text:       String
        @Binding var isModified: Bool
        weak var textView: NSTextView?

        init(text: Binding<String>, isModified: Binding<Bool>) {
            self._text       = text
            self._isModified = isModified
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text       = tv.string
            isModified = true
        }
    }
}

// MARK: - Swift Markdown → HTML renderer
// (MarkdownToHTML enum is defined below — unchanged from previous version)

enum MarkdownToHTML {

    static func render(_ markdown: String, title: String) -> String {
        htmlTemplate(title: title, body: parseBlocks(markdown))
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Block-level parser
    // ─────────────────────────────────────────────────────────────────────

    private static func parseBlocks(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var out   = ""
        var i     = 0

        while i < lines.count {
            let line = lines[i]
            let trim = line.trimmingCharacters(in: .whitespaces)

            if trim.isEmpty { i += 1; continue }

            // Fenced code block
            let fenceSeq: String? = line.hasPrefix("```") ? "```"
                                  : line.hasPrefix("~~~") ? "~~~" : nil
            if let fence = fenceSeq {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix(fence) {
                    body.append(escapeHTML(lines[i])); i += 1
                }
                if i < lines.count { i += 1 }
                let cls = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
                out += "<pre><code\(cls)>\(body.joined(separator: "\n"))</code></pre>\n"
                continue
            }

            // ATX heading
            if let (lvl, txt) = atxHeading(trim) {
                let anchor = txt.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }.joined(separator: "-")
                out += "<h\(lvl) id=\"\(anchor)\">\(parseInline(txt))</h\(lvl)>\n"
                i += 1; continue
            }

            // Horizontal rule
            if isHR(trim) { out += "<hr>\n"; i += 1; continue }

            // Blockquote
            if line.hasPrefix(">") {
                var bqLines: [String] = []
                while i < lines.count &&
                      (lines[i].hasPrefix(">") ||
                       lines[i].trimmingCharacters(in: .whitespaces).isEmpty) {
                    let l = lines[i]
                    if l.hasPrefix("> ")     { bqLines.append(String(l.dropFirst(2))) }
                    else if l.hasPrefix(">") { bqLines.append(String(l.dropFirst())) }
                    else                     { bqLines.append("") }
                    i += 1
                }
                out += "<blockquote>\(parseBlocks(bqLines.joined(separator: "\n")))</blockquote>\n"
                continue
            }

            // Unordered list
            if isULItem(line) {
                out += "<ul>\n"
                while i < lines.count && isULItem(lines[i]) {
                    out += "  <li>\(parseInline(String(lines[i].dropFirst(2))))</li>\n"; i += 1
                }
                out += "</ul>\n"; continue
            }

            // Ordered list
            if isOLItem(line) {
                out += "<ol>\n"
                while i < lines.count && isOLItem(lines[i]) {
                    let content = lines[i].replacingOccurrences(
                        of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                    out += "  <li>\(parseInline(content))</li>\n"; i += 1
                }
                out += "</ol>\n"; continue
            }

            // Table
            if trim.contains("|"), i + 1 < lines.count, isSepRow(lines[i + 1]) {
                let headers = tableRow(line); i += 2
                out += "<table>\n<thead>\n<tr>"
                for h in headers { out += "<th>\(parseInline(h))</th>" }
                out += "</tr>\n</thead>\n<tbody>\n"
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    out += "<tr>"
                    for c in tableRow(lines[i]) { out += "<td>\(parseInline(c))</td>" }
                    out += "</tr>\n"; i += 1
                }
                out += "</tbody>\n</table>\n"; continue
            }

            // Paragraph
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]; let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if atxHeading(t) != nil || isHR(t) { break }
                if l.hasPrefix("```") || l.hasPrefix("~~~") { break }
                if isULItem(l) || isOLItem(l) || l.hasPrefix(">") { break }
                if i + 1 < lines.count {
                    let nxt = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !nxt.isEmpty && nxt.allSatisfy({ $0 == "=" }) {
                        out += "<h1>\(parseInline(t))</h1>\n"; i += 2; paraLines = []; break
                    }
                    if !nxt.isEmpty && nxt.count >= 2 && nxt.allSatisfy({ $0 == "-" }) {
                        out += "<h2>\(parseInline(t))</h2>\n"; i += 2; paraLines = []; break
                    }
                }
                paraLines.append(l); i += 1
            }
            if !paraLines.isEmpty {
                let text = paraLines.map { $0.hasSuffix("  ") ? String($0.dropLast(2)) + "<br>" : $0 }
                    .joined(separator: "\n")
                out += "<p>\(parseInline(text))</p>\n"
            }
        }
        return out
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Inline formatter
    // ─────────────────────────────────────────────────────────────────────

    private static func parseInline(_ raw: String) -> String {
        var slots: [String] = []
        var s     = ""
        var idx   = raw.startIndex
        while idx < raw.endIndex {
            let ch = raw[idx]
            if ch == "`" {
                var end = raw.index(after: idx)
                while end < raw.endIndex && raw[end] != "`" { end = raw.index(after: end) }
                if end < raw.endIndex {
                    let inner = escapeHTML(String(raw[raw.index(after: idx)..<end]))
                    s += "\u{FFFE}\(slots.count)\u{FFFF}"
                    slots.append("<code>\(inner)</code>")
                    idx = raw.index(after: end); continue
                }
            }
            switch ch {
            case "&":  s += "&amp;"
            case "<":  s += "&lt;"
            case ">":  s += "&gt;"
            case "\"": s += "&quot;"
            default:   s.append(ch)
            }
            idx = raw.index(after: idx)
        }

        let rules: [(String, String)] = [
            (#"\*\*\*(.+?)\*\*\*"#,        "<strong><em>$1</em></strong>"),
            (#"___(.+?)___"#,               "<strong><em>$1</em></strong>"),
            (#"\*\*(.+?)\*\*"#,             "<strong>$1</strong>"),
            (#"__(.+?)__"#,                 "<strong>$1</strong>"),
            (#"\*([^*\n]+)\*"#,             "<em>$1</em>"),
            (#"_([^_\n]+)_"#,              "<em>$1</em>"),
            (#"~~(.+?)~~"#,                 "<del>$1</del>"),
            (#"!\[([^\]]*)\]\(([^)]+)\)"#, "<img src=\"$2\" alt=\"$1\">"),
            (#"\[([^\]]+)\]\(([^)]+)\)"#,  "<a href=\"$2\">$1</a>"),
        ]
        for (pat, tmpl) in rules {
            guard let re = try? NSRegularExpression(pattern: pat) else { continue }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: tmpl)
        }
        for (n, code) in slots.enumerated() { s = s.replacingOccurrences(of: "\u{FFFE}\(n)\u{FFFF}", with: code) }
        return s
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────

    private static func atxHeading(_ s: String) -> (Int, String)? {
        var lvl = 0
        for c in s { if c == "#" { lvl += 1 } else { break } }
        guard lvl >= 1, lvl <= 6 else { return nil }
        let rest = String(s.dropFirst(lvl)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (lvl, rest)
    }
    private static func isHR(_ s: String) -> Bool {
        let c = s.filter { !$0.isWhitespace }
        guard c.count >= 3, let ch = c.first else { return false }
        return (ch == "-" || ch == "*" || ch == "_") && c.allSatisfy { $0 == ch }
    }
    private static func isULItem(_ l: String) -> Bool { l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("+ ") }
    private static func isOLItem(_ l: String) -> Bool { l.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil }
    private static func isSepRow(_ l: String) -> Bool {
        let s = l.trimmingCharacters(in: .whitespaces)
        return s.contains("|") && s.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }
    private static func tableRow(_ l: String) -> [String] {
        var s = l.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: HTML template  (Obsidian-inspired dark/light)
    // ─────────────────────────────────────────────────────────────────────

    private static func htmlTemplate(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

        :root {
            --bg:      #ffffff;
            --surface: #f6f8fa;
            --border:  #d0d7de;
            --text:    #1f2328;
            --muted:   #57606a;
            --accent:  #0969da;
            --code-fg: #0550ae;
            --code-bg: #f0f2f5;
            --pre-bg:  #f6f8fa;
            --bq-bar:  #0969da;
            --bq-bg:   #ddf4ff;
            --th-bg:   #f0f2f5;
            --del-fg:  #cf222e;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg:      #1e1e2e;
                --surface: #181825;
                --border:  #45475a;
                --text:    #cdd6f4;
                --muted:   #a6adc8;
                --accent:  #89b4fa;
                --code-fg: #a6e3a1;
                --code-bg: #313244;
                --pre-bg:  #181825;
                --bq-bar:  #89b4fa;
                --bq-bg:   rgba(137,180,250,0.08);
                --th-bg:   #181825;
                --del-fg:  #f38ba8;
            }
        }

        html, body { background: var(--bg); color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 16px; line-height: 1.75; }
        body { max-width: 820px; margin: 0 auto; padding: 36px 36px 80px; }
        ::selection { background: rgba(137,180,250,0.35); }

        h1,h2,h3,h4,h5,h6 { font-weight: 650; line-height: 1.3; margin: 1.6em 0 0.5em; }
        h1:first-child,h2:first-child { margin-top: 0; }
        h1 { font-size:2em;   border-bottom: 2px solid var(--border); padding-bottom:.3em; }
        h2 { font-size:1.5em; border-bottom: 1px solid var(--border); padding-bottom:.2em; }
        h3 { font-size:1.25em; } h4 { font-size:1.05em; }
        h5 { font-size:.95em; } h6 { font-size:.875em; color:var(--muted); }

        p { margin:.75em 0; }
        a { color:var(--accent); text-decoration:none; } a:hover { text-decoration:underline; }
        strong { font-weight:700; } em { font-style:italic; }
        del { color:var(--del-fg); text-decoration:line-through; }

        code { font-family:"SF Mono",ui-monospace,"Cascadia Code",Consolas,monospace;
               font-size:.85em; background:var(--code-bg); color:var(--code-fg);
               padding:.15em .4em; border-radius:4px; border:1px solid var(--border); }
        pre { background:var(--pre-bg); border:1px solid var(--border); border-radius:8px;
              padding:18px 20px; overflow-x:auto; margin:1.1em 0; }
        pre code { background:transparent; border:none; padding:0; color:var(--text);
                   font-size:.875em; line-height:1.65; }

        blockquote { border-left:4px solid var(--bq-bar); background:var(--bq-bg);
                     margin:1em 0; padding:10px 18px; border-radius:0 8px 8px 0; }
        blockquote p { margin:0; color:var(--muted); }

        ul,ol { padding-left:1.8em; margin:.75em 0; } li { margin:.3em 0; }
        li > ul, li > ol { margin:.2em 0; }
        hr { border:none; border-top:1px solid var(--border); margin:2em 0; }

        table { border-collapse:collapse; width:100%; margin:1em 0; font-size:.9em;
                display:block; overflow-x:auto; }
        th,td { border:1px solid var(--border); padding:8px 14px; text-align:left; }
        th { background:var(--th-bg); font-weight:650; white-space:nowrap; }
        tr:nth-child(even) td { background:var(--surface); }

        img { max-width:100%; height:auto; border-radius:8px; margin:.5em 0; display:block; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
