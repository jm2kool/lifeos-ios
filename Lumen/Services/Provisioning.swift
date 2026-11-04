import Foundation

/// What the sideloading tool's provisioning profile actually grants this install (embedded.mobileprovision).
/// Push needs `aps-environment` and Screen Time needs `com.apple.developer.family-controls`; a free Apple ID's profile
/// has neither, so features check here and step aside instead of failing.
enum Provisioning {
    static let entitlements: [String: Any] = {
        #if targetEnvironment(simulator)
        return [:]
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>") else { return [:] }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any] else { return [:] }
        return plist["Entitlements"] as? [String: Any] ?? [:]
        #endif
    }()

    static func has(_ key: String) -> Bool {
        if let b = entitlements[key] as? Bool { return b }
        return entitlements[key] != nil
    }

    /// "sandbox" or "production" for APNs, or nil when this install can't receive pushes.
    static var apnsEnvironment: String? {
        switch entitlements["aps-environment"] as? String {
        case "production": return "production"
        case "development": return "sandbox"
        default: return nil
        }
    }
}
