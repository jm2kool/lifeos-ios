import SwiftUI

// MARK: design tokens
enum UI {
    static let radius: CGFloat = 26
    static let gutter: CGFloat = 16
    static func number(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

extension View {
    /// Content card on a frosted material so the background colour glows through softly. Liquid Glass stays on controls, as Apple recommends.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: UI.radius, style: .continuous))
    }
    /// Screen background: soft colour pools (see AmbientBackground) instead of flat grey or black.
    func pageBackground() -> some View { self.scrollContentBackground(.hidden).background { AmbientBackground() } }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var perform: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let action, let perform { Button(action, action: perform).font(.subheadline.weight(.medium)) }
        }
        .padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 2)
    }
}

struct CheckCircle: View {
    let done: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: done)
        .accessibilityLabel(done ? "Mark not done" : "Mark done")
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
    }
}

struct IconTile: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct StatTile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    var unit: String = ""
    var sub: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.footnote.weight(.semibold)).foregroundStyle(color).labelStyle(.titleAndIcon)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(UI.number(30)).contentTransition(.numericText())
                if !unit.isEmpty { Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            }
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .card(padding: 14)
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
    }
}

struct Divided<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { content } }
}

struct RowDivider: View {
    var inset: CGFloat = 52
    var body: some View { Divider().padding(.leading, inset) }
}

/// Floating glass toast with optional Undo.
struct ToastView: View {
    @Environment(Store.self) private var store
    let toast: Toast
    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text).font(.subheadline.weight(.medium)).lineLimit(2)
            if toast.undo {
                Button("Undo") { store.undoLast(); store.toast = nil }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The glow-free avatar used in toolbars.
struct Avatar: View {
    let name: String
    var size: CGFloat = 30
    var body: some View {
        Text(String(name.prefix(2)).uppercased().isEmpty ? "?" : String(name.prefix(2)).uppercased())
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.background)
            .frame(width: size, height: size)
            .background(Color.primary.gradient, in: .circle)
    }
}

extension Store {
    var tint: Color {
        switch doc["settings"]["tint"].string ?? "graphite" {
        case "blue": return .blue
        case "indigo": return .indigo
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "teal": return .teal
        default: return .primary
        }
    }
    var scheme: ColorScheme? {
        switch doc["settings"]["theme"].string ?? "auto" { case "light": return .light; case "dark": return .dark; default: return nil }
    }
}
