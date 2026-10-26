import SwiftUI
import UIKit

/// A story-sized picture of a film — poster, logo and your rating — to share anywhere.
struct ShareCard: View {
    let film: FilmRef
    let poster: UIImage?
    let logo: UIImage?
    let rating: Double?
    let liked: Bool
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            tint.opacity(0.35)
            if let poster {
                Image(uiImage: poster).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1920).clipped()
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.85), location: 0.78),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 34) {
                if let logo {
                    Image(uiImage: logo).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 760, maxHeight: 300)
                        .shadow(color: .black.opacity(0.6), radius: 30)
                } else {
                    Text(film.title).font(.system(size: 110, weight: .bold, design: .serif)).multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.5)
                }
                HStack(spacing: 22) {
                    if let r = rating, r > 0 {
                        if FilmRatingStyle.current == .stars {
                            Text(Stars.text(Score.starsShown(r))).font(.system(size: 84, weight: .semibold)).foregroundStyle(Theme.star)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(Score.text(r)).font(.system(size: 130, weight: .heavy, design: .rounded))
                                Text("/100").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                            }
                            .foregroundStyle(Score.color(r))
                        }
                    }
                    if liked { Image(systemName: "heart.fill").font(.system(size: 70)).foregroundStyle(Theme.heart) }
                }
                Text(film.yearText).font(.system(size: 44, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 14) {
                    MatineeMark().frame(width: 64, height: 64).scaleEffect(1)
                    Text("Matinee").font(.system(size: 50, weight: .heavy, design: .serif))
                }
                .padding(.top, 30)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 90)
            .padding(.bottom, 150)
        }
        .frame(width: 1080, height: 1920)
        .background(Color.black)
    }

    /// Renders the card from images that are already on screen (and so already cached).
    @MainActor
    static func render(film: FilmRef, poster: URL?, logo: URL?, rating: Double?, liked: Bool, tint: Color) async -> UIImage? {
        let p: UIImage? = if let poster { await ImageStore.shared.load(poster) } else { nil }
        let l: UIImage? = if let logo { await ImageStore.shared.load(logo) } else { nil }
        let r = ImageRenderer(content: ShareCard(film: film, poster: p, logo: l, rating: rating, liked: liked, tint: tint))
        r.scale = 1
        return r.uiImage
    }
}
