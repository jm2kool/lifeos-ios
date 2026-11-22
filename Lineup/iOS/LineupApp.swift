import SwiftUI

/// Lineup: your school timetable on your iPhone and Apple Watch.
@main
struct LineupApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(PhoneSync.shared)
        }
        .onChange(of: phase) { _, phase in
            guard phase == .active else { return }
            // Reminders are booked two weeks ahead, so top them up whenever the app comes back.
            store.scheduleReminders()
            PhoneSync.shared.push(store.timetable)
        }
    }
}

/// The four tabs.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "clock") { TodayView() }
            Tab("Week", systemImage: "calendar") { WeekView() }
            Tab("Homework", systemImage: "checklist") { HomeworkView() }
            Tab("Subjects", systemImage: "books.vertical") { SubjectsView() }
        }
    }
}
