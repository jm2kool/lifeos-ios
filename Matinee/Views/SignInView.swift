import SwiftUI
import AuthenticationServices

struct SignInView: View {
    var asSheet = false
    @Environment(Auth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var posters: [FilmRef] = []
    @State private var emailForm = false
    @State private var serverForm = false

    /// Apple and Google get their own buttons; the rest sit under "More ways to sign in".
    private func offers(_ p: Auth.Provider) -> Bool { auth.enabledProviders.map { $0.contains(p.rawValue) } ?? true }
    private var more: [Auth.Provider] { Auth.Provider.allCases.filter { $0 != .apple && $0 != .google && offers($0) } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            PosterWall(films: posters).ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0), .init(color: .black.opacity(0.55), location: 0.4),
                                   .init(color: .black, location: 0.68)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                brand
                VStack(spacing: 12) {
                    if auth.configured {
                        if offers(.apple) {
                            providerButton(.apple, title: "Continue with Apple", prominent: true) {
                                Image(systemName: "apple.logo").font(.system(size: 19, weight: .semibold))
                            }
                        }
                        if offers(.google) {
                            providerButton(.google, title: "Continue with Google", prominent: !offers(.apple)) {
                                Text("G").font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        HStack(spacing: 12) {
                            if auth.emailEnabled {
                                Button { auth.error = nil; emailForm = true } label: {
                                    Label("Email", systemImage: "envelope.fill").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
                                }
                                .buttonStyle(.glass).controlSize(.large)
                            }
                            if !more.isEmpty {
                                Menu {
                                    ForEach(more) { p in Button("Continue with \(p.name)") { signIn(p) } }
                                } label: {
                                    Label("More", systemImage: "ellipsis.circle").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
                                }
                                .buttonStyle(.glass).controlSize(.large)
                            }
                        }
                        .disabled(auth.busy != nil)
                    } else {
                        Button { serverForm = true } label: {
                            Label("Connect an account server", systemImage: "server.rack").font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 32)
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    }

                    if !asSheet {
                        Button { auth.continueAsGuest() } label: {
                            Text("Use without an account").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
                VStack(spacing: 8) {
                    Text(auth.error ?? footnote)
                        .font(.footnote)
                        .foregroundStyle(auth.error == nil ? Theme.dim : Theme.accent)
                        .multilineTextAlignment(.center)
                        .animation(.smooth, value: auth.error)
                    if auth.configured {
                        Button("Account server") { serverForm = true }
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topTrailing) {
            if asSheet {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                    .padding(20)
            }
        }
        .sheet(isPresented: $emailForm) { EmailSignInSheet().environment(auth).preferredColorScheme(.dark) }
        .sheet(isPresented: $serverForm) {
            NavigationStack { AccountServerForm() }.environment(auth).preferredColorScheme(.dark)
        }
        .task {
            async let a = try? Catalog.shelf(.trending)
            async let b = try? Catalog.shelf(.topRated)
            var seen = Set<String>()
            let all = (((await a) ?? []) + ((await b) ?? [])).filter { seen.insert($0.id).inserted }
            withAnimation(.easeIn(duration: 0.8)) { posters = all }
        }
        .task(id: auth.serverURL) { await auth.loadProviders() }
        .onChange(of: auth.signedIn) { _, v in if v && asSheet { dismiss() } }
    }

    private var footnote: String {
        if !auth.configured { return "Sign-in needs a free Supabase project of your own. Without one, everything stays on this iPhone." }
        return asSheet ? "Sign in to sync your diary, ratings and lists across devices."
            : "Without an account, everything stays on this iPhone. You can sign in later from your profile."
    }

    private func providerButton<Mark: View>(_ p: Auth.Provider, title: String, prominent: Bool, @ViewBuilder mark: () -> Mark) -> some View {
        let icon = mark()
        let ink: Color = prominent ? .black : .white
        return Button { signIn(p) } label: {
            HStack(spacing: 10) {
                if auth.busy == p.rawValue { ProgressView().tint(ink) } else { icon }
                Text(title)
            }
            .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
            .foregroundStyle(ink)
        }
        .buttonStyle(.glassProminent)
        .tint(prominent ? .white : Color(white: 0.18))
        .controlSize(.large)
        .disabled(auth.busy != nil)
    }

    private var brand: some View {
        VStack(spacing: 10) {
            MatineeMark().frame(width: 64, height: 64)
            Text("Matinee").font(.system(size: 44, weight: .heavy, design: .serif))
            Text("Every film you watch, kept beautifully.\nLog it, rate it, find what's next.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Apple, Google and the rest open in a secure browser sheet and come back to matinee://auth-callback.
    private func signIn(_ p: Auth.Provider) {
        auth.error = nil
        guard let pending = auth.begin(p) else { return }
        auth.busy = p.rawValue
        Task {
            defer { auth.busy = nil }
            do {
                let callback = try await webAuth.authenticate(using: pending.url, callbackURLScheme: Auth.callbackScheme)
                await auth.finish(callback: callback, verifier: pending.verifier)
            } catch {
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    auth.error = error.localizedDescription
                }
            }
        }
    }
}

/// Sign in, or make an account, with an email address and a password. Forgotten passwords get a reset link.
struct EmailSignInSheet: View {
    @Environment(Auth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @FocusState private var field: Int?

    private var valid: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($field, equals: 0).submitLabel(.next).onSubmit { field = 1 }
                    SecureField("Password", text: $password)
                        .textContentType(creating ? UITextContentType.newPassword : UITextContentType.password)
                        .focused($field, equals: 1).submitLabel(.go).onSubmit(go)
                } footer: {
                    Text(creating ? "Use at least 6 characters. You may get an email to confirm the address first." : "")
                }
                Section {
                    Button(action: go) {
                        HStack {
                            Spacer()
                            if auth.busy == "email" { ProgressView() } else { Text(creating ? "Create account" : "Sign in").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(!valid || auth.busy != nil)
                    Button(creating ? "I already have an account" : "Create a new account") {
                        withAnimation(.smooth) { creating.toggle() }
                        auth.error = nil
                    }
                    if !creating {
                        Button("Forgot your password?") { Task { await auth.resetPassword(email.trimmingCharacters(in: .whitespaces)) } }
                            .disabled(!email.contains("@"))
                    }
                }
                if let e = auth.error {
                    Section { Text(e).font(.footnote).foregroundStyle(Theme.accent) }
                }
            }
            .oledBackground()
            .navigationTitle(creating ? "Create an account" : "Sign in with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
            .onAppear { field = 0 }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: auth.signedIn) { _, v in if v { dismiss() } }
    }

    private func go() {
        guard valid, auth.busy == nil else { return }
        auth.error = nil
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines), p = password, c = creating
        Task { await auth.email(e, password: p, create: c) }
    }
}

/// Which Supabase project Matinee signs in and syncs through. Empty fields go back to the one built into the app.
struct AccountServerForm: View {
    @Environment(Auth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var key = ""
    @State private var loaded = false

    private var builtIn: Bool { (Bundle.main.object(forInfoDictionaryKey: "MatineeSupabaseURL") as? String ?? "").contains(".") }

    var body: some View {
        Form {
            Section {
                TextField("https://your-project.supabase.co", text: $url)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("anon / publishable key", text: $key, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("Supabase project") } footer: {
                Text(builtIn ? "This build comes with an account server. Fill these in only to use your own; leave them empty to go back to the built-in one."
                     : "In supabase.com open your project → Project Settings → API, and copy the Project URL and the anon (publishable) key. Add matinee://auth-callback under Authentication → URL Configuration.")
            }
            if auth.signedIn {
                Section { Text("Changing the server signs you out. Your library stays on this iPhone.").font(.footnote).foregroundStyle(Theme.dim) }
            }
            Section {
                Link(destination: URL(string: "https://supabase.com/dashboard")!) { Label("Open Supabase", systemImage: "arrow.up.right") }
            }
        }
        .oledBackground()
        .navigationTitle("Account server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    auth.setServer(url: url, key: key)
                    Task { await auth.loadProviders() }
                    Library.shared.toast = Toast(text: auth.configured ? "Account server saved" : "Account server cleared", symbol: "server.rack")
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(!url.isEmpty && (URL(string: url.hasPrefix("http") ? url : "https://" + url)?.host == nil || key.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            url = UserDefaults.standard.string(forKey: "supabaseURL") ?? ""
            key = UserDefaults.standard.string(forKey: "supabaseKey") ?? ""
        }
    }
}

/// Slowly drifting columns of posters behind the sign-in screen.
struct PosterWall: View {
    let films: [FilmRef]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            let cols = 4
            let w = (geo.size.width + 60) / CGFloat(cols)
            let h = w * 1.5
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<cols, id: \.self) { c in
                        let column = stride(from: c, to: films.count, by: cols).map { films[$0] }
                        let loop = h * CGFloat(max(column.count, 1)) + 8 * CGFloat(column.count)
                        let speed = 9.0 + Double(c % 2) * 5
                        let offset = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(max(loop, 1))))
                        VStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { _ in
                                ForEach(column) { f in PosterView(film: f, width: w - 8, corner: 10, showTitleFallback: false) }
                            }
                        }
                        .offset(y: c % 2 == 0 ? -offset : offset - loop)
                    }
                }
                .frame(width: geo.size.width + 60, alignment: .leading)
                .offset(x: -30)
                .rotationEffect(.degrees(-8))
                .scaleEffect(1.15)
            }
            .opacity(films.isEmpty ? 0 : 0.85)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The app mark: a ticket with a play notch.
struct MatineeMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Theme.heart], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "ticket.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.black.opacity(0.85)).rotationEffect(.degrees(-12))
        }
        .shadow(color: Theme.accent.opacity(0.5), radius: 20)
    }
}
