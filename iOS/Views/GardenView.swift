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

    private var field: some View {
        let b = store.gardenBonuses
        let open = store.gardenPlotCount
        let cellW = 16 * scale, cellH = 32 * scale
        return VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.6)) { tl in
                let frame = Int(tl.date.timeIntervalSince1970 / 0.6)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: 14), count: columns), spacing: 6) {
                    ForEach(store.state.garden.plots.prefix(Garden.maxPlots)) { plot in
                        PlotCell(plot: plot, locked: plot.id >= open, bonuses: b, frame: frame, scale: scale,
                                 cellW: cellW, cellH: cellH, now: tl.date)
                            .onTapGesture { tap(plot) }
                    }
                    // brand-new saves: show all patches
                    if store.state.garden.plots.count < Garden.maxPlots {
                        ForEach(store.state.garden.plots.count..<Garden.maxPlots, id: \.self) { i in
                            PlotCell(plot: GardenPlot(id: i), locked: i >= open, bonuses: b, frame: frame, scale: scale,
                                     cellW: cellW, cellH: cellH, now: tl.date)
                                .onTapGesture { tap(GardenPlot(id: i)) }
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background { grassBackground }
            .overlay { WorkersLayer(workers: store.gardenWorkers) }
            .clipShape(RoundedRectangle(cornerRadius: 18))

            if let i = info, let plot = store.state.garden.plots.first(where: { $0.id == i }), let berry = plot.berry {
                plotInfo(plot, berry: berry, bonuses: b)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(duration: 0.3), value: info)
    }

    @ViewBuilder private var grassBackground: some View {
        if let g = gfx.grass, let tile = Self.scaled(g, by: scale) {
            Rectangle().fill(ImagePaint(image: Image(uiImage: tile)))
        } else {
            Color(red: 0.45, green: 0.77, blue: 0.64)
        }
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
        guard plot.id < store.gardenPlotCount else {
            ladySays = "That soil's too hard. Tillers (Ground, Rock, Steel and Fighting types) can dig more patches."
            Haptics.tap()
            return
        }
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Team bonuses").font(.rounded(17, .heavy)).foregroundStyle(.white)
                Spacer()
                Text("Grow time \(hoursText(GardenRules.hoursToGrow(b)))").font(.rounded(13, .bold)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(GardenTrait.allCases) { t in TraitRow(trait: t, count: b.counts[t] ?? 0, tier: b.tier(t)) }
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(b.families.isEmpty ? Theme.inkSoft : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(b.families.isEmpty ? Color.white.opacity(0.08) : Color.purple.opacity(0.7)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Family Ties").font(.rounded(14, .heavy)).foregroundStyle(.white)
                    Text(b.families.isEmpty
                         ? "2 from the same evolution family: 10% faster growth and +1 friendship each harvest (up to 3 families)"
                         : b.families.map { Dex.species($0).name }.joined(separator: ", ") + " family · \(b.families.count * 10)% faster, +\(b.families.count) friendship")
                        .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(14)
        .glassCard(22)
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

// MARK: - One patch of soil

private struct PlotCell: View {
    let plot: GardenPlot
    let locked: Bool
    let bonuses: GardenBonuses
    let frame: Int
    let scale: CGFloat
    let cellW: CGFloat
    let cellH: CGFloat
    let now: Date
    @ObservedObject private var gfx = GardenGfx.shared

    var body: some View {
        let progress = GardenRules.progress(plot, bonuses: bonuses, now: now)
        let stage = BerryStage.at(progress: progress)
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                // soft soil (the bottom half of the tree's 16×32 cell, like on Route 123)
                Group {
                    if locked {
                        Image(systemName: "lock.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                            .frame(width: cellW, height: cellW)
                    } else if let soil = gfx.soil {
                        PixelImageView(image: soil).frame(width: cellW, height: cellW)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.6, green: 0.45, blue: 0.42)).frame(width: cellW, height: cellW)
                    }
                }
                if let berry = plot.berry, !locked, let img = gfx.sprite(berry: berry, stage: stage, frame: frame) {
                    let h = img.size.height * scale
                    PixelImageView(image: img)
                        .frame(width: img.size.width * scale, height: h)
                        .offset(y: -cellW / 4)
                        .shadow(color: stage == .berries ? .yellow.opacity(0.6) : .clear, radius: 6)
                }
            }
            .frame(width: cellW, height: cellH, alignment: .bottom)
            label(progress: progress, stage: stage)
                .frame(height: 16)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "Locked patch" : plot.berry.map { "\(Dex.itemName($0)), \(stage.name)" } ?? "Empty soil")
    }

    @ViewBuilder private func label(progress: Double, stage: BerryStage) -> some View {
        if locked {
            Text("Locked").font(.rounded(11, .heavy)).foregroundStyle(.white.opacity(0.6))
        } else if plot.berry == nil {
            Text("Plant").font(.rounded(11, .heavy)).foregroundStyle(.white.opacity(0.85))
        } else if stage == .berries {
            Text("Pick!").font(.rounded(12, .black)).foregroundStyle(.yellow)
        } else if let at = GardenRules.readyAt(plot, bonuses: bonuses) {
            let s = max(0, Int(at.timeIntervalSince(now)))
            Text(s >= 3600 ? "\(s / 3600)h \((s % 3600) / 60)m" : "\(s / 60)m").font(.rounded(11, .heavy))
                .foregroundStyle(.white).monospacedDigit()
        }
    }
}

// MARK: - Working Pokémon hopping about

private struct WorkersLayer: View {
    let workers: [OwnedPokemon]
    var body: some View {
        GeometryReader { geo in
            ForEach(Array(workers.enumerated()), id: \.element.id) { i, mon in
                HoppingWorker(mon: mon, area: geo.size, seed: i)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HoppingWorker: View {
    let mon: OwnedPokemon
    let area: CGSize
    let seed: Int
    @State private var pos: CGPoint = .zero
    @State private var facingRight = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSince1970 + Double(seed) * 0.37
            let hop = abs(sin(t * 7)) * 7
            LocalIcon(speciesID: mon.speciesID, shiny: mon.isShiny)
                .frame(width: 44, height: 44)
                .scaleEffect(x: facingRight ? -1 : 1, y: 1)
                .offset(y: -hop)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        }
        .position(pos)
        .task(id: area) {
            guard area.width > 60, area.height > 60 else { return }
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
        CGPoint(x: .random(in: 26...(area.width - 26)), y: .random(in: 30...(area.height - 26)))
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
