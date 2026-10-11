import XCTest

final class RenameNameTests: XCTestCase {

    // MARK: - Initial selection (stem selected, extension not — Finder style)

    func testSelectionIsStemWithoutExtension() {
        XCTAssertEqual(inlineEditSelectionRange(for: "notes.txt"), NSRange(location: 0, length: 5))
    }

    func testSelectionIsWholeNameWhenNoExtension() {
        XCTAssertNil(inlineEditSelectionRange(for: "New Folder"))
    }

    func testSelectionIsWholeNameForDotFile() {
        // ".zshrc" has no visible stem — Finder selects the entire name.
        XCTAssertNil(inlineEditSelectionRange(for: ".zshrc"))
    }

    func testSelectionStopsAtLastDot() {
        // "archive.tar.gz" → stem is "archive.tar" (extension is "gz").
        XCTAssertEqual(inlineEditSelectionRange(for: "archive.tar.gz"), NSRange(location: 0, length: 11))
    }

    // MARK: - Commit rules (Finder re-appends the original extension)

    func testCommitReappendsOriginalExtension() {
        XCTAssertEqual(committedRenameName("notes2", original: "notes.txt"), "notes2.txt")
    }

    func testCommitKeepsNewExtension() {
        XCTAssertEqual(committedRenameName("notes2.md", original: "notes.txt"), "notes2.md")
    }

    func testCommitWithoutExtensionLeavesNameAlone() {
        XCTAssertEqual(committedRenameName("notes2", original: "notes"), "notes2")
    }

    func testCommitKeepsMultiDotExtensionShortened() {
        XCTAssertEqual(committedRenameName("archive2", original: "archive.tar.gz"), "archive2.gz")
    }

    func testCommitTrimsWhitespace() {
        XCTAssertEqual(committedRenameName("  notes2  ", original: "notes.txt"), "notes2.txt")
    }

    func testCommitEmptyNameYieldsEmpty() {
        XCTAssertEqual(committedRenameName("   ", original: "notes.txt"), "")
    }

    func testCommitDotsOnlyYieldsEmpty() {
        XCTAssertEqual(committedRenameName("...", original: "notes.txt"), "")
    }

    func testCommitDotFileStaysDotFile() {
        XCTAssertEqual(committedRenameName(".hidden2", original: ".hidden"), ".hidden2")
    }
}
