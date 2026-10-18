import SwiftUI
import MessageUI

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
        default: return Self.graphite
        }
    }
    /// A slate grey that reads as text on either background and still carries white text when it fills a button.
    static let graphite = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.50, green: 0.52, blue: 0.57, alpha: 1) : UIColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
    })
    var scheme: ColorScheme? {
        switch doc["settings"]["theme"].string ?? "auto" { case "light": return .light; case "dark": return .dark; default: return nil }
    }
}

/// Draft text with light Markdown: # headings, - bullets, **bold**, _italic_ and links.
struct RichText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.isEmpty {
                    Color.clear.frame(height: 2)
                } else if l.hasPrefix("#") {
                    Text(md(String(l.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))).font(l.hasPrefix("##") ? .subheadline.weight(.semibold) : .headline)
                } else if ["- ", "* ", "• "].contains(where: { l.hasPrefix($0) }) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(.secondary); Text(md(String(l.dropFirst(2)))) }.font(.subheadline)
                } else {
                    Text(md(l)).font(.subheadline)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// "Changed by FRIDAY" on anything an assistant added or edited. Shows nothing for your own changes.
struct ChangedByTag: View {
    @Environment(Store.self) private var store
    let by: String
    var body: some View {
        if let who = store.changedBy(by) {
            Label("Changed by " + who, systemImage: "person.crop.circle").font(.caption).foregroundStyle(.purple).labelStyle(.titleAndIcon)
        }
    }
}

/// On Today: what your assistants changed since you last looked, with Review and Undo all.
struct ChangesBanner: View {
    @Environment(Store.self) private var store
    @State private var busy = false
    var body: some View {
        let list = store.unseenChanges
        if !list.isEmpty {
            let names = ListFormatter.localizedString(byJoining: Array(Set(list.map { $0["by"].str })).sorted())
            let undoable = list.filter { !$0["undo"].isNull }.map { $0["id"].str }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    IconTile(symbol: "person.badge.clock.fill", color: .purple, size: 30)
                    Text("\(names) made \(list.count) change\(list.count == 1 ? "" : "s")").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                ForEach(Array(list.prefix(4).enumerated()), id: \.offset) { _, e in
                    Text("• " + store.describe(e) + " · " + store.ago(e["at"].double ?? 0)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if list.count > 4 { Text("and \(list.count - 4) more").font(.footnote).foregroundStyle(.tertiary) }
                HStack {
                    Button("Review") { store.sheet = .activity }.buttonStyle(.glass)
                    if !undoable.isEmpty {
                        Button {
                            busy = true
                            Task { await store.undoOnServer(undoable, label: "Undid \(undoable.count) change\(undoable.count == 1 ? "" : "s")"); busy = false }
                        } label: { if busy { ProgressView() } else { Text("Undo all") } }
                        .buttonStyle(.glass).disabled(busy)
                    }
                    Spacer()
                    Button("OK") { withAnimation(.smooth) { store.markChangesSeen() } }.buttonStyle(.glassProminent)
                }
            }
            .card(padding: 14).padding(.bottom, 10)
        }
    }
}

/// The system email composer, inside the app. `finished` gets the result once it closes.
struct MailComposer: UIViewControllerRepresentable {
    let to: [String]
    let subject: String
    let body: String
    var finished: @MainActor (MFMailComposeResult) -> Void
    static var available: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to); vc.setSubject(subject); vc.setMessageBody(body, isHTML: false)
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finished: @MainActor (MFMailComposeResult) -> Void
        init(finished: @escaping @MainActor (MFMailComposeResult) -> Void) { self.finished = finished }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
                finished(result)
            }
        }
    }
}
