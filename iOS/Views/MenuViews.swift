import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main menu

extension Notification.Name {
    /// Posted the moment the map's menu panel starts closing.
    static let menuPanelClosing = Notification.Name("menuPanelClosing")
}

struct MainMenuView: View {
    @EnvironmentObject private var store: GameStore
    var close: () -> Void = {}

    enum Dest: Hashable {
        case pc, dex, bag, shop, journal, trainer, settings, summary(UUID)
    }

    private struct Item: Identifiable { let dest: Dest; let title: String; let symbol: String; var id: String { title } }
    private let items: [Item] = [
        .init(dest: .pc, title: "Pokémon", symbol: "square.grid.3x3.fill"),
        .init(dest: .dex, title: "Pokédex", symbol: "book.closed.fill"),
        .init(dest: .bag, title: "Bag", symbol: "bag.fill"),
        .init(dest: .shop, title: "Poké Mart", symbol: "cart.fill"),
        .init(dest: .journal, title: "Journal", symbol: "map.fill"),
        .init(dest: .trainer, title: "Trainer", symbol: "person.text.rectangle.fill"),
        .init(dest: .settings, title: "Settings", symbol: "gearshape.fill"),
    ]

    @State private var path: [Dest] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    if let buddy = store.state.buddy {
                        NavigationLink(value: Dest.summary(buddy.id)) { BuddyHeader(mon: buddy) }
                            .buttonStyle(.plain)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(items) { item in
                            let title = item.title, symbol = item.symbol
                            NavigationLink(value: item.dest) {
                                VStack(spacing: 10) {
                                    Image(systemName: symbol).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.tealDark)
                                    Text(title).font(.rounded(17, .black)).foregroundStyle(.white)
                                }
                                .frame(maxWidth: .infinity).frame(height: 112)
                                .contentShape(RoundedRectangle(cornerRadius: 24))
                                .glassCard(24)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                // Fade the menu out while a screen slides in over it (the panel is see-through)
                .opacity(path.isEmpty ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: path.isEmpty)
            }
            .navigationTitle("Menu")
            .glassScreen(transparent: true)
            // The PC's closing sound plays the moment you leave it, not after the slide finishes
            .onChange(of: path) { old, new in
                if old.contains(.pc) && !new.contains(.pc) { SoundKit.shared.play(.closePC) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuPanelClosing)) { _ in
                if path.contains(.pc) { SoundKit.shared.play(.closePC) }
            }
            .navigationDestination(for: Dest.self) { d in
                switch d {
                case .pc: PCView()
                case .dex: PokedexView()
                case .bag: BagView()
                case .shop: ShopView()
                case .journal: JournalView()
                case .trainer: TrainerCardView()
                case .settings: SettingsView()
                case .summary(let id): SummaryView(pokemonID: id)
                }
            }
        }
    }
}

/// Buddy card at the top of the menu: animated sprite, name, level, Exp, steps and distance together.
struct BuddyHeader: View {
    let mon: OwnedPokemon

    var body: some View {
        let tint = Color(mon.species.primaryType)
        HStack(spacing: 14) {
            AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mon.name).font(.rounded(22, .black)).lineLimit(1)
                    Text(mon.gender.symbol).font(.rounded(15, .heavy))
                    Spacer(minLength: 4)
                    Text("Lv \(mon.level)").font(.rounded(16, .heavy)).foregroundStyle(Theme.tealDark)
                }
                ExpBar(progress: mon.levelProgress, tint: tint, height: 8)
                Text("\(mon.expToNext.formatted()) Exp to next level").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 14) {
                    Label(mon.stepsWalked.formatted(), systemImage: "figure.walk")
                    Label(Distance.text(mon.metersWalked), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
                }
                .font(.rounded(13, .heavy))
            }
        }
        .padding(14)
        .foregroundStyle(.white)
        .glassCard(26, tint: tint)
    }
}

// MARK: - Pokédex

struct PokedexView: View {
    @State private var playedOpen = false
    @EnvironmentObject private var store: GameStore
    @State private var filter = 0
    @State private var gen = 0
    @State private var selected: Species?

    @State private var search = ""

