import SwiftUI
import AuthenticationServices

struct SignInView: View {
    var asSheet = false
    @Environment(Auth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var posters: [FilmRef] = []
    @State private var showEmail = false
    @State private var showServer = false
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var serverURL = ""
    @State private var serverKey = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            PosterWall(films: posters).ignoresSafeArea()
            LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0), .init(color: .black.opacity(0.6), location: 0.35),
                                   .init(color: .black, location: 0.62)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: showEmail || showServer ? 80 : 280)
                    brand
                    if let e = auth.error {
                        Text(e).font(.footnote.weight(.medium)).foregroundStyle(Theme.accent).multilineTextAlignment(.center)
                            .padding(.horizontal, 12).transition(.opacity)
                    }
                    buttons
                    if showEmail { emailForm.transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if !auth.configured || showServer { serverSetup }
                    if !asSheet {
                        Button("Skip — keep everything on this iPhone") { auth.continueAsGuest() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .animation(.smooth, value: showEmail)
                .animation(.smooth, value: auth.error)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topTrailing) {
            if asSheet {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                    .padding(20)
            }
        }
        .task {
            serverURL = auth.serverURL; serverKey = auth.anonKey
            async let a = try? Catalog.shelf(.trending)
            async let b = try? Catalog.shelf(.topRated)
            let all = ((await a) ?? []) + ((await b) ?? [])
            withAnimation(.easeIn(duration: 0.8)) { posters = all }
        }
        .onChange(of: auth.signedIn) { _, v in if v && asSheet { dismiss() } }
    }

    private var brand: some View {
        VStack(spacing: 10) {
            MatineeMark().frame(width: 64, height: 64)
            Text("Matinee").font(.system(size: 44, weight: .heavy, design: .serif))
            Text("Every film you watch, kept beautifully.\nLog it, rate it, find what's next.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button { start(.apple) } label: {
                HStack(spacing: 8) { Image(systemName: "apple.logo"); Text("Continue with Apple") }
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .controlSize(.large)

            Button { start(.google) } label: {
                HStack(spacing: 10) {
                    Text("G").font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Continue with Google")
                }
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach([Auth.Provider.github, .discord, .twitter, .facebook, .azure, .spotify]) { p in
                        Button { start(p) } label: {
                            Text(p.mark).font(.system(size: p.mark.count > 1 ? 13 : 18, weight: .bold, design: .rounded))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("Continue with \(p.name)")
                    }
                }
            }

            Button { withAnimation { showEmail.toggle() } } label: {
                Label(showEmail ? "Hide email" : "Use email instead", systemImage: "envelope")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 2)

            if auth.busy != nil { ProgressView().tint(.white) }
        }
        .disabled(auth.busy != nil)
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
            SecureField("Password", text: $password)
                .textContentType(creating ? .newPassword : .password)
                .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
            Button {
                Task { await auth.email(email.trimmingCharacters(in: .whitespaces), password: password, create: creating) }
            } label: {
                Text(creating ? "Create account" : "Sign in").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(!email.contains("@") || password.count < 6)
            HStack {
                Button(creating ? "I have an account" : "New here? Create account") { creating.toggle() }
                Spacer()
                if !creating { Button("Forgot password") { Task { await auth.resetPassword(email) } }.disabled(!email.contains("@")) }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
        }
    }

    private var serverSetup: some View {
        DisclosureGroup(isExpanded: $showServer) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign-in runs through your own free Supabase project. Paste its Project URL and anon/publishable key — the README walks through turning on Google, Apple and the rest.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                TextField("https://xxxx.supabase.co", text: $serverURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(Theme.card, in: .rect(cornerRadius: 12))
                TextField("anon / publishable key", text: $serverKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(Theme.card, in: .rect(cornerRadius: 12))
                Button("Save server") {
                    auth.serverURL = serverURL; auth.anonKey = serverKey; auth.error = nil
                    withAnimation { showServer = false }
                }
                .buttonStyle(.glass)
                .disabled(URL(string: serverURL)?.host == nil || serverKey.isEmpty)
            }
            .padding(.top, 8)
        } label: {
            Label(auth.configured ? "Account server connected" : "Set up account server", systemImage: auth.configured ? "checkmark.circle.fill" : "server.rack")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(auth.configured ? Theme.watch : .white.opacity(0.8))
        }
        .tint(.white)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func start(_ p: Auth.Provider) {
        auth.error = nil
        guard let pending = auth.begin(p) else { withAnimation { showServer = true }; return }
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

/// Slowly drifting columns of posters behind the sign-in screen.
struct PosterWall: View {
    let films: [FilmRef]
    var body: some View {
        GeometryReader { geo in
            let cols = 4
            let w = (geo.size.width + 60) / CGFloat(cols)
            let h = w * 1.5
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
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
