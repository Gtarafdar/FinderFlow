import SwiftUI

/// Persisted browse preferences — defaults mirror macOS Finder (list view, name sort,
/// date-modified groups, folders on top). Users can change any setting; it sticks.
enum UserPreferences {
    static let viewModeKey       = "ffViewMode"
    static let sortFieldKey      = "ffSortField"
    static let sortAscendingKey  = "ffSortAscending"
    static let groupByKey        = "ffGroupBy"
    static let folderOrderKey    = "ffFolderOrder"
    static let showHiddenKey     = "ffShowHidden"
    static let showPreviewKey    = "ffShowPreview"
    static let showColumnTreeKey = "ffShowColumnTree"

    // Finder-like factory defaults for first launch
    static let defaultViewMode:       ViewMode     = .list
    static let defaultSortField:      SortField    = .name
    static let defaultSortAscending:  Bool         = true
    static let defaultGroupBy:        GroupBy      = .dateModified
    static let defaultFolderOrder:    FolderOrder  = .foldersFirst
}

// MARK: - AppStorage helpers (enum ↔ persisted raw string)

extension ViewMode {
    static func fromStorage(_ raw: String) -> ViewMode {
        ViewMode(rawValue: raw) ?? UserPreferences.defaultViewMode
    }
}

extension SortField {
    static func fromStorage(_ raw: String) -> SortField {
        SortField(rawValue: raw) ?? UserPreferences.defaultSortField
    }
}

extension GroupBy {
    static func fromStorage(_ raw: String) -> GroupBy {
        GroupBy(rawValue: raw) ?? UserPreferences.defaultGroupBy
    }
}

extension FolderOrder {
    static func fromStorage(_ raw: String) -> FolderOrder {
        FolderOrder(rawValue: raw) ?? UserPreferences.defaultFolderOrder
    }
}
