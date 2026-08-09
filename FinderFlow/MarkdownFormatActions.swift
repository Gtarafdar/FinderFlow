import AppKit

/// Real markdown source formatting helpers that mutate an `NSTextView` through
/// AppKit APIs so Undo/Redo stay on the native `NSUndoManager`.
enum MarkdownFormatActions {

    // MARK: - Undo / Redo

    static func undo(_ tv: NSTextView) {
        tv.window?.makeFirstResponder(tv)
        tv.undoManager?.undo()
    }

    static func redo(_ tv: NSTextView) {
        tv.window?.makeFirstResponder(tv)
        tv.undoManager?.redo()
    }

    static func canUndo(_ tv: NSTextView?) -> Bool { tv?.undoManager?.canUndo ?? false }
    static func canRedo(_ tv: NSTextView?) -> Bool { tv?.undoManager?.canRedo ?? false }

    // MARK: - Inline wrap

    static func bold(_ tv: NSTextView)          { wrap(tv, left: "**", right: "**") }
    static func italic(_ tv: NSTextView)        { wrap(tv, left: "*", right: "*") }
    static func strikethrough(_ tv: NSTextView) { wrap(tv, left: "~~", right: "~~") }
    static func inlineCode(_ tv: NSTextView)    { wrap(tv, left: "`", right: "`") }

    static func link(_ tv: NSTextView, url: String = "https://") {
        let sel = tv.selectedRange()
        let ns  = tv.string as NSString
        let selected = sel.length > 0 ? ns.substring(with: sel) : "link text"
        let replacement = "[\(selected)](\(url))"
        replace(tv, range: sel, with: replacement)
        // Select the URL so the user can type over it
        let urlStart = sel.location + selected.count + 3
        tv.setSelectedRange(NSRange(location: urlStart, length: (url as NSString).length))
    }

    static func codeFence(_ tv: NSTextView) {
        let sel = tv.selectedRange()
        let ns  = tv.string as NSString
        let selected = sel.length > 0 ? ns.substring(with: sel) : ""
        let body = selected.isEmpty ? "\n\n" : "\n\(selected)\n"
        let replacement = "```\(body)```"
        replace(tv, range: sel, with: replacement)
        if selected.isEmpty {
            tv.setSelectedRange(NSRange(location: sel.location + 4, length: 0))
        }
    }

    static func horizontalRule(_ tv: NSTextView) {
        let sel = tv.selectedRange()
        let ns  = tv.string as NSString
        let beforeNeedsNL = sel.location > 0 && ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n"
        let afterNeedsNL: Bool = {
            let end = sel.location + sel.length
            guard end < ns.length else { return true }
            return ns.substring(with: NSRange(location: end, length: 1)) != "\n"
        }()
        var piece = "---"
        if beforeNeedsNL { piece = "\n" + piece }
        if afterNeedsNL  { piece = piece + "\n" }
        replace(tv, range: sel, with: piece)
    }

    // MARK: - Line prefixes

    static func heading(_ tv: NSTextView, level: Int) {
        let hashes = String(repeating: "#", count: max(1, min(6, level))) + " "
        toggleLinePrefix(tv, prefixesToStrip: (1...6).map { String(repeating: "#", count: $0) + " " },
                         apply: hashes)
    }

    static func bulletList(_ tv: NSTextView) {
        toggleLinePrefix(tv, prefixesToStrip: ["- ", "* ", "+ "], apply: "- ")
    }

    static func numberedList(_ tv: NSTextView) {
        toggleLinePrefix(tv, prefixesToStrip: [], apply: "1. ",
                         alsoStripRegex: #"^\d+\.\s+"#)
    }

    static func quote(_ tv: NSTextView) {
        toggleLinePrefix(tv, prefixesToStrip: ["> "], apply: "> ")
    }

    // MARK: - Core

    private static func wrap(_ tv: NSTextView, left: String, right: String) {
        let sel = tv.selectedRange()
        let ns  = tv.string as NSString
        let selected = ns.substring(with: sel)
        // Toggle off if already wrapped
        if sel.length >= left.count + right.count {
            let full = selected
            if full.hasPrefix(left), full.hasSuffix(right) {
                let inner = String(full.dropFirst(left.count).dropLast(right.count))
                replace(tv, range: sel, with: inner)
                return
            }
        }
        let replacement = left + selected + right
        replace(tv, range: sel, with: replacement)
        if selected.isEmpty {
            tv.setSelectedRange(NSRange(location: sel.location + left.count, length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: sel.location, length: (replacement as NSString).length))
        }
    }

    private static func toggleLinePrefix(_ tv: NSTextView,
                                        prefixesToStrip: [String],
                                        apply: String,
                                        alsoStripRegex: String? = nil) {
        tv.undoManager?.beginUndoGrouping()
        defer { tv.undoManager?.endUndoGrouping() }

        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: sel)
        if sel.length == 0 {
            lineEnd = contentsEnd
        } else {
            // Extend to cover full lines of the selection
            let endLoc = max(sel.location + sel.length - 1, sel.location)
            var endLineStart = 0, endLineEnd = 0, endContents = 0
            ns.getLineStart(&endLineStart, end: &endLineEnd, contentsEnd: &endContents,
                            for: NSRange(location: endLoc, length: 0))
            lineEnd = endContents
        }

        let blockRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        let block = ns.substring(with: blockRange)
        let lines = block.components(separatedBy: "\n")

        let allHave: Bool = lines.allSatisfy { line in
            if line.isEmpty { return true }
            if prefixesToStrip.contains(where: { line.hasPrefix($0) }) { return true }
            if apply == "1. ", line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil { return true }
            if alsoStripRegex != nil, line.range(of: alsoStripRegex!, options: .regularExpression) != nil { return true }
            return line.hasPrefix(apply)
        }

        var rebuilt: [String] = []
        for (i, line) in lines.enumerated() {
            if line.isEmpty { rebuilt.append(line); continue }
            var working = line
            for p in prefixesToStrip where working.hasPrefix(p) {
                working = String(working.dropFirst(p.count))
            }
            if let rx = alsoStripRegex,
               let range = working.range(of: rx, options: .regularExpression) {
                working.removeSubrange(range)
            }
            if apply == "1. ",
               let range = working.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                working.removeSubrange(range)
            }
            if allHave && line.hasPrefix(apply) {
                // already stripped above when apply matches
                rebuilt.append(working)
            } else if allHave {
                rebuilt.append(working)
            } else {
                let prefix = apply == "1. " ? "\(i + 1). " : apply
                rebuilt.append(prefix + working)
            }
        }

        replace(tv, range: blockRange, with: rebuilt.joined(separator: "\n"))
    }

    private static func replace(_ tv: NSTextView, range: NSRange, with string: String) {
        tv.window?.makeFirstResponder(tv)
        guard tv.shouldChangeText(in: range, replacementString: string) else { return }
        tv.replaceCharacters(in: range, with: string)
        tv.didChangeText()
    }
}
