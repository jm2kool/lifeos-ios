import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var phase

    private let store = Store.shared
    private let auth = Auth.shared
    private let router = Router.shared
    private let timer = FocusTimer.shared
    private let sync = SyncEngine.shared

    init() { Demo.prepare() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .environment(router)
                .environment(timer)
                .environment(sync)
                .modelContainer(store.container)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { router.handle($0) }
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active: Lifecycle.becameActive()
            case .background: Lifecycle.wentToBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Lifecycle.refreshID)) {
            await Lifecycle.backgroundRefresh()
        }
    }
}

/// What happens when the app opens, goes away, or is woken in the background.
@MainActor
enum Lifecycle {
    static let refreshID = "com.jm2kool.lumen.refresh"

    static func becameActive() {
        FocusTimer.shared.tick()
        _ = Store.shared.prefs
        Task {
            await CalendarSync.shared.run()
            await SyncEngine.shared.sync()
            Realtime.shared.connect()
            await Notifier.shared.reschedule()
            await WidgetBridge.refresh()
            await Files.uploadPending()
        }
    }

    static func wentToBackground() {
        Realtime.shared.disconnect()
        try? Store.shared.context.save()
        scheduleRefresh()
        Task { await WidgetBridge.refresh() }
    }

    /// Background App Refresh (there are no push notifications in a sideloaded app): pull Instinct's changes,
    /// then reschedule notifications and redraw widgets.
    static func backgroundRefresh() async {
        scheduleRefresh()
        await CalendarSync.shared.run()
        await SyncEngine.shared.sync()
        await Notifier.shared.reschedule()
        await WidgetBridge.refresh()
    }

    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { Notifier.shared.setUp() }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            let type = item.type
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                Router.shared.handleShortcut(type)
            }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        Task { @MainActor in Router.shared.handleShortcut(type) }
        completionHandler(true)
    }
}
