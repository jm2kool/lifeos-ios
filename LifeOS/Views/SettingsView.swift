import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var timezone = ""
    @State private var model = ""
    @State private var assistantName = ""
    @State private var assistantAddress = ""
    @State private var assistantEmail = ""
    @State private var syncURL = ""
    @State private var syncKey = ""
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var testing = false
    @State private var importPlan: Store.ImportPlan?
    @State private var importResult: String?
    @State private var checking = false

    private let tints: [(String, Color)] = [("graphite", .primary), ("blue", .blue), ("indigo", .indigo), ("green", .green), ("orange", .orange), ("pink", .pink)]

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name).onSubmit { store.act(["op": "profile.set", "value": ["name": .string(name)]]) }
                    TextField("Time zone", text: $timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { if TimeZone(identifier: timezone) != nil { store.act(["op": "profile.set", "value": ["timezone": .string(timezone)]]) } else { store.show("That time zone isn't recognised") } }
                }
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { store.doc["settings"]["theme"].string ?? "auto" }, set: { store.act(["op": "settings.set", "value": ["theme": .string($0)]]) })) {
                        Text("System").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Accent")
                        Spacer()
                        ForEach(tints, id: \.0) { k, c in
                            let on = (store.doc["settings"]["tint"].string ?? "graphite") == k
                            Button { store.act(["op": "settings.set", "value": ["tint": .string(k)]]) } label: {
                                Circle().fill(c).frame(width: 26, height: 26).overlay { if on { Circle().stroke(.background, lineWidth: 2).padding(3) } }
                            }
                            .buttonStyle(.plain).accessibilityLabel(k)
                        }
                    }
                }
                Section {
                    Toggle("Notify me when study blocks start", isOn: Binding(get: { store.studyAlertsOn }, set: { store.act(["op": "settings.set", "value": ["study": ["alerts": .bool($0)]]]) }))
                    Picker("Heads-up", selection: Binding(get: { store.studyLead }, set: { store.act(["op": "settings.set", "value": ["study": ["lead": JSON($0)]]]) })) {
                        Text("None").tag(0); Text("5 min before").tag(5); Text("10 min before").tag(10); Text("15 min before").tag(15)
                    }
                    .disabled(!store.studyAlertsOn)
                    Toggle("Study lock", isOn: Binding(get: { store.studyLockOn }, set: { store.act(["op": "settings.set", "value": ["study": ["lock": .bool($0)]]]) }))
                    NavigationLink("Set up the study lock") { StudyLockGuide() }
                } header: { Text("Study blocks") } footer: {
                    Text("Study blocks are the ones on your timetable and study plan. Lunch, breaks and school calendar events don't count.")
                }
                Section {
                    NavigationLink { GeminiKeysView() } label: { LabeledContent("API keys", value: GeminiKeys.summary(model: model)) }
                    TextField("Model", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Update Today", selection: Binding(get: { assistant.intervalHours }, set: { store.act(["op": "settings.set", "value": ["ai": ["interval": JSON($0)]]]) })) {
                        Text("Every hour").tag(1); Text("Every 2 hours").tag(2); Text("Off").tag(0)
                    }
                    Toggle("Ask before changing things", isOn: Binding(get: { assistant.askFirst }, set: { store.act(["op": "settings.set", "value": ["ai": ["askFirst": .bool($0)]]]) }))
                    Button {
                        save(); testing = true
                        Task { await assistant.runPulse(force: true); testing = false; if store.pulse["brief"].string != nil { store.show("Gemini is working") } }
                    } label: { HStack { Text("Save and run Gemini now"); Spacer(); if testing { ProgressView() } } }
                } header: { Text("Gemini") } footer: {
                    Text("Add several free keys: when one hits its limit the next takes over. Keys on this iPhone stay in the Keychain and are only sent to Google. Gemini refreshes Today, drafts email replies and can move things around; every change is logged in Activity and can be undone.")
                }
                Section {
                    TextField("Name", text: $assistantName)
                    TextField("iMessage address (phone or email)", text: $assistantAddress).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    TextField("Email address (for sending replies)", text: $assistantEmail).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                } header: { Text("Your iMessage assistant") } footer: {
                    Text("“Send to” buttons open Messages with a ready-made message to this address.")
                }
                Section {
                    TextField("Server, e.g. https://lifeos.vercel.app", text: $syncURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Sync key", text: $syncKey)
                    Button("Save and sync now") { save(); Task { await store.pull(); store.show(store.syncStatus) } }
                    LabeledContent("Status", value: store.syncStatus)
                    if !store.syncURL.isEmpty { NavigationLink("Access keys") { AccessKeysView() } }
                } header: { Text("Sync and assistant access") } footer: {
                    Text("Optional. With a LifeOS server, your assistants can add and remove things by sending a plain sentence to one web address, and this iPhone picks the changes up. Give each assistant its own key under Access keys.")
                }
                Section("Your data") {
                    if let exportURL { ShareLink("Export backup", item: exportURL) } else { Button("Prepare backup") { exportURL = makeExport() } }
                    Button { importing = true } label: { HStack { Text("Import backup or data file"); if checking { Spacer(); ProgressView() } } }.disabled(checking)
                    Button("Activity") { store.sheet = .activity }
                    Button("Start fresh", role: .destructive) { confirmReset = true }
                }
                Section { LabeledContent("Version", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.0") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
            .onAppear(perform: load)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: url), let j = JSON.parse(d), j["content"].isObject || j["state"].isObject else { store.show("That isn't a LifeOS file"); return }
                checking = true
                Task {
                    do { importPlan = try await store.planImport(j) } catch { importResult = "Nothing was imported. " + error.localizedDescription }
                    checking = false
                }
            }
            .sheet(item: $importPlan) { plan in ImportReview(plan: plan) { importResult = $0; load() } }
            .alert("Import", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) { Button("OK") {} } message: { Text(importResult ?? "") }
            .confirmationDialog("Erase everything on this iPhone?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase and start over", role: .destructive) {
                    store.replace(with: ["profile": ["timezone": .string(TimeZone.current.identifier)], "settings": ["theme": "auto"], "content": [:], "state": [:]])
                    dismiss(); store.sheet = .onboarding
                }
            } message: { Text("Export a backup first if you might want it back.") }
        }
    }
    private func load() {
        let d = store.doc
        name = d["profile"]["name"].str; timezone = d["profile"]["timezone"].string ?? TimeZone.current.identifier
        model = d["settings"]["ai"]["model"].string ?? "gemini-3.5-flash"
        assistantName = d["profile"]["assistant"]["name"].str; assistantAddress = d["profile"]["assistant"]["imessage"].str; assistantEmail = store.assistantEmail
        syncURL = d["settings"]["sync"]["url"].str; syncKey = Keychain.get("syncKey") ?? ""
    }
    private func save() {
        Keychain.set("syncKey", syncKey.trimmingCharacters(in: .whitespacesAndNewlines))
        var ops: [JSON] = []
        if name != store.profileName || assistantName != store.doc["profile"]["assistant"]["name"].str || assistantAddress != store.assistantAddress || assistantEmail != store.assistantEmail {
            let email = assistantEmail.trimmingCharacters(in: .whitespaces)
            ops.append(["op": "profile.set", "value": ["name": .string(name), "assistant": ["name": .string(assistantName), "imessage": .string(assistantAddress), "email": .string(email.isEmpty && assistantAddress.contains("@") ? assistantAddress : email)]]])
        }
        if model != (store.doc["settings"]["ai"]["model"].string ?? "gemini-3.5-flash") { ops.append(["op": "settings.set", "value": ["ai": ["model": .string(model)]]]) }
        if syncURL != store.syncURL { ops.append(["op": "settings.set", "value": ["sync": ["url": .string(syncURL.trimmingCharacters(in: .whitespaces))]]]) }
        if !ops.isEmpty { store.act(ops) }
    }
    private func makeExport() -> URL? {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("lifeos-backup-\(store.today).json")
        try? store.doc.data(pretty: true).write(to: u)
        return u
    }
}

