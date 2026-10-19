import SwiftUI

/// Settings › Gemini keys: the keys on this iPhone (Keychain only) and, with a server, the server's own pool.
/// Values are never shown after they're added; only labels and whether each key is working.
struct GeminiKeysView: View {
    @Environment(Store.self) private var store
    @State private var keys: [GeminiKeys.Key] = []
    @State private var newKey = ""
    @State private var newLabel = ""
    @State private var problem: String?
    @State private var server: JSON = .null
    @State private var serverProblem: String?
    @State private var serverKey = ""
    @State private var serverLabel = ""
    @State private var busy = false
    @State private var tick = Date()

    private var model: String { store.doc["settings"]["ai"]["model"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "gemini-3.5-flash" }

    var body: some View {
        Form {
            Section {
                ForEach(keys) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.label)
                        Text(status(GeminiKeys.cooldown(k.id, model: model))).font(.caption).foregroundStyle(GeminiKeys.cooldown(k.id, model: model) == nil ? .green : .secondary)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { GeminiKeys.remove(k.id); reload() }
                        if GeminiKeys.cooldown(k.id, model: model) != nil { Button("Retry") { GeminiKeys.reset(k.id); reload() }.tint(.blue) }
                    }
                }
                if keys.isEmpty { Text("No keys on this iPhone yet.").foregroundStyle(.secondary) }
            } header: { Text("On this iPhone · \(GeminiKeys.activeCount(model: model)) of \(keys.count) active") } footer: {
                Text("Kept in the iPhone Keychain only, never sent to your server. When one is rate limited or out of its free quota, the next is used and the tired one rests (until Google's daily reset, for a daily quota). Swipe left to remove or retry a key.")
            }
            Section {
                SecureField("Gemini API key", text: $newKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Label (optional)", text: $newLabel)
                Button("Add key") {
                    problem = GeminiKeys.add(newKey, label: newLabel)
                    if problem == nil { newKey = ""; newLabel = ""; store.show("Key added"); reload() }
                }
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
                Link("Get a free key in Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
            } header: { Text("Add a key") }

            if !store.syncURL.isEmpty {
                Section {
                    ForEach(server["keys"].array, id: \.self) { k in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k["label"].str)
                            Text(serverStatus(k)).font(.caption).foregroundStyle(k["status"].str == "active" ? .green : .secondary)
                        }
                        .swipeActions {
                            if !k["builtin"].bool { Button("Remove", role: .destructive) { Task { await serverCall("DELETE", ["id": k["id"]], done: "Removed " + k["label"].str) } } }
                            if k["status"].str != "active" { Button("Retry") { Task { await serverCall("PATCH", ["id": k["id"], "reset": true], done: "Cooldown cleared") } }.tint(.blue) }
                        }
                    }
                    if let serverProblem { Text(serverProblem).font(.footnote).foregroundStyle(.secondary) }
                    if server["canAdd"].bool {
                        SecureField("Gemini API key", text: $serverKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Label (optional)", text: $serverLabel)
                        Button { Task { await addToServer() } } label: { HStack { Text("Add to server"); Spacer(); if busy { ProgressView() } } }
                            .disabled(busy || serverKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else if !server.isNull {
                        Text("To store extra keys on the server, add GEMINI_KEYS_SECRET (any long random string) in Vercel and redeploy.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(server.isNull ? "On your server" : "On your server · \(server["active"].int ?? 0) of \(server["total"].int ?? 0) active")
                } footer: {
                    Text("Stored encrypted on your server and used first; the keys on this iPhone are the fallback. The server checks a key with Google before adding it. Needs the owner (admin) sync key.")
                }
            }
        }
        .navigationTitle("Gemini keys")
        .onAppear(perform: reload)
        .task { await loadServer() }
        .refreshable { reload(); await loadServer() }
    }

    private func reload() { keys = GeminiKeys.all(); tick = Date() }

    private func status(_ c: GeminiKeys.Cooldown?) -> String {
        guard let c else { return "Active" }
        if c.reason == "rejected" { return "Google rejected this key · retrying " + store.time(c.until) }
        return (c.reason == "daily quota" ? "Out of today's quota" : "Rate limited") + " · back " + when(c.until)
    }
    private func serverStatus(_ k: JSON) -> String {
        let until = k["until"].double.map { Date(timeIntervalSince1970: $0 / 1000) }
        switch k["status"].str {
        case "active": return k["builtin"].bool ? "Active · from Vercel" : "Active"
        case "rejected": return "Google rejected this key" + (until.map { " · retrying " + store.time($0) } ?? "")
        default: return (k["reason"].str == "daily quota" ? "Out of today's quota" : "Rate limited") + (until.map { " · back " + when($0) } ?? "")
        }
    }
    private func when(_ d: Date) -> String {
        Calendar.current.isDate(d, inSameDayAs: Date()) ? store.time(d) : store.relDay(store.dayKey(d)).lowercased() + " " + store.time(d)
    }

    private func loadServer() async {
        guard !store.syncURL.isEmpty else { return }
        do {
            server = try await store.api("GET", "gemini-keys", query: ["model": model])
            GeminiKeys.serverActive = server["active"].int; GeminiKeys.serverTotal = server["total"].int
            serverProblem = nil
        } catch { serverProblem = error.localizedDescription }
    }
    private func addToServer() async {
        busy = true; defer { busy = false }
        do {
            server = try await store.api("POST", "gemini-keys", query: ["model": model], body: ["key": .string(serverKey.trimmingCharacters(in: .whitespacesAndNewlines)), "label": .string(serverLabel)])
            GeminiKeys.serverActive = server["active"].int; GeminiKeys.serverTotal = server["total"].int
            serverKey = ""; serverLabel = ""; serverProblem = nil; store.show("Key added to the server")
        } catch { serverProblem = GeminiKeys.scrub(error.localizedDescription) }
    }
    private func serverCall(_ method: String, _ body: JSON, done: String) async {
        do {
            server = try await store.api(method, "gemini-keys", query: ["model": model], body: body)
            GeminiKeys.serverActive = server["active"].int; GeminiKeys.serverTotal = server["total"].int
            store.show(done)
        } catch { serverProblem = error.localizedDescription }
    }
}

extension GeminiKeys {
    /// "3 active · 1 cooling down", for the Settings row.
    @MainActor static func summary(model: String) -> String {
        let n = all().count, a = activeCount(model: model)
        var parts: [String] = []
        if n == 0 && serverTotal == nil { return "No key yet" }
        if n > 0 { parts.append(a == n ? "\(n) active" : "\(a) of \(n) active") }
        if let st = serverTotal, st > 0 { parts.append("server \(serverActive ?? 0) of \(st)") }
        return parts.joined(separator: " · ")
    }
}
