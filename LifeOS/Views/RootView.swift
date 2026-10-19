import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            ForEach(store.barTabs, id: \.self) { t in
                Tab(t.title, systemImage: t.symbol, value: t) { screen(t) }
                    .badge(barBadge(t))
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) {
                NavigationStack(path: $store.libraryPath) { LibraryView().voiceCaptureButton() }.environment(\.ambientPalette, .library)
            }
            .badge(store.moreTabs.contains(.drafts) ? store.pendingDrafts.count : 0)
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().voiceCaptureButton() }.environment(\.ambientPalette, .search)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NowAccessory() }
        .fullScreenCover(isPresented: $store.lockShown) {
            StudyLockView().environment(store).environment(focus).tint(store.tint)
        }
        .task(id: store.studyAlertKey) { await StudyAlerts.reschedule(store); StudyActivityController.refresh(store) }
        .sheet(item: $store.sheet) { route in
            SheetHost(route: route)
                .environment(store).environment(assistant).environment(focus)
                .tint(store.tint)
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(toast: t)
                    .padding(.top, 6)
                    .task(id: t.id) {
                        try? await Task.sleep(for: .seconds(t.undo ? 4.5 : 2.4))
                        withAnimation(.smooth(duration: 0.4)) { if store.toast?.id == t.id { store.toast = nil } }
                    }
            }
        }
        .animation(.smooth(duration: 0.4), value: store.toast)
        .task {
            if store.profileName.isEmpty { store.sheet = .onboarding }
            await previewMode()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                store.tick = Date()
                focus.checkFinished()
                StudyActivityController.refresh(store)
            }
        }
    }
}

extension RootView {
    /// One tab's screen. Today, Inbox and Study keep their own navigation; a page from More gets a stack of its own.
    @ViewBuilder func screen(_ t: AppTab) -> some View {
        switch t {
        case .today: NavigationStack { TodayView().voiceCaptureButton() }.environment(\.ambientPalette, .today)
        case .inbox: NavigationStack { InboxView().voiceCaptureButton() }.environment(\.ambientPalette, .inbox)
        case .study: NavigationStack { StudyView().voiceCaptureButton() }.environment(\.ambientPalette, .study)
        default:
            NavigationStack(path: store.pathBinding(t)) {
                if let p = t.page { p.view.voiceCaptureButton().navigationDestination(for: LibraryPage.self) { $0.view } }
            }
            .environment(\.ambientPalette, t.palette)
        }
    }
    func barBadge(_ t: AppTab) -> Int {
        switch t {
        case .inbox: return store.inboxTodo.count
        case .drafts: return store.pendingDrafts.count
        default: return 0
        }
    }

    /// Only used by the cloud preview build (set through simulator launch environment): open a given tab, or walk through every tab.
    func previewMode() async {
        let env = ProcessInfo.processInfo.environment
        if let name = env["LIFEOS_TAB"], let t = AppTab(rawValue: name) { store.go(t) }
        if env["LIFEOS_LOCK"] != nil { try? await Task.sleep(for: .seconds(1)); store.lockShown = true }
        guard env["LIFEOS_TOUR"] != nil else { return }
        let order: [AppTab] = store.barTabs + [.library, .search, store.barTabs.first ?? .library]
        try? await Task.sleep(for: .seconds(3))
        for t in order {
            withAnimation(.smooth(duration: 0.45)) { store.tab = t }
            try? await Task.sleep(for: .seconds(3.5))
        }
    }
}

/// The bar that rides above the tab bar (and folds into it when you scroll): your current block, a running focus session, or Gemini's next step.
struct NowAccessory: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var focus
    @Environment(Assistant.self) private var assistant
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        let _ = store.tick
        let (cur, next) = store.now
        HStack(spacing: 12) {
            if focus.running {
                ring(focus.progress, symbol: "timer")
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if focus.paused { Text("Paused · \(Int(focus.remaining / 60)) min left").font(.caption).foregroundStyle(.secondary) }
                    else { Text(timerInterval: Date()...focus.endDate, countsDown: true).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Button { focus.togglePause() } label: { Image(systemName: focus.paused ? "play.fill" : "pause.fill") }
                    .accessibilityLabel(focus.paused ? "Resume focus" : "Pause focus")
            } else if let cur {
                ring(Date().timeIntervalSince(cur.start) / max(1, cur.end.timeIntervalSince(cur.start)), symbol: nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cur.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(store.duration(cur.end.timeIntervalSinceNow)) left").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { store.sheet = .focus } label: { Image(systemName: "timer") }.accessibilityLabel("Start focus")
            } else {
                let suggestion = store.pulse["focus"].string.flatMap { $0.isEmpty ? nil : $0 }
                let target = suggestion.flatMap { store.target(for: $0, hint: store.pulse["focusTarget"]) }
                Image(systemName: "sparkles").foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion ?? next.map { "Next: \($0.title)" } ?? "Ask Gemini anything")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(target.map(store.targetLabel) ?? (suggestion == nil ? next.map { store.relDay($0.day) + ", " + store.time($0.start) } : nil) ?? "Plan your day, draft replies, move things")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: target != nil || (suggestion == nil && next != nil) ? "chevron.right" : "arrow.up.circle.fill")
                    .font(target != nil || (suggestion == nil && next != nil) ? .footnote.weight(.bold) : .title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, placement == .inline ? 10 : 14)
        .contentShape(.rect)
        .onTapGesture(perform: primary)
    }

    /// Tapping the bar goes where it points: the running focus session, your current block, or the screen Gemini's suggestion is about.
    private func primary() {
        if focus.running { store.sheet = .focus; return }
        let (cur, next) = store.now
        if cur != nil { store.go(.study); return }
        if let s = store.pulse["focus"].string, !s.isEmpty {
            if let t = store.target(for: s, hint: store.pulse["focusTarget"]) { store.open(t) } else { store.sheet = .ask(s) }
            return
        }
        if let next {
            switch next.kind {
            case .calendar: store.open(["page": "calendar", "id": .string(String(next.id.dropFirst(3)))])
            case .study: store.go(.study)
            default: store.open(["page": "timetable"])
            }
            return
        }
        store.sheet = .ask("")
    }

    private func ring(_ p: Double, symbol: String?) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, min(1, p))).stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.tint) }
        }
        .frame(width: 24, height: 24)
        .animation(.smooth, value: p)
    }
}
