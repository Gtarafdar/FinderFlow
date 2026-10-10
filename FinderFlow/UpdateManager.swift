import AppKit
import Sparkle

/// Signed updates via Sparkle. The appcast is checked with the EdDSA public key in Info.plist.
/// The private key never ships with the app.
@MainActor
final class UpdateManager: NSObject, ObservableObject {

    static let shared = UpdateManager()

    private let controller: SPUStandardUpdaterController
    private static let migratedAutoCheckKey = "ffSparkleAutoCheckMigrated"

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        migrateAutoCheckPreference()
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Settings → Updates. Sparkle stores the value itself after the one-time migration below.
    var autoCheckEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Older builds stored this in `ffAutoCheck`. Sparkle uses its own default after migration.
    private func migrateAutoCheckPreference() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migratedAutoCheckKey) else { return }
        if defaults.object(forKey: "ffAutoCheck") != nil {
            controller.updater.automaticallyChecksForUpdates = defaults.bool(forKey: "ffAutoCheck")
        }
        defaults.set(true, forKey: Self.migratedAutoCheckKey)
    }
}
