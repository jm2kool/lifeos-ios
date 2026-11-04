import Foundation
import UIKit
import ActivityKit

/// Push notifications through APNs. When Instinct changes the plan the server pushes straight away: a visible
/// notification for things you should see (a new plan to review, an assignment it added) and a silent one that makes
/// Lumen sync and reschedule its reminders in the background. Before a study block the server can also start the
/// Live Activity by push, so it appears in the Dynamic Island even if Lumen hasn't run.
///
/// This needs the install's provisioning profile to include push (`aps-environment`), which a paid Apple Developer
/// account gives when sideloading. Without it Lumen falls back to Realtime and Background App Refresh.
@Observable @MainActor
final class Push {
    static let shared = Push()

    enum Kind: String { case device, liveActivityStart = "live_activity_start", liveActivity = "live_activity" }

    enum State: Equatable {
        case unavailable, registering, on, failed(String)
    }

    /// "sandbox" or "production", from the provisioning profile; nil when this install can't get pushes.
    let environment: String? = Provisioning.apnsEnvironment
    private(set) var state: State
    private(set) var deviceToken: String?
    @ObservationIgnored private var queued: [(token: String, kind: Kind, key: String?)] = []
    @ObservationIgnored private var sent = Set<String>()
    @ObservationIgnored private var watchingStartTokens = false

    /// Live Activities can be updated and ended by push.
    var canUpdateLiveActivities: Bool { environment != nil && deviceToken != nil }

    private init() { state = Provisioning.apnsEnvironment == nil ? .unavailable : .registering }

    /// Asks iOS for a device token (no prompt; alerts still need notification permission).
    func register() {
        guard environment != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
        watchStartTokens()
    }

    func didRegister(_ token: Data) {
        deviceToken = token.hex
        state = .on
        Task { await upload(token: token, kind: .device, key: nil) }
    }

    func didFail(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    /// The token iOS gives for starting the study block Live Activity by push.
    private func watchStartTokens() {
        guard !watchingStartTokens else { return }
        watchingStartTokens = true
        Task {
            for await token in Activity<StudyBlockAttributes>.pushToStartTokenUpdates {
                await upload(token: token, kind: .liveActivityStart, key: nil)
            }
        }
    }

    /// Saves a token in lumen.push_tokens (or keeps it until you're signed in).
    func upload(token: Data, kind: Kind, key: String?) async {
        let hex = token.hex
        guard let env = environment else { return }
        guard Auth.shared.signedIn, let user = Auth.shared.userID else {
            queued.append((hex, kind, key))
            return
        }
        let signature = "\(user)|\(hex)|\(kind.rawValue)|\(key ?? "")"
        guard !sent.contains(signature) else { return }
        let row: [String: Any] = [
            "user_id": user, "token": hex, "kind": kind.rawValue, "environment": env,
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.jm2kool.lumen", "activity_key": key.json,
            "device_name": UIDevice.current.name, "updated_at": ISO.string(Date()), "disabled_at": NSNull(), "last_error": NSNull(),
        ]
        do {
            _ = try await API.request("POST", "/rest/v1/push_tokens", query: [URLQueryItem(name: "on_conflict", value: "token")], body: [row],
                                      headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
            sent.insert(signature)
        } catch {
            queued.append((hex, kind, key))
        }
    }

    /// Sends tokens that were waiting for you to sign in.
    func uploadQueued() async {
        let waiting = queued
        queued.removeAll()
        for item in waiting {
            guard let data = Data(hexString: item.token) else { continue }
            await upload(token: data, kind: item.kind, key: item.key)
        }
    }

    /// A push arrived (silent or not): bring everything up to date.
    func handle(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let pulled = await SyncEngine.shared.sync()
        await Notifier.shared.reschedule()
        await WidgetBridge.refresh()
        return pulled > 0 ? .newData : .noData
    }

    var summary: String {
        switch state {
        case .unavailable:
            return "Not in this install — it needs a paid Apple Developer account when sideloading. Lumen uses Realtime and Background App Refresh instead."
        case .registering: return "Connecting…"
        case .on: return Auth.shared.signedIn ? "On — Instinct's changes arrive straight away." : "Ready — sign in to receive them."
        case .failed(let why): return "Couldn't turn on: \(why)"
        }
    }
}

extension Data {
    init?(hexString: String) {
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
