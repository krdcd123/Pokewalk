import SwiftUI

/// Menu › Ranch: a long-term build. Send box Pokémon out on shifts to gather materials, then spend them
/// (with Pokédollars and plenty of time) on one project after another until there's a house to furnish.
struct RanchView: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var gfx = RanchGfx.shared
    @State private var foremanSays: String?
    @State private var addingRancher = false
    @State private var builtOpen = false
    @State private var foreman: UIImage?
    @State private var confirmRecall = false
    @State private var traitsOpen = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                foremanCard
                ranchMap
                shiftCard
                traitsCard
                materialsCard
                buildCard
                if store.ranch.houseBuilt {
                    NavigationLink { RanchHouseView() } label: {
                        Label("Go inside the house", systemImage: "door.left.hand.open")
                            .font(.rounded(17, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .task {
            await gfx.loadOutdoors()
            if foreman == nil { foreman = await PretFiles.sprite("graphics/trainers/front_pics/hiker.png") }
            if let p = store.finishRanchProjectIfDone() { celebrate(p) }
        }
        .alert("Recall your ranchers?", isPresented: $confirmRecall) {
            Button("Recall", role: .destructive) {
                store.recallRanchShift()
                SoundKit.shared.play(.select)
                withAnimation { foremanSays = "Everyone's back. Swap the team around, then start a new shift." }
            }
            Button("Keep working", role: .cancel) {}
        } message: {
            Text("The shift timer will reset and they won't bring anything back from this shift. You can swap Pokémon in or out, then start a fresh shift.")
        }
        .sheet(isPresented: $addingRancher) {
            WorkerPicker(forRanch: true) { id in store.addRancher(id); SoundKit.shared.play(.select) }
                .presentationDetents([.medium, .large])
        }
    }

    private func celebrate(_ p: RanchProject) {
        Haptics.hold()
        SoundKit.shared.play(.useItem)
        var text = "\(p.name) is finished! \(p.reward)."
        if let t = p.ticket.flatMap(RanchTickets.ticket) { text += " And look — an \(t.name)! It's in your Bag." }
        withAnimation { foremanSays = text }
    }

    // MARK: Foreman

    private var foremanCard: some View {
        HStack(spacing: 12) {
            Group {
                if let foreman { PixelImageView(image: foreman) } else { ProgressView() }
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text("Foreman").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                Text(foremanSays ?? greeting).font(.rounded(15, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(22)
    }

    private var greeting: String {
        let r = store.ranch
        if r.built == 0 && store.ranchWorkers.isEmpty { return "Some land, eh? It'll take a lot of work. Send some Pokémon from your boxes out on a shift to start gathering." }
        if store.ranchShiftDone { return "The shift's over — collect what your Pokémon gathered!" }
        if r.building != nil { return "The builders are hard at it. Keep the shifts going in the meantime." }
        if let p = r.nextProject, store.canAfford(p) { return "We've got enough for the \(p.name). Shall we start?" }
        if r.nextProject == nil { return "The ranch is finished. You've built something special here." }
        return "Every shift gets us closer. Different types gather different materials."
    }

    // MARK: The ranch map

    private var ranchMap: some View {
        let r = store.ranch
        return VStack(spacing: 10) {
            GeometryReader { geo in
                let k = geo.size.width / CGFloat(RanchMap.width * 16)
                let tile = 16 * k
                ZStack(alignment: .topLeading) {
                    if let t = gfx.outdoors {
                        PixelImageView(image: RanchMap.image(t, built: r.built)).frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: store.ranchShiftRunning ? 6 : 0)
                            .overlay(Color.black.opacity(store.ranchShiftRunning ? 0.15 : 0))
                    } else {
                        Color(red: 0.45, green: 0.77, blue: 0.64)
                        ProgressView().tint(.white).frame(width: geo.size.width, height: geo.size.height)
                    }
                    if r.houseBuilt {
                        NavigationLink { RanchHouseView() } label: { Color.white.opacity(0.001) }
                            .frame(width: tile * 4, height: tile * 4)
                            .offset(x: tile * CGFloat(RanchMap.house.x), y: tile * CGFloat(RanchMap.house.y))
                            .accessibilityLabel("House")
                    }
                    // While building: a little sign of works going on
                    if let b = r.building {
                        Image(systemName: "hammer.fill").font(.system(size: tile * 0.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: tile * 1.1, height: tile * 1.1).glassCircle()
                            .symbolEffect(.bounce, options: .repeating.speed(0.4))
                            .position(RanchMap.workSite(b.project, tile: tile))
                    }
                    if !store.ranchShiftRunning {
                        WorkersHop(workers: store.ranchWorkers, iconSize: tile * 1.2)
                            .frame(width: tile * 10, height: tile * 5)
                            .offset(x: tile * 2, y: tile * 3.5)
                    } else {
                        // Out on shift: the ranch goes soft and the team shows in the middle
                        OnShiftBadges(workers: store.ranchWorkers, end: r.shiftEnd ?? .now, size: min(tile * 2.6, geo.size.width / 4.2))
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .aspectRatio(CGFloat(RanchMap.width) / CGFloat(RanchMap.height), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))

            HStack {
                Label("Rank \(r.built)/\(RanchProject.all.count)", systemImage: "star.fill")
                    .font(.rounded(14, .heavy)).foregroundStyle(.yellow)
                Spacer()
                Text("\(r.shiftCount) shifts worked").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .padding(8)
        .glassCard(24)
    }

    // MARK: Shifts

    private var shiftCard: some View {
        let r = store.ranch
        let workers = store.ranchWorkers
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ranchers").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Text("\(workers.count)/\(r.slots)").font(.rounded(14, .bold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                if workers.count < r.slots && !store.ranchShiftRunning {
                    Button { SoundKit.shared.play(.openPC); addingRancher = true } label: {
                        Label("Add", systemImage: "plus").font(.rounded(14, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            if workers.isEmpty {
                Text("Pokémon from your boxes work shifts here. Their type decides what they gather; level, friendship and nature decide how much.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(workers) { mon in rancherRow(mon) }

            if !workers.isEmpty { shiftControl }
        }
        .padding(14)
        .glassCard(22)
    }

    private func rancherRow(_ mon: OwnedPokemon) -> some View {
        let job = RanchJob.of(mon.species.types[0])
        let attr = RanchAttribute.of(nature: mon.nature)
        let h = RanchRules.haul(for: mon, ranch: store.ranch, team: RanchTeam.of(store.ranchWorkers), random: false)
        return HStack(spacing: 10) {
            LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(mon.name)  Lv. \(mon.level)").font(.rounded(15, .heavy)).foregroundStyle(.white)
                HStack(spacing: 5) {
                    chip(job.name, job.symbol, Theme.teal)
                    chip(attr.name, attr.symbol, .orange)
                }
                Text(haulText(h)).font(.rounded(11, .bold)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if !store.ranchShiftRunning {
                Button { store.removeRancher(mon.id); SoundKit.shared.play(.select) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send \(mon.name) back to the PC")
            }
        }
        .contextMenu {
            Text("\(job.name): \(job.text)")
            Text("\(attr.name): \(attr.text)")
        }
    }

    private func chip(_ text: String, _ symbol: String, _ c: Color) -> some View {
        Label(text, systemImage: symbol).font(.rounded(11, .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.35)))
            .foregroundStyle(.white)
    }

    private func haulText(_ h: RanchRules.Haul) -> String {
        var parts = RanchMaterial.allCases.compactMap { m in h.materials[m].flatMap { $0 > 0 ? "~\($0) \(m.name)" : nil } }
        if h.money > 0 { parts.append("~₽\(h.money)") }
        return "Per shift: " + parts.joined(separator: " · ")
    }

    @ViewBuilder private var shiftControl: some View {
        if let end = store.ranch.shiftEnd {
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let left = end.timeIntervalSince(tl.date)
                if left <= 0 {
                    Button {
                        if let h = store.collectRanchShift() {
                            Haptics.hold()
                            SoundKit.shared.play(.useItem)
                            var text = "The team brought back " + RanchMaterial.allCases.compactMap { m in
                                h.materials[m].flatMap { $0 > 0 ? "\($0) \(m.name)" : nil }
                            }.joined(separator: ", ")
                            if h.money > 0 { text += " and ₽\(h.money)" }
                            text += "."
                            if let t = h.ticket.flatMap(RanchTickets.ticket) { text += " They found an \(t.name)!!" }
                            withAnimation { foremanSays = text }
                        }
                    } label: {
                        Label("Collect the haul", systemImage: "basket.fill").font(.rounded(16, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    let total = end.timeIntervalSince(store.ranch.shiftStart ?? end)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("On shift", systemImage: "figure.walk").font(.rounded(14, .heavy)).foregroundStyle(.white)
                            Spacer()
                            Text(Self.countdown(left)).font(.rounded(14, .heavy)).monospacedDigit().foregroundStyle(.white)
                        }
                        ProgressView(value: max(0, min(1, 1 - left / max(1, total)))).tint(Theme.teal)
                        Button {
                            Haptics.tap()
                            confirmRecall = true
                        } label: {
                            Label("Recall early", systemImage: "arrow.uturn.backward").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .glassCapsule(interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Button {
                store.startRanchShift()
                Haptics.tap()
                SoundKit.shared.play(.select)
                withAnimation { foremanSays = "Off they go! Back in \(Self.hours(store.ranchShiftHours))." }
            } label: {
                Label("Start a \(Self.hours(store.ranchShiftHours)) shift", systemImage: "play.fill")
                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .glassCapsule(tint: Theme.teal, interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Jobs & attributes (collapsible, like the Garden's traits)

    private var traitsCard: some View {
        let workers = store.ranchWorkers
        let jobs = Dictionary(grouping: workers) { RanchJob.of($0.species.types[0]) }.mapValues(\.count)
        let team = RanchTeam.of(workers)
        let attrs = Dictionary(grouping: workers) { RanchAttribute.of(nature: $0.nature) }.mapValues(\.count)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                SoundKit.shared.play(.select)
                withAnimation(.spring(duration: 0.35)) { traitsOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Traits").font(.rounded(17, .heavy)).foregroundStyle(.white)
                    HStack(spacing: 4) {
                        ForEach(RanchJob.allCases.filter { jobs[$0] != nil }, id: \.self) { j in
                            Image(systemName: j.symbol).font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(team.tier(j) > 0 ? .white : Theme.teal)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(team.tier(j) > 0 ? Theme.teal : Color.white.opacity(0.1)))
                        }
                        if team.varietyTier > 0 {
                            Image(systemName: "square.grid.2x2.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(Color.purple))
                        }
                        ForEach(RanchAttribute.allCases.filter { attrs[$0] != nil }, id: \.self) { a in
                            Image(systemName: a.symbol).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Circle().fill(Color.orange))
                        }
                    }
                    Spacer()
                    Text("Shift \(Self.hours(store.ranchShiftHours))").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(traitsOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if traitsOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Jobs — from a Pokémon's first type. Same jobs together earn team bonuses.")
                        .font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    ForEach(RanchJob.allCases, id: \.self) { j in
                        let tiers = j == .scavenger ? [2, 3] : RanchTeam.tiers
                        let tier = team.tier(j)
                        traitRow(symbol: j.symbol, tint: Theme.teal, name: j.name, count: jobs[j] ?? 0,
                                 detail: "\(Self.types(for: j)) · \(j.text)" + (tier > 0 ? "\nTeam bonus: \(RanchTeam.tierText(j)[tier - 1])" : "\nTeam of \(tiers[0]): \(RanchTeam.tierText(j)[0])"),
                                 tiers: tiers, tier: tier)
                    }
                    traitRow(symbol: "square.grid.2x2.fill", tint: .purple, name: "Variety", count: team.distinct,
                             detail: team.varietyTier > 0 ? RanchTeam.varietyText[team.varietyTier - 1] : RanchTeam.varietyText.joined(separator: " · "),
                             tiers: [4, 5], tier: team.varietyTier)
                    Text("Attributes — from a Pokémon's nature").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                        .padding(.top, 4)
                    ForEach(RanchAttribute.allCases, id: \.self) { a in
                        traitRow(symbol: a.symbol, tint: .orange, name: a.name, count: attrs[a] ?? 0,
                                 detail: "\(Self.natures(for: a)) · \(a.text)")
                    }
                    Text("Every rancher also gathers more the higher its level and friendship.")
                        .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .glassCard(22)
        .clipped()
    }

    private func traitRow(symbol: String, tint: Color, name: String, count: Int, detail: String,
                          tiers: [Int] = [], tier: Int = 0) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .foregroundStyle(count > 0 ? .white : Theme.inkSoft)
                .frame(width: 34, height: 34)
                .background(Circle().fill(count > 0 ? tint : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.rounded(14, .heavy)).foregroundStyle(.white)
                    // team sizes, lit up as you reach them
                    ForEach(Array(tiers.enumerated()), id: \.offset) { i, n in
                        Text("\(n)").font(.rounded(11, .black)).monospacedDigit()
                            .foregroundStyle(i < tier ? .black : Theme.inkSoft)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(i < tier ? tint : Color.white.opacity(0.08)))
                    }
                    Spacer()
                    Text("\(count)").font(.rounded(14, .heavy)).foregroundStyle(count > 0 ? .white : Theme.inkSoft)
                }
                Text(detail).font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    static func types(for job: RanchJob) -> String {
        PokeType.allCases.filter { RanchJob.of($0) == job }.map(\.displayName).joined(separator: ", ")
    }

    static func natures(for a: RanchAttribute) -> String {
        Dex.natures.filter { RanchAttribute.of(nature: $0) == a }.joined(separator: ", ")
    }

    // MARK: Materials

    private var materialsCard: some View {
        HStack(spacing: 8) {
            ForEach(RanchMaterial.allCases) { m in
                VStack(spacing: 4) {
                    Image(systemName: m.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: m.hex))
                    Text(store.ranch.amount(m).formatted()).font(.rounded(16, .heavy)).foregroundStyle(.white).monospacedDigit()
                    Text(m.name).font(.rounded(11, .bold)).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .glassCard(22)
    }

    // MARK: Building

    private var buildCard: some View {
        let r = store.ranch
        return VStack(alignment: .leading, spacing: 12) {
            Text("Building").font(.rounded(17, .heavy)).foregroundStyle(.white)
            if let b = r.building, let p = RanchProject.all.first(where: { $0.id == b.project }) {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = b.endsAt.timeIntervalSince(tl.date)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(p.name, systemImage: p.symbol).font(.rounded(16, .heavy)).foregroundStyle(.white)
                        if left > 0 {
                            HStack {
                                Text("Finishes in").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                                Spacer()
                                Text(Self.countdown(left)).font(.rounded(14, .heavy)).monospacedDigit().foregroundStyle(.white)
                            }
                            ProgressView(value: max(0, min(1, 1 - left / b.endsAt.timeIntervalSince(b.startedAt)))).tint(.orange)
                        } else {
                            Button {
                                if let p = store.finishRanchProjectIfDone() { celebrate(p) }
                            } label: {
                                Label("Finish building", systemImage: "checkmark.seal.fill").font(.rounded(16, .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 46)
                                    .glassCapsule(tint: Color(hex: 0xF5A623), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let p = r.nextProject {
                projectDetail(p)
            } else {
                Text("Everything's built. 🎉").font(.rounded(15, .bold)).foregroundStyle(.white)
            }

            // Everything done so far, and what's still to come
            Button {
                SoundKit.shared.play(.select)
                withAnimation(.spring(duration: 0.35)) { builtOpen.toggle() }
            } label: {
                HStack {
                    Text("Ranch plans").font(.rounded(14, .heavy)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(builtOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if builtOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(RanchProject.all) { p in
                        HStack(spacing: 10) {
                            Image(systemName: r.has(p.id) ? "checkmark.circle.fill" : p.id == r.built ? "circle.dotted" : "circle")
                                .foregroundStyle(r.has(p.id) ? .green : Theme.inkSoft)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.rounded(14, .heavy)).foregroundStyle(r.has(p.id) ? .white : Theme.inkSoft)
                                Text(p.reward).font(.rounded(11, .semibold)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            if let t = p.ticket { ItemSprite(key: t).frame(width: 24, height: 24).opacity(r.has(p.id) ? 1 : 0.5) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .glassCard(22)
        .clipped()
    }

    private func projectDetail(_ p: RanchProject) -> some View {
        let afford = store.canAfford(p)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(p.name, systemImage: p.symbol).font(.rounded(16, .heavy)).foregroundStyle(.white)
                Spacer()
                Text(Self.hours(p.hours)).font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
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
                ProgressView(value: min(1, Double(have) / Double(need))).tint(Color(hex: m.hex))
            }
            if p.money > 0 {
                HStack {
                    Image(systemName: "yensign.circle.fill").foregroundStyle(.yellow).frame(width: 20)
                    Text("Pokédollars").font(.rounded(13, .bold)).foregroundStyle(.white)
                    Spacer()
                    Text("₽\(min(store.state.money, p.money).formatted()) / ₽\(p.money.formatted())").font(.rounded(13, .heavy))
                        .monospacedDigit().foregroundStyle(store.state.money >= p.money ? .green : .white)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "gift.fill").foregroundStyle(.pink)
                Text(p.reward).font(.rounded(12, .bold)).foregroundStyle(.white)
                if let t = p.ticket { ItemSprite(key: t).frame(width: 22, height: 22) }
            }
            Button {
                if store.startRanchProject() {
                    Haptics.hold()
                    SoundKit.shared.play(.useItem)
                    withAnimation { foremanSays = "Right, the \(p.name) it is! Give us \(Self.hours(p.hours))." }
                }
            } label: {
                Text(afford ? "Start building" : "Not enough yet").font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .glassCapsule(tint: afford ? Theme.teal : nil, interactive: afford)
            }
            .buttonStyle(.plain)
            .disabled(!afford)
        }
    }

    static func hours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        if m >= 48 * 60 && m % (24 * 60) == 0 { return "\(m / 1440) days" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    static func countdown(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        if t >= 86_400 { return "\(t / 86_400)d \((t % 86_400) / 3600)h" }
        return t >= 3600 ? "\(t / 3600)h \((t % 3600) / 60)m" : String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - The outdoor map (Emerald's general tileset)

enum RanchMap {
    static let width = 14, height = 10
    static let house = (x: 5, y: 3)

    private static func put(_ g: inout [[Int]], _ x: Int, _ y: Int, _ rows: [[Int]]) {
        for (dy, row) in rows.enumerated() { for (dx, id) in row.enumerated() { g[y + dy][x + dx] = id } }
    }

    /// The ranch after `built` projects.
    static func grid(built: Int) -> [[Int]] {
        var g = Array(repeating: Array(repeating: 0x001, count: width), count: height)
        g[0] = Array(repeating: 0x0C6, count: width)
        g[1] = Array(repeating: 0x016, count: width)
        let has = { (p: Int) in built > p }
        // Overgrown until it's cleared
        for y in 2..<height { for x in 0..<width { g[y][x] = has(0) ? 0x001 : ((x + y) % 5 == 0 ? 0x001 : 0x00D) } }
        if has(0) { for (x, y) in [(2, 3), (11, 7), (1, 8), (12, 3), (3, 8)] { g[y][x] = 0x004 } }
        // Fence & gate
        if has(2) {
            for x in 1...12 { g[2][x] = 0x149; g[9][x] = 0x149 }
            for y in 3...8 { g[y][0] = 0x142; g[y][13] = 0x140 }
            g[2][0] = 0x141; g[2][13] = 0x139; g[9][0] = 0x133; g[9][13] = 0x132
            g[9][6] = 0x001; g[9][7] = 0x001                       // the gate
        }
        // Well, later a pond
        if has(8) {
            put(&g, 9, 3, [[0x0B0, 0x0B1, 0x0B1, 0x0B2], [0x0B8, 0x0A1, 0x0A1, 0x0BA], [0x002, 0x002, 0x002, 0x002]])
        } else if has(1) {
            put(&g, 10, 3, [[0x0B0, 0x0B1, 0x0B2], [0x0B8, 0x0A1, 0x0BA], [0x002, 0x002, 0x002]])
        }
        // Barn: a fenced pen
        if has(3) {
            put(&g, 1, 6, [[0x141, 0x149, 0x149, 0x139], [0x142, 0x001, 0x001, 0x140], [0x133, 0x149, 0x149, 0x132]])
        }
        // The house: foundations → frame → finished
        if has(6) {
            put(&g, house.x, house.y, [[0x008, 0x009, 0x009, 0x00A], [0x010, 0x011, 0x011, 0x012],
                                       [0x018, 0x019, 0x00B, 0x01A], [0x020, 0x021, 0x013, 0x022]])
        } else if has(5) {
            put(&g, house.x, house.y + 2, [[0x018, 0x019, 0x00B, 0x01A], [0x020, 0x021, 0x013, 0x022]])
        } else if has(4) {
            put(&g, house.x, house.y + 2, [[0x118, 0x119, 0x119, 0x11A], [0x128, 0x129, 0x129, 0x12A]])
        }
        // Workshop sign; the extension adds a flower border
        if has(7) { g[7][4] = 0x003 }
        if has(9) { for x in [5, 8] { g[7][x] = 0x004 }; g[8][9] = 0x004; g[8][4] = 0x004 }
        return g
    }

    private static var cache: [Int: UIImage] = [:]

    @MainActor static func image(_ t: PretTileset, built: Int) -> UIImage {
        if let c = cache[built] { return c }
        let img = t.compose(grid(built: built))
        cache[built] = img
        return img
    }

    /// Where the hammer shows while a project is being built.
    static func workSite(_ project: Int, tile: CGFloat) -> CGPoint {
        switch project {
        case 0: return CGPoint(x: tile * 7, y: tile * 6)
        case 1, 8: return CGPoint(x: tile * 11.5, y: tile * 4.5)
        case 2: return CGPoint(x: tile * 7, y: tile * 9.5)
        case 3: return CGPoint(x: tile * 3, y: tile * 7.5)
        case 7: return CGPoint(x: tile * 4.5, y: tile * 7.5)
        default: return CGPoint(x: tile * 7, y: tile * 5)
        }
    }
}

/// The ranchers on shift: their box sprites hopping in glass circles, with the time left.
private struct OnShiftBadges: View {
    let workers: [OwnedPokemon]
    let end: Date
    let size: CGFloat

    var body: some View {
        let rows = workers.count > 3 ? [Array(workers.prefix((workers.count + 1) / 2)), Array(workers.dropFirst((workers.count + 1) / 2))]
                                     : [workers]
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSince1970
            VStack(spacing: size * 0.18) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: size * 0.22) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { i, mon in
                            let seed = Double(workers.firstIndex(of: mon) ?? i) * 0.45
                            LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny)
                                .frame(width: size * 0.78, height: size * 0.78)
                                .offset(y: -abs(sin((t + seed) * 6)) * size * 0.1 + size * 0.04)
                                .frame(width: size, height: size)
                                .glassCircle(interactive: false)
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        }
                    }
                }
                let left = max(0, end.timeIntervalSince(tl.date))
                Label(left > 0 ? "On shift · \(RanchView.countdown(left))" : "Back from their shift!",
                      systemImage: left > 0 ? "figure.walk" : "basket.fill")
                    .font(.rounded(13, .heavy)).foregroundStyle(.white).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassCapsule()
            }
        }
        .allowsHitTesting(false)
    }
}

/// Box icons hopping around (shared look with the Garden's workers).
struct WorkersHop: View {
    let workers: [OwnedPokemon]
    var iconSize: CGFloat = 40
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(workers.enumerated()), id: \.element.id) { i, mon in
                Hopper(mon: mon, area: geo.size, seed: i, size: iconSize)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Hopper: View {
        let mon: OwnedPokemon
        let area: CGSize
        let seed: Int
        let size: CGFloat
        @State private var pos: CGPoint = .zero
        @State private var facingRight = true

        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let t = tl.date.timeIntervalSince1970 + Double(seed) * 0.37
                let hop = abs(sin(t * 7)) * size * 0.14
                LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny)
                    .frame(width: size, height: size)
                    .scaleEffect(x: facingRight ? -1 : 1, y: 1)
                    .offset(y: -hop)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            }
            .position(pos)
            .task(id: "\(area.width)x\(area.height)") {
                guard area.width > size * 2, area.height > size * 2 else { return }
                pos = random()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 1.6...3.4)))
                    let next = random()
                    facingRight = next.x > pos.x
                    withAnimation(.easeInOut(duration: 1.4)) { pos = next }
                }
            }
        }

        private func random() -> CGPoint {
            let m = size / 2
            return CGPoint(x: .random(in: m...(area.width - m)), y: .random(in: m...(area.height - m)))
        }
    }
}

// MARK: - Inside the house (Secret Base tiles and decorations)

struct RanchHouseView: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var gfx = RanchGfx.shared
    @State private var decorating = false
    @State private var selected: String?
    @State private var shopping = false
    @State private var note: String?

    private var style: String { store.ranch.style }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                room
                if let note {
                    Text(note).font(.rounded(13, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).glassCard(16)
                        .transition(.opacity)
                }
                HStack(spacing: 10) {
                    Button {
                        SoundKit.shared.play(.select)
                        withAnimation { decorating.toggle(); selected = nil }
                    } label: {
                        Label(decorating ? "Done" : "Decorate", systemImage: decorating ? "checkmark" : "paintbrush.fill")
                            .font(.rounded(15, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .glassCapsule(tint: decorating ? Theme.teal : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    Button { SoundKit.shared.play(.select); shopping = true } label: {
                        Label("Furniture shop", systemImage: "cart.fill")
                            .font(.rounded(15, .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                if decorating { inventory }
                if store.ranch.has(7) { styles }
            }
            .padding()
        }
        .navigationTitle("Your House")
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen(transparent: true)
        .task(id: style) {
            await gfx.loadRoom(style)
            for d in RanchDecor.all { if let s = d.sprite, store.ranch.decor[d.key] != nil || store.ranch.placed.contains(where: { $0.key == d.key }) { await gfx.loadSprite(s) } }
        }
        .sheet(isPresented: $shopping) {
            DecorShop(style: style).presentationDetents([.large])
        }
        .animation(.easeInOut, value: note)
    }

    static func roomGrid(_ r: Ranch) -> [[Int]] {
        let (w, h) = r.roomSize
        var g: [[Int]] = [Array(repeating: 0x210, count: w)]
        g.append([0x210, 0x201] + Array(repeating: 0x202, count: w - 4) + [0x203, 0x210])
        for _ in 0..<(h - 3) { g.append([0x210, 0x209] + Array(repeating: 0x20A, count: w - 4) + [0x20B, 0x210]) }
        var bottom = [0x210, 0x211] + Array(repeating: 0x212, count: w - 4) + [0x213, 0x210]
        bottom[w / 2] = 0x20C                                     // the doorway
        g.append(bottom)
        return g
    }

    private var room: some View {
        let r = store.ranch
        let (w, h) = r.roomSize
        return GeometryReader { geo in
            let tile = geo.size.width / CGFloat(w)
            ZStack(alignment: .topLeading) {
                if let t = gfx.rooms[style] {
                    PixelImageView(image: t.compose(Self.roomGrid(r))).frame(width: geo.size.width, height: geo.size.height)
                    // mats first, then everything else top to bottom so lower things overlap higher ones
                    ForEach(r.placed.sorted { order($0) < order($1) }) { p in
                        if let d = RanchDecor.find(p.key), let img = image(d, t) {
                            let pw = img.size.width / 16 * tile, ph = img.size.height / 16 * tile
                            PixelImageView(image: img)
                                .frame(width: pw, height: ph)
                                .position(x: (CGFloat(p.x) + CGFloat(d.w) / 2) * tile,
                                          y: (CGFloat(p.y) + CGFloat(d.h)) * tile - ph / 2)
                                .allowsHitTesting(false)
                        }
                    }
                } else {
                    Color.black.opacity(0.3)
                    ProgressView().tint(.white).frame(width: geo.size.width, height: geo.size.height)
                }
                if decorating {
                    // a tap target per cell: place the selected piece here, or pick up what's here
                    ForEach(0..<(w * h), id: \.self) { i in
                        let x = i % w, y = i / w
                        Rectangle().fill(.white.opacity(0.001))
                            .overlay(Rectangle().stroke(.white.opacity(floorCell(x, y) ? 0.12 : 0), lineWidth: 0.5))
                            .frame(width: tile, height: tile)
                            .position(x: (CGFloat(x) + 0.5) * tile, y: (CGFloat(y) + 0.5) * tile)
                            .onTapGesture { tapCell(x, y) }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(w) / CGFloat(h), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
        .padding(8)
        .glassCard(24)
    }

    private func floorCell(_ x: Int, _ y: Int) -> Bool {
        let f = RanchHouse.floor(store.ranch)
        return f.x.contains(x) && (f.y.contains(y) || y == 1)
    }

    private func order(_ p: PlacedDecor) -> Int {
        guard let d = RanchDecor.find(p.key) else { return 0 }
        return (d.category == .mat ? 0 : 1000) + (p.y + d.h) * 10
    }

    private func image(_ d: RanchDecor, _ t: PretTileset) -> UIImage? {
        if let s = d.sprite { return gfx.sprites[s] }
        return t.decoration(d.tiles, w: d.w, h: d.h)
    }

    private func tapCell(_ x: Int, _ y: Int) {
        let r = store.ranch
        // something already here? pick it up
        if let p = r.placed.first(where: { p in
            guard let d = RanchDecor.find(p.key) else { return false }
            return RanchHouse.cells(d, x: p.x, y: p.y).contains { $0 == (x, y) }
        }) {
            store.pickUpDecor(p.id)
            Haptics.tap()
            SoundKit.shared.play(.select)
            note = "Put the \(RanchDecor.find(p.key)?.name ?? "decoration") away."
            return
        }
        guard let key = selected, let d = RanchDecor.find(key) else {
            note = "Pick something from your furniture below, then tap where it should go."
            return
        }
        if store.placeDecor(key, x: x, y: y) {
            Haptics.tap()
            SoundKit.shared.play(.useItem)
            note = nil
            if (store.ranch.decor[key] ?? 0) == 0 { selected = nil }
        } else {
            note = d.placement == .wall ? "\(d.name) goes on the back wall." : "\(d.name) doesn't fit there."
        }
    }

    private var inventory: some View {
        let owned = RanchDecor.all.filter { (store.ranch.decor[$0.key] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your furniture").font(.rounded(15, .heavy)).foregroundStyle(.white)
            if owned.isEmpty {
                Text("Nothing to place yet — buy some in the furniture shop. Tap a placed piece to put it away.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(owned) { d in
                        Button {
                            SoundKit.shared.play(.select)
                            selected = selected == d.key ? nil : d.key
                            Task { if let s = d.sprite { await gfx.loadSprite(s) } }
                        } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if let t = gfx.rooms[style], let img = image(d, t) { PixelImageView(image: img) }
                                    else { Image(systemName: d.category.symbol).foregroundStyle(.white) }
                                }
                                .frame(width: 44, height: 44)
                                Text("×\(store.ranch.decor[d.key] ?? 0)").font(.rounded(11, .heavy)).foregroundStyle(.white)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(selected == d.key ? Theme.teal.opacity(0.6) : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Room style").font(.rounded(15, .heavy)).foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RanchGfx.styles, id: \.key) { s in
                        let owned = store.ranch.styles.contains(s.key)
                        Button {
                            if store.setRoomStyle(s.key) { SoundKit.shared.play(.select) }
                            else { note = "\(s.name) costs ₽\(GameStore.roomStylePrice.formatted())." }
                        } label: {
                            VStack(spacing: 2) {
                                Text(s.name).font(.rounded(13, .heavy))
                                Text(owned ? (style == s.key ? "In use" : "Owned") : "₽\(GameStore.roomStylePrice.formatted())")
                                    .font(.rounded(11, .bold)).foregroundStyle(Theme.inkSoft)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(style == s.key ? Theme.teal.opacity(0.6) : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }
}

/// Lilycove-style decoration shop.
private struct DecorShop: View {
    let style: String
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var gfx = RanchGfx.shared
    @State private var category: RanchDecor.Category = .desk
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RanchDecor.Category.allCases) { c in
                            Button { SoundKit.shared.play(.select); category = c } label: {
                                Label(c.name, systemImage: c.symbol).font(.rounded(13, .heavy))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(category == c ? Theme.teal.opacity(0.7) : Color.secondary.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                if let message { Text(message).font(.rounded(13, .bold)).padding(.horizontal) }
                List(RanchDecor.all.filter { $0.category == category }) { d in
                    HStack(spacing: 12) {
                        Group {
                            if let s = d.sprite, let img = gfx.sprites[s] { PixelImageView(image: img) }
                            else if d.sprite == nil, let t = gfx.rooms[style] { PixelImageView(image: t.decoration(d.tiles, w: d.w, h: d.h)) }
                            else { Image(systemName: d.category.symbol) }
                        }
                        .frame(width: 48, height: 48)
                        .task { if let s = d.sprite { await gfx.loadSprite(s) } }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.rounded(15, .heavy))
                            Text("\(d.w)×\(d.h)\(d.placement == .wall ? " · on the wall" : "") · own \((store.ranch.decor[d.key] ?? 0) + store.ranch.placed.filter { $0.key == d.key }.count)")
                                .font(.rounded(12, .semibold)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if store.buyDecor(d) {
                                Haptics.tap()
                                SoundKit.shared.play(.useItem)
                                message = "Bought a \(d.name)!"
                            } else {
                                message = "You need ₽\(d.price.formatted()) (you have ₽\(store.state.money.formatted()))."
                            }
                        } label: {
                            Text("₽\(d.price.formatted())").font(.rounded(14, .heavy))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(store.state.money >= d.price ? Theme.teal.opacity(0.7) : Color.secondary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Furniture · ₽\(store.state.money.formatted())")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Map timer

struct RanchTimerChip: View {
    let date: Date
    let building: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let s = max(0, Int(date.timeIntervalSince(tl.date)))
            HStack(spacing: 6) {
                Image(systemName: s == 0 ? "checkmark.seal.fill" : building ? "hammer.fill" : "figure.walk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(s == 0 ? .yellow : .orange)
                Text(s == 0 ? (building ? "Built!" : "Shift done!") : RanchView.countdown(TimeInterval(s)))
                    .font(.rounded(15, .heavy)).foregroundStyle(.white).monospacedDigit()
            }
            .padding(.horizontal, 14).frame(height: 44)
            .glassCapsule()
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
    }
}
