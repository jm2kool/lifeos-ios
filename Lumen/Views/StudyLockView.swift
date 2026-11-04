import SwiftUI

/// Shown when the study lock sends you back here from another app.
struct StudyLockView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(FocusTimer.self) private var timer
    @Namespace private var ns

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let session = StudyLock.current(now: ctx.date)
            let color = store.color(for: session?.subjectID)
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: session == nil ? "checkmark.circle" : "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 84, height: 84)
                    .glassEffect(.regular.tint(color.opacity(0.3)), in: .circle)
                    .padding(.bottom, 6)
                Text(session == nil ? "No study block right now" : "You're meant to be studying")
                    .font(.headline).foregroundStyle(.secondary)
                if let s = session {
                    Text(s.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if !s.goal.isEmpty && s.goal != s.title {
                        Label(s.goal, systemImage: "target").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Text(left(until: s.end, from: ctx.date))
                        .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .padding(.top, 8)
                    Text("left, until \(Fmt.time(s.end))").foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if let s = session, !s.focusing {
                            Button {
                                if let id = s.blockID { router.openFocus(block: id) }
                                timer.start()
                                close()
                            } label: { Label("Start focus", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent).tint(color).controlSize(.large)
                            .glassEffectID("focus", in: ns)
                        }
                        Button { close() } label: { Text(session == nil ? "Close" : "Back to it").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass).controlSize(.large)
                            .glassEffectID("back", in: ns)
                    }
                }
                if session != nil {
                    Button("Take a five-minute break") { StudyLock.snooze(minutes: 5); close() }
                        .font(.subheadline).padding(.top, 6).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Aurora(colors: [color, Theme.instinct], intensity: 0.45) }
        }
        .sensoryFeedback(.warning, trigger: router.lockShown)
        .preferredColorScheme(.dark)
    }

    private func close() { withAnimation(.smooth(duration: 0.4)) { router.lockShown = false } }

    private func left(until end: Date, from now: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(now)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// How to set up the Shortcuts automation that powers the study lock.
struct StudyLockGuide: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var on = StudyLock.enabled

    var body: some View {
        Form {
            Section {
                Toggle("Study lock", isOn: $on)
                    .onChange(of: on) { _, v in StudyLock.enabled = v }
            } footer: {
                Text("While a study block or focus round is on, opening a distracting app sends you straight back to Lumen. Outside study time nothing happens. Blocking apps through Screen Time needs a paid Apple Developer account, so this uses a Shortcuts automation instead — it works with a free Apple ID.")
            }
            Section("Set it up once") {
                step(1, "Open the Shortcuts app, go to Automation and tap +.")
                step(2, "Choose App, pick the apps that distract you, tick Is Opened and choose Run Immediately.")
                step(3, "Tap Next, search for Lumen and add Study lock check. Done.")
                Button("Open Shortcuts") { if let u = URL(string: "shortcuts://") { UIApplication.shared.open(u) } }
            }
            Section {
                step(4, "If iOS asks for permission each time, use: Is it study time? → If (Value is true) → Open study lock.")
            } header: { Text("If it asks every time") }
            Section {
                step(5, "For the Dynamic Island before your blocks without opening Lumen: Automation → Time of Day (e.g. 15:50 on school days) → Show next study block.")
            } header: { Text("Live Activity without opening the app") }
            Section {
                Button("Preview the lock screen") {
                    dismiss()
                    router.sheet = nil
                    Task { try? await Task.sleep(for: .milliseconds(700)); router.showLock() }
                }
                if let until = StudyLock.snoozedUntil {
                    LabeledContent("On a break until", value: Fmt.time(until))
                    Button("End the break") { StudyLock.clearSnooze() }
                }
            } footer: {
                Text("“Take a five-minute break” on the lock screen pauses it for five minutes.")
            }
        }
        .glassForm()
        .navigationTitle("Study lock")
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent).frame(width: 18)
            Text(text)
        }
    }
}
