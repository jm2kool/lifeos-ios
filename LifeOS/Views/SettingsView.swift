import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var timezone = ""
    @State private var geminiKey = ""
    @State private var model = ""
    @State private var assistantName = ""
    @State private var assistantAddress = ""
    @State private var syncURL = ""
    @State private var syncKey = ""
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var testing = false

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
                    SecureField("Gemini API key", text: $geminiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Update Today", selection: Binding(get: { assistant.intervalHours }, set: { store.act(["op": "settings.set", "value": ["ai": ["interval": JSON($0)]]]) })) {
                        Text("Every hour").tag(1); Text("Every 2 hours").tag(2); Text("Off").tag(0)
                    }
                    Toggle("Ask before changing things", isOn: Binding(get: { assistant.askFirst }, set: { store.act(["op": "settings.set", "value": ["ai": ["askFirst": .bool($0)]]]) }))
                    Button {
                        save(); testing = true
                        Task { await assistant.runPulse(force: true); testing = false; if store.pulse["brief"].string != nil { store.show("Gemini is working") } }
                    } label: { HStack { Text("Save and run Gemini now"); Spacer(); if testing { ProgressView() } } }
                    Link("Get a key in Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
                } header: { Text("Gemini") } footer: {
                    Text("Your key is stored in the iPhone Keychain and only sent to Google. Gemini refreshes Today, drafts email replies and can move things around; every change is logged in Activity and can be undone.")
                }
                Section {
                    TextField("Name", text: $assistantName)
                    TextField("iMessage address (phone or email)", text: $assistantAddress).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                } header: { Text("Your iMessage assistant") } footer: {
                    Text("“Send to” buttons open Messages with a ready-made message to this address.")
                }
                Section {
                    TextField("Server, e.g. https://lifeos.vercel.app", text: $syncURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Sync key", text: $syncKey)
                    Button("Save and sync now") { save(); Task { await store.pull(); store.show(store.syncStatus) } }
                    LabeledContent("Status", value: store.syncStatus)
                } header: { Text("Sync and assistant access") } footer: {
                    Text("Optional. With a LifeOS server, your iMessage assistant can add and remove things by sending a plain sentence to one web address, and this iPhone picks the changes up.")
                }
                Section("Your data") {
                    if let exportURL { ShareLink("Export backup", item: exportURL) } else { Button("Prepare backup") { exportURL = makeExport() } }
                    Button("Import backup or data file") { importing = true }
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
                store.replace(with: j); load(); store.show("Imported")
            }
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
        geminiKey = Keychain.get("geminiKey") ?? ""; model = d["settings"]["ai"]["model"].string ?? "gemini-3.5-flash"
        assistantName = d["profile"]["assistant"]["name"].str; assistantAddress = d["profile"]["assistant"]["imessage"].str
        syncURL = d["settings"]["sync"]["url"].str; syncKey = Keychain.get("syncKey") ?? ""
    }
    private func save() {
        Keychain.set("geminiKey", geminiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        Keychain.set("syncKey", syncKey.trimmingCharacters(in: .whitespacesAndNewlines))
        var ops: [JSON] = []
        if name != store.profileName || assistantName != store.doc["profile"]["assistant"]["name"].str || assistantAddress != store.assistantAddress {
            ops.append(["op": "profile.set", "value": ["name": .string(name), "assistant": ["name": .string(assistantName), "imessage": .string(assistantAddress), "email": .string(assistantAddress.contains("@") ? assistantAddress : "")]]])
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
                Button("Finish") { Keychain.set("geminiKey", key.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }.buttonStyle(.glassProminent).controlSize(.large)
            }
            Spacer()
        }
        .padding(28)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let j = JSON.parse(d), j["content"].isObject {
                store.replace(with: j); name = store.profileName; withAnimation(.smooth) { step = 2 }
            } else { store.show("That isn't a LifeOS file") }
        }
    }
    private func next() {
        guard !name.isEmpty else { return }
        store.act(["op": "profile.set", "value": ["name": .string(name), "timezone": .string(store.doc["profile"]["timezone"].string.flatMap { $0.isEmpty ? nil : $0 } ?? TimeZone.current.identifier)]])
        withAnimation(.smooth) { step = 2 }
    }
}
