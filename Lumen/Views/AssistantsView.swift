import SwiftUI
import CryptoKit

/// Access keys for assistants like Instinct. A key is made on this iPhone and shown once; only its SHA-256 hash
/// is stored in Supabase, so not even the database can give it back.
struct AssistantsView: View {
    @Environment(Auth.self) private var auth
    @State private var keys: [AgentKey] = []
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false
    @State private var revealed: Revealed?

    struct AgentKey: Identifiable {
        var id: String
        var name: String
        var prefix: String
        var scopes: [String]
        var createdAt: Date?
        var lastUsedAt: Date?
        var revokedAt: Date?
    }

    struct Revealed: Identifiable {
        var id = UUID()
        var name: String
        var key: String
    }

    var body: some View {
        Form {
            if !auth.signedIn {
                Section { Text("Sign in to make keys — Instinct talks to your Supabase account, not to this iPhone.").foregroundStyle(.secondary) }
            } else {
                Section {
                    Button { creating = true } label: { Label("New access key", systemImage: "key.badge.plus") }
                    LabeledContent("API address") { Text(auth.agentURL).font(.caption2.monospaced()).textSelection(.enabled) }
                } footer: {
                    Text("Give Instinct the address and a key, plus docs/INSTINCT.md from the Lumen repo. It sends the key as \"Authorization: Bearer <key>\".")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.warn).font(.caption) } }
                Section("Keys") {
                    if loading && keys.isEmpty { ProgressView() }
                    if !loading && keys.isEmpty { Text("No keys yet.").foregroundStyle(.secondary) }
                    ForEach(keys) { k in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(k.name).font(.headline)
                                if k.revokedAt != nil { Text("Revoked").font(.caption2.weight(.bold)).foregroundStyle(Theme.bad) }
                                Spacer()
                                Text(k.prefix + "…").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(k.scopes.map(Scope.label).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            Text(k.lastUsedAt.map { "Last used \($0.formatted(.relative(presentation: .named)))" } ?? "Never used")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if k.revokedAt == nil {
                                Button("Revoke", role: .destructive) { Task { await revoke(k) } }
                            } else {
                                Button("Delete", role: .destructive) { Task { await delete(k) } }
                            }
                        }
                    }
                }
            }
        }
        .glassForm()
        .navigationTitle("Assistants")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) {
            NewKeySheet { name, scopes in
                Task {
                    if let key = await create(name: name, scopes: scopes) { revealed = Revealed(name: name, key: key) }
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $revealed) { r in KeyRevealSheet(revealed: r, agentURL: auth.agentURL).preferredColorScheme(.dark) }
    }

    private func load() async {
        guard auth.signedIn else { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await API.select("agent_keys", [("select", "id,name,prefix,scopes,created_at,last_used_at,revoked_at"), ("order", "created_at.desc")])
            keys = rows.map { raw in
                let r = Row(raw)
                return AgentKey(id: r.str("id") ?? "", name: r.str("name") ?? "Key", prefix: r.str("prefix") ?? "",
                                scopes: ((raw["scopes"] as? [Any]) ?? []).compactMap { $0 as? String },
                                createdAt: r.date("created_at"), lastUsedAt: r.date("last_used_at"), revokedAt: r.date("revoked_at"))
            }
            error = nil
        } catch let e as APIError {
            error = e.needsSetup ? "Run the Lumen SQL migration and expose the lumen schema first." : e.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create(name: String, scopes: [String]) async -> String? {
        let key = "lmn_" + Self.randomKey(40)
        let hash = Data(SHA256.hash(data: Data(key.utf8))).hex
        do {
            _ = try await API.insert("agent_keys", ["name": name, "key_hash": hash, "prefix": String(key.prefix(10)), "scopes": scopes,
                                                     "user_id": auth.userID ?? ""])
            await load()
            return key
        } catch {
            self.error = "Couldn't save the key: \(error.localizedDescription)"
            return nil
        }
    }

    private func revoke(_ k: AgentKey) async {
        do {
            try await API.patch("agent_keys", id: k.id, ["revoked_at": ISO.string(Date())])
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ k: AgentKey) async {
        do {
            try await API.delete("agent_keys", id: k.id)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    static func randomKey(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var out = ""
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<n { out.append(chars[Int.random(in: 0..<chars.count, using: &rng)]) }
        return out
    }
}

enum Scope: String, CaseIterable, Identifiable {
    case read
    case assignments = "write:assignments"
    case plan = "write:plan"
    case cards = "write:cards"
    case syllabus = "write:syllabus"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .read: return "Read everything"
        case .assignments: return "Add and change assignments"
        case .plan: return "Plan study blocks"
        case .cards: return "Make decks and cards"
        case .syllabus: return "Update the syllabus"
        }
    }
    static func label(_ raw: String) -> String {
        switch raw {
        case "read": return "Read"
        case "write:assignments": return "Assignments"
        case "write:plan": return "Plan"
        case "write:cards": return "Cards"
        case "write:syllabus": return "Syllabus"
        default: return raw
        }
    }
}

struct NewKeySheet: View {
    var onCreate: (String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Instinct"
    @State private var scopes: Set<Scope> = Set(Scope.allCases)

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Instinct", text: $name) }
                Section {
                    ForEach(Scope.allCases) { s in
                        Toggle(s.title, isOn: Binding(get: { scopes.contains(s) }, set: { on in
                            if on { scopes.insert(s) } else if s != .read { scopes.remove(s) }
                        }))
                        .disabled(s == .read)
                    }
                } header: { Text("What it may do") } footer: { Text("Every key can read. Write access can be narrowed; make a new key to change it later.") }
            }
            .glassForm()
            .navigationTitle("New key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Instinct" : name, Scope.allCases.filter { scopes.contains($0) }.map(\.rawValue))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The new key, shown this once.
struct KeyRevealSheet: View {
    var revealed: AssistantsView.Revealed
    var agentURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Copy it now — Lumen can't show this key again.", systemImage: "exclamationmark.lock.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warn)
                    Text(revealed.key)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .glassCard(tint: Theme.instinct, radius: 18, padding: 14)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button { UIPasteboard.general.string = revealed.key; flash() } label: {
                                Label(copied ? "Copied" : "Copy key", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            Button { UIPasteboard.general.string = setup; flash() } label: {
                                Label("Copy setup", systemImage: "text.badge.plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                    Text("“Copy setup” gives you a short note for \(revealed.name) with the address, the key and how to start. The full guide is docs/INSTINCT.md in the repo.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(setup).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .glassCard(radius: 16, padding: 12)
                }
                .padding()
            }
            .navigationTitle("Key for \(revealed.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .interactiveDismissDisabled(!copied)
    }

    private var setup: String {
        """
        Lumen study planner API
        Base URL: \(agentURL)
        Header: Authorization: Bearer \(revealed.key)

        Start every planning run with GET /context?from=<today>&to=<+14 days>.
        Submit plans with POST /plan; follow up on GET /events?since=<cursor>.
        Never plan over busy_slots or outside free_slots, keep to the preferences,
        spread work before deadlines and replan missed blocks.
        Full reference: docs/INSTINCT.md and docs/openapi.yaml in the Lumen repo.
        """
    }

    private func flash() {
        Haptics.success()
        withAnimation { copied = true }
    }
}
