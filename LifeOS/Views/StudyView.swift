import SwiftUI
import UIKit
import Charts

struct StudyView: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        let _ = store.tick
        let st = store.content["study"], L = store.content["studyLabels"]
        let now = store.studyNow
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L["clock"].string ?? "Right now").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                    Text(now.title).font(.title3.weight(.semibold))
                    if !now.time.isEmpty { Text(now.time).font(.subheadline).foregroundStyle(.secondary) }
                    if !now.note.isEmpty { Divider().padding(.vertical, 4); Text(now.note).font(.footnote).foregroundStyle(.secondary) }
                }
                .card()

                SectionHeader(title: "Focus")
                FocusCard()

                if !st["blocks"].array.isEmpty {
                    SectionHeader(title: st["date"].str < store.today ? "Last plan" : (L["today"].string ?? "Plan"))
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 0) { ForEach(st["blocks"].array, id: \.self) { slot($0["time"].str, $0["title"].str, $0["detail"].str, $0["status"].str) } }
                    } label: { Text(L["today"].string ?? "Plan").font(.body.weight(.medium)) }
                    .card()
                    if !st["note"].str.isEmpty {
                        DisclosureGroup("Notes for this plan") { Text(st["note"].str).font(.footnote).foregroundStyle(.secondary).padding(.top, 6) }.card().padding(.top, 10)
                    }
                }
                if !st["tomorrow"].array.isEmpty {
                    SectionHeader(title: L["tomorrow"].string ?? "Next")
                    VStack(alignment: .leading, spacing: 0) { ForEach(st["tomorrow"].array, id: \.self) { slot($0["time"].str, $0["title"].str, $0["detail"].str, "") } }.card()
                }

                let links = st["links"].array
                if !links.isEmpty {
                    SectionHeader(title: L["resources"].string ?? "Resources")
                    VStack(spacing: 0) {
                        ForEach(Array(links.prefix(4)), id: \.self) { l in resource(l); RowDivider() }
                        NavigationLink { ResourcesList(links: links) } label: {
                            Text("All \(links.count) resources").font(.body.weight(.medium)).foregroundStyle(.tint).frame(maxWidth: .infinity).padding(12)
                        }
                    }.card(padding: 0)
                }

                let sets = store.coverage
                ForEach(Array(Set(sets.map(\.group))).sorted(), id: \.self) { g in
                    SectionHeader(title: g)
                    VStack(spacing: 0) {
                        let group = sets.filter { $0.group == g }
                        ForEach(group) { s in
                            NavigationLink { CoverageList(set: s) } label: { coverageRow(s) }.buttonStyle(.plain)
                            if s.id != group.last?.id { RowDivider(inset: 14) }
                        }
                    }.card(padding: 0)
                }
                if let n = store.content["copy"]["coverageNote"].string { Text(n).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 8) }

                archive
                if let tx = store.content["copy"]["tallentexNote"].string {
                    DisclosureGroup(L["tallentex"].string ?? "Plan notes") { Text(tx).font(.footnote).foregroundStyle(.secondary).padding(.top, 6) }.card().padding(.top, 22)
                }
                let recap = st["recap"]
                if recap.isObject {
                    DisclosureGroup(recap["title"].string ?? "Recap") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recap["text"].str).font(.footnote).foregroundStyle(.secondary)
                            if recap["spotCheck"].isObject {
                                Pill(text: recap["spotCheck"]["score"].str + " · " + recap["spotCheck"]["time"].str)
                                ForEach(recap["spotCheck"]["entries"].array, id: \.self) { Text($0.str).font(.footnote).padding(.vertical, 4); Divider() }
                            }
                        }.padding(.top, 6)
                    }.card().padding(.top, 10)
                }
                if let u = store.parse(st["updatedAt"].str) {
                    Text("Plan updated \(store.dayLabel(store.dayKey(u), long: false)), \(store.time(u))").font(.caption).foregroundStyle(.tertiary).padding(.top, 18).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, UI.gutter).padding(.bottom, 30)
        }
        .pageBackground()
        .navigationTitle(L["title"].string ?? "Study")
        .navigationSubtitle(st["block"].str)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { TimetableView() } label: { Image(systemName: "clock") }.accessibilityLabel("Timetable")
            }
        }
    }

    private func slot(_ time: String, _ title: String, _ detail: String, _ status: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                if !status.isEmpty { Pill(text: status) }
            }
        }
        .padding(.vertical, 8)
    }
    private func resource(_ l: JSON) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "link", color: .blue)
            Text(l["title"].str).font(.body).lineLimit(2)
            Spacer()
            if let u = URL(string: l["url"].str) {
                Menu {
                    Link("Open", destination: u)
                    Button("Save", systemImage: "bookmark") { store.act(["op": "saved.add", "title": l["title"], "url": l["url"], "source": "Study"]); store.show("Saved") }
                    Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.string = l["url"].str }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
    private func coverageRow(_ s: CoverageSet) -> some View {
        let n = store.doneCount(s)
        return HStack(spacing: 12) {
            Gauge(value: Double(n), in: 0...Double(max(1, s.items.count))) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity).scaleEffect(0.6).frame(width: 34, height: 34).tint(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.body.weight(.medium))
                Text("\(n) of \(s.items.count) marked").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(.rect)
    }
    @ViewBuilder private var archive: some View {
        let p = store.content["examPrep"], L = store.content["studyLabels"]
        let groups: [(String, [JSON])] = [(L["week1"].string ?? "Week 1", p["week1Days"].array), (L["week2"].string ?? "Week 2", p["week2Days"].array), (L["later"].string ?? "Later", p["laterDays"].array)].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            SectionHeader(title: L["archive"].string ?? "Exam timetable")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.0) { title, days in
                    DisclosureGroup("\(title) · \(days.count) days") {
                        ForEach(days, id: \.self) { d in
                            DisclosureGroup("\(d["day"].str) · \(d["date"].str)") {
                                VStack(alignment: .leading, spacing: 0) {
                                    if !d["tag"].str.isEmpty { Text(d["tag"].str).font(.footnote).foregroundStyle(.secondary) }
                                    ForEach(d["slots"].array, id: \.self) { slot($0["time"].str, $0["subject"].str, $0["detail"].str, "") }
                                }
                            }
                            .font(.subheadline).padding(.vertical, 2)
                        }
                    }
                    .card()
                }
            }
        }
    }
}

