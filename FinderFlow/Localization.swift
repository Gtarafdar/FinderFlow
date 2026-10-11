import SwiftUI

// MARK: - Supported languages

/// Interface languages the user can pick in Settings. "system" follows macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHans

    var id: String { rawValue }

    static let storageKey = "ffLanguage"

    /// The language actually in effect right now (UserDefaults is read
    /// directly so background threads see a consistent, thread-safe value).
    static var effective: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// The locale used for formatting (dates, numbers) with the effective language.
    var locale: Locale {
        switch self {
        case .en:     return Locale(identifier: "en")
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .system: return Locale.autoupdatingCurrent
        }
    }

    /// True when the interface should render in Simplified Chinese.
    var isChinese: Bool {
        switch self {
        case .zhHans: return true
        case .system: return Locale.autoupdatingCurrent.identifier.hasPrefix("zh")
        case .en:     return false
        }
    }

    /// Picker labels stay in their own language (endonyms), except "System".
    var displayName: String {
        switch self {
        case .system: return L10n.s("System")
        case .en:     return "English"
        case .zhHans: return "简体中文"
        }
    }
}

// MARK: - Observable state (drives re-rendering when the user switches)

/// Views hold this via `@EnvironmentObject` so switching the language in
/// Settings re-renders every open window. The actual lookup lives in `L10n`
/// and reads UserDefaults directly, so non-view code (services, alerts,
/// toasts) is always correct without observing anything.
final class LocaleState: ObservableObject {
    static let shared = LocaleState()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey) }
    }

    private init() {
        language = AppLanguage.effective
    }
}

// MARK: - String lookup

/// All user-facing strings, English + Simplified Chinese. English is the
/// source of truth: the lookup key *is* the English text, so an untranslated
/// string degrades to English instead of showing a raw key.
enum L10n {

    /// True when the interface language is Simplified Chinese.
    static var isChinese: Bool { AppLanguage.effective.isChinese }

    /// Locale for formatting dates / numbers under the effective language.
    static var locale: Locale { AppLanguage.effective.locale }

    /// Translate `key` (English source text) to the active language.
    static func s(_ key: String) -> String {
        isChinese ? (zhHans[key] ?? key) : key
    }