// MARK: first run
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name = ""
    @State private var key = ""
    @State private var importing = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            switch step {
            case 0:
                Image(systemName: "sun.max.fill").font(.system(size: 64)).foregroundStyle(.orange.gradient).symbolEffect(.bounce, value: step)
                Text("Welcome to LifeOS").font(.largeTitle.bold())
                Text("Your day, tasks, study plan and inbox in one place, kept up to date by Gemini and your iMessage assistant.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Get started") { withAnimation(.smooth) { step = 1 } }.buttonStyle(.glassProminent).controlSize(.large)
                Button("Import my LifeOS data") { importing = true }.buttonStyle(.glass).controlSize(.large)
            case 1:
                Text("What should we call you?").font(.title.bold())
                TextField("Your name", text: $name).textFieldStyle(.roundedBorder).font(.title3).padding(.horizontal, 30).submitLabel(.next).onSubmit(next)
                Button("Continue", action: next).buttonStyle(.glassProminent).controlSize(.large).disabled(name.isEmpty)
            default:
                Image(systemName: "sparkles").font(.system(size: 54)).foregroundStyle(.tint)
                Text("Add Gemini").font(.title.bold())
                Text("Paste your Gemini API key and Gemini will plan your day, draft email replies and keep Today fresh. It stays in your Keychain. You can do this later in Settings.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                SecureField("Gemini API key", text: $key).textFieldStyle(.roundedBorder).padding(.horizontal, 30)
                Button("Finish") { if !key.trimmingCharacters(in: .whitespaces).isEmpty { GeminiKeys.add(key) }; dismiss() }.buttonStyle(.glassProminent).controlSize(.large)
            }
            Spacer()
        }
        .padding(28)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let j = JSON.parse(d), j["content"].isObject {
                store.replace(with: j); name = store.profileName; withAnimation(.smooth) { step = 2 }
                store.show("Imported " + Store.counts(j))
            } else { store.show("That isn't a LifeOS file") }
        }
    }
    private func next() {
        guard !name.isEmpty else { return }
        store.act(["op": "profile.set", "value": ["name": .string(name), "timezone": .string(store.doc["profile"]["timezone"].string.flatMap { $0.isEmpty ? nil : $0 } ?? TimeZone.current.identifier)]])
        withAnimation(.smooth) { step = 2 }
    }
}

