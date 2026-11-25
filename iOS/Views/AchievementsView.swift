import SwiftUI

/// Menu › 🏆: every achievement, its progress, and rewards to collect.
struct AchievementsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var filter = 0                  // 0 all, 1 to collect, 2 in progress, 3 done
    @State private var confetti: Date?
    @State private var claimed: String?

    var body: some View {
        let s = store.state
        let all = Achievements.all
        let done = all.filter { s.achievementsClaimed.contains($0.id) }.count
        let ready = Achievements.ready(s)
        ScrollView {
            VStack(spacing: 14) {
                // Summary
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "trophy.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(done) of \(all.count)").font(.rounded(24, .black)).foregroundStyle(.white)
                            Text("achievements collected").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if !ready.isEmpty {
                            Button { collectAll(ready) } label: {
                                Text("Collect all (\(ready.count))").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ProgressView(value: Double(done), total: Double(all.count)).tint(.yellow)
                }
                .padding(14)
                .glassCard(22)

                Picker("Show", selection: $filter) {
                    Text("All").tag(0)
                    Text("Collect").tag(1)
                    Text("To do").tag(2)
                    Text("Done").tag(3)
                }
                .pickerStyle(.segmented)

                ForEach(Achievement.Category.allCases) { cat in
                    let list = all.filter { $0.category == cat && show($0, s) }
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(cat.rawValue, systemImage: cat.symbol).font(.rounded(16, .heavy)).foregroundStyle(.white)
                            ForEach(list) { a in row(a, s) }
                        }
                        .padding(14)
                        .glassCard(22)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen(transparent: true)
        .overlay { ConfettiRain(start: confetti).allowsHitTesting(false).ignoresSafeArea() }
    }

    private func show(_ a: Achievement, _ s: GameState) -> Bool {
        let isClaimed = s.achievementsClaimed.contains(a.id)
        switch filter {
        case 1: return !isClaimed && a.done(s)
        case 2: return !isClaimed && !a.done(s)
        case 3: return isClaimed
        default: return true
        }
    }

    private func row(_ a: Achievement, _ s: GameState) -> some View {
        let isClaimed = s.achievementsClaimed.contains(a.id)
        let isDone = a.done(s)
        let p = a.progress(s)
        return HStack(spacing: 12) {
            Image(systemName: a.symbol).font(.system(size: 18, weight: .bold))
                .foregroundStyle(isDone ? .black : .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(Circle().fill(isDone ? Color(hex: a.tierHex) : Color.white.opacity(0.08)))
                .overlay(Circle().stroke(Color(hex: a.tierHex).opacity(0.9), lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.title).font(.rounded(15, .heavy)).foregroundStyle(.white)
                    Text(a.tierName).font(.rounded(10, .black)).foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: a.tierHex)))
                }
                Text(a.detail).font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                if !isClaimed {
                    ProgressView(value: Double(p), total: Double(a.target)).tint(Color(hex: a.tierHex))
                    Text("\(p.formatted()) / \(a.target.formatted())").font(.rounded(11, .bold)).foregroundStyle(Theme.inkSoft).monospacedDigit()
                }
                Text("Reward: " + a.reward.lines.joined(separator: " · ")).font(.rounded(11, .bold))
                    .foregroundStyle(isClaimed ? Theme.inkSoft : Color(hex: 0xF5C542))
            }
            Spacer(minLength: 0)
            if isClaimed {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
            } else if isDone {
                Button { collect(a) } label: {
                    Text("Collect").font(.rounded(14, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) { Circle().fill(.red).frame(width: 9, height: 9).offset(x: 2, y: -2) }
            }
        }
        .scaleEffect(claimed == a.id ? 1.04 : 1)
        .animation(.spring(duration: 0.3), value: claimed)
    }

    private func collect(_ a: Achievement) {
        guard store.claimAchievement(a) else { return }
        celebrate(a.id, text: "\(a.title)! " + a.reward.lines.joined(separator: ", "))
    }

    private func collectAll(_ list: [Achievement]) {
        var got = 0
        for a in list where store.claimAchievement(a) { got += 1 }
        if got > 0 { celebrate(nil, text: "Collected \(got) achievement\(got == 1 ? "" : "s")!") }
    }

    private func celebrate(_ id: String?, text: String) {
        Haptics.hold()
        SoundKit.shared.play(.useItem)
        confetti = .now
        claimed = id
        store.toast = text
        Task { try? await Task.sleep(for: .milliseconds(600)); claimed = nil }
    }
}
