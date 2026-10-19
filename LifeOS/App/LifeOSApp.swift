import SwiftUI
import BackgroundTasks
import UserNotifications

let pulseTaskID = "com.jm2kool.lifeos.pulse"

@main
struct LifeOSApp: App {
    @State private var store = Store.shared
    @State private var assistant = Assistant.shared
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
                    StudyActivityController.refresh(store)
                    await assistant.runPulse()
                }
            }
            if p == .background { StudyActivityController.refresh(store); schedulePulse(hours: assistant.intervalHours, store: store) }
        }
        .backgroundTask(.appRefresh(pulseTaskID)) {
            await MainActor.run { schedulePulse(hours: 2, store: store) }
            await store.pull(quiet: true)
            await MainActor.run { StudyActivityController.refresh(store) }
            await assistant.runPulse()
            await StudyAlerts.reschedule(store)
        }
    }
}

/// iOS decides the exact time; this asks for roughly every hour or two, or sooner when a study block is about to end
/// (so its Live Activity can turn into the break or "done").
@MainActor
func schedulePulse(hours: Int, store: Store? = nil) {
    var wait = hours > 0 ? Double(hours) * 3600 : 0
    if let store, let edge = store.timeline.filter({ StudyAlerts.isStudy($0) }).flatMap({ [$0.start, $0.end] }).filter({ $0 > Date() }).min() {
        let soon = max(60, edge.timeIntervalSinceNow + 30)
        wait = wait == 0 ? soon : min(wait, soon)
    }
    guard wait > 0 else { return }
    let r = BGAppRefreshTaskRequest(identifier: pulseTaskID)
    r.earliestBeginDate = Date(timeIntervalSinceNow: wait)
    try? BGTaskScheduler.shared.submit(r)
}