// MARK: import review
/// Shows what an import will do before it runs, then reports what actually happened.
struct ImportReview: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: Store.ImportPlan
    var finished: (String) -> Void
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(plan.summary)
                } footer: {
                    Text(plan.viaServer
                         ? "Merged with what is on your server: nothing there is deleted, items with the same id are updated, and likely duplicates are skipped. You can undo the whole import from Activity."
                         : "Sync is off, so this replaces the data on this iPhone.")
                }
                if !plan.skipped.isEmpty {
                    Section(plan.viaServer ? "Skipped as likely duplicates" : "Look like duplicates") {
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, t in Text(t).font(.footnote) }
                    }
                }
                if !plan.failed.isEmpty {
                    Section("Can't be imported") {
                        ForEach(Array(plan.failed.enumerated()), id: \.offset) { _, t in Text(t).font(.footnote).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Import").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(running) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        running = true
                        Task {
                            let message: String
                            do { message = try await store.runImport(plan) } catch { message = "Nothing was imported. " + error.localizedDescription }
                            running = false; dismiss(); finished(message)
                        }
                    } label: { if running { ProgressView() } else { Text("Import") } }
                    .disabled(running)
                }
            }
        }
        .interactiveDismissDisabled(running)
    }
}

// MARK: access keys
/// One key per assistant, each read-only or allowed to make changes, with a log of who changed what.
struct AccessKeysView: View {
    @Environment(Store.self) private var store
    @State private var keys: [JSON] = []
    @State private var audit: [JSON] = []
    @State private var problem: String?
    @State private var name = ""
    @State private var scope = "write"
    @State private var newKey: String?
    @State private var revoking: JSON?
    @State private var busy = false

