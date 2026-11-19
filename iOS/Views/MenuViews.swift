import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main menu

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

    var body: some View {
        NavigationStack {
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
            }
            .navigationTitle("Menu")
            .glassScreen(transparent: true)
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
    @EnvironmentObject private var store: GameStore
    @State private var filter = 0
    @State private var gen = 0
    @State private var selected: Species?

    private var list: [Species] {
        Dex.all.filter { sp in
            (gen == 0 || sp.generation == gen) &&
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
                                if seen {
                                    AnimatedSprite(speciesID: sp.id, kind: .icons).frame(height: 34).opacity(caught ? 1 : 0.45)
                                } else {
                                    Image(systemName: "questionmark").font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Theme.inkSoft).frame(height: 34)
                                }
                                Text(String(format: "%03d", sp.id)).font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                                Text(seen ? sp.name : "???").font(.rounded(11, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
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
        .glassScreen()
        .sheet(item: $selected) { sp in
            ScrollView {
                VStack(spacing: 10) {
                    AnimatedSprite(speciesID: sp.id).frame(width: 140, height: 140)
                    Text("\(sp.dexNumber) \(sp.name)").font(.rounded(24, .black))
                    HStack { ForEach(sp.types, id: \.self) { TypeChip(type: $0) } }
                    Text("Found near: " + sp.habitats.map(\.displayName).joined(separator: ", "))
                        .font(.rounded(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    if !sp.evolutions.isEmpty {
                        Text("Evolves: " + sp.evolutions.map(\.summary).joined(separator: "; "))
                            .font(.rounded(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    }
                    if let first = store.state.pokemon.filter({ $0.speciesID == sp.id }).min(by: { $0.metDate < $1.metDate }) {
                        MetCard(mon: first)
                    }
                }
                .padding()
            }
            .glassScreen()
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Bag

struct BagView: View {
    @State private var openItem: String?
    @EnvironmentObject private var store: GameStore

    var body: some View {
        List {
            Section("Balls") {
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
            }
            Section {
                let keys = store.state.bag.keys.sorted { Dex.itemName($0) < Dex.itemName($1) }
                if keys.isEmpty { Text("Nothing yet — keep walking!").foregroundStyle(Theme.inkSoft).glassRow() }
                ForEach(keys, id: \.self) { key in
                    BagItemRow(key: key, expanded: openItem == key) {
                        withAnimation(.snappy) { openItem = openItem == key ? nil : key }
                    }
                    .glassRow()
                }
            } header: { Text("Items") } footer: {
                Text("Balls: 1 every \(store.state.settings.ballSteps) steps (every 10th is a Great Ball, every 50th an Ultra Ball). Items: 1 every \(store.state.settings.itemSteps.formatted()) steps — evolution stones, Rare Candies, Link Cables and rare balls. Your buddy also picks up an Exp. Candy about every 300 steps and holds it until you take it from its summary. Tap an item to use it on a Pokémon in your party.")
            }
        }
        .navigationTitle("Bag")
        .glassScreen()
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
                            if let mon { AnimatedSprite(speciesID: mon.speciesID, kind: .icons).padding(3) }
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
                Picker("Shiny chance", selection: binding(\.shinyOdds)) {
                    Text("1 in 8192 (Gen 3)").tag(8192); Text("1 in 4096").tag(4096); Text("1 in 1000").tag(1000); Text("1 in 512").tag(512); Text("1 in 128").tag(128)
                }
                .glassRow()
            } header: { Text("Game balance") } footer: {
                Text("Your buddy gets the Exp per step; the rest of your party gets the share of that (e.g. 10 Exp → 2 Exp at 20%). Pokémon in the PC don't gain Exp.")
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
        .confirmationDialog("Erase your Pokémon, PC, items and progress? Walk tracks are kept.", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { store.resetGame() }
        }
    }

    private func title(_ k: SpriteStore.Kind) -> String {
        switch k {
        case .front: return "animated (front)"
        case .shiny: return "shiny"
        case .icons: return "party icon"
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
                        Text(GameRules.itemDescription(key)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
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

            if expanded, let price = ItemCatalog.sellPrice[key] {
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
                            AnimatedSprite(speciesID: mon.speciesID, kind: .icons).frame(width: 34, height: 28)
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
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Poké Mart")
        .glassScreen()
    }
}
