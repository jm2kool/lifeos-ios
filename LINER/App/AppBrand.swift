import SwiftUI

/// The app's name in one place, so a rename is a one-line change (plus the display name in project.yml).
enum AppBrand {
    static let name = "LINER."
    static let tagline = "Your music. Your history."

    /// The Facebook app ID Instagram asks for as the story source, read from Info.plist (`LINERFacebookAppID`).
    static var facebookAppID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LINERFacebookAppID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
