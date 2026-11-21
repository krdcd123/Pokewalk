import Foundation

/// The weekly stamp card on the back of the trainer card (like Pokémon Sleep's reward stamp cards):
/// opening the game stamps the next day's box (once a day, resets at midnight) and gives that day's small
/// reward. Day 7 is the big one. A fresh card starts every Monday.
enum DailyStamps {
    struct Reward {
        enum Kind {
            case ball(BallKind), item(String), money
            var isMoney: Bool { if case .money = self { return true }; return false }
        }
        var kind: Kind
        var count: Int
        var big = false

        /// Item key for the icon (money uses an icon of its own).
        var iconKey: String? {
            switch kind {
            case .ball(let b): return b.itemKey
            case .item(let k): return k
            case .money: return nil
            }
        }

        var text: String {
            switch kind {
            case .ball(let b): return "\(count) \(b.name)\(count == 1 ? "" : "s")"
            case .item(let k): return count == 1 ? "a \(Dex.itemName(k))" : "\(count) \(Dex.itemName(k))s"
            case .money: return "₽\(count)"
            }
        }
    }

    static let days = 7
    static let rewards: [[Reward]] = [
        [Reward(kind: .ball(.poke), count: 5)],
        [Reward(kind: .item("pomeg-berry"), count: 3)],
        [Reward(kind: .ball(.great), count: 3)],
        [Reward(kind: .item("exp-candy-m"), count: 1)],
        [Reward(kind: .money, count: 200)],
        [Reward(kind: .ball(.ultra), count: 2)],
        // Day 7: the big one
        [Reward(kind: .item("rare-candy"), count: 2, big: true), Reward(kind: .ball(.ultra), count: 3, big: true),
         Reward(kind: .money, count: 500, big: true)],
    ]

    static func text(_ rs: [Reward]) -> String {
        let parts = rs.map(\.text)
        return parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? ""
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Monday of the week `d` is in.
    static func weekStart(_ d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
    }

    /// How many boxes are stamped on this week's card.
    static func stampedThisWeek(_ s: GameState, now: Date = .now) -> Int {
        let start = weekStart(now)
        let keys = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }.map(key)
        return Set(s.stampDays).intersection(keys).count
    }

    static func stampedToday(_ s: GameState, now: Date = .now) -> Bool { s.stampDays.contains(key(now)) }

    /// Stamps today's box and gives its reward. Returns (day number 1–7, rewards) or nil if already stamped
    /// today (or this week's card is full).
    static func stamp(_ s: inout GameState, now: Date = .now) -> (day: Int, rewards: [Reward])? {
        let k = key(now)
        let done = stampedThisWeek(s, now: now)
        guard !s.stampDays.contains(k), done < days else { return nil }
        s.stampDays.append(k)
        if s.stampDays.count > 400 { s.stampDays.removeFirst(s.stampDays.count - 400) }
        let rs = rewards[done]
        for r in rs {
            switch r.kind {
            case .ball(let b): s.balls[b, default: 0] += r.count
            case .item(let i): s.bag[i, default: 0] += r.count
            case .money: s.money += r.count
            }
        }
        return (done + 1, rs)
    }
}