    private var list: [Species] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return Dex.all.filter { sp in
            if !q.isEmpty {
                // Only Pokémon you've met: caught ones by name or number, seen-only ones by number
                let caught = store.state.dexCaught.contains(sp.id), seen = store.state.dexSeen.contains(sp.id)
                guard seen || caught else { return false }
                let num = String(sp.id), padded = String(format: "%03d", sp.id)
                let byNumber = num.hasPrefix(q.trimmingCharacters(in: CharacterSet(charactersIn: "#no. "))) || padded.hasPrefix(q)
                let byName = caught && sp.name.lowercased().contains(q)
                if !(byNumber || byName) { return false }
            }
            return (gen == 0 || sp.generation == gen) &&
            (filter == 0 || (filter == 1 ? store.state.dexCaught.contains(sp.id)
                                          : store.state.dexSeen.contains(sp.id) && !store.state.dexCaught.contains(sp.id)))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("Show", selection: $filter) {
                    Text("All").tag(0); Text("Caught").tag(1); Text("Seen").tag(2)
                }.pickerStyle(.segmented)
                Picker("Generation", selection: $gen) {
                    Text("All gens").tag(0)
                    ForEach(1...3, id: \.self) { Text("Gen \($0)").tag($0) }
                }.pickerStyle(.segmented)
                Text("Caught \(store.state.dexCaught.count) · Seen \(store.state.dexSeen.count) · of \(Dex.count)")
                    .font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(list) { sp in
                        let caught = store.state.dexCaught.contains(sp.id)
                        let seen = store.state.dexSeen.contains(sp.id)
                        Button { if seen { selected = sp } } label: {
                            VStack(spacing: 2) {
                                if caught {
                                    AnimatedSprite(speciesID: sp.id, kind: .icons).frame(height: 34)
                                } else if seen {
                                    // Seen but not caught: just its silhouette
                                    AnimatedSprite(speciesID: sp.id, kind: .icons).frame(height: 34)
                                        .brightness(-1).opacity(0.75)
                                } else {
                                    Image(systemName: "questionmark").font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Theme.inkSoft).frame(height: 34)
                                }
                                Text(String(format: "%03d", sp.id)).font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                                Text(caught ? sp.name : "???").font(.rounded(11, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .glassCard(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Pokédex")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Pokémon you've met")
        .onAppear { if !playedOpen { playedOpen = true; SoundKit.shared.play(.dexOpen) } }
        .glassScreen()
        .navigationDestination(item: $selected) { DexEntryView(species: $0) }
    }
}

// MARK: - Bag

struct BagView: View {
    enum Pocket: String, CaseIterable, Identifiable {
        case balls = "Balls", berries = "Berries", items = "Items", candies = "Candies", key = "Key"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .balls: return "circle.circle.fill"
            case .berries: return "leaf.fill"
            case .items: return "bag.fill"
            case .candies: return "sparkles"
            case .key: return "key.fill"
            }
        }
        static func of(_ key: String) -> Pocket {
            if key == Fishing.rodKey { return .key }
            if ItemCatalog.isBerry(key) || Fishing.isBait(key) { return .berries }
            if key == "rare-candy" || ExpCandy.exp(key) != nil { return .candies }
            return .items
        }
    }

    @State private var openItem: String?
    @State private var pocket: Pocket = .balls
    @State private var fished: PendingEncounter?
    @EnvironmentObject private var store: GameStore

    private func keys(in p: Pocket) -> [String] {
        let all = store.state.bag.filter { $0.value > 0 }.keys.filter { Pocket.of($0) == p }
        if p == .candies {
            let order = ["rare-candy"] + ExpCandy.all.map(\.key)
            return all.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        }
        return all.sorted { Dex.itemName($0) < Dex.itemName($1) }
    }

    var body: some View {
        List {
            Section {
                Picker("Pocket", selection: $pocket) {
                    ForEach(Pocket.allCases) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if pocket == .balls {
                Section {
                    ForEach(BallKind.allCases.filter { $0.isStepBall || store.state.balls[$0, default: 0] > 0 }) { k in
                        HStack(spacing: 12) {
                            ItemSprite(key: k.itemKey).frame(width: 30, height: 30)
                            VStack(alignment: .leading) {
                                Text(k.name).font(.rounded(16, .heavy))
                                Text(k.effect).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text("×\(store.state.balls[k, default: 0])").font(.rounded(16, .heavy))
                        }
                        .glassRow()
                    }
                } footer: {
                    Text("A Poké Ball every \(store.state.settings.ballSteps.formatted()) steps (every 10th is a Great Ball, every 50th an Ultra Ball). Rarer balls turn up as items, or buy them at the Poké Mart.")
                }
            } else {
                if pocket == .berries { BaitMaker() }
                if pocket == .key, (store.state.bag[Fishing.rodKey] ?? 0) > 0 {
                    Section {
                        FishingRodRow { fished = $0 }.glassRow()
                    } footer: {
                        Text("Cast once every 20 minutes. Bait made from more berries gets more bites and rarer Pokémon (Dratini, Gyarados, Feebas…).")
                    }
                }
                Section {
                    let list = keys(in: pocket).filter { $0 != Fishing.rodKey }
                    if list.isEmpty && !(pocket == .key && (store.state.bag[Fishing.rodKey] ?? 0) > 0) {
                        Text(emptyText).foregroundStyle(Theme.inkSoft).glassRow()
                    }
                    ForEach(list, id: \.self) { key in
                        BagItemRow(key: key, expanded: openItem == key) {
                            withAnimation(.snappy) { openItem = openItem == key ? nil : key }
                        }
                        .glassRow()
                    }
                } footer: {
                    Text(footerText)
                }
            }
        }
        .animation(.snappy, value: pocket)
        .navigationTitle("Bag")
        .glassScreen()
        .fullScreenCover(item: $fished) { SafariView(wild: $0) }
    }

    private var emptyText: String {
        switch pocket {
        case .berries: return "No berries yet — they're the most common thing you find on walks."
        case .candies: return "No candies yet. Your buddy picks up Exp. Candies as you walk; take them from its Summary."
        case .key: return "No key items yet. A Fishing Rod is sold at the Poké Mart."
        default: return "Nothing yet — keep walking!"
        }
    }

    private var footerText: String {
        switch pocket {
        case .berries: return "You find a berry every \(store.state.settings.berrySteps.formatted()) steps (change it in Settings). Throw them in wild encounters so the Pokémon stays longer, or give one to a Pokémon to make it friendlier."
        case .candies: return "Rare Candies raise a level; Exp. Candies give Exp. Your buddy finds an Exp. Candy about every 300 steps."
        case .key: return "Key items are never used up."
        default: return "An item every \(store.state.settings.itemSteps.formatted()) steps: evolution stones, Link Cables, held items, bitter herbs and valuables to sell. Tap one to use or sell it."
        }
    }
}

// MARK: - Trainer card (Liquid Glass, inspired by the Hoenn trainer card)

struct TrainerCardView: View {
    @EnvironmentObject private var store: GameStore
    var popup = false
    @State private var totalMeters: Double = 0
    @State private var totalSteps: Int = 0

    private let gold = Color(hex: 0xF2CC4A)

    private var stars: Int {
        let s = store.state
        return [s.dexCaught.count >= 100, s.dexCaught.count >= Dex.count, s.lifetimeSteps >= 1_000_000,
                s.pokemon.contains(where: \.isShiny)].filter { $0 }.count
    }

    var body: some View {
        if popup {
            card
        } else {
            ScrollView { card.padding(16).padding(.top, 20) }
                .navigationTitle("Trainer")
                .glassScreen()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Capsule().fill(gold).frame(width: 4, height: 15)
                Text(label).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 6)
                Text(value).font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
        }
    }

    private var card: some View {
        let t = store.state.trainer
        let accent = Color(hex: t.style.cardHex)
        return VStack(spacing: 14) {
            HStack {
                Text("TRAINER CARD")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassCapsule(tint: Color(hex: 0x3D7BE0))
                Spacer()
                Text("IDNo.\(t.idString)").font(.system(size: 17, weight: .heavy, design: .monospaced))
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 10) {
                    row("NAME", t.name.uppercased())
                    row("POKéDEX", "\(store.state.dexCaught.count)")
                    row("MONEY", "₽\(store.state.money.formatted())")
                    row("STEPS", max(totalSteps, store.state.lifetimeSteps).formatted())
                    row("DISTANCE", Distance.text(totalMeters))
                    row("STARTED", t.startedOn.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(i < stars ? gold : .white.opacity(0.3))
                        }
                        Spacer()
                    }
                }
                ZStack {
                    Circle().fill(accent.opacity(0.25)).frame(width: 118, height: 118).glassCircle(tint: accent, interactive: false)
                    TrainerSprite(style: t.style, pose: .card).frame(width: 110, height: 128)
                }
                .frame(width: 122)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PARTY").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 6) {
                    ForEach(0..<GameState.maxParty, id: \.self) { i in
                        let mon = i < store.state.party.count ? store.state.party[i] : nil
                        ZStack {
                            if let mon { AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons).padding(3) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .glassCard(10)
                    }
                }
            }
            .padding(10)
            .glassCard(16, tint: gold)
        }
        .padding(16)
        .foregroundStyle(.white)
        .glassCard(28, tint: accent)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .task {
            let tracks = TrackStore.shared
            let tracked = tracks.daysWithTracks.reduce(0) { $0 + tracks.meters(on: $1) }
            let buddies = store.state.pokemon.reduce(0) { $0 + $1.metersWalked }
            totalMeters = max(tracked, buddies)
            // Lifetime: everything since the day you started your adventure, not just today.
            let since = Calendar.current.startOfDay(for: store.state.trainer.startedOn)
            let all = await StepEngine.shared.totals(since: since)
            totalSteps = all.steps
            totalMeters = max(totalMeters, all.meters)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var name = ""
    @State private var importKind: SpriteStore.Kind?
    @State private var importing = false
    @State private var message: String?
    @State private var confirmReset = false
    @State private var testBattle: PendingEncounter?
    @State private var importingSave = false
    @State private var confirmImport: URL?
    @State private var exportURL: URL?
    @State private var liveActivity = LiveActivityManager.shared.enabled
    @StateObject private var downloader = SpriteDownloader.shared
    @StateObject private var cries = CryPlayer.shared

    var body: some View {
        Form {
            Section("Trainer") {
                TextField("Trainer name", text: $name).onSubmit { store.setTrainerName(name) }.glassRow()
                LabeledContent("ID No.", value: store.state.trainer.idString).glassRow()
                Picker("Look", selection: Binding(get: { store.state.trainer.appearance }, set: { store.setAppearance($0) })) {
                    ForEach(TrainerStyle.all) { Text("\($0.name) (\($0.game))").tag($0.id) }
                }
                .glassRow()
            }

            Section {
                NavigationLink { SoundSettingsView() } label: {
                    Label("Sounds & music", systemImage: "speaker.wave.2.fill").font(.rounded(16, .heavy))
                }
                .glassRow()
            }

            StepSyncSection()

            Section {
                Picker("Location tracking", selection: binding(\.trackingMode)) {
                    ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
                }
                .glassRow()
                Toggle("Lock Screen Live Activity", isOn: $liveActivity)
                    .onChange(of: liveActivity) { _, on in
                        LiveActivityManager.shared.enabled = on
                        if on { LiveActivityManager.shared.startIfNeeded(with: store) }
                    }
                    .glassRow()
                Toggle("Encounter notifications", isOn: binding(\.notifyEncounters)).glassRow()
            } header: { Text("Walking") } footer: {
                Text("Adventure mode records where you walk all day and pauses automatically when you stop. iOS ends Live Activities after 8 hours; PokéWalk starts a new one each time you open it. Set Location to \"Always\" in iOS Settings to get rid of the blue location arrow.")
            }

            Section {
                Picker("Buddy Exp per step", selection: binding(\.expPerStep)) {
                    Text("0.1").tag(0.1); Text("0.2").tag(0.2); Text("0.25").tag(0.25); Text("0.3").tag(0.3)
                    Text("0.5").tag(0.5); Text("1 (Pokéwalker)").tag(1.0)
                }
                .glassRow()
                Picker("Party Exp share", selection: binding(\.partyShare)) {
                    Text("Off").tag(0.0); Text("10%").tag(0.1); Text("20%").tag(0.2); Text("50%").tag(0.5)
                }
                .glassRow()
                Stepper("Encounter every ~\(store.state.settings.encounterSteps) steps",
                        value: binding(\.encounterSteps), in: 100...2_000, step: 50).glassRow()
                Stepper("Ball every \(store.state.settings.ballSteps) steps", value: binding(\.ballSteps), in: 50...2_000, step: 50).glassRow()
                Stepper("Item every \(store.state.settings.itemSteps.formatted()) steps", value: binding(\.itemSteps), in: 250...5_000, step: 250).glassRow()
                Stepper("Berry every \(store.state.settings.berrySteps.formatted()) steps", value: binding(\.berrySteps), in: 100...2_000, step: 50).glassRow()
                Picker("Wild shiny chance", selection: binding(\.shinyOdds)) {
                    Text("1 in 8192 (Gen 3)").tag(8192); Text("1 in 4096").tag(4096); Text("1 in 1000").tag(1000); Text("1 in 512").tag(512); Text("1 in 128").tag(128)
                }
                .glassRow()
            } header: { Text("Game balance") } footer: {
                Text("Your buddy gets the Exp per step; the rest of your party gets the share of that (e.g. 10 Exp → 2 Exp at 20%). Pokémon in the PC don't gain Exp. Wild shiny chance applies to Pokémon you meet on walks; starters are always 1 in 8192.")
            }

            Section {
                let pc = PhoneConnectivity.shared
                LabeledContent("Watch paired", value: pc.isWatchPaired ? "Yes" : "No").glassRow()
                LabeledContent("PokéWalk on Watch", value: pc.isWatchAppInstalled ? "Installed" : "Not installed").glassRow()
                LabeledContent("Complication on a face", value: pc.isComplicationOnFace ? "Yes" : "No").glassRow()
            } header: { Text("Apple Watch") } footer: {
                Text("Watch complications need the Watch app, which SideStore can't install. The Lock Screen Live Activity also appears in your Watch's Smart Stack.")
            }

            Section {
                Button {
                    SoundKit.shared.play(.select)
                    testBattle = PendingEncounter(speciesID: 1, level: 30, gender: .male, isShiny: false, nature: "Quirky",
                                                  personality: 0, appearedAt: .now, expiresAt: .now.addingTimeInterval(600),
                                                  location: nil, habitat: nil)
                } label: {
                    Label("Test battle", systemImage: "questionmark.square.dashed")
                }
                .glassRow()
            } footer: {
                Text("Battle a MissingNo. with unlimited Poké Balls to see how battles look. Nothing is saved and no balls are used.")
            }

            Section {
                ForEach(SpriteStore.Kind.allCases, id: \.self) { kind in
                    Button("Import \(title(kind)) folder…") { importKind = kind; importing = true }.glassRow()
                }
                Button("Re-send party icons to Watch") {
                    PhoneConnectivity.shared.resetSentSprites(); store.pushOutward()
                }
                .glassRow()
                if let p = downloader.progress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloading sprites… \(Int(p * 100))%")
                        ProgressView(value: p).tint(Theme.teal)
                    }
                    .glassRow()
                } else {
                    Button(downloader.finished ? "Download all sprites again" : "Download all sprites for offline") {
                        downloader.start()
                    }
                    .glassRow()
                    if downloader.finished {
                        Text(downloader.failed == 0 ? "All sprites saved — PokéWalk looks complete offline."
                                                    : "Saved all but \(downloader.failed). Tap again on Wi-Fi to fill the gaps.")
                            .font(.rounded(13)).foregroundStyle(Theme.inkSoft).glassRow()
                    }
                }
                Button("Clear downloaded sprites") { SpriteStore.shared.clearDownloads() }.glassRow()
            } header: { Text("Sprites") } footer: {
                Text("Name Pokémon sprites by Pokédex number (25.gif) or name (pikachu.gif). Trainer sprites: red-walk.gif (walking), red-head.gif (map button), red-card.png (trainer card) — also leaf, gold, kris, brendan, may. Missing ones are downloaded. \"Download all\" saves every Pokémon (animated, shiny and box icon) and every trainer, about 15–25 MB — best on Wi-Fi.")
            }

            Section {
                Toggle("Play cries", isOn: Binding(get: { cries.enabled }, set: { cries.enabled = $0 })).glassRow()
                if let p = cries.progress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloading cries… \(Int(p * 100))%")
                        ProgressView(value: p).tint(Theme.teal)
                    }
                    .glassRow()
                } else {
                    Button(cries.finished || cries.downloadedCount >= Dex.count ? "Download all cries again" : "Download all cries for offline") {
                        cries.downloadAll()
                    }
                    .glassRow()
                    if cries.finished {
                        Text(cries.failed == 0 ? "All \(Dex.count) cries saved."
                                               : "Saved all but \(cries.failed). Tap again on Wi-Fi to fill the gaps.")
                            .font(.rounded(13)).foregroundStyle(Theme.inkSoft).glassRow()
                    }
                }
                Button("Delete downloaded cries") { cries.clear() }.glassRow()
            } header: { Text("Sounds") } footer: {
                Text("A Pokémon cries when you open its summary or meet it in the wild. Cries follow your silent switch and play over music. Each one is saved the first time you hear it; Download all saves all \(Dex.count) (about 5 MB).")
            }

            Section {
                Button("Export save…") { exportURL = store.exportSave() }.glassRow()
                Button("Import save…") { importingSave = true; importKind = nil; importing = true }.glassRow()
            } header: { Text("Save data") } footer: {
                Text("Export before installing a new IPA, then Import in the new one — or save it to iCloud Drive. PokéWalk also keeps an automatic backup in Files › On My iPhone › PokéWalk › Backups. Installing an update over the top (same SideStore app) keeps your save without doing anything.")
            }

            Section {
                Button("Start a new game", role: .destructive) { confirmReset = true }.glassRow()
            }
        }
        .navigationTitle("Settings")
        .glassScreen()
        .onAppear { name = store.state.trainer.name }
        .fullScreenCover(item: $testBattle) { SafariView(wild: $0, test: true) }
        .fileImporter(isPresented: $importing, allowedContentTypes: importingSave ? [.json, .data] : [.folder]) { result in
            defer { importingSave = false }
            if importingSave {
                if case .success(let url) = result { confirmImport = url }
                return
            }
            guard let kind = importKind, case .success(let url) = result else { return }
            do {
                let n = try SpriteStore.shared.importFolder(url, as: kind)
                message = "Imported \(n) \(title(kind)) sprites."
                if kind == .icons { PhoneConnectivity.shared.resetSentSprites(); store.pushOutward() }
            } catch {
                message = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
        .confirmationDialog("Replace this game with the imported save?", isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }),
                            titleVisibility: .visible) {
            Button("Replace with imported save", role: .destructive) {
                guard let url = confirmImport else { return }
                message = store.importSave(from: url) ?? "Save imported. Welcome back, \(store.state.trainer.name)!"
                name = store.state.trainer.name
            }
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let url = exportURL { ShareSheet(items: [url]).presentationDetents([.medium, .large]) }
        }
        .confirmationDialog("Erase your Pokémon, PC, items and progress? Walk tracks and Pokémon in Storage are kept.", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { store.resetGame() }
        }
    }

