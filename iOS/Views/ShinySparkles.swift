import SwiftUI

/// The shiny sparkle: two waves of big glowing stars bursting out in a ring, like the games' shiny animation.
/// Set `start` to the moment it should begin.
struct ShinySparkles: View {
    let start: Date?
    var radius: CGFloat = 95
    @State private var done = false

    private static let gold = Color(hex: 0xFFE27A)

    var body: some View {
        if let start, !done {
            TimelineView(.animation) { tl in
                let elapsed = tl.date.timeIntervalSince(start)
                ZStack {
                    ForEach(0..<2, id: \.self) { wave in
                        let t = (elapsed - Double(wave) * 0.32) / 0.95
                        if t > 0 && t < 1 {
                            ForEach(0..<8, id: \.self) { i in
                                let a = (Double(i) / 8 + Double(wave) / 16) * 2 * .pi - .pi / 2
                                let eased = 1 - pow(1 - t, 2.2)
                                let r = radius * (0.25 + 0.85 * eased)
                                Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "star.fill")
                                    .font(.system(size: i.isMultiple(of: 2) ? 30 : 20, weight: .black))
                                    .foregroundStyle(i.isMultiple(of: 2) ? .white : Self.gold)
                                    .shadow(color: Self.gold, radius: 6)
                                    .shadow(color: .white.opacity(0.8), radius: 2)
                                    .scaleEffect(0.35 + 0.95 * sin(.pi * min(1, t * 1.15)))
                                    .rotationEffect(.degrees(t * 90))
                                    .opacity(t < 0.75 ? 1 : (1 - t) / 0.25)
                                    .offset(x: cos(a) * r, y: sin(a) * r)
                            }
                        }
                    }
                    // a bright flash in the middle as it starts
                    Circle().fill(.white).frame(width: radius * 1.2, height: radius * 1.2).blur(radius: 22)
                        .opacity(max(0, 0.55 - elapsed * 1.4))
                }
            }
            .allowsHitTesting(false)
            .task(id: start) {
                try? await Task.sleep(for: .seconds(1.5))
                done = true
            }
        }
    }
}
