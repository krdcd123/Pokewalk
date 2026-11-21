import SwiftUI

/// Confetti raining down from the top of the screen (like iMessage's), for a few seconds after `start`.
struct ConfettiRain: View {
    let start: Date?
    @State private var done = false

    private struct Piece {
        var x: Double, delay: Double, speed: Double, sway: Double, swaySpeed: Double
        var spin: Double, size: CGSize, color: Color, round: Bool
    }

    private static let colors: [Color] = ([0xFF4A4A, 0xFFD23A, 0x3AC9FF, 0x6BE36B, 0xC77DFF, 0xFF8FC7, 0xFF9A3A] as [UInt32])
        .map { Color(hex: $0) }

    // made once per view (not on every redraw), so pieces don't jump around
    @State private var pieces: [Piece] = ConfettiRain.makePieces()

    private static func makePieces() -> [Piece] { (0..<140).map { i in
        Piece(x: .random(in: 0...1), delay: .random(in: 0...0.9), speed: .random(in: 0.55...1.0),
              sway: .random(in: 8...28), swaySpeed: .random(in: 2...5), spin: .random(in: -540...540),
              size: CGSize(width: .random(in: 6...10), height: .random(in: 10...16)),
              color: colors[i % colors.count], round: i % 5 == 0)
    } }

    private let duration = 3.6

    var body: some View {
        if let start, !done {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSince(start)
                    for p in pieces {
                        let local = t - p.delay
                        guard local > 0 else { continue }
                        // fall from just above the top to past the bottom
                        let y = -20 + local * p.speed * size.height / 1.9
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(local * p.swaySpeed) * p.sway
                        let fade = t > duration - 0.6 ? max(0, (duration - t) / 0.6) : 1
                        var c = ctx
                        c.opacity = fade
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(p.spin * local))
                        // squash on one axis so pieces look like they're tumbling
                        c.scaleBy(x: 1, y: max(0.15, abs(cos(local * p.swaySpeed * 1.3))))
                        let r = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        c.fill(p.round ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: start) {
                done = false
                try? await Task.sleep(for: .seconds(duration))
                done = true
            }
        }
    }
}
