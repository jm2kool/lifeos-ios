import SwiftUI
import AuthenticationServices

/// The first screen: sign in with Google so your study plan syncs and Instinct can reach it.
struct SignInView: View {
    @Environment(Auth.self) private var auth
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var showServer = false
    @State private var url = ""
    @State private var key = ""
    @Namespace private var ns

    var body: some View {
        ZStack {
            Aurora(colors: [Theme.accent, Theme.instinct, Color(hex: "#5CC8FF")], intensity: 0.55)
            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle().fill(Color.clear).frame(width: 120, height: 120)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.3)), in: .circle)
                    Image(systemName: "sparkles").font(.system(size: 48, weight: .semibold)).foregroundStyle(.white)
                        .symbolEffect(.breathe)
                }
                VStack(spacing: 6) {
                    Text("Lumen").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Your study plan, run by Instinct.").font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                if !auth.configured || showServer { serverFields }
                if let e = auth.error {
                    Text(e).font(.footnote).foregroundStyle(Theme.warn).multilineTextAlignment(.center).padding(.horizontal)
                }
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button { Task { await signIn() } } label: {
                            HStack(spacing: 10) {
                                if auth.busy { ProgressView() } else { Text("G").font(.headline.weight(.heavy)) }
                                Text("Continue with Google").font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.extraLarge)
                        .disabled(auth.busy || !auth.configured)
                        .glassEffectID("google", in: ns)
                        Button("Use on this iPhone only") { auth.useOffline() }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .glassEffectID("offline", in: ns)
                    }
                }
                .padding(.horizontal, 24)
                Button(showServer ? "Hide server settings" : "Server settings") { withAnimation(.snappy) { showServer.toggle() } }
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .onAppear { url = auth.serverURL; key = auth.anonKey }
    }

    private var serverFields: some View {
        VStack(spacing: 8) {
            TextField("https://your-project.supabase.co", text: $url)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Anon (publishable) key", text: $key)
            Button("Save server") { auth.setServer(url: url, key: key) }
                .buttonStyle(.glass)
                .disabled(url.isEmpty || key.isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func signIn() async {
        guard let pending = auth.beginGoogle() else { return }
        do {
            let callback = try await webAuth.authenticate(using: pending.url, callbackURLScheme: Auth.callbackScheme)
            await auth.finish(callback: callback, verifier: pending.verifier)
            if auth.signedIn { Haptics.success() }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                auth.error = "Sign-in didn't finish: \(error.localizedDescription)"
            }
        }
    }
}
