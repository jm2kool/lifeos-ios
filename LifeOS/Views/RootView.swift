import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView() }.environment(\.ambientPalette, .today)
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack { InboxView() }.environment(\.ambientPalette, .inbox)
            }
            .badge(store.inboxTodo.count)
            Tab("Study", systemImage: "book.closed", value: AppTab.study) {
                NavigationStack { StudyView() }.environment(\.ambientPalette, .study)
            }
            Tab("Library", systemImage: "square.grid.2x2", value: AppTab.library) {
                NavigationStack { LibraryView() }.environment(\.ambientPalette, .library)
            }
            .badge(store.pendingDrafts.count)
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }.environment(\.ambientPalette, .search)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NowAccessory() }
        .fullScreenCover(isPresented: $store.lockShown) {
            StudyLockView().environment(store).environment(focus).tint(store.tint)
        }
        .task(id: store.studyAlertKey) { await StudyAlerts.reschedule(store) }
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
            }
        }
    }
}

extension RootView {
    /// Only used by the cloud preview build (set through simulator launch environment): open a given tab, or walk through every tab.
    func previewMode() async {
        let env = ProcessInfo.processInfo.environment
        let tabs: [String: AppTab] = ["today": .today, "inbox": .inbox, "study": .study, "library": .library, "search": .search]
        if let name = env["LIFEOS_TAB"], let t = tabs[name] { store.tab = t }
        if env["LIFEOS_LOCK"] != nil { try? await Task.sleep(for: .seconds(1)); store.lockShown = true }
        guard env["LIFEOS_TOUR"] != nil else { return }
        let order: [AppTab] = [.today, .inbox, .study, .library, .search, .today]
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
                Image(systemName: "sparkles").foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.pulse["focus"].string ?? next.map { "Next: \($0.title)" } ?? "Ask Gemini anything")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(next.map { store.relDay($0.day) + ", " + store.time($0.start) } ?? "Plan your day, draft replies, move things")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button { store.sheet = .ask("") } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                    .accessibilityLabel("Ask Gemini")
            }
        }
        .padding(.horizontal, placement == .inline ? 10 : 14)
        .contentShape(.rect)
        .onTapGesture {
            if focus.running || store.now.current == nil { store.sheet = focus.running ? .focus : .ask("") }
            else { store.tab = .study }
        }
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
