import Foundation
import AppKit
import SwiftUI
import CryptoKit

/// Checks GitHub Releases for a newer FinderFlow build and can download + install
/// the .dmg with one click (quit → replace → relaunch).
@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String, dmgURL: URL)
        case downloading(progress: Double)
        case installing
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var pendingSHA256: String?

    private let repoOwner = "Gtarafdar"
    private let repoName  = "FinderFlow"
    private let checkInterval: TimeInterval = 12 * 3600   // twice a day max

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoCheck) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoCheck) }
    }

    func checkIfNeeded(force: Bool = false) {
        guard autoCheckEnabled || force else { return }
        if !force {
            let last = UserDefaults.standard.double(forKey: Keys.lastCheck)
            guard Date().timeIntervalSince1970 - last >= checkInterval else { return }
        }
        Task { await checkForUpdates(force: force) }
    }

    func checkForUpdates(force: Bool = false) async {
        phase = .checking
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)

        do {
            let release = try await fetchLatestRelease()
            let latest  = release.version
            guard isVersion(latest, newerThan: currentVersion) else {
                phase = .upToDate
                return
            }
            if !force, UserDefaults.standard.string(forKey: Keys.dismissedVersion) == latest {
                phase = .idle
                return
            }
            phase = .available(version: latest, notes: release.notes, dmgURL: release.dmgURL)
            pendingSHA256 = release.sha256
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func dismissAvailableUpdate() {
        if case .available(let version, _, _) = phase {
            UserDefaults.standard.set(version, forKey: Keys.dismissedVersion)
        }
        phase = .idle
    }

    /// Download the release DMG and hand off to a short shell script that replaces
    /// the running .app and relaunches — the only reliable pattern on macOS.
    func downloadAndInstall() async {
        guard case .available(_, _, let dmgURL) = phase else { return }
        let installDir = Bundle.main.bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installDir.path) else {
            phase = .error("Move FinderFlow to Applications (or another writable folder), then try again.")
            return
        }
        phase = .downloading(progress: 0)

        do {
            let localDMG = try await downloadDMG(from: dmgURL) { [weak self] p in
                Task { @MainActor in self?.phase = .downloading(progress: p) }
            }
            if let expected = pendingSHA256 {
                let actual = try Self.sha256(of: localDMG)
                guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                    try? FileManager.default.removeItem(at: localDMG)
                    phase = .error("Download failed integrity check. Try again later or download manually from GitHub.")
                    return
                }
            }
            phase = .installing
            try launchInstaller(dmgPath: localDMG.path)
            // App quits — no return
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    // MARK: - GitHub API

    private struct ReleaseInfo {
        let version: String
        let notes:   String
        let dmgURL:  URL
        let sha256:  String?   // expected DMG hash from release asset
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let body:     String?
        let assets:   [GHAsset]
    }

    private struct GHAsset: Decodable {
        let name:                  String
        let browser_download_url:  String
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("FinderFlow/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network("Could not reach GitHub (status \((resp as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard let dmgAsset = release.assets.first(where: {
            $0.name.hasSuffix(".dmg") && !$0.name.hasSuffix(".dmg.sha256")
        }), let dmgURL = URL(string: dmgAsset.browser_download_url) else {
            throw UpdateError.noAsset
        }
        let sha256 = try await fetchExpectedSHA256(for: dmgAsset.name, assets: release.assets)
        return ReleaseInfo(version: version, notes: release.body ?? "", dmgURL: dmgURL, sha256: sha256)
    }

    /// Reads the companion `FinderFlow-x.y.dmg.sha256` asset published with each release.
    private func fetchExpectedSHA256(for dmgName: String, assets: [GHAsset]) async throws -> String {
        guard let hashAsset = assets.first(where: { $0.name == "\(dmgName).sha256" }),
              let hashURL = URL(string: hashAsset.browser_download_url) else {
            throw UpdateError.noChecksum
        }
        let (data, resp) = try await URLSession.shared.data(from: hashURL)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network("Could not fetch release checksum")
        }
        let line = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first ?? ""
        guard line.count == 64, line.allSatisfy({ $0.isHexDigit }) else {
            throw UpdateError.badChecksum
        }
        return line
    }

    private static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Download

    private func downloadDMG(from url: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network("Download failed")
        }
        onProgress(1.0)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderFlow-update-\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    // MARK: - Install (detach, replace, relaunch)

    private func launchInstaller(dmgPath: String) throws {
        let installDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        let scriptPath   = FileManager.default.temporaryDirectory
            .appendingPathComponent("finderflow-install-\(UUID().uuidString).sh").path

        let script = """
        #!/bin/bash
        set -e
        DMG="\(dmgPath.replacingOccurrences(of: "\"", with: "\\\""))"
        INSTALL_DIR="\(installDir.replacingOccurrences(of: "\"", with: "\\\""))"
        APP="FinderFlow.app"
        sleep 2
        MOUNT_LINE=$(hdiutil attach "$DMG" -nobrowse -quiet 2>&1 | grep "/Volumes/" | tail -1)
        MOUNT=$(echo "$MOUNT_LINE" | awk -F'\t' '{print $NF}')
        test -d "$MOUNT/$APP" || { echo "App not found in DMG"; exit 1; }
        ditto "$MOUNT/$APP" "$INSTALL_DIR/$APP"
        hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
        xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP" 2>/dev/null || true
        rm -f "$DMG"
        open "$INSTALL_DIR/$APP"
        """

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptPath]
        try proc.run()

        NSApp.terminate(nil)
    }

    // MARK: - Semver compare

    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n  = max(pa.count, pb.count)
        for i in 0..<n {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    private enum Keys {
        static let lastCheck        = "ffUpdateLastCheck"
        static let dismissedVersion = "ffUpdateDismissedVersion"
        static let autoCheck        = "ffAutoCheckUpdates"
    }

    private enum UpdateError: LocalizedError {
        case network(String)
        case noAsset
        case noChecksum
        case badChecksum

        var errorDescription: String? {
            switch self {
            case .network(let m): return m
            case .noAsset:        return "No .dmg found on the latest GitHub release."
            case .noChecksum:     return "Release is missing a checksum file — update blocked for safety."
            case .badChecksum:    return "Release checksum file is invalid."
            }
        }
    }
}

// MARK: - In-app update banner

struct UpdateBanner: View {
    @ObservedObject var manager: UpdateManager
    let version: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("FinderFlow ") + Text(version).bold() + Text(" is available — you have \(manager.currentVersion).")
                .font(.system(size: 12))
            Spacer(minLength: 8)
            if case .downloading(let p) = manager.phase {
                ProgressView(value: p)
                    .frame(width: 80)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .installing = manager.phase {
                ProgressView()
                    .controlSize(.small)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Update Now") {
                    Task { await manager.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Later") { manager.dismissAvailableUpdate() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