    private func title(_ k: SpriteStore.Kind) -> String {
        switch k {
        case .front: return "animated (front)"
        case .shiny: return "shiny"
        case .back: return "animated (back)"
        case .backShiny: return "shiny (back)"
        case .icons: return "party icon"
        case .iconsShiny: return "shiny party icon"
        case .items: return "item"
        case .trainers: return "trainer"
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: kp] }, set: { v in store.updateSettings { $0[keyPath: kp] = v } })
    }
}


/// System share sheet (Save to Files, iCloud Drive, AirDrop…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}


/// Shows where today's steps come from, so a mismatch with the Health app can be fixed.
private struct StepSyncSection: View {
    @EnvironmentObject private var store: GameStore
    @State private var health: Int?
    @State private var healthError: String?
    @State private var phone: Int?
    @State private var checking = false

    var body: some View {
        Section {
            row("Apple Health (incl. Watch)", health.map { $0.formatted() } ?? (healthError == nil ? "…" : "Not connected"))
            row("iPhone motion chip", phone.map { $0.formatted() } ?? "…")
            row("Shortcut (Health)", ShortcutSteps.lastSync.map { _ in
                ShortcutSteps.steps(for: TrackStore.key(for: Calendar.current.startOfDay(for: .now))).formatted()
            } ?? "Not set up")
            row("PokéWalk today", store.stepsToday.formatted())
            if let healthError {
                Text(healthError).font(.rounded(12)).foregroundStyle(Theme.inkSoft).glassRow()
            }
            Button(checking ? "Checking…" : "Reconnect Apple Health") {
                Task {
                    checking = true
                    try? await StepCounter.shared.requestAuthorizationWithDistance()
                    await refresh()
                    await store.tick()
                    checking = false
                }
            }
            .disabled(checking)
            .glassRow()
            Button("Open the Health app") {
                if let u = URL(string: "x-apple-health://") { UIApplication.shared.open(u) }
            }
            .glassRow()
        } header: { Text("Step sync") } footer: {
            Text("PokéWalk uses whichever is higher. If Apple Health shows 0 here but more in the Health app, PokéWalk isn't allowed to read it: in the Health app tap your profile picture › Apps › PokéWalk and turn on Steps and Walking + Running Distance. (Settings › Privacy & Security › Health › PokéWalk works too.) Steps earned before the fix are added on the next sync — from today and yesterday.")
        }
        .task { await refresh() }

        Section {
            NavigationLink {
                StepSyncSetupView()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up Apple Watch step sync").font(.rounded(16, .heavy))
                    Text(ShortcutSteps.lastSync.map { "Last synced \($0.formatted(.relative(presentation: .named)))" }
                         ?? "Step-by-step guide · about 3 minutes")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .glassRow()
        } header: { Text("Shortcut sync") }
    }

    private func refresh() async {
        let start = Calendar.current.startOfDay(for: .now)
        do {
            health = try await StepCounter.shared.steps(from: start)
            healthError = health == 0 ? "Health returned no steps — usually means read access is off." : nil
        } catch {
            health = nil
            healthError = "Apple Health error: \(error.localizedDescription)"
        }
        phone = await StepEngine.shared.pedometerSteps(from: start, to: .now)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(.rounded(16, .heavy)).foregroundStyle(Theme.teal)
        }
        .glassRow()
    }
}


