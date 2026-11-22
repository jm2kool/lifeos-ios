import SwiftUI

/// A planned watch is over: score it, like it and log it in one go, or say it didn't happen.
/// Comes up the next time you open Matinee after the film should have finished, or from its notification.
struct HowWasItSheet: View {
    let planID: UUID
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Double?
    @State private var liked = false
    @State private var palette: PosterPalette?
    /// Set when you've answered, so closing the sheet doesn't also put the question off.
    @State private var answered = false

    private var plan: PlannedWatch? { library.plan(id: planID) }
    private var bg: Color { palette?.background ?? .black }

    var body: some View {
        NavigationStack {
            Group {
                if let p = plan { content(p) } else {
                    EmptyState(symbol: "checkmark.circle", title: "All done", message: "That plan has already been logged or removed.")
                }
            }
            .background {
                ZStack {
                    bg
                    if let g = palette?.glow {
                        Circle().fill(g).frame(width: 420, height: 420).blur(radius: 120).opacity(0.45).offset(y: -260)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ask me later", systemImage: "clock") { later() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(bg)
        .animation(.easeInOut(duration: 0.5), value: palette)
        .task(id: planID) {
            guard let p = plan else { return }
            rating = library.rating(p.film.id)
            liked = library.isLiked(p.film.id)
            let url = p.film.largePoster ?? p.film.poster
            if let hit = Palette.cached(url) { palette = hit } else { palette = await Palette.of(url) }
        }
        // Swiping it away counts as "Ask me later", so it doesn't come straight back.
        .onDisappear { if !answered, let p = plan { library.snoozePlan(p) } }
    }

    private func content(_ p: PlannedWatch) -> some View {
        let comfort = library.isComfort(p.film.id)
        return ScrollView {
            VStack(spacing: 18) {
                PosterView(film: p.film, width: 150, corner: 12).padding(.top, 8)
                VStack(spacing: 6) {
                    Text("HOW WAS IT?").font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(palette?.highlight ?? Theme.accent)
                    Text(p.film.title).font(.title.weight(.bold)).multilineTextAlignment(.center)
                    Label(p.place.isEmpty ? p.when : "\(p.place) · \(p.when)", systemImage: p.placeSymbol)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
                if comfort {
                    Text("A comfort \(p.film.isShow ? "show" : "film") — no score needed. Just log that you watched it.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                } else {
                    FilmRatingInput(score: rating, dialSize: 200) { rating = $0 }
                }
                Button { liked.toggle(); UIImpactFeedbackGenerator(style: .medium).impactOccurred() } label: {
                    Label(liked ? "Loved it" : "Love it?", systemImage: liked ? "heart.fill" : "heart")
                        .font(.headline)
                        .foregroundStyle(liked ? Theme.heart : .white.opacity(0.75))
                        .symbolEffect(.bounce, value: liked)
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    Button { log(p) } label: {
                        Label("Log it", systemImage: "eye.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button { review(p) } label: {
                        Label("Log it with a review…", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Menu {
                        Button("Plan it for another day", systemImage: "calendar.badge.clock") {
                            answered = true
                            router.sheet = .plan(p.film, p)
                        }
                        Button("Forget this plan", systemImage: "calendar.badge.minus", role: .destructive) {
                            answered = true
                            library.removePlan(p)
                            dismiss()
                        }
                    } label: {
                        Label("I didn't watch it", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private func entry(_ p: PlannedWatch) -> LogEntry {
        var e = LogEntry(film: p.film)
        e.watchedOn = min(p.date, .now)
        e.rating = library.isComfort(p.film.id) ? nil : rating
        e.liked = liked
        e.rewatch = library.isWatched(p.film.id)
        if p.place.lowercased().contains("cinema") { e.tags = ["cinema"] }
        return e
    }

    private func log(_ p: PlannedWatch) {
        answered = true
        library.log(entry(p))
        library.removePlan(p, toast: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    /// The full log sheet, with the score you've just given. Saving it settles the plan; cancelling keeps it.
    private func review(_ p: PlannedWatch) {
        answered = true
        router.sheet = .logDraft(entry(p))
    }

    private func later() {
        answered = true
        if let p = plan { library.snoozePlan(p) }
        dismiss()
    }
}

/// Home's row of what you've planned to watch: cinema trips and film nights, with how long until each.
/// Finished ones stay until you say how they were.
struct PlansSection: View {
    var media: MediaFilter = .all
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let list = library.plans.filter { media.includes($0.film) }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Your plans", subtitle: "What you're going to watch, and when")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(list) { p in PlanCard(plan: p) }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}

struct PlanCard: View {
    let plan: PlannedWatch
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        // Ticks over each minute, so "in 2 hours" and "on now" stay true.
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            HStack(alignment: .top, spacing: 12) {
                PosterView(film: plan.film, width: 72, corner: 8)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.film.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Label(plan.when, systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    if !plan.place.isEmpty {
                        Label(plan.place, systemImage: plan.placeSymbol).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    status(at: tl.date)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 290, height: 132, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(plan.isOver ? Theme.accent.opacity(0.6) : Theme.line, lineWidth: 1))
            .contentShape(.rect(cornerRadius: 20))
            .onTapGesture {
                if plan.isOver { router.sheet = .howWasIt(plan.id) } else { router.open(plan.film) }
            }
        }
        .contextMenu {
            if plan.isOver {
                Button("How was it?", systemImage: "star.bubble") { router.sheet = .howWasIt(plan.id) }
            }
            Button("Open \(plan.film.isShow ? "show" : "film")", systemImage: "film") { router.open(plan.film) }
            Button("Change plan…", systemImage: "calendar.badge.clock") { router.sheet = .plan(plan.film, plan) }
            Button("Remove plan", systemImage: "calendar.badge.minus", role: .destructive) { library.removePlan(plan) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(plan.isOver ? "Say how it was" : "Opens the \(plan.film.isShow ? "show" : "film")")
    }

    @ViewBuilder private func status(at now: Date) -> some View {
        if plan.endsAt <= now {
            Label("How was it?", systemImage: "star.bubble.fill").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
        } else if plan.hasTime && plan.date <= now {
            Label("On now", systemImage: "play.circle.fill").font(.caption.weight(.heavy)).foregroundStyle(Theme.watch)
        } else if !plan.hasTime && Calendar.current.isDateInToday(plan.date) {
            Label("Today", systemImage: "sparkles").font(.caption.weight(.heavy)).foregroundStyle(Theme.star)
        } else {
            Text(plan.date.formatted(.relative(presentation: .named)).capitalizedFirst)
                .font(.caption.weight(.heavy)).foregroundStyle(Theme.star)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