    /// Translate, then fill positional arguments (%d, %@) with locale-aware formatting.
    static func sf(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: locale, arguments: args)
    }

    /// "3 items" / "3 个项目" — Chinese has no plural distinction.
    static func itemsLabel(_ n: Int) -> String {
        isChinese ? "\(n) 个项目" : (n == 1 ? "1 item" : "\(n) items")
    }

    /// Label for an action on N items: the quoted name when it's one,
    /// otherwise the item count. Used by every toast ("Copied 3 items").
    static func actionLabel(_ names: [String]) -> String {
        names.count == 1 ? "\"\(names[0])\"" : itemsLabel(names.count)
    }

    /// Status bar selection summary: "3 selected" / "已选 3 项".
    static func selectionLabel(_ n: Int) -> String {
        isChinese ? "已选 \(n) 项" : "\(n) selected"
    }

    // MARK: - Simplified Chinese dictionary

    private static let zhHans: [String: String] = [
        // ── Context menus ────────────────────────────────────────────────
        "Open":                            "打开",
        "Open in New Window":              "在新窗口中打开",
        "Show Package Contents":           "显示包内容",
        "Quick Look":                      "快速查看",
        "Get Info":                        "显示简介",
        "Rename…":                         "重命名…",
        "Rename":                          "重命名",
        "Rename \"%@\"":                   "重命名 \"%@\"",
        "Enter a new name:":               "输入新名称：",
        "Duplicate":                       "制作副本",
        "Duplicate %d Items":              "制作 %d 个项目的副本",
        "Make Alias":                      "制作替身",
        "Make %d Aliases":                 "制作 %d 个替身",
        "Compress \"%@\"":                 "压缩 \"%@\"",
        "Compress %d Items":               "压缩 %d 个项目",
        "Extract Here":                    "解压到此处",
        "Cut":                             "剪切",
        "Copy":                            "拷贝",
        "Paste":                           "粘贴",
        "Share":                           "共享",
        "AirDrop":                         "隔空投送",
        "Share…":                          "共享…",
        "Tags":                            "标签",
        "Clear Tags":                      "清除标签",
        "Add to Sidebar":                  "添加到边栏",
        "Remove from Sidebar":             "从边栏移除",
        "Show in Finder":                  "在访达中显示",
        "Copy Path":                       "拷贝路径",
        "Copy %d Paths":                   "拷贝 %d 个路径",
        "Move to Trash":                   "移到废纸篓",
        "Delete Permanently…":             "彻底删除…",
        "Delete Permanently":              "彻底删除",
        "New Folder":                      "新建文件夹",
        "New File":                        "新建文件",
        "New Text File":                   "新建文本文件",
        "Move":                            "移动",
        "Undo":                            "撤销",
        "Redo":                            "重做",
        "Refresh":                         "刷新",
        "Cancel":                          "取消",
        "Create":                          "创建",
        "Replace":                         "替换",
        "OK":                              "好",
        "Insert":                          "插入",
        "Done":                            "完成",

        // ── Toasts ───────────────────────────────────────────────────────
        "Created \"%@\"":                  "已创建 \"%@\"",
        "Copied %@":                       "已拷贝 %@",
        "Cut %@":                          "已剪切 %@",
        "Pasted %@":                       "已粘贴 %@",
        "Moved %@":                        "已移动 %@",
        "Renamed to %@":                   "已重命名为 %@",
        "Duplicated %@":                   "已制作副本 %@",
        "Trashed %@":                      "已放入废纸篓 %@",
        "Permanently deleted %@":          "已彻底删除 %@",
        "Tagged %@":                       "已添加标签 %@",
        "Removed %@ tag":                  "已移除标签 %@",
        "Cleared tags":                    "已清除标签",
        "Path copied":                     "已拷贝路径",
        "Undone":                          "已撤销",
        "Undone: %@":                      "已撤销：%@",
        "Redone":                          "已重做",
        "Redone: %@":                      "已重做：%@",
        "Saved":                           "已保存",
        "Save failed":                     "保存失败",

        // ── Creation / delete dialogs ────────────────────────────────────
        "New Folder in \"%@\"":            "在 \"%@\" 中新建文件夹",
        "Enter a name for the new folder:": "输入新文件夹的名称：",
        "New File in \"%@\"":              "在 \"%@\" 中新建文件",
        "Enter a name for the new file (include extension, e.g. notes.txt):":
                                          "输入新文件的名称（包含扩展名，例如 notes.txt）：",
        "Permanently delete %@?":          "彻底删除 %@？",
        "This cannot be undone. %@ will be permanently deleted and cannot be recovered.":
                                          "此操作无法撤销。%@ 将被彻底删除，且无法恢复。",
        "This cannot be undone. %@ will be permanently deleted and cannot be recovered from Trash.":
                                          "此操作无法撤销。%@ 将被彻底删除，且无法从废纸篓恢复。",
        "The item":                        "该项目",
        "The items":                       "这些项目",

        // ── Archives ─────────────────────────────────────────────────────
        "Replace existing %@?":            "替换已有的 %@？",
        "Extracting will replace items already in this folder. This cannot be undone.":
                                          "解压将替换此文件夹中已有的项目。此操作无法撤销。",
        "FinderFlow can't extract this file type.":
                                          "FinderFlow 无法解压此类型文件。",
        "This archive is empty.":          "此压缩包是空的。",
        "This archive can't be extracted because it contains an unsafe path.":
                                          "此压缩包包含不安全的路径，无法解压。",
        "This archive can't be extracted because it contains a link that points outside the archive.":
                                          "此压缩包包含指向压缩包外部的链接，无法解压。",
        "Couldn't extract because \"%@\" already exists.":
                                          "无法解压，因为 \"%@\" 已存在。",
        "One of these items can't be compressed because its name isn't allowed.":
                                          "其中一个项目的名称不被允许，无法压缩。",
        "Couldn't read this archive.":     "无法读取此压缩包。",
        "Could not create file at %@":     "无法在 %@ 创建文件。",

        // ── Toolbar ──────────────────────────────────────────────────────
        "Open Terminal":                   "打开终端",
        "Open in VS Code":                 "在 VS Code 中打开",
        "Open in Claude Code (opens Terminal)": "在 Claude Code 中打开（打开终端）",
        "Open in Cursor":                  "在 Cursor 中打开",
        "Open in Codex":                   "在 Codex 中打开",
        "Hidden Files":                    "隐藏文件",
        "Show hidden files":               "显示隐藏文件",
        "Hide hidden files":               "不再显示隐藏文件",
        "Group By":                        "分组方式",
        "Grouped by %@":                   "已按 %@ 分组",
        "File Preview":                    "文件预览",
        "Show file preview panel":         "显示文件预览面板",
        "Hide preview panel":              "隐藏预览面板",
        "Show Tree":                       "显示树",
        "Show full folder tree from root": "从根目录显示完整文件夹树",
        "Hide folder tree — show current folder only": "隐藏文件夹树 — 只显示当前文件夹",
        "Go Up":                           "前往上一层",
        "Sort by":                         "排序方式",
        "Ascending":                       "升序",
        "Descending":                      "降序",
        "Folder / file order: %@":         "文件夹 / 文件顺序：%@",
        "Switch view":                     "切换视图",

        // ── Menus ────────────────────────────────────────────────────────
        "Toggle Hidden Files":             "切换显示隐藏文件",
        "Check for Updates…":              "检查更新…",
        "Launch at Login":                 "在登录时启动",

        // ── Status bar ───────────────────────────────────────────────────
        "%@ available":                    "%@ 可用",

        // ── Date group headers ───────────────────────────────────────────
        "Today":                           "今天",
        "Yesterday":                       "昨天",
        "Previous 7 Days":                 "最近 7 天",
        "Previous 30 Days":                "最近 30 天",
        "Previous 90 Days":                "最近 90 天",
        "Earlier":                         "更早",

        // ── Sort / group / band names ────────────────────────────────────
        "None":                            "无",
        "Name":                            "名称",
        "Date Modified":                   "修改日期",
        "Date Created":                    "创建日期",
        "Kind":                            "种类",
        "Extension":                       "扩展名",
        "Size":                            "大小",
        "Folders":                         "文件夹",
        "Other":                           "其他",
        "Unknown":                         "未知",
        "Over 1 GB":                       "超过 1 GB",
        "Zero KB":                         "0 KB",
        "Folders on Top":                  "文件夹优先",
        "Files on Top":                    "文件优先",
        "Mixed (Sort Only)":               "混合（仅排序）",

        // ── Sidebar ──────────────────────────────────────────────────────
        "Favorites":                       "个人收藏",
        "Pinned":                          "已固定",
        "Recent":                          "最近使用",
        "Remove from Pinned":              "取消固定",

        // ── Search ───────────────────────────────────────────────────────
        "Scope":                           "范围",
        "This Folder":                     "此文件夹",
        "This Folder & Subfolders":        "此文件夹及子文件夹",
        "Desktop":                         "桌面",
        "Documents":                       "文稿",
        "Downloads":                       "下载",
        "Home Folder":                     "个人文件夹",
        "Entire Mac":                      "整台 Mac",
        "Name or .ext (e.g. .pdf)…":       "名称或 .ext（例如 .pdf）…",
        "%d found":                        "找到 %d 个",

        // ── Path bar ─────────────────────────────────────────────────────
        "Path":                            "路径",
        "Copy full path":                  "拷贝完整路径",

        // ── First run ────────────────────────────────────────────────────
        "You're all set":                  "一切就绪",
        "If macOS asked you to allow FinderFlow once under System Settings → Privacy & Security, that was expected. This is a free open-source app without a paid Apple Developer certificate — the one-time Open Anyway step is safe.":
            "如果 macOS 曾在「系统设置 → 隐私与安全性」中要求你允许 FinderFlow，这是正常现象。这是一款免费的开源应用，没有付费的 Apple 开发者证书——只需一次性的「仍要打开」操作，是安全的。",
        "When you browse Desktop, Documents, or Downloads, macOS may ask for folder access — click Allow. You can enable the optional Finder right-click menu later under Login Items & Extensions.":
            "当你在桌面、文稿或下载中浏览时，macOS 可能会请求文件夹访问权限——点击「允许」。之后可以在「登录项与扩展」中启用可选的访达右键菜单。",
        "Continue":                        "继续",

        // ── Error sheet ──────────────────────────────────────────────────
        "Error":                           "错误",
        "Details":                         "详情",
        "Contact Support":                 "联系支持",
        "Copies diagnostics, then opens GitHub Issues": "先拷贝诊断信息，然后打开 GitHub Issues",

        // ── Preview panel ────────────────────────────────────────────────
        "Modified":                        "修改时间",
        "Created":                         "创建时间",
        "Select a file\nto preview":       "选择文件\n以预览",

        // ── File kinds ───────────────────────────────────────────────────
        "Folder":                          "文件夹",
        "File":                            "文件",
        "%@ File":                         "%@ 文件",

        // ── Editor ───────────────────────────────────────────────────────
        "Editor":                          "编辑器",
        "Increase Font":                   "放大字体",
        "Decrease Font":                   "缩小字体",
        "Sublime Keybindings":             "Sublime 键位",
        "Editor options":                  "编辑器选项",
        "Settings…":                         "设置…",
        "Saved %@":                          "已保存 %@",
        "Minimap: on  ⌘⇧M":                 "缩略图：开  ⌘⇧M",
        "Minimap: off  ⌘⇧M":                "缩略图：关  ⌘⇧M",
        "Save  ⌘S":                          "保存  ⌘S",
        "Close Tab  ⌘W":                     "关闭标签页  ⌘W",
        "Read":                            "阅读",
        "Edit":                            "编辑",
        "Insert link":                     "插入链接",
        "Back":                            "返回",
        "Go back":                         "返回",
        "Open in FinderFlow editor":       "在 FinderFlow 编辑器中打开",
        "Bold":                            "粗体",
        "Italic":                          "斜体",
        "Strikethrough":                   "删除线",
        "Inline code":                     "行内代码",
        "Bullet list":                     "无序列表",
        "Numbered list":                   "有序列表",
        "Quote":                           "引用",
        "Code block":                      "代码块",
        "Link":                            "链接",
        "Horizontal rule":                 "分割线",
        "Heading 1":                         "标题 1",
        "Heading 2":                         "标题 2",
        "Heading 3":                         "标题 3",

        // ── Settings ─────────────────────────────────────────────────────
        "Language":                        "语言",
        "Interface language":              "界面语言",
        "System":                          "系统",
        "Updates":                         "更新",
        "Version":                         "版本",
        "Check for updates automatically": "自动检查更新",
        "Sparkle installs an update only when it carries the maintainer's signature. Version 1.5.2 and earlier need one manual download from GitHub.":
            "只有带有维护者签名的更新才会被安装。1.5.2 及更早版本需要从 GitHub 手动下载一次。",
        "Browse defaults":                 "浏览默认设置",
        "New installs start with Finder-like settings: list view, date-modified groups sorted newest first, folders on top. Reset restores those defaults.":
            "新安装默认使用类似访达的设置：列表视图、按修改日期分组且最新在前、文件夹置顶。重置可恢复这些默认值。",
        "Reset to Finder defaults":        "重置为访达默认设置",
        "Text editor":                     "文本编辑器",
        "Open unknown file types in the editor": "在编辑器中打开未知文件类型",
        "When on, files without a known code extension open in FinderFlow’s editor if they look like text. When off, only known text/code files do.":
            "开启时，看起来是文本但没有已知代码扩展名的文件会在 FinderFlow 编辑器中打开。关闭时，只有已知的文本 / 代码文件才会这样打开。",
        "Open folders in FinderFlow":      "使用 FinderFlow 打开文件夹",
        "Routes folder-open actions (the `open` command, other apps, and “Open With”) to FinderFlow instead of Finder.":
            "将打开文件夹的操作（`open` 命令、其他应用和“打开方式”）路由到 FinderFlow 而不是访达。",
        "Couldn't update the setting: %@": "无法更新设置：%@",
        "FinderFlow is now the default for folders. Log out and back in if some apps still open Finder.":
            "FinderFlow 现在是文件夹的默认打开方式。如果某些应用仍然打开访达，请注销后重新登录。",
        "Finder restored as the default for folders.": "访达已恢复为文件夹的默认打开方式。",
        "What this can and can't do":      "此功能能做什么、不能做什么",
        "FinderFlow opens when you open a folder from Terminal, other apps, or “Open With”.":
            "从终端、其他应用或“打开方式”打开文件夹时，FinderFlow 会打开。",
        "Finder can't be fully replaced. The Desktop, drive mounting, Open/Save dialogs and the Dock’s Finder icon always stay Finder.":
            "访达无法被完全替代。桌面、磁盘挂载、打开 / 保存对话框和程序坞中的访达图标始终属于访达。",
        "Some changes only take effect after you log out and back in (or restart).":
            "某些更改需要注销并重新登录（或重启）后才生效。",
    ]
}
