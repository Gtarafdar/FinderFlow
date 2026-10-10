import XCTest

final class ArchiveSecurityTests: XCTestCase {

    func testZipArgumentsEndOptionsBeforeNames() {
        let names = ["Notes", "-draft", "Photos"]
        let args = zipArguments(archivePath: "/tmp/Archive.zip", names: names)
        XCTAssertEqual(args, ["-r", "-y", "/tmp/Archive.zip", "--", "Notes", "-draft", "Photos"])
    }

    func testZipRejectsNewlinesAndPathSeparators() {
        XCTAssertNil(zipArguments(archivePath: "/tmp/Archive.zip", names: ["ok", "bad\nname"]))
        XCTAssertNil(zipArguments(archivePath: "/tmp/Archive.zip", names: ["nested/name"]))
        XCTAssertNil(zipArguments(archivePath: "/tmp/Archive.zip", names: [".."]))
        XCTAssertNil(zipArguments(archivePath: "/tmp/Archive.zip", names: []))
    }

    func testArchiveEntriesRejectEscapePaths() {
        XCTAssertTrue(archiveEntryIsSafe("Notes/draft.txt"))
        XCTAssertTrue(archiveEntryIsSafe("Folder/"))
        XCTAssertFalse(archiveEntryIsSafe("../outside"))
        XCTAssertFalse(archiveEntryIsSafe("/etc/passwd"))
        XCTAssertFalse(archiveEntryIsSafe("folder/../../outside"))
        XCTAssertFalse(archiveEntryIsSafe(""))
        XCTAssertFalse(archiveEntryIsSafe("bad\nname"))
        XCTAssertEqual(archiveTopLevelNames(["Notes/a.txt", "Notes/b.txt", "Other/"]), ["Notes", "Other"])
    }

    func testFinderFlowLinkDoesNotOpenAnAppBundle() {
        let facts = ExternalOpenFacts(
            isDirectory: true,
            isBrowsableFolder: false,
            isMarkdown: false,
            isEditableText: false
        )
        let decision = externalOpenDecision(
            source: .finderFlowLink,
            path: "/Applications/Calculator.app",
            facts: facts
        )
        XCTAssertEqual(decision, .ignore)
    }

    func testFinderFlowLinkNavigatesIntoAFolder() {
        let facts = ExternalOpenFacts(
            isDirectory: true,
            isBrowsableFolder: true,
            isMarkdown: false,
            isEditableText: false
        )
        XCTAssertEqual(
            externalOpenDecision(source: .finderFlowLink, path: "/Users/me/Documents", facts: facts),
            .navigate(path: "/Users/me/Documents")
        )
    }

    func testFileURLCanStillOpenAPackage() {
        let facts = ExternalOpenFacts(
            isDirectory: true,
            isBrowsableFolder: false,
            isMarkdown: false,
            isEditableText: false
        )
        XCTAssertEqual(
            externalOpenDecision(source: .fileURL, path: "/Applications/Calculator.app", facts: facts),
            .launchPackage(path: "/Applications/Calculator.app")
        )
    }

    func testSymlinkOutsideRootIsDetected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("finderflow-symlink-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr"))
        XCTAssertTrue(symlinkEscapesRoot(link, root: root))

        let inside = root.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let local = root.appendingPathComponent("local")
        try FileManager.default.createSymbolicLink(at: local, withDestinationURL: inside)
        XCTAssertFalse(symlinkEscapesRoot(local, root: root))
    }
}