struct FocusCard: View {
    @Environment(Store.self) private var store
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        let today = store.today
        let week = (0..<7).map { store.addDays(today, $0 - 6) }
        VStack(alignment: .leading, spacing: 14) {
            if focus.running {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.paused ? "Paused" : "Focusing").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                        if focus.paused { Text("\(Int(focus.remaining / 60)) min left").font(UI.number(36)) }
                        else { Text(timerInterval: Date()...focus.endDate, countsDown: true).font(UI.number(36)).monospacedDigit() }
                        Text(focus.label).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Button(focus.paused ? "Resume" : "Pause", systemImage: focus.paused ? "play.fill" : "pause.fill") { focus.togglePause() }.buttonStyle(.glassProminent)
                        Button("End", systemImage: "stop.fill") { focus.stop() }.buttonStyle(.glass)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(store.focusMinutes(today))").font(UI.number(36)).contentTransition(.numericText())
                    Text("min today").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start", systemImage: "play.fill") { store.sheet = .focus }.buttonStyle(.glassProminent)
                }
            }
            Chart(week, id: \.self) { d in
                BarMark(x: .value("Day", store.date(d, minutes: 720), unit: .day), y: .value("Minutes", store.focusMinutes(d)))
                    .foregroundStyle(d == today ? Color.accentColor : Color.secondary.opacity(0.35))
                    .clipShape(.rect(cornerRadius: 4))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .chartYAxis(.hidden)
            .frame(height: 70)
        }
        .card()
    }
}

struct CoverageList: View {
    @Environment(Store.self) private var store
    let set: CoverageSet
    var body: some View {
        List {
            Section {
                ForEach(set.items) { item in
                    let on = store.marked(item.id)
                    Button {
                        store.act(["op": "progress.set", "id": .string(item.id), "done": .bool(!on), "label": .string(set.name + ": " + Store.clean(item.text)), "title": .string(Store.clean(item.text))])
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                            Text(Store.clean(item.text)).foregroundStyle(.primary)
                            Spacer()
                            if item.text.hasPrefix("🟢") { Circle().fill(.green).frame(width: 7, height: 7) }
                            else if item.text.hasPrefix("🟡") { Circle().fill(.orange).frame(width: 7, height: 7) }
                            else if item.text.hasPrefix("🔴") { Circle().fill(.red).frame(width: 7, height: 7) }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: on)
                }
            } footer: { Text("Tick what you've actually finished. \(store.doneCount(set)) of \(set.items.count) marked.") }
        }
        .navigationTitle(set.name)
    }
}

struct ResourcesList: View {
    @Environment(Store.self) private var store
    let links: [JSON]
    @State private var q = ""
    var body: some View {
        List(links.filter { q.isEmpty || $0["title"].str.localizedCaseInsensitiveContains(q) }, id: \.self) { l in
            if let u = URL(string: l["url"].str) {
                Link(destination: u) { Label(l["title"].str, systemImage: "link") }
                    .swipeActions { Button("Save", systemImage: "bookmark") { store.act(["op": "saved.add", "title": l["title"], "url": l["url"], "source": "Study"]); store.show("Saved") }.tint(.orange) }
            }
        }
        .searchable(text: $q)
        .navigationTitle("Resources")
    }
}
