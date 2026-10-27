import SwiftUI

/// A watch party: the film, who's in, the shared timer, and play/pause for the whole room.
/// Opened from "Watch together" on a film you're watching, or from a matinee://party/CODE link.
struct PartySheet: View {
    let code: String
    @Environment(Watching.self) private var watching
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var joining = false
    @State private var error: String?

    private var party: Party { Party.shared }
    private var row: PartyRow? { party.rows[code] }
    private var session: WatchSession? { watching.sessions.first { $0.party == code } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let row {
                        content(row)
                    } else if joining {
                        ProgressView("Joining \(code)…").padding(.top, 80)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "person.3.fill").font(.system(size: 48)).foregroundStyle(Theme.accent)
                            Text("Watch party \(code)").font(.title2.weight(.bold))
                            Text(error ?? "Join to watch in step: when anyone pauses or plays, everyone's timer follows.")
                                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                            if auth.signedIn {
                                Button("Join the party", systemImage: "person.badge.plus") { Task { await join() } }
                                    .buttonStyle(.glassProminent).controlSize(.large)
                            } else {
                                Button("Sign in to join", systemImage: "person.crop.circle") { router.sheet = .signIn }
                                    .buttonStyle(.glassProminent).controlSize(.large)
                            }
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .oledBackground()
            .navigationTitle("Watch party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .task {
                // Arriving from a link: join straight away when signed in.
                if row == nil && session == nil && auth.signedIn { await join() }
                else if row == nil, session != nil { await join() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func join() async {
        joining = true
        let ok = await party.join(code)
        joining = false
        if !ok { error = party.error }
    }

    @ViewBuilder private func content(_ row: PartyRow) -> some View {
        VStack(spacing: 12) {
            PosterView(film: row.film, width: 150, corner: 12)
            Text(row.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let t = row.elapsed(at: tl.date)
                VStack(spacing: 4) {
                    Text(clock(t)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    if let r = row.runtimeMinutes, r > 0 {
                        ProgressView(value: min(1, t / Double(r * 60))).tint(Theme.accent).frame(maxWidth: 240)
                        Text("of \(filmClock(TimeInterval(r * 60)))").font(.caption).foregroundStyle(Theme.dim)
                    }
                    Label(row.running ? "Playing for everyone" : "Paused for everyone", systemImage: row.running ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(row.running ? Theme.watch : Theme.star)
                }
            }
        }

        if let s = session {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if s.running {
                        Button { watching.intermission(s.id, at: s.elapsed(), mood: s.lastStop?.mood ?? "🍿", note: "") } label: {
                            Label("Pause for all", systemImage: "pause.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button { watching.resume(s.id) } label: { Label("Play for all", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                    }
                    ShareLink(item: Party.link(code), message: Text("Watch \(row.film.title) with me on Matinee — party code \(code)")) {
                        Label("Invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }

        VStack(spacing: 6) {
            Text("PARTY CODE").font(.caption2.weight(.heavy)).tracking(1.4).foregroundStyle(Theme.dim)
            Text(code).font(.system(size: 30, weight: .heavy, design: .monospaced)).tracking(6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)

        VStack(alignment: .leading, spacing: 10) {
            Text("IN THE ROOM · \(row.members.count)").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
            ForEach(row.members) { m in
                HStack(spacing: 12) {
                    Avatar(profile: Profile(name: m.name), size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.name).font(.subheadline.weight(.semibold))
                        if let h = m.handle { Text("@\(h)").font(.caption).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    if m.userID == row.host { Text("HOST").font(.caption2.weight(.heavy)).foregroundStyle(Theme.accent) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 20))

        Button(role: .destructive) {
            Task { await party.leave(code); dismiss() }
        } label: {
            Text(row.host == auth.session?.userID ? "End the party for everyone" : "Leave the party").font(.footnote.weight(.semibold))
        }
        .padding(.top, 4)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// Type a party code someone gave you.
struct JoinPartyButton: View {
    @Environment(Router.self) private var router
    @State private var asking = false
    @State private var code = ""

    var body: some View {
        Button("Join a watch party", systemImage: "person.3") { asking = true }
            .alert("Join a watch party", isPresented: $asking) {
                TextField("Party code", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Join") {
                    let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
                    code = ""
                    if !c.isEmpty { router.sheet = .party(c) }
                }
                Button("Cancel", role: .cancel) { code = "" }
            } message: { Text("Enter the six-character code from the person hosting.") }
    }
}
