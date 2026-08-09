import SwiftUI

/// Persisted browse preferences — defaults mirror macOS Finder with newest-first
/// date grouping. Users can change any setting; it sticks.
enum UserPreferences {
    static let viewModeKey       = "ffViewMode"
    static let sortFieldKey      = "ffSortField"
    static let sortAscendingKey  = "ffSortAscending"
    static let groupByKey        = "ffGroupBy"
    static let folderOrderKey    = "ffFolderOrder"
    static let showHiddenKey     = "ffShowHidden"
    static let showPreviewKey    = "ffShowPreview"
    static let showColumnTreeKey = "ffShowColumnTree"
    /// Bumped key so 1.5.1 re-runs migration for users who got a narrow 1.5 pass.
    static let defaultsMigratedKey = "ffBrowseDefaultsMigrated151"
    static let didShowFirstRunKey  = "ffDidShowFirstRun"

    // Finder-like factory defaults: list + date groups + newest first + folders on top
    static let defaultViewMode:       ViewMode     = .list
    static let defaultSortField:      SortField    = .dateModified
    static let defaultSortAscending:  Bool         = false
    static let defaultGroupBy:        GroupBy      = .dateModified
    static let defaultFolderOrder:    FolderOrder  = .foldersFirst

    /// One-time: upgrades from pre-1.5 (or old factory Name A→Z / no grouping)
    /// get newest-first date sort + date-modified groups. Deliberate custom prefs
    /// (Size, Kind, descending Name, etc.) are left alone.
    static func migrateBrowseDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsMigratedKey) else { return }
        defaults.set(true, forKey: defaultsMigratedKey)

        let sortMissing = defaults.object(forKey: sortFieldKey) == nil
        let groupMissing = defaults.object(forKey: groupByKey) == nil
        let sort = defaults.string(forKey: sortFieldKey) ?? SortField.name.rawValue
        let ascObj = defaults.object(forKey: sortAscendingKey)
        let ascending = (ascObj as? Bool) ?? true
        let group = defaults.string(forKey: groupByKey) ?? GroupBy.none.rawValue

        let nameAscending = (sort == SortField.name.rawValue && ascending == true)
        let groupLooksDefault =
            groupMissing
            || group == GroupBy.none.rawValue
            || group == GroupBy.dateModified.rawValue

        // Old factory / missing prefs / Name↑ with no intentional exotic group
        let shouldApply =
            sortMissing
            || (nameAscending && groupLooksDefault)

        guard shouldApply else { return }

        defaults.set(defaultSortField.rawValue, forKey: sortFieldKey)
        defaults.set(defaultSortAscending, forKey: sortAscendingKey)
        defaults.set(defaultGroupBy.rawValue, forKey: groupByKey)
        if defaults.object(forKey: viewModeKey) == nil {
            defaults.set(defaultViewMode.rawValue, forKey: viewModeKey)
        }
        if defaults.object(forKey: folderOrderKey) == nil {
            defaults.set(defaultFolderOrder.rawValue, forKey: folderOrderKey)
        }
    }

    /// Apply factory browse defaults (Settings reset + install repair).
    static func applyFactoryBrowseDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(defaultViewMode.rawValue, forKey: viewModeKey)
        defaults.set(defaultSortField.rawValue, forKey: sortFieldKey)
        defaults.set(defaultSortAscending, forKey: sortAscendingKey)
        defaults.set(defaultGroupBy.rawValue, forKey: groupByKey)
        defaults.set(defaultFolderOrder.rawValue, forKey: folderOrderKey)
    }
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
