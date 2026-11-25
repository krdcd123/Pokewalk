import SwiftUI

/// The Daycare: built on the ranch, then two Pokémon stay together and find Eggs while you walk.
struct DaycareView: View {
    @EnvironmentObject private var store: GameStore
    @State private var picking = false
    @State private var says: String?
    @State private var couple: UIImage?
    @State private var egg: UIImage?

    var body: some View {
        let d = store.state.daycare
        ScrollView {
            VStack(spacing: 16) {
                hostCard
                if !DaycareRules.canStart(store.state) {
                    lockedCard
                } else {
                    if d.open { parentsCard; eggsCard }
                    BuildCard(projects: DaycareRules.projects, built: d.built, building: d.building,
                              start: { store.startDaycareProject() },
                              finish: { if let p = store.finishDaycareProjectIfDone() { celebrate(p) } })
                }
            }
            .padding()
        }
        .task {
            if couple == nil { couple = await PretFiles.sprite("graphics/trainers/front_pics/old_couple.png") }
            if egg == nil { egg = await PretFiles.egg() }
            if let p = store.finishDaycareProjectIfDone() { celebrate(p) }
        }
        .sheet(isPresented: $picking) {
            WorkerPicker(forDaycare: true) { id in store.leaveAtDaycare(id); SoundKit.shared.play(.select) }
                .presentationDetents([.medium, .large])
        }
    }

    private func celebrate(_ p: RanchProject) {
        Haptics.hold()
        SoundKit.shared.play(.useItem)
        withAnimation { says = "The \(p.name) is ready! \(p.reward)." }
    }

