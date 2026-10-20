import SwiftUI

/// Log a viewing: when, how much you liked it, and what you thought — all on one screen.
struct LogSheet: View {
    let film: FilmRef
    let existing: LogEntry?
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var rating: Double?
    @State private var liked = false
    @State private var rewatch = false
    @State private var review = ""
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var showCalendar = false
    @FocusState private var reviewFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        PosterView(film: film, width: 70, corner: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(film.title).font(.title3.weight(.bold)).lineLimit(2)
                            Text(film.yearText).foregroundStyle(Theme.dim)
                            if !library.entries(for: film.id).isEmpty && existing == nil {
                                Label("You've seen this before", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.watch)
                            }
                        }
                    }

                    // When
                    VStack(alignment: .leading, spacing: 10) {
                        label("Watched")
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                chip("Today", Calendar.current.isDateInToday(date)) { date = .now; showCalendar = false }
                                chip("Yesterday", Calendar.current.isDateInYesterday(date)) {
                                    date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!; showCalendar = false
                                }
                                chip(isCustomDate ? date.formatted(.dateTime.day().month(.abbreviated)) : "Pick date", isCustomDate || showCalendar) {
                                    withAnimation(.smooth) { showCalendar.toggle() }
                                }
                            }
                        }
                        if showCalendar {
                            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .padding(8)
                                .background(Theme.card, in: .rect(cornerRadius: 20))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // Rating + like
                    VStack(alignment: .leading, spacing: 10) {
                        label("Rating")
                        HStack {
                            StarRating(rating: rating, size: 34, spacing: 7) { rating = $0 }
                            Spacer()
                            Button { liked.toggle(); UIImpactFeedbackGenerator(style: .medium).impactOccurred() } label: {
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(.system(size: 30))
                                    .foregroundStyle(liked ? Theme.heart : .white.opacity(0.5))
                                    .symbolEffect(.bounce, value: liked)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(liked ? "Liked" : "Like")
                        }
                        Text(rating.map { "\(Stars.text($0))  ·  \(ratingWord($0))" } ?? "Slide across the stars — half stars work too")
                            .font(.footnote).foregroundStyle(Theme.dim)
                    }

                    Toggle(isOn: $rewatch) {
                        Label("I've seen this before", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(Theme.watch)

                    // Review
                    VStack(alignment: .leading, spacing: 10) {
                        label("Review")
                        TextField("What did you think?", text: $review, axis: .vertical)
                            .lineLimit(4...12)
                            .focused($reviewFocused)
                            .padding(14)
                            .background(Theme.card, in: .rect(cornerRadius: 18))
                    }

                    // Tags
                    VStack(alignment: .leading, spacing: 10) {
                        label("Tags")
                        FlowTags(tags: tags) { t in tags.removeAll { $0 == t } }
                        HStack {
                            TextField("Add a tag (who with, where…)", text: $tagDraft)
                                .textInputAutocapitalization(.never)
                                .onSubmit(addTag)
                            if !tagDraft.isEmpty { Button("Add", action: addTag).fontWeight(.semibold) }
                        }
                        .padding(14)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                        let suggestions = library.allTags.filter { !tags.contains($0) && (tagDraft.isEmpty || $0.hasPrefix(tagDraft.lowercased())) }
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal) {
                                HStack { ForEach(suggestions.prefix(10), id: \.self) { t in Button("#\(t)") { tags.append(t); tagDraft = "" }.buttonStyle(.glass).controlSize(.small) } }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }

                    if let existing {
                        Button(role: .destructive) { library.delete(existing); dismiss() } label: {
                            Label("Delete this entry", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .oledBackground()
            .navigationTitle(existing == nil ? "Log film" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }.buttonStyle(.glassProminent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
    }

    private var isCustomDate: Bool { !Calendar.current.isDateInToday(date) && !Calendar.current.isDateInYesterday(date) }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
    }

    private func chip(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(t).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity) }
            .buttonStyle(.glass)
            .tint(on ? Theme.accent : nil)
            .controlSize(.large)
            .overlay(Capsule().strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5).allowsHitTesting(false))
    }

    private func ratingWord(_ r: Double) -> String {
        switch r {
        case ..<1.5: return "Not for me"
        case ..<2.5: return "Meh"
        case ..<3.5: return "Good"
        case ..<4.5: return "Great"
        default: return "Masterpiece"
        }
    }

    private func addTag() {
        let t = tagDraft.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        if !t.isEmpty && !tags.contains(t) { tags.append(t) }
        tagDraft = ""
    }

    private func prefill() {
        if let e = existing {
            date = e.watchedOn; rating = e.rating; liked = e.liked; rewatch = e.rewatch; review = e.review; tags = e.tags
        } else {
            rating = library.rating(film.id)
            liked = library.isLiked(film.id)
            rewatch = !library.entries(for: film.id).isEmpty
        }
    }

    private func save() {
        addTag()
        var e = existing ?? LogEntry(film: film)
        e.watchedOn = date; e.rating = rating; e.liked = liked; e.rewatch = rewatch
        e.review = review.trimmingCharacters(in: .whitespacesAndNewlines); e.tags = tags
        library.log(e)
        if !liked && library.isLiked(film.id) { library.toggleLike(film) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

struct FlowTags: View {
    let tags: [String]
    var onRemove: ((String) -> Void)? = nil
    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { t in
                        HStack(spacing: 4) {
                            Text("#\(t)")
                            if onRemove != nil { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.18), in: .capsule)
                        .foregroundStyle(Theme.accent)
                        .onTapGesture { onRemove?(t) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
