import SwiftUI

/// Settings → Update: the build on this phone, the newest one on GitHub, and ways to install it without a
/// computer (SideStore or AltStore), or the .ipa itself for Sideloadly.
struct UpdateView: View {
    @Environment(\.openURL) private var openURL
    @State private var message: String?
    private var updater: AppUpdater { AppUpdater.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("On this iPhone", value: "\(updater.installedVersion) (\(updater.installedBuild))")
                if let latest = updater.latest {
                    LabeledContent("Newest build", value: "\(latest.version) (\(latest.build))")
                    if let date = latest.date {
                        LabeledContent("Built", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let notes = latest.notes, !notes.isEmpty { Text(notes).font(.footnote).foregroundStyle(.secondary) }
                }
                Button(updater.state == .checking ? "Checking…" : "Check for updates", systemImage: "arrow.clockwise") {
                    Task { await updater.check() }
                }
                .disabled(updater.state == .checking)
            } footer: { Text(status) }

            if let latest = updater.latest {
                Section {
                    ForEach(AppUpdater.Installer.allCases) { installer in
                        Button("\(updater.isAvailable ? "Update" : "Reinstall") with \(installer.rawValue)", systemImage: "arrow.down.app") {
                            Task {
                                let opened = await updater.install(with: installer)
                                message = opened ? nil : "\(installer.rawValue) isn't on this iPhone."
                            }
                        }
                    }
                    Button("Download the .ipa", systemImage: "arrow.down.circle") { openURL(latest.ipa) }
                    ShareLink("Send the .ipa link", item: latest.ipa)
                } header: { Text("Install") } footer: {
                    Text("iOS doesn't let an app update itself, so the build goes to an installer that signs it on the phone with your Apple ID. SideStore needs a computer once, to set it up; after that updates and the 7-day refresh happen on the phone. Without one, download the .ipa and use Sideloadly as before.")
                }
                if latest.source != nil {
                    Section {
                        ForEach(AppUpdater.Installer.allCases) { installer in
                            Button("Add \(AppBrand.name) to \(installer.rawValue)", systemImage: "plus.app") {
                                Task {
                                    let opened = await updater.follow(in: installer)
                                    message = opened ? nil : "\(installer.rawValue) isn't on this iPhone."
                                }
                            }
                        }
                    } header: { Text("Follow updates") } footer: {
                        Text("Adds \(AppBrand.name)'s source, so the installer lists new builds on its own.")
                    }
                }
            }
            if let message { Section { Text(message).font(.footnote).foregroundStyle(.orange) } }
        }
        .navigationTitle("Update")
        .navigationBarTitleDisplayMode(.inline)
        .task { if updater.latest == nil { await updater.check() } }
    }

    private var status: String {
        switch updater.state {
        case .idle, .checking: "Builds come from GitHub each time the code changes."
        case .upToDate: "You have the newest build."
        case .available: "A newer build is ready. Export a backup first (Settings → Backup) if this is your first update through an installer."
        case .failed(let why): why
        }
    }
}

#Preview { NavigationStack { UpdateView() }.preferredColorScheme(.dark) }