    private var hostCard: some View {
        HStack(spacing: 12) {
            Group { if let couple { PixelImageView(image: couple) } else { ProgressView() } }
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text("Daycare Couple").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                Text(says ?? greeting).font(.rounded(15, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(22)
    }

    private var greeting: String {
        let d = store.state.daycare
        if !DaycareRules.canStart(store.state) { return "We'd love to run a Daycare on your ranch, dear. Put up a fence first so the little ones can't wander off!" }
        if !d.open { return d.building == nil ? "Build us a hut and we'll look after your Pokémon." : "The hut's coming along nicely." }
        if d.waiting != nil { return "Ah, there you are! While you were out, we found an Egg. Your Pokémon had it!" }
        if d.parents.count < 2 { return "Leave two Pokémon with us and we'll see whether they get along." }
        return "Your Pokémon are doing just fine. Keep walking and we'll see if anything turns up."
    }

    private var lockedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 50, height: 50).glassCircle()
            Text("Build the Fence & Gate at your Ranch to start a Daycare.")
                .font(.rounded(14, .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassCard(22)
    }

    private var parentsCard: some View {
        let parents = store.daycareParents
        let compat = parents.count == 2 ? DaycareRules.compatibility(parents[0], parents[1]) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Staying here").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Spacer()
                if parents.count < 2 {
                    Button { SoundKit.shared.play(.openPC); picking = true } label: {
                        Label("Leave a Pokémon", systemImage: "plus").font(.rounded(14, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { i in
                    VStack(spacing: 6) {
                        if i < parents.count {
                            let m = parents[i]
                            AnimatedSprite(speciesID: m.speciesID, shiny: m.isShiny).frame(width: 72, height: 72)
                            Text("\(m.name) \(m.gender == .male ? "♂" : m.gender == .female ? "♀" : "")")
                                .font(.rounded(13, .heavy)).foregroundStyle(.white)
                            Button { store.takeFromDaycare(m.id); SoundKit.shared.play(.select) } label: {
                                Text("Take back").font(.rounded(12, .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5).glassCapsule(interactive: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: "questionmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                                .frame(width: 72, height: 72)
                            Text("Empty").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
                }
            }
            if parents.count == 2 {
                Text(DaycareRules.compatibilityText(compat)).font(.rounded(14, .bold))
                    .foregroundStyle(compat > 0 ? .white : .orange)
                if compat > 0 {
                    let chance = Int((min(0.95, compat * DaycareRules.multiplier(store.state.daycare)) * 100).rounded())
                    Text("\(chance)% chance of an Egg every 1,000 steps · next check in \(max(0, DaycareRules.stepsPerCheck - store.state.daycare.eggProgress).formatted()) steps")
                        .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("Pokémon need a shared Egg Group and to be male and female — or pair one with Ditto.")
                        .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }

    private var eggsCard: some View {
        let d = store.state.daycare
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Eggs").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Text("\(d.basket.count)/\(Daycare.basketSize) carried · \(d.hatched) hatched").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            if d.waiting != nil {
                Button {
                    if store.collectEgg() {
                        Haptics.hold()
                        SoundKit.shared.play(.useItem)
                        withAnimation { says = "Take good care of it! Walk with it and it'll hatch." }
                    } else {
                        says = "You're carrying 6 Eggs already — hatch one first."
                    }
                } label: {
                    HStack(spacing: 10) {
                        Group { if let egg { PixelImageView(image: egg) } else { Image(systemName: "oval.portrait.fill") } }
                            .frame(width: 40, height: 40)
                        Text("Pick up the Egg").font(.rounded(16, .heavy)).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 54)
                    .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                }
                .buttonStyle(.plain)
            }
            if d.basket.isEmpty && d.waiting == nil {
                Text("Eggs you carry hatch as you walk. Bigger, rarer Pokémon take much longer. A buddy with Flame Body or Magma Armor hatches them twice as fast.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(d.basket) { e in
                let left = Double(max(0, e.stepsLeft)) / Double(max(1, e.total))
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                        Circle().trim(from: 0, to: 1 - left).stroke(Color(hex: 0xF5A623), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Group { if let egg { PixelImageView(image: egg) } else { Image(systemName: "oval.portrait.fill") } }
                            .frame(width: 30, height: 30)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.hint(left)).font(.rounded(14, .heavy)).foregroundStyle(.white)
                        Text("About \(max(0, e.stepsLeft).formatted()) steps to go").font(.rounded(12, .bold)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }

    /// The games' Egg summaries.
    static func hint(_ left: Double) -> String {
        switch left {
        case 0.75...: return "It looks like it will take a long time to hatch."
        case 0.4...: return "What will hatch from this? It will take some time."
        case 0.15...: return "It moves occasionally. It should hatch soon."
        default: return "Sounds can be heard coming from inside! It will hatch soon!"
        }
    }
}

/// A list of projects built with ranch materials (used by the Daycare).
struct BuildCard: View {
    let projects: [RanchProject]
    let built: Int
    let building: RanchBuild?
    let start: () -> Bool
    let finish: () -> Void
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Building").font(.rounded(17, .heavy)).foregroundStyle(.white)
            if let b = building, let p = projects.first(where: { $0.id == b.project }) {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = b.endsAt.timeIntervalSince(tl.date)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(p.name, systemImage: p.symbol).font(.rounded(16, .heavy)).foregroundStyle(.white)
                        if left > 0 {
                            HStack {
                                Text("Finishes in").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                                Spacer()
                                Text(RanchView.countdown(left)).font(.rounded(14, .heavy)).monospacedDigit().foregroundStyle(.white)
                            }
                            ProgressView(value: max(0, min(1, 1 - left / b.endsAt.timeIntervalSince(b.startedAt)))).tint(.orange)
                        } else {
                            Button(action: finish) {
                                Label("Finish building", systemImage: "checkmark.seal.fill").font(.rounded(16, .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 46)
                                    .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let p = projects.first(where: { $0.id == built }) {
                let afford = store.canAfford(p)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(p.name, systemImage: p.symbol).font(.rounded(16, .heavy)).foregroundStyle(.white)
                        Spacer()
                        Text(RanchView.hours(p.hours)).font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                    }
                    Text(p.text).font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
                    ForEach(RanchMaterial.allCases.filter { p.cost[$0] != nil }) { m in
                        let need = p.cost[m]!, have = store.ranch.amount(m)
                        HStack {
                            Image(systemName: m.symbol).foregroundStyle(Color(hex: m.hex)).frame(width: 20)
                            Text(m.name).font(.rounded(13, .bold)).foregroundStyle(.white)
                            Spacer()
                            Text("\(min(have, need).formatted()) / \(need.formatted())").font(.rounded(13, .heavy)).monospacedDigit()
                                .foregroundStyle(have >= need ? .green : .white)
                        }
                    }
                    HStack {
                        Image(systemName: "yensign.circle.fill").foregroundStyle(.yellow).frame(width: 20)
                        Text("Pokédollars").font(.rounded(13, .bold)).foregroundStyle(.white)
                        Spacer()
                        Text("₽\(min(store.state.money, p.money).formatted()) / ₽\(p.money.formatted())").font(.rounded(13, .heavy))
                            .monospacedDigit().foregroundStyle(store.state.money >= p.money ? .green : .white)
                    }
                    Label(p.reward, systemImage: "gift.fill").font(.rounded(12, .bold)).foregroundStyle(.white)
                    Button {
                        if start() { Haptics.hold(); SoundKit.shared.play(.useItem) }
                    } label: {
                        Text(afford ? "Start building" : "Not enough yet (materials come from Ranch shifts)")
                            .font(.rounded(15, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .glassCapsule(tint: afford ? Theme.teal : nil, interactive: afford)
                    }
                    .buttonStyle(.plain)
                    .disabled(!afford)
                }
            } else {
                Text("Everything's built. 🎉").font(.rounded(15, .bold)).foregroundStyle(.white)
            }
            // what's been built
            HStack(spacing: 6) {
                ForEach(projects) { p in
                    Image(systemName: built > p.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(built > p.id ? .green : Theme.inkSoft)
                    Text(p.name).font(.rounded(10, .bold)).foregroundStyle(built > p.id ? .white : Theme.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }
}

/// "Oh? Your Egg is hatching!" over the map.
struct HatchCard: View {
    let mon: OwnedPokemon
    let done: () -> Void
    @State private var egg: UIImage?
    @State private var phase = 0          // 0 wobbling, 1 flash, 2 revealed
    @State private var wobble = 0.0

    var body: some View {
        VStack(spacing: 14) {
            Text(phase < 2 ? "Oh?" : "\(mon.species.name) hatched from the Egg!")
                .font(.rounded(20, .black)).foregroundStyle(.white).multilineTextAlignment(.center)
            ZStack {
                if phase < 2 {
                    Group { if let egg { PixelImageView(image: egg) } else { Image(systemName: "oval.portrait.fill").font(.system(size: 60)) } }
                        .frame(width: 128, height: 128)
                        .rotationEffect(.degrees(wobble))
                } else {
                    AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 140, height: 140)
                        .transition(.scale.combined(with: .opacity))
                    if mon.isShiny { ShinySparkles(start: .now).frame(width: 160, height: 160).allowsHitTesting(false) }
                }
                if phase == 1 { Circle().fill(.white).frame(width: 220, height: 220).blur(radius: 20).transition(.opacity) }
            }
            .frame(height: 160)
            if phase == 2 {
                Button(action: done) {
                    Text("OK").font(.rounded(17, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .glassCapsule(tint: Theme.teal, interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .glassCard(28)
        .task {
            egg = await PretFiles.egg()
            for i in 0..<3 {
                withAnimation(.easeInOut(duration: 0.12).repeatCount(3, autoreverses: true)) { wobble = i % 2 == 0 ? 12 : -12 }
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(700))
                wobble = 0
                try? await Task.sleep(for: .milliseconds(300))
            }
            withAnimation(.easeOut(duration: 0.25)) { phase = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.5)) { phase = 2 }
            CryPlayer.shared.play(mon.speciesID)
            SoundKit.shared.play(.ballCatch)
            Haptics.hold()
        }
    }
}
