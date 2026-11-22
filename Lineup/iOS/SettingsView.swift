import SwiftUI
import WatchConnectivity

/// School days, two-week timetables, reminders and the watch.
struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: PhoneSync
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Reminders.onKey) private var remindersOn = false
    @AppStorage(Reminders.leadKey) private var lead = 2
    @State private var confirmExample = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            Form {
                Section("School days") {
                    ForEach(Clock.mondayFirst, id: \.self) { day in
                        Toggle(Clock.dayName(day), isOn: Binding(
                            get: { store.timetable.schoolDays.contains(day) },
                            set: { on in
                                store.timetable.schoolDays.removeAll { $0 == day }
                                if on { store.timetable.schoolDays.append(day) }
                            }))
                    }
                }

                Section {
                    Toggle("Two-week timetable", isOn: $store.timetable.twoWeeks)
                    if store.timetable.twoWeeks {
                        Picker("This week is", selection: Binding(
                            get: { store.timetable.weekIndex(on: .now) },
                            set: { index in
                                let thisWeek = Timetable.startOfWeek(.now)
                                store.timetable.weekAStart = index == 0
                                    ? thisWeek
                                    : Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
                            })) {
                            Text("Week A").tag(0)
                            Text("Week B").tag(1)
                        }
                    }
                } footer: {
                    Text("For schools where the timetable alternates between a Week A and a Week B.")
                }

                Section {
                    Toggle("Heads-up before each lesson", isOn: $remindersOn)
                    if remindersOn {
                        Picker("How early", selection: $lead) {
                            ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                } footer: {
                    Text("A notification with the room and what to bring. It shows on your watch when your phone is locked. Reminders are booked two weeks ahead, so open Lineup now and then to keep them coming.")
                }

                Section("Apple Watch") {
                    Text(sync.status).foregroundStyle(.secondary)
                    if let lastSent = sync.lastSent {
                        LabeledContent("Last sent", value: lastSent.formatted(date: .omitted, time: .shortened))
                    }
                    Button("Send to watch now") { sync.push(store.timetable) }
                }

                Section {
                    Button("Load the example timetable") {
                        if store.timetable.isEmpty { store.timetable = .example() } else { confirmExample = true }
                    }
                    Button("Erase everything", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Everything stays on your iPhone and Apple Watch. There's no account, and nothing needs the internet.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: remindersOn) { _, on in
                Task {
                    if on, !(await Reminders.requestPermission()) { remindersOn = false }
                    store.scheduleReminders()
                }
            }
            .onChange(of: lead) { _, _ in store.scheduleReminders() }
            .confirmationDialog("Replace your timetable with the example?", isPresented: $confirmExample, titleVisibility: .visible) {
                Button("Replace", role: .destructive) { store.timetable = .example() }
            }
            .confirmationDialog("Erase your timetable, subjects and homework?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { store.timetable = Timetable() }
            }
        }
    }
}
