import SwiftUI

/// The day at a glance: what's on now, the rest of today, homework due and what to pack.
struct TodayView: View {
    @EnvironmentObject private var store: Store
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let plan = DayPlan(store.timetable, now: context.date)
                List {
                    if store.timetable.lessons.isEmpty {
                        GettingStarted()
                    } else {
                        Section { NowCard(plan: plan, timetable: store.timetable) }

                        if !plan.slots.isEmpty {
                            Section("Today") {
                                ForEach(plan.slots) { slot in
                                    SlotRow(slot: slot, now: context.date)
                                }
                            }
                        }

                        let open = store.timetable.openAssignments
                        if !open.isEmpty {
                            Section("Homework") {
                                ForEach(open.prefix(4)) { assignment in
                                    AssignmentRow(assignment: assignment)
                                }
                            }
                        }

                        if !plan.packGroups.isEmpty || !plan.handIn.isEmpty {
                            Section(plan.packTitle) { PackList(plan: plan) }
                        }
                    }
                }
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide)))
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

/// The big card at the top: the lesson on now, or the next one.
struct NowCard: View {
    let plan: DayPlan
    let timetable: Timetable

    var body: some View {
        if let slot = plan.focus {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.label(for: slot))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(slot.colour)
                Text(slot.name).font(.largeTitle.bold())
                Text([slot.room, slot.teacher, Clock.range(slot.start, slot.end)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                if slot.isNow(plan.now) {
                    ProgressView(value: slot.progress(plan.now)).tint(slot.colour)
                    Text("Ends in \(Text(timerInterval: plan.now...slot.end, countsDown: true))")
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text("Starts \(Text(slot.start, style: .relative)) from now")
                        .font(.subheadline)
                }
                if let next = plan.upcoming.first(where: { $0.id != slot.id }) {
                    Text("Then \(next.name) at \(Clock.time(next.start))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !slot.bring.isEmpty {
                    Label(slot.bring.joined(separator: ", "), systemImage: "backpack")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.isOver ? "That's school done for today" : "No lessons today")
                    .font(.title2.bold())
                if let day = timetable.nextSchoolDay(after: plan.now), let first = timetable.slots(on: day).first {
                    Text("\(Clock.relativeDay(day, now: plan.now)): \(first.name) at \(Clock.time(first.start))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// One lesson in a list of the day.
struct SlotRow: View {
    let slot: Slot
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(slot.colour).frame(width: 6, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(.headline)
                if !slot.room.isEmpty { Text(slot.room).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Clock.time(slot.start)).font(.subheadline.monospacedDigit())
                Text(Clock.time(slot.end)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .opacity(slot.end <= now ? 0.45 : 1)
        .listRowBackground(slot.isNow(now) ? slot.colour.opacity(0.15) : nil)
    }
}

/// What to put in your bag for the next school day.
struct PackList: View {
    let plan: DayPlan

    var body: some View {
        ForEach(plan.packGroups) { group in
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(group.subject.colour.color).frame(width: 10, height: 10)
                VStack(alignment: .leading) {
                    Text(group.subject.name).font(.subheadline.weight(.semibold))
                    if !group.items.isEmpty {
                        Text(group.items.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        ForEach(plan.handIn) { assignment in
            Label("Hand in: \(assignment.title)", systemImage: "tray.and.arrow.up")
                .font(.subheadline)
        }
    }
}

/// Shown until there's a timetable.
struct GettingStarted: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text("Put your timetable on your wrist").font(.title2.bold())
                Text("Add your subjects, then your lessons in the Week tab. Your Apple Watch gets a copy and keeps working without your phone or the internet.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            Button("Try an example timetable") { store.timetable = .example() }
        }
    }
}
