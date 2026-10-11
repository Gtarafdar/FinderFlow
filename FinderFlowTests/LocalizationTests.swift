import XCTest

final class LocalizationTests: XCTestCase {

    private let key = AppLanguage.storageKey
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    private func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }

    // MARK: - Lookup

    func testEnglishPassesSourceTextThrough() {
        select(.en)
        XCTAssertEqual(L10n.s("New Folder"), "New Folder")
        XCTAssertEqual(L10n.s("Move to Trash"), "Move to Trash")
    }

    func testChineseReturnsTranslation() {
        select(.zhHans)
        XCTAssertEqual(L10n.s("New Folder"), "新建文件夹")
        XCTAssertEqual(L10n.s("Move to Trash"), "移到废纸篓")
        XCTAssertEqual(L10n.s("Quick Look"), "快速查看")
    }

    func testUntranslatedKeyFallsBackToEnglish() {
        select(.zhHans)
        // A key missing from the dictionary must show English, never the key
        // transformed or dropped.
        XCTAssertEqual(L10n.s("Definitely not in the dictionary"), "Definitely not in the dictionary")
    }

    func testEffectiveDefaultsToSystem() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppLanguage.effective, .system)
    }

    // MARK: - Formatted lookups

    func testFormattedStringEnglish() {
        select(.en)
        XCTAssertEqual(L10n.sf("Compress \"%@\"", "notes.txt"), "Compress \"notes.txt\"")
        XCTAssertEqual(L10n.sf("Make %d Aliases", 3), "Make 3 Aliases")
    }

    func testFormattedStringChinese() {
        select(.zhHans)
        XCTAssertEqual(L10n.sf("Compress \"%@\"", "notes.txt"), "压缩 \"notes.txt\"")
        XCTAssertEqual(L10n.sf("Make %d Aliases", 3), "制作 3 个替身")
    }

    // MARK: - Count helpers

    func testItemsLabelPlurals() {
        select(.en)
        XCTAssertEqual(L10n.itemsLabel(1), "1 item")
        XCTAssertEqual(L10n.itemsLabel(4), "4 items")
        select(.zhHans)
        XCTAssertEqual(L10n.itemsLabel(1), "1 个项目")
        XCTAssertEqual(L10n.itemsLabel(4), "4 个项目")
    }

    func testActionLabelSingleIsQuotedName() {
        select(.en)
        XCTAssertEqual(L10n.actionLabel(["a.txt"]), "\"a.txt\"")
        XCTAssertEqual(L10n.actionLabel(["a.txt", "b"]), "2 items")
        select(.zhHans)
        XCTAssertEqual(L10n.actionLabel(["a.txt", "b"]), "2 个项目")
    }

    func testSelectionLabel() {
        select(.en)
        XCTAssertEqual(L10n.selectionLabel(3), "3 selected")
        select(.zhHans)
        XCTAssertEqual(L10n.selectionLabel(3), "已选 3 项")
    }

    // MARK: - Group headers

    func testDateCategoryTitlesLocalize() {
        select(.zhHans)
        XCTAssertEqual(L10n.s("Today"), "今天")
        XCTAssertEqual(L10n.s("Previous 7 Days"), "最近 7 天")
        select(.en)
        XCTAssertEqual(L10n.s("Today"), "Today")
    }

    func testGroupByNamesLocalize() {
        // The display keys are the raw values of GroupBy / SortField / FolderOrder
        // in FileItem.swift (which the test target does not compile).
        select(.zhHans)
        XCTAssertEqual(L10n.s("Date Modified"), "修改日期")
        XCTAssertEqual(L10n.s("Name"), "名称")
        XCTAssertEqual(L10n.s("Folders on Top"), "文件夹优先")
    }
}
