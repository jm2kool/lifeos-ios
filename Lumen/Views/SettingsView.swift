import SwiftUI
import SwiftData
import UserNotifications

/// Settings, in a glass sheet.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Auth.self) private var auth
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let s = auth.session {
                        LabeledContent("Signed in", value: s.email ?? s.name ?? "Google")
                        LabeledContent("Sync", value: sync.summary)
                        Button("Sync now") { Task { await sync.sync() } }
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    } else {
                        Text("Using Lumen on this iPhone only.").foregroundStyle(.secondary)
                        Button("Sign in with Google") {
                            // The sign-in screen covers everything, so the sheet goes first.
                            dismiss()
                            Task { try? await Task.sleep(for: .seconds(0.6)); auth.offline = false }
                        }
                    }
                } header: { Text("Account") }

                Section("Study") {
                    NavigationLink { SubjectsList() } label: { LabeledContent("Subjects", value: "\(subjects.count)") }
                    NavigationLink { PreferencesView(prefs: store.prefs) } label: { Label("Planning preferences", systemImage: "slider.horizontal.3") }
                    NavigationLink { AvailabilityView() } label: { Label("When you're free", systemImage: "clock.badge.checkmark") }
                    NavigationLink { CalendarSettings() } label: { Label("iPhone calendar", systemImage: "calendar") }
                }

                Section {
                    Picker("Instinct's plans", selection: Binding(get: { store.prefs.planMode }, set: { store.prefs.planMode = $0; store.prefs.touch(); store.save() })) {
                        ForEach(PlanMode.allCases) { Text($0.label).tag($0) }
                    }
                    NavigationLink { AssistantsView() } label: { Label("Assistants & access keys", systemImage: "key") }
                    NavigationLink { WebhookView(prefs: store.prefs) } label: { Label("Webhook", systemImage: "arrow.up.forward.app") }
                } header: { Text("Instinct") } footer: {
                    Text(store.prefs.planMode == .auto ? "Instinct's plans go straight into your planner. Undo any of them from Planner → Activity."
                         : "Instinct's plans wait on Today for you to accept, edit or reject.")
                }

                Section("Focus & cards") {
                    NavigationLink { FocusSettings(prefs: store.prefs) } label: { Label("Pomodoro & blocking apps", systemImage: "timer") }
                    NavigationLink { StudyLockGuide() } label: { Label("Study lock", systemImage: "lock") }
                    NavigationLink { CardSettings(prefs: store.prefs) } label: { Label("Flashcards", systemImage: "rectangle.on.rectangle.angled") }
                    NavigationLink { NotificationSettings() } label: { Label("Notifications", systemImage: "bell.badge") }
                }

                Section("About") {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    LabeledContent("AI cards", value: "Claude, then Apple Intelligence")
                    LabeledContent("Apple Intelligence", value: CardMaker.onDeviceStatus)
                    LabeledContent("Widgets", value: SharedStore.hasSharedFolder ? "Shared folder" : "Through the server")
                    NavigationLink { ServerSettings() } label: { Label("Supabase project", systemImage: "server.rack") }
                }
            }
            .glassForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut) {
                Button("Sign out and clear this iPhone", role: .destructive) {
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        Realtime.shared.disconnect()
                        SyncEngine.shared.resetCursors()
                        auth.signOut()
                        store.wipeLocal()
                        UserDefaults.standard.removeObject(forKey: "auth.lastUser")
                    }
                }
            } message: { Text("Everything is safe in your account and comes back when you sign in again.") }
        }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// A Form that lets the glass sheet behind it show through.
    func glassForm() -> some View {
        self.scrollContentBackground(.hidden)
    }
}

// MARK: - Subjects

