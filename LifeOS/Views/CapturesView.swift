import SwiftUI

extension Store {
    /// Captures Gemini wasn't sure about (or couldn't sort), waiting for you to check where they went.
    var capturesToReview: [JSON] { content["captures"].array.filter { $0["review"].bool } }
    /// The More tab gets a review dot while a draft (if Drafts is under More) or an unsure capture waits for you.
    var moreNeedsReview: Bool { (moreTabs.contains(.drafts) && !pendingDrafts.isEmpty) || !capturesToReview.isEmpty }
    /// Screens whose row in More shows a review dot instead of a count.
    func reviewDot(for t: AppTab) -> Bool { t == .drafts && !pendingDrafts.isEmpty }
    /// The count shown next to a screen's row in More.
    func badge(for t: AppTab) -> Int {
        switch t {
        case .inbox: return inboxTodo.count
        case .board: return cards.filter { $0.column < 2 }.count
        default: return 0
        }
    }
    func markCaptureReviewed(_ id: String) {
        let list = content["captures"].array.map { c -> JSON in var c = c; if c["id"].str == id { c["review"] = .null }; return c }
        act(["op": "content.set", "path": "captures", "value": .array(list)], quiet: true)
    }
}

/// More › Captured: everything you've said or typed into Capture, and where it went.
struct CapturesView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        let list = store.content["captures"].array
        List {
            if !store.capturesToReview.isEmpty {
                Section { Text("Gemini wasn't sure about these, or couldn't sort them. Check where they went, then tap Looks right.").font(.footnote).foregroundStyle(.secondary) }
            }
            ForEach(list, id: \.self) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        if c["review"].bool { Circle().fill(.orange).frame(width: 8, height: 8).accessibilityLabel("Needs review") }
                        Text(c["summary"].str).font(.subheadline.weight(.semibold))
                    }
                    Text("“\(c["text"].str)”").font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    Text(c["source"].str + " · " + store.ago(c["at"].double ?? 0)).font(.caption).foregroundStyle(.tertiary)
                    HStack(spacing: 10) {
                        if c["review"].bool { Button("Looks right") { store.markCaptureReviewed(c["id"].str) }.buttonStyle(.glassProminent) }
                        if c["target"].isObject { Button("Open") { store.markCaptureReviewed(c["id"].str); store.open(c["target"]) }.buttonStyle(.glass) }
                        if let f = c["friday"].string { Button("Tell \(store.assistantName)") { tell(f) }.buttonStyle(.glass) }
                    }
                    .controlSize(.small).padding(.top, 2)
                }
                .padding(.vertical, 4)
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        store.act(["op": "content.set", "path": "captures", "value": .array(list.filter { $0["id"] != c["id"] })], quiet: true)
                    }
                }
            }
        }
        .navigationTitle("Captured")
        .pageBackground()
    }
    private func tell(_ text: String) {
        guard !store.assistantAddress.isEmpty else { store.sheet = .delegate(text); return }
        var c = URLComponents(); c.scheme = "sms"; c.path = store.assistantAddress
        c.queryItems = [URLQueryItem(name: "body", value: text)]
        if let u = c.url { openURL(u) }
    }
}

/// The small red dot that means "waiting for your review".
struct ReviewDot: View {
    var body: some View {
        Circle().fill(.red).frame(width: 9, height: 9).accessibilityLabel("Waiting for review")
    }
}