    var body: some View {
        List {
            if let problem { Section { Text(problem).foregroundStyle(.secondary) } }
            Section {
                ForEach(keys, id: \.self) { k in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(k["name"].str).font(.body.weight(.medium))
                            Spacer()
                            Pill(text: Self.label(k["scope"].str), color: k["scope"].str == "admin" ? .orange : k["scope"].str == "read" ? .secondary : .blue)
                        }
                        Text(detail(k)).font(.caption).foregroundStyle(.secondary)
                    }
                    .opacity(k["revokedAt"].isNull ? 1 : 0.45)
                    .swipeActions {
                        if k["revokedAt"].isNull && k["id"].str != "owner" { Button("Revoke", role: .destructive) { revoking = k } }
                    }
                    .contextMenu {
                        if k["revokedAt"].isNull && !k["builtin"].bool && k["id"].str.hasPrefix("key-") {
                            ForEach(["read", "write", "admin"], id: \.self) { sc in
                                Button(Self.label(sc), systemImage: sc == (k["grantedScope"].string ?? k["scope"].str) ? "checkmark" : "") { Task { await change(k, to: sc) } }
                            }
                        }
                    }
                }
            } header: { Text("Keys") } footer: {
                Text("Changes are labelled with the name of the key that made them, so a key can't pass itself off as another. Touch and hold a key to change what it may do; swipe left to revoke it.")
            }
            Section {
                TextField("Name, e.g. FRIDAY", text: $name).autocorrectionDisabled()
                Picker("Allowed to", selection: $scope) {
                    Text("Read only").tag("read"); Text("Read and change").tag("write"); Text("Everything, incl. keys").tag("admin")
                }
                Button("Create key") { Task { await create() } }.disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: { Text("New key") } footer: {
                Text("The key is shown once. Give it to the assistant, which sends it in the Authorization header. Keys in links are refused.")
            }
            if !audit.isEmpty {
                Section("Who changed what") {
                    ForEach(Array(audit.enumerated()), id: \.offset) { _, a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text((a["op"].str == "denied" ? "Refused: " : "") + a["op"].str + (a["summary"].str.isEmpty ? "" : " · " + a["summary"].str))
                                .font(.subheadline).lineLimit(2).foregroundStyle(a["ok"] == .bool(false) ? .red : .primary)
                            Text(a["name"].str + " · " + store.ago(a["at"].double ?? 0) + (a["error"].string.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Access keys")
        .task { await load() }
        .refreshable { await load() }
        .alert("Key for \(name)", isPresented: Binding(get: { newKey != nil }, set: { if !$0 { newKey = nil; name = "" } })) {
            Button("Copy key") { UIPasteboard.general.string = newKey; store.show("Copied"); newKey = nil; name = "" }
            Button("Done", role: .cancel) {}
        } message: { Text((newKey ?? "") + "\n\nCopy it now: it won't be shown again.") }
        .confirmationDialog("Revoke \(revoking?["name"].str ?? "")?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("Revoke", role: .destructive) { if let k = revoking { Task { await revoke(k) } } }
        } message: { Text("Anything using this key stops working straight away. Its past changes stay in the log.") }
    }

    static func label(_ scope: String) -> String { ["read": "Read only", "write": "Can change", "admin": "Admin"][scope] ?? scope }
    private func detail(_ k: JSON) -> String {
        if !k["revokedAt"].isNull { return "Revoked" + (k["revokedAt"].double.map { " " + store.ago($0) } ?? "") }
        if k["id"].str == "owner" { return "This iPhone's sync key (LIFEOS_TOKEN in Vercel)" }
        if k["legacy"].bool { return "The old shared assistant key (LIFEOS_AGENT_TOKEN). Revoke it once each assistant has its own." }
        var parts = ["Created " + store.ago(k["createdAt"].double ?? 0)]
        if !k["viaSetting"].isNull { parts.insert("Admin through the \(k["viaSetting"].str) setting in Vercel", at: 0) }
        parts.append(k["lastUsedAt"].double.map { "used " + store.ago($0) } ?? "never used")
        return parts.joined(separator: " · ")
    }
    private func load() async {
        do {
            keys = try await store.api("GET", "keys")["keys"].array
            audit = try await store.api("GET", "keys", query: ["view": "audit", "limit": "60"])["audit"].array
            problem = nil
        } catch { problem = error.localizedDescription }
    }
    private func create() async {
        busy = true; defer { busy = false }
        do {
            let j = try await store.api("POST", "keys", body: ["name": .string(name.trimmingCharacters(in: .whitespaces)), "scope": .string(scope)])
            newKey = j["key"].str
            await load()
        } catch { problem = error.localizedDescription }
    }
    private func change(_ k: JSON, to scope: String) async {
        do { _ = try await store.api("PATCH", "keys", body: ["id": k["id"], "scope": .string(scope)]); store.show(k["name"].str + ": " + Self.label(scope)); await load() }
        catch { problem = error.localizedDescription }
    }
    private func revoke(_ k: JSON) async {
        do { _ = try await store.api("DELETE", "keys", body: ["id": k["id"]]); store.show("Revoked " + k["name"].str); await load() }
        catch { problem = error.localizedDescription }
    }
}
