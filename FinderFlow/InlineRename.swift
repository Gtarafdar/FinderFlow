import SwiftUI
import AppKit

// MARK: - Inline edit target (Finder-style create & rename)

/// What an inline text field is editing. Finder creates a new folder/file
/// immediately and then lets you type its name in place — cancelling (Esc)
/// with a *new* item deletes the item, while cancelling a plain rename just
/// restores the original name.
enum InlineEditKind: Equatable {
    case rename     // existing item — Esc restores the name
    case newFolder  // just-created folder — Esc deletes it
    case newFile    // just-created file — Esc deletes it
}

struct InlineEditTarget: Equatable {
    let kind: InlineEditKind
    let url: URL
}

// MARK: - Finder rename name rules

/// Initial selection when an inline edit begins: the name WITHOUT its
/// extension, exactly like Finder (renaming "notes.txt" starts with "notes"
/// selected and ".txt" left behind). Returns nil when the whole name should
/// be selected (no extension, or a dot-file like ".zshrc" which has no stem).
func inlineEditSelectionRange(for name: String) -> NSRange? {
    let ext = (name as NSString).pathExtension
    guard !ext.isEmpty else { return nil }
    let stem = (name as NSString).deletingPathExtension
    guard !stem.isEmpty else { return nil }
    return NSRange(location: 0, length: (stem as NSString).length)
}

/// Finder re-appends the original extension when you rename "notes.txt" to
/// "notes2" — the result is "notes2.txt". A name the user types that already
/// carries its own extension ("notes2.md") is kept as-is.
func committedRenameName(_ typed: String, original: String) -> String {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    // A name made only of dots (".", "..") is not a usable name.
    guard !trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty else { return "" }
    let ext = (original as NSString).pathExtension
    guard !ext.isEmpty, (trimmed as NSString).pathExtension.isEmpty else { return trimmed }
    return trimmed + "." + ext
}

// MARK: - The inline rename field

/// A borderless NSTextField that mimics Finder's in-place rename field:
/// focus + stem pre-selection on appear, Enter commits, Esc cancels, and
/// committing when the field loses focus (clicking elsewhere) — the same way
/// Finder commits a rename when you click away.
struct RenameField: NSViewRepresentable {
    let initialValue: String
    let initialSelection: NSRange?   // nil → select everything
    let font: NSFont
    let textColor: NSColor
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = _RenameTextField()
        tf.isBezeled      = false
        tf.isBordered     = false
        tf.drawsBackground = false
        tf.focusRingType  = .none
        tf.font           = font
        tf.textColor      = textColor
        tf.isEditable     = true
        tf.isSelectable   = true
        tf.cell?.isScrollable = true
        tf.lineBreakMode  = .byTruncatingTail
        tf.stringValue    = initialValue
        tf.delegate      = context.coordinator
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    /// Takes focus as soon as it is placed in a window (a one-shot async hop in
    /// makeNSView can fire before the view is in its window).
    private final class _RenameTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        /// Set once the user commits/cancels explicitly (Enter/Esc) so the
        /// resign-editor notification that follows doesn't double-fire.
        private var handled = false

        init(_ parent: RenameField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: NSText) {
            // `obj` is the field editor (an NSTextView) while editing.
            guard let editor = obj as? NSTextView else { return }
            let range = parent.initialSelection
                ?? NSRange(location: 0, length: editor.string.count)
            editor.setSelectedRange(range)
        }

        func control(_ obj: NSControl, textView: NSText, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                handled = true
                parent.onCommit((obj as? NSTextField)?.stringValue ?? "")
            case #selector(NSResponder.cancelOperation(_:)):
                handled = true
                parent.onCancel()
            default:
                return false
            }
            return true
        }

        func controlTextDidEndEditing(_ obj: NSTextField) {
            guard !handled else { return }
            parent.onCommit(obj.stringValue)
        }
    }
}
