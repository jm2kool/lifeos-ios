import SwiftUI
import BackgroundTasks
import UserNotifications

let pulseTaskID = "com.jm2kool.lifeos.pulse"

@main
struct LifeOSApp: App {
    @State private var store = Store.shared
    @State private var assistant = Assistant()
    @State private var focus = FocusTimer.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        StudyAlerts.registerCategories()
    }
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(assistant)
                .environment(focus)
                .tint(store.tint)
                .preferredColorScheme(store.scheme)
                .onAppear {
                    assistant.store = store
                    focus.store = store
                    if ProcessInfo.processInfo.environment["LIFEOS_PREVIEW"] == nil {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                    }
                }
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                Task {
                    await store.pull(quiet: true)
                    focus.checkFinished()
                    await assistant.runPulse()
                }
            }
            if p == .background { schedulePulse(hours: assistant.intervalHours) }
        }
        .backgroundTask(.appRefresh(pulseTaskID)) {
            await MainActor.run { schedulePulse(hours: 2) }
            await store.pull(quiet: true)
            await assistant.runPulse()
            await StudyAlerts.reschedule(store)
        }
    }
}

/// iOS decides the exact time; this asks for roughly every hour or two.
func schedulePulse(hours: Int) {
    guard hours > 0 else { return }
    let r = BGAppRefreshTaskRequest(identifier: pulseTaskID)
    r.earliestBeginDate = Date(timeIntervalSinceNow: Double(hours) * 3600)
    try? BGTaskScheduler.shared.submit(r)
}
