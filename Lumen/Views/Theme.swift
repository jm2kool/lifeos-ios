import SwiftUI
import UIKit

/// Lumen's look: true black, Liquid Glass on top, and slow colour from your subjects underneath for the glass to bend.
enum Theme {
    static let accent = Color(hex: "#8FA8FF")
    static let instinct = Color(hex: "#B48CFF")
    static let good = Color(hex: "#5BE3A1")
    static let warn = Color(hex: "#FFB35C")
    static let bad = Color(hex: "#FF6B7A")
    static let subjectPalette = ["#7C8CFF", "#FF7A9C", "#5BE3A1", "#FFB35C", "#5CC8FF", "#C38BFF", "#FF8A5C", "#9BE15D",
                                 "#FF5CD1", "#5CFFE0", "#FFD65C", "#A0A8B8"]
    static let subjectIcons = ["book.closed", "atom", "function", "flask", "leaf", "globe.europe.africa", "text.book.closed",
                               "music.note", "paintpalette", "laptopcomputer", "chart.bar", "building.columns", "brain.head.profile",
                               "character.book.closed", "figure.run", "heart.text.square", "scalemass", "ruler"]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x7C8CFF
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: - Background

/// Slow, blurred colour drifting behind the glass. Still for people who ask iPhone for less motion.
struct Aurora: View {
    var colors: [Color]
    var intensity: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                gc.addFilter(.blur(radius: 70))
                let palette = colors.isEmpty ? [Theme.accent, Theme.instinct] : Array(colors.prefix(5))
                for (i, c) in palette.enumerated() {
                    let phase = Double(i) * 1.9
                    let x = size.width * (0.5 + 0.4 * sin(t / (31 + Double(i) * 6) + phase))
                    let y = size.height * (0.28 + 0.34 * cos(t / (37 + Double(i) * 8) + phase * 1.3))
                    let r = size.width * (0.62 + 0.12 * sin(t / 19 + phase))
                    gc.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r * 0.8)),
                            with: .color(c.opacity(intensity * (i == 0 ? 0.9 : 0.6))))
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The black, softly lit background every screen sits on.
struct Backdrop: ViewModifier {
    var colors: [Color]
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { Aurora(colors: colors, intensity: 0.32) }
            .background(Color.black.ignoresSafeArea())
    }
}

extension View {
    func backdrop(_ colors: [Color]) -> some View { modifier(Backdrop(colors: colors)) }
    /// A glass panel with Lumen's usual padding and corners.
    func glassCard(tint: Color? = nil, radius: CGFloat = 24, padding: CGFloat = 16, interactive: Bool = false) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(Theme.glass(tint: tint, interactive: interactive), in: .rect(cornerRadius: radius))
    }
}

extension Theme {
    static func glass(tint: Color?, interactive: Bool = false) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.22)) }
        if interactive { g = g.interactive() }
        return g
    }
}

// MARK: - Small pieces

/// Marks anything Instinct made or changed.
struct InstinctBadge: View {
    var compact = false
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
            if !compact { Text("Instinct") }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(Theme.instinct.opacity(0.5)), in: .capsule)
        .accessibilityLabel("Made by Instinct")
    }
}

struct SubjectDot: View {
    var color: Color
    var size: CGFloat = 9
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).shadow(color: color.opacity(0.8), radius: 4)
    }
}

struct SubjectChip: View {
    var subject: StudySubject?
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: subject?.icon ?? "tray")
            Text(subject?.name ?? "No subject").lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(Color(hex: subject?.color ?? "#A0A8B8").opacity(0.35)), in: .capsule)
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color = Theme.accent
    var line: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6), radius: 4)
        }
        .animation(.spring(duration: 0.6), value: progress)
    }
}

struct ProgressBar: View {
    var progress: Double
    var color: Color = Theme.accent
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color.gradient).frame(width: max(4, g.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.5), value: progress)
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String?
    init(_ title: String, symbol: String? = nil) { self.title = title; self.symbol = symbol }
    var body: some View {
        HStack {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

struct EmptyCard: View {
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassCard()
    }
}

struct ToastView: View {
    var toast: Store.Toast
    var onUndo: (UUID) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol).foregroundStyle(Theme.good)
            Text(toast.text).font(.subheadline.weight(.semibold)).lineLimit(2)
            if let batch = toast.undoBatch {
                Button("Undo") { onUndo(batch) }.buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// A stat in a glass tile.
struct StatTile: View {
    var value: String
    var label: String
    var symbol: String
    var color: Color = Theme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).font(.headline)
            Text(value).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .glassCard(tint: color, radius: 20, padding: 14)
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func start() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Formatting

enum Fmt {
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day, (0..<7).contains(days) {
            return d.formatted(.dateTime.weekday(.wide))
        }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
    static func dayTime(_ d: Date) -> String { "\(day(d)) \(time(d))" }
    static func span(_ a: Date, _ b: Date) -> String { "\(time(a))–\(time(b))" }
    static func minutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }
    /// "8h 5m" — for tight spaces like stat tiles.
    static func compact(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
    static func hours(_ h: Double) -> String {
        h < 1 ? "\(Int((h * 60).rounded())) min" : (h == h.rounded() ? "\(Int(h)) h" : String(format: "%.1f h", h))
    }
    /// "Due tomorrow 08:00", "Overdue by 2 days".
    static func due(_ d: Date?) -> String {
        guard let d else { return "No due date" }
        if d < Date() {
            let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
            return days >= 1 ? "Overdue by \(days) day\(days == 1 ? "" : "s")" : "Overdue since \(time(d))"
        }
        return "Due \(dayTime(d))"
    }
    static func countdown(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded(.up)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
