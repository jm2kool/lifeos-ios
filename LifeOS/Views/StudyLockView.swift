import SwiftUI

/// Shown when the study lock sends you back here from another app.
struct StudyLockView: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let block = store.currentStudy
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: block == nil ? "checkmark.circle" : "book.closed")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 6)
                Text(block == nil ? "No study block right now" : "You're meant to be studying")
                    .font(.headline).foregroundStyle(.secondary)
                if let b = block {
                    Text(b.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(left(until: b.end, from: ctx.date))
                        .font(UI.number(64))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.top, 8)
                    Text("left, until \(store.time(b.end))").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 12) {
                    if let b = block, !focus.running {
                        Button {
                            let mins = Int(b.end.timeIntervalSince(ctx.date) / 60)
                            focus.start(minutes: max(5, min(240, mins)), label: b.title)
                            close()
                        } label: { Text("Start focus timer").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    Button { close() } label: { Text(block == nil ? "Close" : "Back to it").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass).controlSize(.large)
                    if block != nil {
                        Button("Take a five-minute break") { StudyLock.snooze(minutes: 5); close() }
                            .font(.subheadline).padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackground(palette: .study) }
            .tint(.green)
        }
        .sensoryFeedback(.warning, trigger: store.lockShown)
    }

    private func close() { withAnimation(.smooth(duration: 0.4)) { store.lockShown = false } }

    private func left(until end: Date, from now: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(now)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// How to set up the Shortcuts automation that powers the study lock.
struct StudyLockGuide: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                Text("While one of your study blocks is on, opening a distracting app sends you straight back here. Outside study blocks nothing happens. Apple only lets apps block other apps through Screen Time with a paid developer account, so this uses a Shortcuts automation instead.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Set it up once") {
                step(1, "Open the Shortcuts app, go to Automation and tap +.")
                step(2, "Choose App, pick the apps that distract you, tick Is Opened and choose Run Immediately.")
                step(3, "Tap Next, search for LifeOS and add Study lock check. Done.")
                Button("Open Shortcuts") { if let u = URL(string: "shortcuts://") { UIApplication.shared.open(u) } }
            }
            Section {
                step(4, "If iOS asks for permission each time, swap the action for: Is it study time? → If (Value is true) → Open study lock.")
            } header: { Text("If it asks every time") }
            Section {
                Button("Preview the lock screen") {
                    store.sheet = nil
                    Task { try? await Task.sleep(for: .milliseconds(600)); store.lockShown = true }
                }
            } footer: {
                Text("“Take a five-minute break” on the lock screen pauses it for five minutes.")
            }
        }
        .navigationTitle("Study lock")
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.tint).frame(width: 18)
            Text(text)
        }
    }
}
