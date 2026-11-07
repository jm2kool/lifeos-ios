import SwiftUI

/// The app's name in one place, so a rename is a one-line change (plus the display name in project.yml).
enum AppBrand {
    /// Rename in Settings → About (or change the default here and the display name in project.yml).
    static var name: String {
        let custom = UserDefaults.standard.string(forKey: "brandName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? "LINER." : custom
    }
    static let tagline = "Your music. Your history."

    /// The Facebook app ID Instagram asks for as the story source, read from Info.plist (`LINERFacebookAppID`).
    static var facebookAppID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LINERFacebookAppID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
