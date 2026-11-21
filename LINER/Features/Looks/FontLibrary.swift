import CoreText
import UIKit

/// Fonts for album faces: the iPhone's own families plus `.ttf` / `.otf` files you import, which are copied into
/// Application Support/LINER/Fonts and registered for LINER. each launch.
@MainActor
enum FontLibrary {
    static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "LINER/Fonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var registered = false

    /// Registers every imported font (once per launch).
    static func registerImported() {
        guard !registered else { return }
        registered = true
        for url in files() { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    private static func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
    }

    /// The families of the fonts you imported.
    static func importedFamilies() -> [String] {
        Array(Set(files().flatMap(families(in:)))).sorted()
    }

    /// The iPhone's font families (without the ones only for system use).
    static func systemFamilies() -> [String] {
        UIFont.familyNames.filter { !$0.hasPrefix(".") }.sorted()
    }

    private static func families(in url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return [] }
        return descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
    }

    /// Copies a font file in and registers it. Returns its family name, or nil when it isn't a font.
    static func importFont(from source: URL) -> String? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let family = families(in: source).first else { return nil }
        let target = folder.appending(path: source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { return nil }
            CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
        }
        return family
    }

    /// Imported font files, for backups.
    static func exported() -> [String: Data] {
        Dictionary(uniqueKeysWithValues: files().compactMap { url in (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) } })
    }

    static func restore(_ fonts: [String: Data]) {
        for (name, data) in fonts {
            let target = folder.appending(path: (name as NSString).lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)),
                  (try? data.write(to: target, options: .atomic)) != nil else { continue }
            CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
        }
    }
}
