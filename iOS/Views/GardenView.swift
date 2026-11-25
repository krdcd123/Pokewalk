import SwiftUI

/// Menu › Garden: the Aroma Lady's berry garden. Plant berries in the soft soil, pick 1–3 (or more) a day
/// later, and put box Pokémon to work — their types make team bonuses, like traits in TFT.
struct GardenView: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var gfx = GardenGfx.shared

    @State private var planting: Int?            // plot being planted
    @State private var info: Int?                // plot whose details are showing
    @State private var addingWorker = false
    @State private var ladySays: String?
    @State private var traitsOpen = false
    @State private var showingBoosts = false

    private let scale: CGFloat = 4               // Emerald pixels → points
    private let columns = 4

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                aromaLady
                field
                traits
                workers
            }
            .padding()
        }
        .navigationTitle("Garden")
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen(transparent: true)
        .task { await gfx.load() }
        .sheet(item: Binding(get: { planting.map { PlotID(id: $0) } }, set: { planting = $0?.id })) { p in
            PlantPicker(plotID: p.id) { berry in
                if store.plant(berry, in: p.id) {
                    Haptics.tap()
                    SoundKit.shared.play(.useItem)
                    ladySays = "\(Dex.itemName(berry)) planted! Check back in about \(hoursText(GardenRules.hoursToGrow(store.gardenBonuses)))."
                }
                planting = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $addingWorker) {
            WorkerPicker { id in store.addGardenWorker(id); SoundKit.shared.play(.select) }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: The Aroma Lady

    private var aromaLady: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let img = gfx.aromaLady { PixelImageView(image: img) } else { ProgressView() }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text("Aroma Lady").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                Text(ladySays ?? greeting).font(.rounded(15, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if store.gardenGiftWaiting {
                    Button {
                        if let b = store.claimGardenGift() {
                            Haptics.hold()
                            SoundKit.shared.play(.useItem)
                            withAnimation { ladySays = "Here, a \(Dex.itemName(b)) for you. Plant it and it'll grow more!" }
                        }
                    } label: {
                        Label("Today's berry", systemImage: "gift.fill").font(.rounded(14, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(22)
    }

    private var greeting: String {
        let berries = ItemCatalog.berries.reduce(0) { $0 + (store.state.bag[$1] ?? 0) }
        let ready = store.state.garden.plots.filter { GardenRules.progress($0, bonuses: store.gardenBonuses) >= 1 }.count
        if ready > 0 { return "Your berries are ready! Tap a plant to pick them." }
        if store.gardenPlanted == 0 && berries == 0 { return "Welcome to the garden! Take a berry to start — I give one away every day." }
        if store.gardenPlanted == 0 { return "Welcome! Tap the soft soil to plant a berry. In a day it'll give you 1–3 back." }
        if store.gardenWorkers.isEmpty { return "Pokémon from your boxes can help out here. Ones with matching types work even better together!" }
        return "The plants are coming along nicely. Your Pokémon are working hard!"
    }

    // MARK: The field

    @State private var page = 0

    private var field: some View {
        let b = store.gardenBonuses
        let owned = store.state.garden.fields
        // a page to buy the next garden appears once the first is fully cleared
        let pages = owned + (owned < Garden.maxFields && store.gardenFirstFieldCleared ? 1 : 0)
        return VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(0..<pages, id: \.self) { f in
                    Group {
                        if f < owned { fieldPage(f, bonuses: b) } else { buyPage(f) }
                    }
                    .tag(f)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages > 1 ? .always : .never))
            .aspectRatio(CGFloat(GardenGfx.fieldWidth) / CGFloat(GardenGfx.fieldHeight), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
            .overlay(alignment: .top) {
                if showingBoosts { boostsCard(b).padding(.top, 52).padding(.horizontal, 12).transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing))) }
            }
            .animation(.spring(duration: 0.25), value: showingBoosts)
            .onChange(of: page) { _, _ in SoundKit.shared.play(.select); info = nil }

            if let i = info, let plot = store.state.garden.plots.first(where: { $0.id == i }), let berry = plot.berry {
                plotInfo(plot, berry: berry, bonuses: b)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                statusLine(b)
            }
        }
        .padding(8)
        .glassCard(24)
        .animation(.spring(duration: 0.3), value: info)
    }

    /// One garden: the map, its plants (two per oval patch, standing in the middle of the soil), lock badges on
    /// patches still to clear, and the workers.
    private func fieldPage(_ f: Int, bonuses b: GardenBonuses) -> some View {
        let open = f == 0 ? store.gardenPlotCount : Garden.plotsPerField
        return GeometryReader { geo in
            let k = geo.size.width / CGFloat(GardenGfx.fieldWidth * 16)     // points per Emerald pixel
            let tile = 16 * k
            ZStack(alignment: .topLeading) {
                if let img = gfx.field(openPlots: open) {
                    PixelImageView(image: img).frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color(red: 0.45, green: 0.77, blue: 0.64)
                    ProgressView().tint(.white).frame(width: geo.size.width, height: geo.size.height)
                }
                TimelineView(.periodic(from: .now, by: 0.6)) { tl in
                    let frame = Int(tl.date.timeIntervalSince1970 / 0.6)
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: geo.size.width, height: geo.size.height)
                        ForEach(0..<Garden.plotsPerField, id: \.self) { i in
                            if i < open {
                                let id = f * Garden.plotsPerField + i
                                let c = Self.plantCentre(i, tile: tile)
                                PlantSprite(plot: store.gardenPlot(id), bonuses: b, frame: frame, now: tl.date, k: k)
                                    .frame(width: tile, height: tile * 2)
                                    .position(x: c.x, y: c.y - tile)        // sprite's bottom = the plant's base
                                    .allowsHitTesting(false)
                                // tap area: the oval and the plant on it
                                Color.white.opacity(0.001)
                                    .frame(width: tile * 2, height: tile * 2)
                                    .contentShape(Rectangle())
                                    .position(x: c.x, y: c.y - tile * 0.55)
                                    .onTapGesture { tap(store.gardenPlot(id)) }
                                    .accessibilityLabel(store.gardenPlot(id).berry.map { Dex.itemName($0) } ?? "Empty soil")
                            }
                        }
                    }
                }
                // Overgrown patches (the Tillers clear them): a tap just explains
                if f == 0 {
                    ForEach(0..<Garden.plotsPerField, id: \.self) { j in
                        if j >= open {
                            let o = GardenGfx.ovalTile(j)
                            Color.white.opacity(0.001)
                                .frame(width: tile * 2, height: tile * 2)
                                .contentShape(Rectangle())
                                .position(x: CGFloat(o.x + 1) * tile, y: CGFloat(o.y + 1) * tile)
                                .onTapGesture { lockedTapped(oval: j) }
                        }
                    }
                }
                WorkersLayer(workers: store.gardenWorkers, iconSize: tile * 1.2)
                    .frame(width: tile * 8, height: tile * 5.6)
                    .offset(x: tile * 2, y: tile * 2.4)
                boostsBadge(b, tile: tile)
                    .offset(x: geo.size.width - tile * 1.75, y: tile * 0.3)
            }
        }
    }

    /// Middle of the soil for plant `i` (in points): one plant in the middle of each oval.
    static func plantCentre(_ i: Int, tile: CGFloat) -> CGPoint {
        let o = GardenGfx.ovalTile(i)
        let cx = (CGFloat(o.x) + 1) * tile
        let base = (CGFloat(o.y) + 1.2) * tile           // the oval is 1½ tiles tall; plants stand just below its middle
        return CGPoint(x: cx, y: base)
    }

    private func lockedTapped(oval j: Int) {
        Haptics.tap()
        SoundKit.shared.play(.select)
        let need = j > Garden.basePlots ? 4 : 2                     // 5th patch → 2 Tillers, 6th → 4
        let have = store.gardenBonuses.counts[.tillers] ?? 0
        withAnimation {
            ladySays = "This patch is overgrown. Clearing it needs \(need) Tillers working here (Ground, Rock, Steel or Fighting types) — you have \(have)."
        }
    }

    /// The next garden, for sale.
    private func buyPage(_ f: Int) -> some View {
        let price = Garden.fieldPrice(f)
        let money = store.state.money
        return ZStack {
            if let img = gfx.field(openPlots: 0) {
                PixelImageView(image: img).blur(radius: 3).overlay(Color.black.opacity(0.25))
            } else {
                Color(red: 0.45, green: 0.77, blue: 0.64)
            }
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 52, height: 52).glassCircle()
                Text("Garden \(f + 1)").font(.rounded(20, .black)).foregroundStyle(.white)
                Text("6 patches, all ready to plant").font(.rounded(13, .bold)).foregroundStyle(.white.opacity(0.85))
                Button {
                    if store.buyGardenField() {
                        Haptics.hold()
                        SoundKit.shared.play(.useItem)
                        withAnimation { ladySays = "Garden \(f + 1) is yours! Plenty of room for more berries." }
                    } else {
                        Haptics.tap()
                        withAnimation { ladySays = "That garden costs ₽\(price.formatted()). You have ₽\(money.formatted())." }
                    }
                } label: {
                    Text("Buy for ₽\(price.formatted())").font(.rounded(16, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .glassCapsule(tint: money >= price ? Theme.teal : nil, interactive: true)
                }
                .buttonStyle(.plain)
                Text("You have ₽\(money.formatted())").font(.rounded(12, .bold)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    /// "3 growing · next ready in 4h 12m" under the garden.
    private func statusLine(_ b: GardenBonuses) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let growing = store.state.garden.plots.filter { $0.berry != nil }
            let ready = growing.filter { GardenRules.progress($0, bonuses: b, now: tl.date) >= 1 }.count
            let next = growing.compactMap { GardenRules.readyAt($0, bonuses: b) }.filter { $0 > tl.date }.min()
            HStack(spacing: 8) {
                Image(systemName: ready > 0 ? "basket.fill" : "leaf.fill")
                    .foregroundStyle(ready > 0 ? .yellow : Color(hex: 0x9BE15D))
                Text(growing.isEmpty ? "Tap the soil to plant a berry"
                     : ready > 0 ? "\(ready) ready to pick" + (next.map { " · next in \(countdown($0.timeIntervalSince(tl.date)))" } ?? "")
                     : "\(growing.count) growing · next ready in \(countdown((next ?? tl.date).timeIntervalSince(tl.date)))")
                    .font(.rounded(14, .heavy)).foregroundStyle(.white).monospacedDigit()
                Spacer()
                Text("\(store.gardenPlanted)/\(store.gardenPlotCount + (store.state.garden.fields - 1) * Garden.plotsPerField)").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    // MARK: Active boosts (hold the badge in the garden)

    private func boostsBadge(_ b: GardenBonuses, tile: CGFloat) -> some View {
        let active = GardenTrait.allCases.filter { b.tier($0) > 0 }
        let any = !active.isEmpty || !b.families.isEmpty
        return HStack(spacing: -6) {
            if any {
                ForEach(active) { t in
                    Image(systemName: t.symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(hex: t.hex)))
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                }
                if !b.families.isEmpty {
                    Image(systemName: "person.2.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.purple))
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                }
            } else {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
            }
        }
        .padding(5)
        .glassCapsule()
        .fixedSize()
        .frame(width: tile * 1.6, alignment: .trailing)
        // Hold for a description of what's boosting the garden right now
        .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 40, pressing: { down in
            if down { Haptics.tap() }
            showingBoosts = down
        }, perform: {})
        .accessibilityLabel("Active garden boosts. Hold to see them.")
    }

    private func boostsCard(_ b: GardenBonuses) -> some View {
        let active = GardenTrait.allCases.filter { b.tier($0) > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Active boosts").font(.rounded(15, .heavy)).foregroundStyle(.white)
            if active.isEmpty && b.families.isEmpty {
                Text("None yet. Put 2 workers with the same trait (or from the same evolution family) in the garden.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(active) { t in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: t.symbol).foregroundStyle(Color(hex: t.hex)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(t.name) (\(b.counts[t] ?? 0))").font(.rounded(13, .heavy)).foregroundStyle(.white)
                        Text(t.tierText[b.tier(t) - 1]).font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            if !b.families.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.2.fill").foregroundStyle(.purple).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Family Ties").font(.rounded(13, .heavy)).foregroundStyle(.white)
                        Text("\(b.families.map { Dex.species($0).name }.joined(separator: ", ")): \(min(30, b.families.count * 10))% faster, +\(b.families.count) friendship")
                            .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            Divider().overlay(.white.opacity(0.2))
            Text("Grows in \(hoursText(GardenRules.hoursToGrow(b))) · workers +\(b.friendshipPerHarvest) friendship per harvest")
                .font(.rounded(12, .bold)).foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .allowsHitTesting(false)
    }

    private func plotInfo(_ plot: GardenPlot, berry: String, bonuses b: GardenBonuses) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let p = GardenRules.progress(plot, bonuses: b, now: tl.date)
            let left = max(0, (GardenRules.readyAt(plot, bonuses: b) ?? tl.date).timeIntervalSince(tl.date))
            HStack(spacing: 10) {
                ItemSprite(key: berry).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Dex.itemName(berry)).font(.rounded(15, .heavy)).foregroundStyle(.white)
                    Text(BerryStage.at(progress: p).name + (left > 0 ? " · ready in \(countdown(left))" : ""))
                        .font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft).monospacedDigit()
                    ProgressView(value: min(1, p)).tint(Theme.teal)
                }
            }
            .padding(12)
            .glassCard(18)
        }
    }

    private func tap(_ plot: GardenPlot) {
        let b = store.gardenBonuses
        guard store.gardenPlotOpen(plot.id) else { lockedTapped(oval: plot.id % Garden.plotsPerField); return }
        if plot.berry == nil {
            let have = ItemCatalog.berries.contains { (store.state.bag[$0] ?? 0) > 0 }
            if have { SoundKit.shared.play(.select); planting = plot.id }
            else { ladySays = "You've no berries to plant. Take today's berry, or your Pokémon may pick some up on walks." }
        } else if GardenRules.progress(plot, bonuses: b) >= 1 {
            guard let r = store.harvest(plot.id) else { return }
            Haptics.hold()
            SoundKit.shared.play(.useItem)
            var text = "You picked \(r.count) \(Dex.itemName(r.berry))\(r.count == 1 ? "" : "s")!"
            if let bonus = r.bonus { text += " The Pollinators found a \(Dex.itemName(bonus)) too!" }
            if r.replanted { text += " Your helpers replanted it for free." }
            withAnimation { ladySays = text; info = nil }
        } else {
            Haptics.tap()
            info = info == plot.id ? nil : plot.id
        }
    }

    // MARK: Traits (team bonuses)

    private var traits: some View {
        let b = store.gardenBonuses
        let active = GardenTrait.allCases.filter { (b.counts[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                SoundKit.shared.play(.select)
                withAnimation(.spring(duration: 0.35)) { traitsOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Traits").font(.rounded(17, .heavy)).foregroundStyle(.white)
                    // what your workers bring, at a glance
                    HStack(spacing: 4) {
                        ForEach(active) { t in
                            Image(systemName: t.symbol).font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(b.tier(t) > 0 ? .white : Color(hex: t.hex))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(b.tier(t) > 0 ? Color(hex: t.hex) : Color.white.opacity(0.1)))
                        }
                    }
                    Spacer()
                    Text("Grows in \(hoursText(GardenRules.hoursToGrow(b)))").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(traitsOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if traitsOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(GardenTrait.allCases) { t in TraitRow(trait: t, count: b.counts[t] ?? 0, tier: b.tier(t)) }
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(b.families.isEmpty ? Theme.inkSoft : .white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(b.families.isEmpty ? Color.white.opacity(0.08) : Color.purple.opacity(0.7)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Family Ties").font(.rounded(14, .heavy)).foregroundStyle(.white)
                            Text("2 from the same evolution family: 10% faster growth and +1 friendship each harvest (up to 3 families)")
                                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
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

    // MARK: Workers

    private var workers: some View {
        let list = store.gardenWorkers
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workers").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Text("\(list.count)/\(Garden.maxWorkers)").font(.rounded(14, .bold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                if list.count < Garden.maxWorkers {
                    Button { SoundKit.shared.play(.openPC); addingWorker = true } label: {
                        Label("Add", systemImage: "plus").font(.rounded(14, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .glassCapsule(tint: Theme.teal, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            if list.isEmpty {
                Text("Put Pokémon from your boxes to work. Each type brings a trait — get 2, 4 or 6 with the same trait for bigger bonuses. Workers gain friendship every harvest.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(list) { mon in
                HStack(spacing: 10) {
                    LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(mon.name)  Lv. \(mon.level)").font(.rounded(15, .heavy)).foregroundStyle(.white)
                        HStack(spacing: 5) {
                            ForEach(Array(Set(mon.species.types.map(GardenTrait.of))).sorted { $0.rawValue < $1.rawValue }) { t in
                                Label(t.name, systemImage: t.symbol).font(.rounded(11, .bold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(Color(hex: t.hex).opacity(0.35)))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    Spacer()
                    Button { store.removeGardenWorker(mon.id); SoundKit.shared.play(.select) } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).glassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop \(mon.name) working")
                }
            }
        }
        .padding(14)
        .glassCard(22)
    }

    // MARK: Helpers

    private struct PlotID: Identifiable { let id: Int }

    private func hoursText(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    private func countdown(_ s: TimeInterval) -> String {
        let t = Int(s)
        return t >= 3600 ? "\(t / 3600)h \((t % 3600) / 60)m" : String(format: "%d:%02d", t / 60, t % 60)
    }

    static func scaled(_ img: UIImage, by k: CGFloat) -> UIImage? {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let size = CGSize(width: img.size.width * k, height: img.size.height * k)
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - One berry plant

private struct PlantSprite: View {
    let plot: GardenPlot
    let bonuses: GardenBonuses
    let frame: Int
    let now: Date
    let k: CGFloat
    @ObservedObject private var gfx = GardenGfx.shared

    private var stage: BerryStage { BerryStage.at(progress: GardenRules.progress(plot, bonuses: bonuses, now: now)) }
    private var image: UIImage? { plot.berry.flatMap { gfx.sprite(berry: $0, stage: stage, frame: frame) } }
    private var markerLift: CGFloat {
        let bounce: Double = abs(sin(Double(frame) * Double.pi / 2)) * 3
        return -32 * k - 4 - CGFloat(bounce)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let img = image {
                let w: CGFloat = img.size.width * k
                let h: CGFloat = img.size.height * k
                PixelImageView(image: img).frame(width: w, height: h)
            }
            if plot.berry != nil && stage == .berries {
                // a little bouncing marker over plants ready to pick
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 7 * k, weight: .black))
                    .foregroundStyle(Color.white, Color(hex: 0xF5A623))
                    .offset(y: markerLift)
            }
        }
    }
}

// MARK: - Working Pokémon hopping about

private struct WorkersLayer: View {
    let workers: [OwnedPokemon]
    var iconSize: CGFloat = 40
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(workers.enumerated()), id: \.element.id) { i, mon in
                HoppingWorker(mon: mon, area: geo.size, seed: i, size: iconSize)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HoppingWorker: View {
    let mon: OwnedPokemon
    let area: CGSize
    let seed: Int
    var size: CGFloat = 40
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

// MARK: - Trait row

private struct TraitRow: View {
    let trait: GardenTrait
    let count: Int
    let tier: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: trait.symbol).font(.system(size: 15, weight: .bold))
                .foregroundStyle(tier > 0 ? .white : Theme.inkSoft)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tier > 0 ? Color(hex: trait.hex) : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trait.name).font(.rounded(14, .heavy)).foregroundStyle(.white)
                    // 2 / 4 / 6 — lit up as you reach them
                    ForEach(Array(trait.tiers.enumerated()), id: \.offset) { i, n in
                        Text("\(n)").font(.rounded(11, .black)).monospacedDigit()
                            .foregroundStyle(i < tier ? .black : Theme.inkSoft)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(i < tier ? Color(hex: trait.hex) : Color.white.opacity(0.08)))
                    }
                    Spacer()
                    Text("\(count)").font(.rounded(14, .heavy)).foregroundStyle(count > 0 ? .white : Theme.inkSoft)
                }
                Text(tier > 0 ? trait.tierText[tier - 1] : "\(trait.types.map(\.displayName).joined(separator: ", ")) · \(trait.tierText[0])")
                    .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

// MARK: - Pickers

private struct PlantPicker: View {
    let plotID: Int
    let choose: (String) -> Void
    @EnvironmentObject private var store: GameStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(ItemCatalog.berries.filter { (store.state.bag[$0] ?? 0) > 0 }, id: \.self) { b in
                    Button { choose(b) } label: {
                        HStack(spacing: 12) {
                            ItemSprite(key: b).frame(width: 32, height: 32)
                            Text(Dex.itemName(b)).font(.rounded(16, .bold))
                            Spacer()
                            Text("×\(store.state.bag[b] ?? 0)").font(.rounded(15, .heavy)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Plant a berry")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WorkerPicker: View {
    let choose: (UUID) -> Void
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let busy = Set(store.gardenWorkers.map(\.id))
        let boxed = store.state.pokemon
            .filter { !store.state.partyIDs.contains($0.id) && !busy.contains($0.id) }
            .sorted { ($0.species.types.first?.rawValue ?? "", $0.speciesID) < ($1.species.types.first?.rawValue ?? "", $1.speciesID) }
        NavigationStack {
            List {
                if boxed.isEmpty {
                    Text("No Pokémon in your boxes. Only boxed Pokémon (not your party) can work in the garden.")
                        .foregroundStyle(.secondary)
                }
                ForEach(boxed) { mon in
                    Button {
                        choose(mon.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(mon.name)  Lv. \(mon.level)").font(.rounded(16, .bold))
                                HStack(spacing: 6) {
                                    ForEach(Array(Set(mon.species.types.map(GardenTrait.of))).sorted { $0.rawValue < $1.rawValue }) { t in
                                        Label(t.name, systemImage: t.symbol).font(.rounded(12, .bold))
                                            .foregroundStyle(Color(hex: t.hex))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a worker")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Map timer

/// Shown on the map while berries are growing: time until the next plant is ready (tap for the Garden).
struct GardenTimerChip: View {
    let readyAt: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let s = max(0, Int(readyAt.timeIntervalSince(tl.date)))
            HStack(spacing: 6) {
                Image(systemName: s == 0 ? "basket.fill" : "leaf.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(s == 0 ? .yellow : Color(hex: 0x9BE15D))
                Text(s == 0 ? "Berries ready!" : s >= 3600 ? "\(s / 3600)h \((s % 3600) / 60)m" : "\(max(1, s / 60))m")
                    .font(.rounded(15, .heavy)).foregroundStyle(.white).monospacedDigit()
            }
            .padding(.horizontal, 14).frame(height: 44)
            .glassCapsule()
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
    }
}
