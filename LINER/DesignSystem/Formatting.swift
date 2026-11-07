import Foundation

extension Double {
    /// "36 MIN" style, rounded to the nearest minute.
    var minutesLabel: String { "\(Int((self / 60).rounded())) MIN" }
    /// "3:41" track time.
    var trackTime: String {
        guard isFinite, self > 0 else { return "–:––" }
        let s = Int(self.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Int {
    /// "1 play" / "42 plays".
    var playsLabel: String { "\(grouped) play\(self == 1 ? "" : "s")" }
}
