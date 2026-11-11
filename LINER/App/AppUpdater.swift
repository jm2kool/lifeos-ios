import SwiftUI
import UIKit

/// "Update from the app": looks at the newest build CI published (the `liner-latest` release) and hands its
/// .ipa to an installer that signs apps on the phone (SideStore or AltStore). iOS doesn't let an app replace
/// itself, so one of those has to be on the phone; without one, the .ipa downloads for Sideloadly as before.
@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// What CI writes next to the .ipa (`version.json`).
    struct Build: Decodable, Sendable {
        let build: Int
        let version: String
        let commit: String
        var branch: String?
        var date: Date?
        var notes: String?
        let ipa: URL
        /// The AltStore-style source SideStore and AltStore can follow for updates.
        var source: URL?
    }

    enum State: Equatable { case idle, checking, upToDate, available, failed(String) }

    enum Installer: String, CaseIterable, Identifiable {
        case sideStore = "SideStore", altStore = "AltStore"
        var id: String { rawValue }
        var scheme: String { self == .sideStore ? "sidestore" : "altstore" }
    }

    private(set) var latest: Build?
    private(set) var state = State.idle

    private static let feed = URL(string: "https://github.com/jm2kool/lifeos-ios/releases/download/liner-latest/version.json")!

    /// This copy's build number. CI numbers builds by workflow run, so a bigger number is a newer build.
    var installedBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
    var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var isAvailable: Bool { (latest?.build ?? 0) > installedBuild }

    func check() async {
        state = .checking
        var request = URLRequest(url: Self.feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // The release is replaced on every build, so it's missing for a minute while a new one uploads.
                state = .failed("No build is published right now. A new one may be on its way; try again in a few minutes.")
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            latest = try decoder.decode(Build.self, from: data)
            state = isAvailable ? .available : .upToDate
            UserDefaults.standard.set(Date.now, forKey: "update.lastCheck")
        } catch {
            state = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }

    /// A check at most once every six hours, for app launch. Returns true the first time a build is seen.
    func checkQuietly() async -> Bool {
        let last = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 6 * 3600 else { return false }
        await check()
        guard isAvailable, let build = latest?.build, UserDefaults.standard.integer(forKey: "update.announced") != build else { return false }
        UserDefaults.standard.set(build, forKey: "update.announced")
        return true
    }

    /// Opens the installer with the newest .ipa. False when that installer isn't on the phone.
    func install(with installer: Installer) async -> Bool {
        guard let ipa = latest?.ipa else { return false }
        return await open(installer, action: "install", url: ipa)
    }

    /// Adds LINER.'s source to the installer, so it lists updates by itself.
    func follow(in installer: Installer) async -> Bool {
        guard let source = latest?.source else { return false }
        return await open(installer, action: "source", url: source)
    }

    private func open(_ installer: Installer, action: String, url: URL) async -> Bool {
        var parts = URLComponents()
        parts.scheme = installer.scheme
        parts.host = action
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let link = parts.url else { return false }
        return await UIApplication.shared.open(link)
    }
}