extension BagItemRow {
    func sellButton(_ title: String, count: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let earned = store.sell(key, count: count)
            if earned > 0 { store.toast = "Sold for ₽\(earned.formatted()). You have ₽\(store.state.money.formatted())." }
        } label: {
            Text(title).font(.rounded(14, .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Theme.teal.opacity(0.75), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A Bag item: tap to see what it does and pick a party Pokémon to use it on (ABLE / NOT ABLE).
private struct BagItemRow: View {
    @EnvironmentObject var store: GameStore
    let key: String
    let expanded: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    ItemSprite(key: key).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Dex.itemName(key)).font(.rounded(16, .heavy))
                        Text(Fishing.isBait(key) ? "Berries mixed into bait. Use it with the Fishing Rod (Key Items)."
                             : GameRules.itemDescription(key)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            .lineLimit(expanded ? nil : 1)
                    }
                    Spacer()
                    Text("×\(store.state.bag[key] ?? 0)").font(.rounded(16, .heavy))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let n = Fishing.baitBerries(key) {
                let w = Fishing.tierWeights(berries: n), total = w.reduce(0, +)
                Text("\(Int(Fishing.biteChance(berries: n) * 100))% chance of a bite · \(Int((w[2] / total * 100).rounded()))% chance of a rare catch")
                    .font(.rounded(12, .heavy)).foregroundStyle(Theme.tealDark)
            } else if expanded, let price = ItemCatalog.sellPrice[key] {
                let have = store.state.bag[key] ?? 0
                HStack(spacing: 10) {
                    sellButton("Sell 1 · ₽\(price)", count: 1)
                    if have > 1 { sellButton("Sell all · ₽\((price * have).formatted())", count: have) }
                }
            } else if expanded {
                Text("Use on…").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                ForEach(store.state.party) { mon in
                    let able = GameRules.canUse(key, on: mon)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let before = mon.level
                        let outcome = store.use(key, on: mon.id)
                        if outcome != .noEffect { SoundKit.shared.play(.useItem) }
                        switch outcome {
                        case .leveled:
                            let now = store.state.mon(mon.id)?.level ?? before
                            store.toast = now > before ? "\(mon.name) grew to Lv \(now)!" : "\(mon.name) gained Exp!"
                        case .evolves: break        // the evolution screen takes over
                        case .friendship(let up):
                            store.toast = up ? "\(mon.name) became more friendly!" : "\(mon.name) looks bitter…"
                        case .noEffect: store.toast = "It won't have any effect."
                        }
                    } label: {
                        HStack(spacing: 10) {
                            AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons).frame(width: 34, height: 28)
                            Text(mon.name).font(.rounded(15, .heavy))
                            Text("Lv \(mon.level)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                            Spacer()
                            Text(able ? "ABLE" : "NOT ABLE").font(.rounded(12, .black))
                                .foregroundStyle(able ? Theme.teal : Theme.inkSoft)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(able ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!able)
                    .opacity(able ? 1 : 0.55)
                }
            }
        }
    }
}


// MARK: - Fishing

/// Berries pocket: mix berries into bait for the Fishing Rod.
private struct BaitMaker: View {
    @EnvironmentObject private var store: GameStore
    @State private var count = 3

    private var berries: Int { ItemCatalog.berries.reduce(0) { $0 + (store.state.bag[$1] ?? 0) } }

    var body: some View {
        if berries > 0 {
            let n = min(count, berries, Fishing.maxBerries)
            let w = Fishing.tierWeights(berries: n), total = w.reduce(0, +)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ItemSprite(key: Fishing.baitKey(berries: n)).frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fishing.baitName(berries: n)).font(.rounded(16, .heavy))
                            Text("\(Int(Fishing.biteChance(berries: n) * 100))% bite · \(Int((w[2] / total * 100).rounded()))% rare catch")
                                .font(.rounded(12, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                    }
                    HStack(spacing: 10) {
                        Stepper("\(n) \(n == 1 ? "berry" : "berries")",
                                value: Binding(get: { n }, set: { count = $0 }), in: 1...max(1, min(berries, Fishing.maxBerries)))
                            .font(.rounded(15, .heavy))
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if store.makeBait(berries: n) {
                                SoundKit.shared.play(.useItem)
                                store.toast = "Made \(Fishing.baitName(berries: n))!"
                            }
                        } label: {
                            Text("Make bait").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(Theme.teal.opacity(0.8), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassRow()
            } header: {
                Text("Make bait")
            } footer: {
                Text("Mix up to \(Fishing.maxBerries) berries into bait for the Fishing Rod (sold at the Poké Mart). More berries, better odds.")
            }
        }
    }
}

/// Key Items pocket: the Fishing Rod — pick a bait and cast (once every 20 minutes).
private struct FishingRodRow: View {
    @EnvironmentObject private var store: GameStore
    var onBite: (PendingEncounter) -> Void
    @State private var casting = false

    private var baits: [String] {
        store.state.bag.filter { $0.value > 0 && Fishing.isBait($0.key) }.keys
            .sorted { (Fishing.baitBerries($0) ?? 0) > (Fishing.baitBerries($1) ?? 0) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let wait = Fishing.cooldownLeft(store.state, now: tl.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ItemSprite(key: Fishing.rodKey).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fishing.rodName).font(.rounded(16, .heavy))
                        Text(casting ? "…" : wait > 0 ? "Ready again in \(Self.mmss(wait))"
                             : baits.isEmpty ? "No bait — make some in the Berries pocket" : "Ready to cast")
                            .font(.rounded(12, .heavy))
                            .foregroundStyle(wait > 0 || baits.isEmpty ? Theme.inkSoft : Theme.tealDark)
                            .monospacedDigit()
                    }
                    Spacer()
                }
                if wait == 0 && !baits.isEmpty && !casting {
                    ForEach(baits, id: \.self) { key in
                        Button { cast(key) } label: {
                            HStack(spacing: 10) {
                                ItemSprite(key: key).frame(width: 26, height: 26)
                                Text("Cast with \(Dex.itemName(key))").font(.rounded(14, .heavy))
                                Spacer()
                                Text("×\(store.state.bag[key] ?? 0)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Theme.teal.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cast(_ bait: String) {
        casting = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))       // waiting for a nibble…
            let result = store.fish(with: bait)
            casting = false
            switch result {
            case .bite(let wild):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                store.toast = "Oh! A bite!"
                try? await Task.sleep(for: .milliseconds(600))
                onBite(wild)
            case .nothing:
                store.toast = "Not even a nibble… Try again in 20 minutes."
            case .notReady:
                break
            }
        }
    }

    static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Poké Mart

/// Spend Pokédollars from selling valuables on balls (pricier than the games — balls also come free every 100 steps).
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @State private var amounts: [BallKind: Int] = [:]

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "yensign.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.teal)
                    VStack(alignment: .leading) {
                        Text("Money").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                        Text("₽\(store.state.money.formatted())").font(.rounded(26, .black))
                            .contentTransition(.numericText(value: Double(store.state.money)))
                    }
                    Spacer()
                }
                .glassRow()
            } footer: {
                Text("You earn ₽1 for every 100 steps (₽0.01 a step), plus whatever you get selling valuables (Pearls, Stardust, Nuggets…) from your Bag. Buy 10 Poké Balls at once for a free Premier Ball.")
            }

            Section {
                ForEach(ItemCatalog.shop, id: \.ball) { entry in
                    let n = amounts[entry.ball, default: 1]
                    let total = entry.price * n
                    let afford = store.state.money >= total
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ItemSprite(key: entry.ball.itemKey).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.ball.name).font(.rounded(16, .heavy))
                                Text(entry.ball.effect).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("₽\(entry.price.formatted())").font(.rounded(15, .heavy))
                                Text("have \(store.state.balls[entry.ball, default: 0])").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        HStack(spacing: 10) {
                            Stepper("×\(n)", value: Binding(get: { amounts[entry.ball, default: 1] },
                                                            set: { amounts[entry.ball] = $0 }), in: 1...99)
                                .font(.rounded(15, .heavy))
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if store.buy(entry.ball, count: n) {
                                    let bonus = entry.ball == .poke && n >= 10 ? " + \(n / 10) Premier Ball\(n >= 20 ? "s" : "")" : ""
                                    store.toast = "Bought \(n) \(entry.ball.name)\(n > 1 ? "s" : "")\(bonus)!"
                                    amounts[entry.ball] = 1
                                }
                            } label: {
                                Text("Buy · ₽\(total.formatted())").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background(afford ? Theme.teal.opacity(0.8) : .white.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!afford)
                        }
                    }
                    .glassRow()
                }
            } header: { Text("Balls") }

            Section {
                let owned = (store.state.bag[Fishing.rodKey] ?? 0) > 0
                let afford = store.state.money >= Fishing.rodPrice
                HStack(spacing: 12) {
                    ItemSprite(key: Fishing.rodKey).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fishing.rodName).font(.rounded(16, .heavy))
                        Text("Fish up water Pokémon with bait made from berries.").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if owned {
                        Text("Owned").font(.rounded(14, .heavy)).foregroundStyle(Theme.tealDark)
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if store.buyFishingRod() { store.toast = "You got the Fishing Rod! It's in your Bag's Key Items." }
                        } label: {
                            Text("₽\(Fishing.rodPrice.formatted())").font(.rounded(14, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(afford ? Theme.teal.opacity(0.8) : .white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!afford)
                    }
                }
                .glassRow()
            } header: { Text("Key items") }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Poké Mart")
        .glassScreen()
    }
}