struct SubjectsList: View {
    @Environment(Store.self) private var store
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var editing: StudySubject?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(subjects) { s in
                Button { editing = s } label: {
                    HStack {
                        Image(systemName: s.icon).foregroundStyle(Color(hex: s.color)).frame(width: 28)
                        Text(s.name).foregroundStyle(.primary)
                        Spacer()
                        if s.byInstinct { InstinctBadge(compact: true) }
                    }
                }
            }
            .onMove { from, to in
                var list = subjects
                list.move(fromOffsets: from, toOffset: to)
                for (i, s) in list.enumerated() where s.sort != i { s.sort = i; s.touch() }
                store.save()
            }
            .onDelete { idx in for i in idx { store.remove(subjects[i]) } }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Subjects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { s in NavigationStack { SubjectEditor(subject: s) }.preferredColorScheme(.dark) }
        .sheet(isPresented: $adding) { NavigationStack { SubjectEditor(subject: nil) }.preferredColorScheme(.dark) }
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @Bindable var prefs: UserPrefs
    @Environment(Store.self) private var store
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        Form {
            Section {
                Stepper("Up to \(Fmt.hours(prefs.maxHoursPerDay)) a day", value: $prefs.maxHoursPerDay, in: 0.5...14, step: 0.5)
                Stepper("Blocks of \(prefs.blockMinutes) min", value: $prefs.blockMinutes, in: 15...180, step: 5)
                Stepper("Breaks of \(prefs.breakMinutes) min", value: $prefs.breakMinutes, in: 0...60, step: 5)
                Stepper("Daily goal \(Fmt.minutes(prefs.dailyGoalMinutes))", value: $prefs.dailyGoalMinutes, in: 15...720, step: 15)
            } header: { Text("How much") }
            Section {
                TimeField(title: "Earliest", value: $prefs.earliestTime)
                TimeField(title: "Latest", value: $prefs.latestTime)
            } header: { Text("When") } footer: { Text("Nothing is planned outside these times.") }
            Section {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { d in
                        let off = prefs.noStudyDays.contains(d)
                        Button {
                            if off { prefs.noStudyDays.removeAll { $0 == d } } else { prefs.noStudyDays.append(d) }
                            Haptics.select()
                        } label: {
                            Text(days[d]).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(off ? .regular.tint(Theme.bad.opacity(0.45)) : .regular, in: .capsule)
                    }
                }
            } header: { Text("No-study days") } footer: { Text("Tap a day to keep it free of study.") }
            Section {
                LabeledContent("Time zone", value: prefs.timezone)
                Button("Use this iPhone's time zone") { prefs.timezone = TimeZone.current.identifier }
            } footer: { Text("Instinct plans in this time zone.") }
        }
        .glassForm()
        .navigationTitle("Planning")
        .onDisappear { prefs.touch(); store.save() }
    }
}

