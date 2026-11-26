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
        [Reward(kind: .ball(.poke), count: 3)],
        [Reward(kind: .item("pomeg-berry"), count: 3)],
        [Reward(kind: .ball(.great), count: 2)],
        [Reward(kind: .item("exp-candy-m"), count: 1)],
        [Reward(kind: .money, count: 200)],
        [Reward(kind: .ball(.ultra), count: 1)],
        [],   // Day 7: a present — see `present(for:)`
    ]

    /// Day 7's present: a different bundle each week, all worth about the same.
    static let presents: [[Reward]] = [
        [Reward(kind: .item("rare-candy"), count: 2), Reward(kind: .ball(.ultra), count: 3), Reward(kind: .money, count: 500)],
        [Reward(kind: .item("exp-candy-l"), count: 1), Reward(kind: .ball(.ultra), count: 3)],
        [Reward(kind: .item("rare-candy"), count: 1), Reward(kind: .item("exp-candy-m"), count: 2), Reward(kind: .money, count: 800)],
        [Reward(kind: .item("rare-candy"), count: 1), Reward(kind: .ball(.timer), count: 2), Reward(kind: .ball(.nest), count: 2),
         Reward(kind: .money, count: 300)],
        [Reward(kind: .item("moon-stone"), count: 1), Reward(kind: .ball(.ultra), count: 3), Reward(kind: .money, count: 400)],
        [Reward(kind: .item("nugget"), count: 1), Reward(kind: .item("rare-candy"), count: 1), Reward(kind: .ball(.great), count: 3)],
        [Reward(kind: .item("star-piece"), count: 1), Reward(kind: .ball(.luxury), count: 2), Reward(kind: .item("rare-candy"), count: 1),
         Reward(kind: .money, count: 500)],
    ]

    /// This week's present (picked from the week, so it stays the same all week but changes every Monday).
    static func present(for now: Date = DailyStamps.clock) -> [Reward] {
        let weeks = Int(weekStart(now).timeIntervalSince1970 / (7 * 86_400))
        // scramble the order a little so it doesn't just cycle 1, 2, 3…
        let i = ((weeks &* 40_503) &+ 7) % presents.count
        return presents[abs(i)]
    }

    static func rewards(day i: Int, now: Date = DailyStamps.clock) -> [Reward] { i == days - 1 ? present(for: now) : rewards[i] }

    /// Days 1–6 are mystery presents too: each stamp rolls one of these small rewards (all worth about the same).
    static func rollDaily() -> [Reward] {
        let berry = ItemCatalog.berries.randomElement() ?? "pomeg-berry"
        let pool: [[Reward]] = [
            [Reward(kind: .ball(.poke), count: 3)],
            [Reward(kind: .ball(.great), count: 2)],
            [Reward(kind: .ball(.ultra), count: 1)],
            [Reward(kind: .item(berry), count: 3)],
            [Reward(kind: .item("exp-candy-m"), count: 1)],
            [Reward(kind: .item("exp-candy-s"), count: 3)],
            [Reward(kind: .money, count: 200)],
            [Reward(kind: .item(Fishing.baitKey(berries: 4)), count: 1)],
            [Reward(kind: .item(Fishing.lureKey(berries: 2)), count: 1)],
        ]
        return pool.randomElement()!
    }

    /// "iconKey|badge" of what a stamped day gave you, to show on the card ("money" for ₽).
    static func record(_ rs: [Reward]) -> String {
        guard rs.count == 1, let r = rs.first else { return "present|\(rs.count)" }
        switch r.kind {
        case .money: return "money|₽\(r.count)"
        default: return "\(r.iconKey ?? "present")|×\(r.count)"
        }
    }

    static func text(_ rs: [Reward]) -> String {
        let parts = rs.map(\.text)
        return parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? ""
    }

    /// The stamp day starts at 7am: before then it still counts as yesterday's card.
    static let dayStartsAtHour = 7
    static var clock: Date { Date().addingTimeInterval(-Double(dayStartsAtHour) * 3600) }

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
    static func stampedThisWeek(_ s: GameState, now: Date = DailyStamps.clock) -> Int {
        let start = weekStart(now)
        let keys = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }.map(key)
        return Set(s.stampDays).intersection(keys).count
    }

    static func stampedToday(_ s: GameState, now: Date = DailyStamps.clock) -> Bool { s.stampDays.contains(key(now)) }

    /// Stamps today's box and gives its reward. Returns (day number 1–7, rewards) or nil if already stamped
    /// today (or this week's card is full).
    static func stamp(_ s: inout GameState, now: Date = DailyStamps.clock) -> (day: Int, rewards: [Reward])? {
        let k = key(now)
        let done = stampedThisWeek(s, now: now)
        guard !s.stampDays.contains(k), done < days else { return nil }
        s.stampDays.append(k)
        if s.stampDays.count > 400 { s.stampDays.removeFirst(s.stampDays.count - 400) }
        let rs = done == days - 1 ? present(for: now) : rollDaily()
        s.stampGot[k] = record(rs)
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
