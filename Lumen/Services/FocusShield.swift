import Foundation
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

/// Blocks distracting apps during focus with Screen Time. This needs Apple's Family Controls entitlement, which a
/// free Apple ID (and most sideloading) can't get: without it the switch is hidden and nothing here runs.
@Observable @MainActor
final class FocusShield {
    static let shared = FocusShield()

    /// The build carries the entitlement (read from the provisioning profile the sideloading tool embedded).
    let available: Bool
    private(set) var authorized = false
    private(set) var problem: String?

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "shield.enabled") } }

    #if canImport(FamilyControls)
    var selection = FamilyActivitySelection() {
        didSet { if let d = try? JSONEncoder().encode(selection) { UserDefaults.standard.set(d, forKey: "shield.selection") } }
    }
    private let settings = ManagedSettingsStore(named: ManagedSettingsStore.Name("lumen.focus"))
    #endif

    private init() {
        available = Self.hasEntitlement("com.apple.developer.family-controls")
        enabled = UserDefaults.standard.bool(forKey: "shield.enabled")
        #if canImport(FamilyControls)
        if let d = UserDefaults.standard.data(forKey: "shield.selection"), let s = try? JSONDecoder().decode(FamilyActivitySelection.self, from: d) {
            selection = s
        }
        if available { authorized = AuthorizationCenter.shared.authorizationStatus == .approved }
        #endif
    }

    var selectedCount: Int {
        #if canImport(FamilyControls)
        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        #else
        return 0
        #endif
    }

    func authorize() async {
        guard available else { return }
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            problem = nil
        } catch {
            authorized = false
            problem = "Screen Time said no: \(error.localizedDescription)"
        }
        #endif
    }

    func engage() {
        guard available, authorized, enabled else { return }
        #if canImport(FamilyControls)
        settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        #endif
    }

    func release() {
        guard available else { return }
        #if canImport(FamilyControls)
        settings.clearAllSettings()
        #endif
    }

    /// Looks for an entitlement in embedded.mobileprovision. A build without a profile (or without the
    /// entitlement) gets false, so Screen Time is never touched.
    static func hasEntitlement(_ key: String) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>") else { return false }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any] else { return false }
        if let b = ent[key] as? Bool { return b }
        return ent[key] != nil
        #endif
    }
}

#if canImport(FamilyControls)
/// Pick the apps and categories to block.
struct ShieldPicker: View {
    @Bindable var shield = FocusShield.shared
    @State private var showing = false
    var body: some View {
        Button {
            showing = true
        } label: {
            LabeledContent("Apps to block", value: shield.selectedCount == 0 ? "None" : "\(shield.selectedCount) chosen")
        }
        .familyActivityPicker(isPresented: $showing, selection: $shield.selection)
    }
}
#endif