/// An "HH:mm" setting edited with a time picker.
struct TimeField: View {
    var title: String
    @Binding var value: String
    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Clock.date(value, on: Date()) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                value = Clock.string((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Availability

struct AvailabilityView: View {
    @Environment(Store.self) private var store
    @Query(filter: #Predicate<AvailabilityWindow> { !$0.trashed }, sort: \AvailabilityWindow.startTime) private var windows: [AvailabilityWindow]
    @Query(filter: #Predicate<BusySlot> { !$0.trashed }, sort: \BusySlot.startAt) private var busy: [BusySlot]
    private let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    @State private var addingBusy = false

    var body: some View {
        Form {
            Section {
                Text("Free windows are when you can study each week; busy windows are regular things like school or practice. With no free windows at all, Lumen uses your earliest–latest times every day.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Fill in school days (16:00–21:00 weekdays, 10:00–18:00 weekends)") { quickFill() }
                    .font(.subheadline)
            }
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in
                Section(names[d]) {
                    ForEach(windows.filter { $0.weekday == d }) { w in WindowRow(window: w) }
                        .onDelete { idx in
                            let list = windows.filter { $0.weekday == d }
                            for i in idx { store.remove(list[i]) }
                        }
                    HStack {
                        Button("Add free time") { add(d, free: true) }
                        Spacer()
                        Button("Add busy time") { add(d, free: false) }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            }
            Section {
                ForEach(busy.filter { $0.source == "manual" && $0.endAt > Date() }) { b in
                    VStack(alignment: .leading) {
                        Text(b.title ?? "Busy")
                        Text("\(Fmt.day(b.startAt)) \(Fmt.span(b.startAt, b.endAt))").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { store.remove(b) } }
                }
                Button("Add a one-off busy time") { addingBusy = true }
            } header: { Text("One-off busy times") } footer: { Text("Calendar events are added automatically when the iPhone calendar is on.") }
        }
        .glassForm()
        .navigationTitle("When you're free")
        .sheet(isPresented: $addingBusy) { NavigationStack { BusySlotEditor() }.presentationDetents([.medium]).preferredColorScheme(.dark) }
    }

    private func add(_ day: Int, free: Bool) {
        let w = AvailabilityWindow(id: UUID())
        w.weekday = day
        w.kindRaw = free ? "free" : "busy"
        w.startTime = free ? "16:00" : "09:00"
        w.endTime = free ? "20:00" : "15:30"
        w.label = free ? nil : "School"
        store.insert(w)
        store.save()
    }

    private func quickFill() {
        for w in windows where w.isFree { w.trashed = true; w.touch() }
        for d in 0..<7 {
            let w = AvailabilityWindow(id: UUID())
            w.weekday = d
            w.kindRaw = "free"
            w.startTime = (d == 0 || d == 6) ? "10:00" : "16:00"
            w.endTime = (d == 0 || d == 6) ? "18:00" : "21:00"
            store.insert(w)
        }
        store.save()
        Haptics.success()
    }
}

struct WindowRow: View {
    @Bindable var window: AvailabilityWindow
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: window.isFree ? "checkmark.circle" : "lock").foregroundStyle(window.isFree ? Theme.good : .secondary)
                if window.isFree { Text("Free") } else {
                    TextField("Busy with…", text: Binding(get: { window.label ?? "" }, set: { window.label = $0.isEmpty ? nil : $0 }))
                }
                if window.byInstinct { InstinctBadge(compact: true) }
            }
            HStack {
                TimeField(title: "From", value: $window.startTime).labelsHidden()
                Text("to").foregroundStyle(.secondary)
                TimeField(title: "To", value: $window.endTime).labelsHidden()
            }
        }
        .onChange(of: window.startTime) { _, _ in window.touch(); store.save() }
        .onChange(of: window.endTime) { _, _ in window.touch(); store.save() }
        .onChange(of: window.label) { _, _ in window.touch(); store.save() }
    }
}

struct BusySlotEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    var body: some View {
        Form {
            TextField("What (optional)", text: $title)
            DatePicker("Starts", selection: $start)
            DatePicker("Ends", selection: $end, in: start...)
        }
        .glassForm()
        .navigationTitle("Busy")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let b = BusySlot(id: UUID())
                    b.title = title.isEmpty ? nil : title
                    b.startAt = start
                    b.endAt = max(end, start.addingTimeInterval(300))
                    b.source = "manual"
                    store.insert(b)
                    store.save()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Calendar

struct CalendarSettings: View {
    @Bindable private var cal = CalendarSync.shared
    @Environment(Store.self) private var store

    var body: some View {
        Form {
            Section {
                if cal.authorized {
                    Toggle("Use my calendars", isOn: Binding(get: { cal.enabled }, set: { on in cal.enabled = on; if !on { cal.clear() } }))
                    Toggle("Count all-day events as busy", isOn: $cal.includeAllDay)
                        .onChange(of: cal.includeAllDay) { _, _ in Task { await cal.run() } }
                    Toggle("Share event titles with Instinct", isOn: Binding(get: { store.prefs.shareCalendarTitles }, set: {
                        store.prefs.shareCalendarTitles = $0; store.prefs.touch(); store.save(); Task { await cal.run() }
                    }))
                    if let last = cal.lastRun {
                        LabeledContent("Last read", value: "\(last.formatted(.relative(presentation: .named))) · \(cal.lastCount) events")
                    }
                    Button("Read now") { Task { await cal.run() } }
                } else {
                    Text("Lumen reads when you're busy so it never plans over class or plans. Only start and end times are synced, unless you allow titles.")
                        .font(.subheadline)
                    Button("Allow calendar access") { Task { _ = await cal.requestAccess() } }
                    if cal.status == .denied { Text("Access is off — turn it on in Settings → Privacy & Security → Calendars.").font(.caption).foregroundStyle(Theme.warn) }
                }
            }
            if cal.authorized && cal.enabled {
                Section("Calendars to use") {
                    ForEach(cal.calendars, id: \.calendarIdentifier) { c in
                        Toggle(isOn: Binding(get: { !cal.excluded.contains(c.calendarIdentifier) }, set: { on in
                            if on { cal.excluded.remove(c.calendarIdentifier) } else { cal.excluded.insert(c.calendarIdentifier) }
                            Task { await cal.run() }
                        })) {
                            HStack { Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10); Text(c.title) }
                        }
                    }
                }
            }
        }
        .glassForm()
        .navigationTitle("iPhone calendar")
    }
}

// MARK: - Focus, cards, notifications

struct FocusSettings: View {
    @Bindable var prefs: UserPrefs
    @Environment(Store.self) private var store
    @Bindable private var shield = FocusShield.shared
    var body: some View {
        Form {
            Section("Pomodoro") {
                Stepper("Focus \(prefs.pomodoroFocus) min", value: $prefs.pomodoroFocus, in: 5...120, step: 5)
                Stepper("Short break \(prefs.pomodoroShort) min", value: $prefs.pomodoroShort, in: 1...30)
                Stepper("Long break \(prefs.pomodoroLong) min", value: $prefs.pomodoroLong, in: 5...60, step: 5)
                Stepper("Long break every \(prefs.pomodoroRounds) rounds", value: $prefs.pomodoroRounds, in: 1...8)
            }
            Section {
                if shield.available {
                    Toggle("Block apps during focus", isOn: Binding(get: { shield.enabled && shield.authorized }, set: { on in
                        if on && !shield.authorized { Task { await shield.authorize(); shield.enabled = shield.authorized } } else { shield.enabled = on }
                    }))
                    #if canImport(FamilyControls)
                    if shield.authorized { ShieldPicker() }
                    #endif
                } else {
                    Text("Screen Time blocking needs Apple's Family Controls entitlement, which this build doesn't have (it can't be added with a free Apple ID). Use the study lock below instead.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Screen Time shield") }
            Section {
                NavigationLink { StudyLockGuide() } label: {
                    LabeledContent("Study lock", value: StudyLock.enabled ? "On" : "Off")
                }
            } header: { Text("Study lock") } footer: {
                Text("Works with a free Apple ID: a Shortcuts automation brings you back to Lumen when you open a distracting app during study time.")
            }
        }
        .glassForm()
        .navigationTitle("Focus")
        .onDisappear { prefs.touch(); store.save() }
    }
}

struct CardSettings: View {
    @Bindable var prefs: UserPrefs
    @Environment(Store.self) private var store
    var body: some View {
        Form {
            Section {
                Stepper("\(prefs.newCardsPerDay) new cards a day", value: $prefs.newCardsPerDay, in: 0...200, step: 5)
                VStack(alignment: .leading) {
                    Text("Remember \(Int(prefs.desiredRetention * 100))% of cards")
                    Slider(value: $prefs.desiredRetention, in: 0.8...0.95, step: 0.01)
                }
                TimeField(title: "Daily review reminder", value: $prefs.reviewTime)
            } footer: {
                Text("Higher retention means more reviews. 90% is a good balance.")
            }
        }
        .glassForm()
        .navigationTitle("Flashcards")
        .onDisappear { prefs.touch(); store.save() }
    }
}

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var tick = 0
    var body: some View {
        Form {
            if status != .authorized && status != .provisional {
                Section {
                    Button("Allow notifications") {
                        Task { _ = await Notifier.shared.requestPermission(); await refresh(); await Notifier.shared.reschedule() }
                    }
                    if status == .denied { Text("Turn notifications on for Lumen in the Settings app.").font(.caption).foregroundStyle(Theme.warn) }
                }
            }
            Section {
                ForEach(Notifier.Kind.allCases) { k in
                    Toggle(k.label, isOn: Binding(get: { _ = tick; return Notifier.shared.isOn(k) }, set: { Notifier.shared.set(k, $0); tick += 1 }))
                }
            } footer: { Text("Block notifications have a Start focus button. They update by themselves when Instinct changes the plan.") }
            Section {
                Label(Push.shared.summary, systemImage: Push.shared.state == .on ? "bell.and.waves.left.and.right" : "bell.slash")
                    .font(.subheadline)
                if let env = Push.shared.environment { LabeledContent("APNs", value: env) }
            } header: { Text("Push from the server") } footer: {
                Text("Pushes tell you when Instinct has a new plan or adds work, keep reminders in step, and start the study block Live Activity before each block.")
            }
        }
        .glassForm()
        .navigationTitle("Notifications")
        .task { await refresh() }
    }

    private func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}

// MARK: - Webhook & server

struct WebhookView: View {
    @Bindable var prefs: UserPrefs
    @Environment(Store.self) private var store
    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $prefs.webhookURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    SecureField("Signing secret", text: $prefs.webhookSecret)
                    Button("Generate") { prefs.webhookSecret = Auth.randomString(40) }.buttonStyle(.borderless)
                }
            } footer: {
                Text("When you finish, miss or change something, Supabase POSTs the event as JSON to this address with an X-Lumen-Signature header (sha256 HMAC of the body with the secret). Instinct's own changes aren't sent back to it.")
            }
        }
        .glassForm()
        .navigationTitle("Webhook")
        .onDisappear { prefs.touch(); store.save() }
    }
}

struct ServerSettings: View {
    @Environment(Auth.self) private var auth
    @State private var url = ""
    @State private var key = ""
    var body: some View {
        Form {
            Section {
                TextField("https://your-project.supabase.co", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Anon (publishable) key", text: $key)
                Button("Save") { auth.setServer(url: url, key: key) }
            } footer: {
                Text(auth.serverIsCustom ? "Using the project typed here." : "Built into the app from GitHub Secrets. Typing a project here overrides it; clear both fields to go back.")
            }
            Section("Instinct's address") {
                Text(auth.agentURL).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .glassForm()
        .navigationTitle("Supabase project")
        .onAppear { url = auth.serverURL; key = auth.anonKey }
    }
}
