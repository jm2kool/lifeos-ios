import SwiftUI
import AuthenticationServices

struct SignInView: View {
    var asSheet = false
    @Environment(Auth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var posters: [FilmRef] = []

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
                    Button(action: google) {
                        HStack(spacing: 10) {
                            if auth.busy == "google" { ProgressView().tint(.black) } else {
                                Text("G").font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                            Text("Continue with Google")
                        }
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .disabled(auth.busy != nil)

                    if !asSheet {
                        Button { auth.continueAsGuest() } label: {
                            Text("Use without an account").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 32)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
                Text(auth.error ?? (asSheet ? "Sign in to sync your diary, ratings and lists across devices."
                                            : "Without an account, everything stays on this iPhone. You can sign in later from your profile."))
                    .font(.footnote)
                    .foregroundStyle(auth.error == nil ? Theme.dim : Theme.accent)
                    .multilineTextAlignment(.center)
                    .animation(.smooth, value: auth.error)
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
        .task {
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

    private func google() {
        auth.error = nil
        guard let pending = auth.begin(.google) else { return }
        auth.busy = "google"
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
