import SwiftUI
import SwiftData
import Charts

/// Minutes per day, subject and week, your streak, and how much of the plan actually happened.
struct StatsSection: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @Environment(Store.self) private var store
    @Query(filter: #Predicate<FocusSession> { !$0.trashed }, sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }) private var blocks: [StudyBlock]
    @State private var range: Range = .week

    struct DayPoint: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(subject)" }
        var day: Date
        var subject: String
        var minutes: Int
    }

    var body: some View {
        let cal = store.calendar
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
        let inRange = sessions.filter { $0.startedAt >= from }
        let names = Dictionary(subjects.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let subjectName: (UUID?) -> String = { id in id.flatMap { names[$0] } ?? "Other" }
        let daily: [DayPoint] = Dictionary(grouping: inRange) { "\(cal.startOfDay(for: $0.startedAt).timeIntervalSince1970)|\(subjectName($0.subjectID))" }
            .map { key, list in
                let parts = key.split(separator: "|", maxSplits: 1)
                return DayPoint(day: Date(timeIntervalSince1970: Double(parts[0]) ?? 0), subject: String(parts.count > 1 ? parts[1] : "Other"),
                                minutes: list.reduce(0) { $0 + $1.minutes })
            }
            .sorted { $0.day < $1.day }
        let bySubject = Dictionary(grouping: inRange) { subjectName($0.subjectID) }
            .map { SubjectTotal(name: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes > $1.minutes }
        let total = inRange.reduce(0) { $0 + $1.minutes }
        let domain = subjects.map(\.name) + ["Other"]
        let colors = subjects.map { Color(hex: $0.color) } + [Color.gray]
        let weeks = weekly(cal: cal)
        let adherence = adherence(cal: cal)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Stats", symbol: "chart.bar.xaxis")
                Picker("Range", selection: $range) { ForEach(Range.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 170)
            }
            HStack(spacing: 10) {
                StatTile(value: Fmt.minutes(total), label: "in \(range.rawValue)", symbol: "clock", color: Theme.accent)
                StatTile(value: "\(store.streak)", label: "day streak", symbol: "flame.fill", color: Theme.warn)
                StatTile(value: adherence.map { "\(Int($0 * 100))%" } ?? "–", label: "plan kept", symbol: "checkmark.seal", color: Theme.good)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Minutes per day").font(.subheadline.weight(.semibold))
                if daily.isEmpty {
                    Text("Your focus time shows up here.").font(.caption).foregroundStyle(.secondary).frame(height: 120)
                } else {
                    Chart(daily) { p in
                        BarMark(x: .value("Day", p.day, unit: .day), y: .value("Minutes", p.minutes))
                            .foregroundStyle(by: .value("Subject", p.subject))
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(domain: domain, range: colors)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                            AxisValueLabel(format: range == .week ? Date.FormatStyle.dateTime.weekday(.narrow) : Date.FormatStyle.dateTime.day())
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 160)
                }
            }
            .glassCard(radius: 22, padding: 14)

            if !bySubject.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By subject").font(.subheadline.weight(.semibold))
                    Chart(bySubject) { item in
                        BarMark(x: .value("Minutes", item.minutes), y: .value("Subject", item.name))
                            .foregroundStyle(by: .value("Subject", item.name))
                            .annotation(position: .trailing) { Text(Fmt.minutes(item.minutes)).font(.caption2).foregroundStyle(.secondary) }
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(domain: domain, range: colors)
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(max(1, bySubject.count)) * 30 + 10)
                }
                .glassCard(radius: 22, padding: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Per week").font(.subheadline.weight(.semibold))
                Chart(weeks, id: \.start) { w in
                    BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Hours", Double(w.minutes) / 60))
                        .foregroundStyle(Theme.accent.gradient)
                        .cornerRadius(4)
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h)) h") } } } }
                .frame(height: 120)
            }
            .glassCard(radius: 22, padding: 14)
        }
    }

    struct Week { var start: Date; var minutes: Int }
    struct SubjectTotal: Identifiable { var name: String; var minutes: Int; var id: String { name } }

    private func weekly(cal: Calendar) -> [Week] {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<8).reversed().compactMap { i -> Week? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return Week(start: start, minutes: sessions.filter { $0.startedAt >= start && $0.startedAt < end }.reduce(0) { $0 + $1.minutes })
        }
    }

    private func adherence(cal: Calendar) -> Double? {
        let from = cal.date(byAdding: .day, value: -range.days, to: Date()) ?? Date()
        let past = blocks.filter { $0.endAt < Date() && $0.startAt >= from }
        guard !past.isEmpty else { return nil }
        let score = past.reduce(0.0) { $0 + ($1.status == .done ? 1 : $1.status == .partial ? 0.5 : 0) }
        return score / Double(past.count)
    }
}
