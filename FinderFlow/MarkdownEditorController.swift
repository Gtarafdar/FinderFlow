import Foundation
import AppKit
import Combine

/// Shared handle so the format toolbar can reach the live `NSTextView`.
@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoObserver: NSObjectProtocol?
    private var redoObserver: NSObjectProtocol?

    func attach(_ tv: NSTextView) {
        textView = tv
        refreshUndoState()
        let nc = NotificationCenter.default
        if let undoObserver { nc.removeObserver(undoObserver) }
        if let redoObserver { nc.removeObserver(redoObserver) }
        undoObserver = nc.addObserver(forName: .NSUndoManagerDidCloseUndoGroup, object: tv.undoManager, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshUndoState() }
        }
        redoObserver = nc.addObserver(forName: .NSUndoManagerDidUndoChange, object: tv.undoManager, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshUndoState() }
        }
        nc.addObserver(forName: .NSUndoManagerDidRedoChange, object: tv.undoManager, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshUndoState() }
        }
        nc.addObserver(forName: NSText.didChangeNotification, object: tv, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshUndoState() }
        }
    }

    func refreshUndoState() {
        canUndo = textView?.undoManager?.canUndo ?? false
        canRedo = textView?.undoManager?.canRedo ?? false
    }

    func run(_ action: (NSTextView) -> Void) {
        guard let tv = textView else { return }
        action(tv)
        refreshUndoState()
    }
}
