import SwiftUI

/// The app tour and What's New: big, simple pages you swipe through. "Try it" jumps straight there.
struct TourView: View {
    let mode: TourMode
    /// Called when the tour ends, with the place to go if "Try it" was tapped.
    var onFinish: (TourAction?) -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        var item: ChangeItem
        var kicker: String
        var id: String
    }

    private var pages: [Page] {
        switch mode {
        case .welcome:
            return Tour.welcomePages.enumerated().map { Page(item: $0.element, kicker: $0.offset == 0 ? "MATINEE \(Changelog.current)" : "TOUR", id: "w\($0.offset)") }
        case .whatsNew(let releases):
            var out = [Page(item: ChangeItem(symbol: "sparkles", title: "What's new",
                                             detail: releases.map { "Version \($0.version): \($0.headline)." }.joined(separator: "\n")),
                            kicker: "UPDATED TO \(Changelog.current)", id: "intro")]
            for r in releases {
                out += r.items.map { Page(item: $0, kicker: "NEW IN \(r.version)", id: "\(r.version)-\($0.id)") }
            }
            return out
        }
    }

    private static let colors: [Color] = [Theme.accent, Theme.list, Theme.heart, Theme.watch, Theme.star,
                                          Color(red: 0.62, green: 0.45, blue: 1.0)]

    var body: some View {
        let list = pages
        let color = Self.colors[page % Self.colors.count]
        ZStack {
            Color.black.ignoresSafeArea()
            Circle().fill(color).frame(width: 520, height: 520).blur(radius: 160).opacity(0.45)
                .offset(y: -220)
                .animation(.easeInOut(duration: 0.6), value: page)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < list.count - 1 {
                        Button("Skip") { onFinish(nil) }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 22)

                TabView(selection: $page) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                        pageView(p, color: Self.colors[i % Self.colors.count]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(list.indices, id: \.self) { i in
                        Capsule().fill(i == page ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 18)

                VStack(spacing: 10) {
                    if let action = list.indices.contains(page) ? list[page].item.action : nil {
                        Button { onFinish(action) } label: {
                            Label("Try it", systemImage: "arrow.up.forward").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    }
                    Button {
                        if page < list.count - 1 { withAnimation(.smooth) { page += 1 } } else { onFinish(nil) }
                    } label: {
                        Text(page < list.count - 1 ? "Next" : mode == .welcome ? "Get started" : "Done")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageView(_ p: Page, color: Color) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(color.gradient.opacity(0.9)).frame(width: 150, height: 150)
                    .shadow(color: color.opacity(0.6), radius: 40)
                Image(systemName: p.item.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(p.kicker).font(.caption.weight(.heavy)).tracking(1.6).foregroundStyle(.white.opacity(0.6))
            Text(p.item.title).font(.system(size: 32, weight: .bold)).multilineTextAlignment(.center)
            Text(p.item.detail).font(.body).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
    }
}

/// Settings → What's new: every version and its changes, newest first, with a tour for each.
struct ChangelogView: View {
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Installed", value: Changelog.installed)
            }
            ForEach(Changelog.releases) { r in
                Section {
                    ForEach(r.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(Theme.dim)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if r.version != "1.0" {
                        Button("Take the tour of \(r.version)", systemImage: "play.rectangle.on.rectangle") { start(.whatsNew([r])) }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(r.version)\(r.version == Changelog.current ? " · current" : "")").font(.headline).foregroundStyle(.white)
                        Text("\(r.headline) · \(r.date)").font(.caption)
                    }
                    .textCase(nil)
                }
            }
        }
        .oledBackground()
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start(_ mode: TourMode) {
        router.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.tour = mode
        }
    }
}
