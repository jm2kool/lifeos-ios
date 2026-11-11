import SwiftUI

/// Where everything sits on the player's turntable deck, for a square deck of side `size`. The tonearm turns
/// about a pivot at the top right; its needle sweeps from the outer groove (start of the song) to the inner
/// groove (end), so its angle *is* the song's progress.
struct DeckGeometry {
    let size: CGFloat

    var center: CGPoint { CGPoint(x: size * 0.45, y: size * 0.5) }
    var radius: CGFloat { size * 0.42 }
    var pivot: CGPoint { CGPoint(x: size * 0.9, y: size * 0.12) }
    private var dist: Double { Double(hypot(pivot.x - center.x, pivot.y - center.y)) }
    /// Pivot to needle.
    var length: Double { dist * 0.97 }
    private var phi: Double { atan2(Double(center.y - pivot.y), Double(center.x - pivot.x)) }

    /// The arm angle (radians, screen coordinates) that puts the needle `r` from the record's centre.
    func angle(forRadius r: CGFloat) -> Double {
        let r = Double(r)
        let c = max(-1, min(1, (length * length + dist * dist - r * r) / (2 * length * dist)))
        return phi - acos(c)
    }

    var rest: Double { angle(forRadius: radius * 1.18) }
    var outer: Double { angle(forRadius: radius * 0.93) }
    var inner: Double { angle(forRadius: radius * 0.45) }

    func needle(_ a: Double) -> CGPoint { CGPoint(x: pivot.x + length * cos(a), y: pivot.y + length * sin(a)) }
    func angle(progress p: Double) -> Double { outer + (inner - outer) * min(1, max(0, p)) }
    func progress(_ a: Double) -> Double { (a - outer) / (inner - outer) }
    /// The angle from the pivot to a finger, kept between resting and the inner groove.
    func armAngle(towards p: CGPoint) -> Double {
        min(inner, max(rest, atan2(Double(p.y - pivot.y), Double(p.x - pivot.x))))
    }

    /// How far a point is from the arm (pivot → needle), for deciding whether a drag picked the arm up.
    func distanceToArm(_ p: CGPoint, angle a: Double) -> CGFloat {
        let n = needle(a)
        let dx = n.x - pivot.x, dy = n.y - pivot.y
        let t = max(0, min(1, ((p.x - pivot.x) * dx + (p.y - pivot.y) * dy) / (dx * dx + dy * dy)))
        return hypot(p.x - (pivot.x + t * dx), p.y - (pivot.y + t * dy))
    }

    func isOnRecord(_ p: CGPoint) -> Bool { hypot(p.x - center.x, p.y - center.y) <= radius }
    /// The centre label (the cover printed in the middle of the record).
    func isOnLabel(_ p: CGPoint) -> Bool { hypot(p.x - center.x, p.y - center.y) <= radius * 0.38 }
}

/// The arm's movement between frames: it glides to where the song is (so a seek or a skip never jumps), and
/// estimates the song's position between samples so it moves smoothly without asking the player every frame.
/// A plain class (not observed): the TimelineView reads it every frame.
@MainActor
final class ArmState {
    private(set) var angle: Double?
    private var last: Date?
    private var sampleTime = 0.0
    private var sampleDate = Date.distantPast
    /// Lifted off the record by hand: rests until the music plays again.
    var parked = false

    func time(at date: Date, player: PlaybackCoordinator) -> Double {
        if date.timeIntervalSince(sampleDate) > 0.5 { sample(player.currentTime, at: date) }
        return sampleTime + (player.isPlaying ? date.timeIntervalSince(sampleDate) : 0)
    }

    func sample(_ t: Double, at date: Date = .now) { sampleTime = t; sampleDate = date }

    func angle(at date: Date, target: Double) -> Double {
        let dt = min(0.1, last.map { date.timeIntervalSince($0) } ?? 0)
        last = date
        guard let current = angle else { angle = target; return target }
        let next = current + (target - current) * min(1, dt * 5)
        angle = next
        return next
    }

    /// Puts the arm exactly here (after a drag), so it doesn't glide back from where it was.
    func set(_ a: Double) { angle = a }
}

/// The tonearm, drawn from the pivot: counterweight, a brushed tube, the headshell, and a shadow that grows
/// when the arm is lifted.
enum TonearmDrawing {
    static func draw(_ ctx: inout GraphicsContext, deck d: DeckGeometry, angle a: Double, lifted: Bool) {
        let s = d.size
        let dir = CGPoint(x: cos(a), y: sin(a))
        let needle = d.needle(a)
        let back = CGPoint(x: d.pivot.x - dir.x * s * 0.1, y: d.pivot.y - dir.y * s * 0.1)
        let shellStart = CGPoint(x: needle.x - dir.x * s * 0.07, y: needle.y - dir.y * s * 0.07)

        var tube = Path()
        tube.move(to: back)
        tube.addLine(to: shellStart)

        // Shell: a short block turned in a little towards the record, as on a real arm.
        let turn = a + 0.35
        let shellEnd = CGPoint(x: shellStart.x + cos(turn) * s * 0.085, y: shellStart.y + sin(turn) * s * 0.085)
        var shell = Path()
        shell.move(to: shellStart)
        shell.addLine(to: shellEnd)

        var shadowCtx = ctx
        let lift: CGFloat = lifted ? s * 0.03 : s * 0.012
        shadowCtx.translateBy(x: lift * 0.6, y: lift)
        shadowCtx.addFilter(.blur(radius: lifted ? 6 : 3))
        shadowCtx.stroke(tube, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
        shadowCtx.stroke(shell, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))

        ctx.stroke(tube, with: .linearGradient(Gradient(colors: [Color(white: 0.82), Color(white: 0.5)]), startPoint: back, endPoint: shellStart),
                   style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
        ctx.stroke(shell, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
        ctx.stroke(shell, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: s * 0.012, lineCap: .round))

        // Counterweight and pivot.
        let w = s * 0.075
        ctx.fill(Path(ellipseIn: CGRect(x: back.x - w / 2, y: back.y - w / 2, width: w, height: w)), with: .color(Color(white: 0.28)))
        let p = s * 0.11
        ctx.fill(Path(ellipseIn: CGRect(x: d.pivot.x - p / 2, y: d.pivot.y - p / 2, width: p, height: p)), with: .color(Color(white: 0.13)))
        ctx.stroke(Path(ellipseIn: CGRect(x: d.pivot.x - p / 2, y: d.pivot.y - p / 2, width: p, height: p)), with: .color(.white.opacity(0.1)), lineWidth: 1)
        let c = s * 0.04
        ctx.fill(Path(ellipseIn: CGRect(x: d.pivot.x - c / 2, y: d.pivot.y - c / 2, width: c, height: c)), with: .color(Color(white: 0.6)))
    }

    /// The platter under the record, with strobe dots round its rim.
    static func platter(_ ctx: inout GraphicsContext, deck d: DeckGeometry, spin: Double) {
        let r = d.radius * 1.06
        ctx.fill(Path(ellipseIn: CGRect(x: d.center.x - r, y: d.center.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.11)))
        for i in 0..<72 {
            let a = Double(i) / 72 * 2 * .pi + spin
            let p = CGPoint(x: d.center.x + cos(a) * r * 0.975, y: d.center.y + sin(a) * r * 0.975)
            let dot = r * 0.012
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)), with: .color(.white.opacity(0.16)))
        }
    }
}
