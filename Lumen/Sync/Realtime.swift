import Foundation

/// Listens to Supabase Realtime while the app is open. Any change to your rows in the `lumen` schema
/// (Instinct planning, another device) triggers a quick pull, so the plan updates without a refresh.
@MainActor
final class Realtime {
    static let shared = Realtime()

    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var ref = 0
    private var wanted = false
    private var retry: TimeInterval = 2
    private let topic = "realtime:lumen-sync"

    func connect() {
        wanted = true
        guard socket == nil, Auth.shared.signedIn, Auth.shared.configured,
              var c = URLComponents(string: Auth.shared.base + "/realtime/v1/websocket") else { return }
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.queryItems = [URLQueryItem(name: "apikey", value: Auth.shared.anonKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        guard let url = c.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        Task {
            await Auth.shared.refreshIfNeeded()
            send(topic: topic, event: "phx_join", payload: [
                "config": [
                    "broadcast": ["self": false], "presence": ["key": ""],
                    "postgres_changes": [["event": "*", "schema": "lumen"]],
                ],
                "access_token": Auth.shared.session?.accessToken ?? "",
            ])
        }
        receive(task)
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                await Auth.shared.refreshIfNeeded()
                self.send(topic: "phoenix", event: "heartbeat", payload: [:])
                if let token = Auth.shared.session?.accessToken {
                    self.send(topic: self.topic, event: "access_token", payload: ["access_token": token])
                }
            }
        }
    }

    func disconnect() {
        wanted = false
        heartbeat?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func send(topic: String, event: String, payload: [String: Any]) {
        ref += 1
        let msg: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": String(ref), "join_ref": "1"]
        guard let data = try? JSONSerialization.data(withJSONObject: msg), let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .failure:
                    self.dropped()
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.retry = 2
                    self.receive(task)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = obj["event"] as? String else { return }
        if event == "postgres_changes" {
            debounce?.cancel()
            debounce = Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                await SyncEngine.shared.sync()
            }
        } else if event == "phx_error" || event == "phx_close" {
            dropped()
        }
    }

    private func dropped() {
        socket?.cancel(with: .abnormalClosure, reason: nil)
        socket = nil
        heartbeat?.cancel()
        guard wanted else { return }
        let wait = retry
        retry = min(60, retry * 2)
        Task {
            try? await Task.sleep(for: .seconds(wait))
            if self.wanted { self.connect() }
        }
    }
}
