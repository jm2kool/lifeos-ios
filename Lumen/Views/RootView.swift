import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Planner", systemImage: "calendar", value: AppTab.planner) {
                NavigationStack { PlannerView() }
            }
            Tab("Focus", systemImage: "timer", value: AppTab.focus) {
                NavigationStack { FocusView() }
            }
            Tab("Cards", systemImage: "rectangle.on.rectangle.angled", value: AppTab.cards) {
                NavigationStack { CardsView() }
            }
            Tab("Syllabus", systemImage: "books.vertical", value: AppTab.syllabus) {
                NavigationStack { SyllabusView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .bottom) {
            // The running timer floats above the tab bar on the other tabs.
            if timer.active && router.tab != .focus {
                FocusAccessory()
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 62)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: timer.active)
        .sheet(item: $router.sheet) { route in
            SheetHost(route: route)
                .environment(store).environment(auth).environment(router).environment(timer).environment(SyncEngine.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .fullScreenCover(item: $router.review) { target in
            ReviewSession(deckID: target.deck)
                .environment(store).environment(router)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $router.lockShown) {
            StudyLockView()
                .environment(store).environment(router).environment(timer)
        }
        .fullScreenCover(isPresented: Binding(get: { auth.needsSignIn }, set: { _ in })) {
            SignInView().environment(auth).environment(store).preferredColorScheme(.dark)
        }
        .sheet(item: Binding(get: { timer.finished }, set: { if $0 == nil { timer.finished = nil } })) { f in
            OutcomeSheet(finished: f)
                .environment(store).environment(timer)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                ToastView(toast: t) { store.undo(batch: $0); store.toast = nil }
                    .task(id: t.id) {
                        try? await Task.sleep(for: .seconds(t.undoBatch == nil ? 2.2 : 5))
                        withAnimation(.snappy) { if store.toast?.id == t.id { store.toast = nil } }
                    }
            }
        }
        .animation(.snappy, value: store.toast)
        .onChange(of: auth.session?.userID) { old, new in
            guard let new else { return }
            // Signing in with a different account than last time starts from that account's data.
            let last = UserDefaults.standard.string(forKey: "auth.lastUser")
            if let last, last != new {
                store.wipeLocal()
                SyncEngine.shared.resetCursors()
            } else if last == nil {
                SyncEngine.shared.adoptLocalData()
            }
            UserDefaults.standard.set(new, forKey: "auth.lastUser")
            _ = old
            Task {
                await SyncEngine.shared.sync()
                Realtime.shared.connect()
                _ = await Notifier.shared.requestPermission()
                await Notifier.shared.reschedule()
                Push.shared.register()
                await Push.shared.uploadQueued()
            }
        }
        .task {
            await Notifier.shared.reschedule()
        }
    }
}

/// The running timer, floating above the tab bar on every tab.
struct FocusAccessory: View {
    @Environment(FocusTimer.self) private var timer
    @Environment(Router.self) private var router
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 10) {
                Image(systemName: timer.phase.isBreak ? "cup.and.saucer.fill" : (timer.running ? "timer" : "pause.fill"))
                    .foregroundStyle(timer.phase.isBreak ? Theme.good : Theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.context.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(timer.waiting ? "Ready for round \(timer.round)" : timer.phase.label).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.countdown(timer.remaining(at: ctx.date))).font(.headline.monospacedDigit())
                Button { timer.togglePause() } label: {
                    Image(systemName: timer.running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture { router.tab = .focus }
            .onChange(of: ctx.date) { _, d in timer.tick(now: d) }
        }
    }
}

struct SheetHost: View {
    let route: SheetRoute
    @Environment(Store.self) private var store

    var body: some View {
        switch route {
        case .settings:
            SettingsView()
        case .newAssignment:
            NavigationStack { AssignmentEditor(assignment: nil) }
        case .assignment(let id):
            if let a = store.find(Assignment.self, id) {
                NavigationStack { AssignmentDetail(assignment: a) }
            } else { Missing() }
        case .block(let id):
            if let b = store.find(StudyBlock.self, id) {
                NavigationStack { BlockEditor(block: b, start: b.startAt) }
            } else { Missing() }
        case .newBlock(let start):
            NavigationStack { BlockEditor(block: nil, start: start) }
        case .proposal(let id):
            if let p = store.find(Proposal.self, id) {
                NavigationStack { ProposalSheet(proposal: p) }
            } else { Missing() }
        case .generateCards(let deck):
            NavigationStack { GenerateCardsView(deckID: deck) }
        case .subject(let id):
            NavigationStack { SubjectEditor(subject: store.find(StudySubject.self, id)) }
        }
    }

    struct Missing: View {
        var body: some View {
            ContentUnavailableView("Not found", systemImage: "questionmark.circle", description: Text("It may have been deleted on another device."))
        }
    }
}
