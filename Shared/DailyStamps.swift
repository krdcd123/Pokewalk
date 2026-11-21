import Foundation

/// Daily stamps on the back of the trainer card: opening the game stamps today (resets at midnight).
/// Every 7 days in a row earns a reward; missing a day starts the streak again.
enum DailyStamps {
    static let rewardEvery = 7
    /// The 7-day reward.
    static let rewardBalls: [(BallKind, Int)] = [(.ultra, 3)]
    static let rewardItems: [(String, Int)] = [("rare-candy", 1)]
    static let rewardMoney = 500
    static var rewardText: String { "3 Ultra Balls, a Rare Candy and ₽\(rewardMoney)" }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Days in a row up to today (or up to yesterday, if today isn't stamped yet).
    static func streak(_ s: GameState, now: Date = .now) -> Int {
        let days = Set(s.stampDays)
        let cal = Calendar.current
        var d = cal.startOfDay(for: now)
        if !days.contains(key(d)) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(key(d)) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }

    static func stampedToday(_ s: GameState, now: Date = .now) -> Bool { s.stampDays.contains(key(now)) }

    /// Stamps today. Returns (new streak, reward earned) or nil if today was already stamped.
    static func stamp(_ s: inout GameState, now: Date = .now) -> (streak: Int, reward: Bool)? {
        let k = key(now)
        guard !s.stampDays.contains(k) else { return nil }
        s.stampDays.append(k)
        if s.stampDays.count > 400 { s.stampDays.removeFirst(s.stampDays.count - 400) }
        let n = streak(s, now: now)
        let reward = n > 0 && n % rewardEvery == 0
        if reward {
            for (b, c) in rewardBalls { s.balls[b, default: 0] += c }
            for (i, c) in rewardItems { s.bag[i, default: 0] += c }
            s.money += rewardMoney
        }
        return (n, reward)
    }
}
