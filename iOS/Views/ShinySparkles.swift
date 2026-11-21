import SwiftUI

/// The shiny sparkle: two waves of big glowing stars bursting out in a ring, like the games' shiny animation.
/// Set `start` to the moment it should begin.
struct ShinySparkles: View {
    let start: Date?
    var radius: CGFloat = 95
    @State private var done = false

    var body: some View {
        if let start, !done {
            TimelineView(.animation) { tl in
                SparkleFrame(elapsed: tl.date.timeIntervalSince(start), radius: radius)
            }
            .allowsHitTesting(false)
            .task(id: start) {
                try? await Task.sleep(for: .seconds(1.5))
                done = true
            }
        }
    }
}

private struct SparkleFrame: View {
    let elapsed: Double
    let radius: CGFloat

    var body: some View {
        ZStack {
            SparkleWave(t: (elapsed - 0.0) / 0.95, turn: 0, radius: radius)
            SparkleWave(t: (elapsed - 0.32) / 0.95, turn: 1.0 / 16, radius: radius)
            // a bright flash in the middle as it starts
            Circle().fill(.white)
                .frame(width: radius * 1.2, height: radius * 1.2)
                .blur(radius: 22)
                .opacity(max(0, 0.55 - elapsed * 1.4))
        }
    }
}

private struct SparkleWave: View {
    let t: Double
    let turn: Double
    let radius: CGFloat

    var body: some View {
        if t > 0 && t < 1 {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    SparkleStar(index: i, t: t, angle: (Double(i) / 8 + turn) * 2 * Double.pi - Double.pi / 2,
                                radius: radius)
                }
            }
        }
    }
}

private struct SparkleStar: View {
    let index: Int
    let t: Double
    let angle: Double
    let radius: CGFloat

    private static let gold = Color(hex: 0xFFE27A)

    var body: some View {
        let big = index % 2 == 0
        let eased: Double = 1 - pow(1 - t, 2.2)
        let r: CGFloat = radius * CGFloat(0.25 + 0.85 * eased)
        let scale: Double = 0.35 + 0.95 * sin(Double.pi * min(1, t * 1.15))
        let fade: Double = t < 0.75 ? 1 : (1 - t) / 0.25
        let dx: CGFloat = CGFloat(cos(angle)) * r
        let dy: CGFloat = CGFloat(sin(angle)) * r
        return Image(systemName: big ? "sparkle" : "star.fill")
            .font(.system(size: big ? 30 : 20, weight: .black))
            .foregroundStyle(big ? Color.white : Self.gold)
            .shadow(color: Self.gold, radius: 6)
            .shadow(color: Color.white.opacity(0.8), radius: 2)
            .scaleEffect(scale)
            .rotationEffect(.degrees(t * 90))
            .opacity(fade)
            .offset(x: dx, y: dy)
    }
}
