import SwiftUI
import UIKit

/// The five Phase 0 spikes from SPEC.md §10.
enum SpikeID: String, CaseIterable, Identifiable, Sendable {
    case lockScreen = "A", intelligence = "B", deezer = "C", libraryPlayback = "D", instagram = "E"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Full-screen lock screen art"
        case .intelligence: "Apple Intelligence"
        case .deezer: "Deezer artist photos"
        case .libraryPlayback: "Library playback"
        case .instagram: "Instagram Stories video"
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: "lock.rectangle.stack"
        case .intelligence: "apple.intelligence"
        case .deezer: "person.crop.square"
        case .libraryPlayback: "music.note.list"
        case .instagram: "camera.circle"
        }
    }
}

/// What a spike showed.
enum Verdict: String, Sendable {
    case untested = "NOT TESTED", works = "WORKS", partial = "PARTLY", fails = "FAILS"

    var color: Color {
        switch self {
        case .untested: .white.opacity(0.35)
        case .works: .green
        case .partial: .orange
        case .fails: .red
        }
    }
}

/// Collects verdicts and log lines from every spike, so the whole result can be copied and sent back in one go.
@MainActor @Observable
final class SpikeReport {
    static let shared = SpikeReport()

    private(set) var verdicts: [SpikeID: Verdict] = [:]
    private(set) var logs: [SpikeID: [String]] = [:]

    func verdict(_ id: SpikeID) -> Verdict { verdicts[id] ?? .untested }

    func set(_ id: SpikeID, _ verdict: Verdict, because note: String? = nil) {
        verdicts[id] = verdict
        if let note { log(id, "VERDICT \(verdict.rawValue): \(note)") }
    }

    func log(_ id: SpikeID, _ line: String) {
        let stamp = Date.now.formatted(.dateTime.hour().minute().second())
        logs[id, default: []].append("[\(stamp)] \(line)")
    }

    func lines(_ id: SpikeID) -> [String] { logs[id] ?? [] }

    /// Plain-text report to paste back to the coding agent.
    var text: String {
        let device = UIDevice.current
        var out = ["\(AppBrand.name) Phase 0 report",
                   "iOS \(device.systemVersion) · \(Self.modelIdentifier) · Low Power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off")",
                   ""]
        for id in SpikeID.allCases {
            out.append("== \(id.rawValue). \(id.title): \(verdict(id).rawValue)")
            out.append(contentsOf: lines(id))
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
