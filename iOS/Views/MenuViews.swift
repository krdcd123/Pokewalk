import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main menu

struct MainMenuView: View {
    @EnvironmentObject private var store: GameStore

    enum Dest: Hashable {
        case pc, dex, bag, journal, trainer, settings, summary(UUID)
    }

    private struct Item: Identifiable { let dest: Dest; let title: String; let symbol: String; var id: String { title } }
    private let items: [Item] = [
        .init(dest: .pc, title: "Pokémon", symbol: "square.grid.3x3.fill"),
        .init(dest: .dex, title: "Pokédex", symbol: "book.closed.fill"),
        .init(dest: .bag, title: "Bag", symbol: "bag.fill"),
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
            .glassScreen()
            .navigationDestination(for: Dest.self) { d in
                switch d {
                case .pc: PCView()
                case .dex: PokedexView()
                case .bag: BagView()
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
                    Label(String(format: "%.1f km", mon.metersWalked / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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
    @EnvironmentObject private var store: GameStore

    var body: some View {
        List {
            Section("Balls") {
                ForEach(BallKind.allCases) { k in
                    HStack(spacing: 12) {
                        ItemSprite(key: k.itemKey).frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            Text(k.name).font(.rounded(16, .heavy))
                            Text("Catch bonus ×\(k.bonus.formatted())").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
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
                    HStack(spacing: 12) {
                        ItemSprite(key: key).frame(width: 30, height: 30)
                        Text(Dex.itemName(key)).font(.rounded(16, .heavy))
                        Spacer()
                        Text("×\(store.state.bag[key] ?? 0)").font(.rounded(16, .heavy))
                    }
                    .glassRow()
                }
            } header: { Text("Items") } footer: {
                Text("Balls: 1 every \(store.state.settings.ballSteps) steps (every 10th is a Great Ball, every 50th an Ultra Ball). Items: 1 every \(store.state.settings.itemSteps.formatted()) steps. Use items from a Pokémon's summary.")
            }
        }
        .navigationTitle("Bag")
        .glassScreen()
    }
}

// MARK: - Trainer card (Hoenn style)

struct TrainerCardView: View {
    @EnvironmentObject private var store: GameStore
    @State private var totalKm: Double = 0

    // Card palette
    private let stripeA = Color(hex: 0xE8789C), stripeB = Color(hex: 0xF098B4)
    private let cardBody = Color(hex: 0xF8F4C8), cardStripe = Color(hex: 0xF0ECB0)
    private let band = Color(hex: 0xE8D050), frame = Color(hex: 0x707880)
    private let textMain = Color(hex: 0x606060), textShadow = Color(hex: 0xD8D8C0)
    private let labelBlue = Color(hex: 0x58A8F8)

    private var stars: Int {
        let s = store.state
        return [s.dexCaught.count >= 100, s.dexCaught.count >= Dex.count, s.lifetimeSteps >= 1_000_000,
                s.pokemon.contains(where: \.isShiny)].filter { $0 }.count
    }

    var body: some View {
        let t = store.state.trainer
        ZStack {
            // Pink stripes behind the card, like the GBA screen
            VStack(spacing: 0) {
                ForEach(0..<120, id: \.self) { i in (i % 2 == 0 ? stripeA : stripeB).frame(height: 8) }
            }
            .ignoresSafeArea()

            VStack(spacing: 18) {
                card(t)
                Text("Tap outside the card or swipe down to close").font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .task {
            let tracks = TrackStore.shared
            let tracked = tracks.daysWithTracks.reduce(0) { $0 + tracks.meters(on: $1) } / 1000
            let buddies = store.state.pokemon.reduce(0) { $0 + $1.metersWalked } / 1000
            totalKm = max(tracked, buddies)
        }
    }

    private func pixel(_ text: String, size: CGFloat = 17) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .foregroundStyle(textMain)
            .shadow(color: textShadow, radius: 0, x: 1.5, y: 1.5)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Rectangle().fill(band).frame(width: 5, height: 14)
                pixel(label)
                Spacer(minLength: 6)
                pixel(value)
            }
            Rectangle().fill(textMain.opacity(0.55)).frame(height: 1.5)
        }
    }

    private func card(_ t: Trainer) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRAINER CARD")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x203048))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(labelBlue, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0x305080), lineWidth: 2))
                Spacer()
                pixel("IDNo.\(t.idString)", size: 18)
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 9) {
                    row("NAME:", t.name.uppercased())
                    HStack(spacing: 3) {
                        Spacer()
                        ForEach(0..<stars, id: \.self) { _ in
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xF0B020))
                        }
                    }
                    .frame(height: 12)
                    row("POKéDEX", "\(store.state.dexCaught.count)")
                    row("STEPS", store.state.lifetimeSteps.formatted())
                    row("DISTANCE", String(format: "%.1fkm", totalKm))
                    row("STARTED", t.startedOn.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                }
                ZStack {
                    Circle().fill(band.opacity(0.75)).frame(width: 104, height: 104)
                    Circle().stroke(.white.opacity(0.7), lineWidth: 6).frame(width: 64, height: 64)
                    TrainerSprite(style: t.style, pose: .card).frame(width: 112, height: 128)
                }
                .frame(width: 112)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PARTY").font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white).shadow(color: Color(hex: 0xB89830), radius: 0, x: 1, y: 1)
                HStack(spacing: 4) {
                    ForEach(0..<GameState.maxParty, id: \.self) { i in
                        let mon = i < store.state.party.count ? store.state.party[i] : nil
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF8F0A8))
                            RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xB8A040), lineWidth: 1.5)
                            if let mon { AnimatedSprite(speciesID: mon.speciesID, kind: .icons).padding(2) }
                        }
                        .frame(height: 36)
                    }
                }
            }
            .padding(10)
            .background(band, in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            ZStack {
                cardBody
                VStack(spacing: 6) { ForEach(0..<40, id: \.self) { _ in cardStripe.frame(height: 3) } }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(frame, lineWidth: 5))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.8), lineWidth: 2).padding(4))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
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
    @State private var liveActivity = LiveActivityManager.shared.enabled

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
                Text("Adventure mode records where you walk all day and pauses automatically when you stop. iOS ends Live Activities after 8 hours; PokéWalk starts a new one each time you open it.")
            }

            Section {
                Picker("Buddy Exp per step", selection: binding(\.expPerStep)) {
                    Text("0.2").tag(0.2); Text("0.25").tag(0.25); Text("0.3").tag(0.3)
                    Text("0.5").tag(0.5); Text("1 (Pokéwalker)").tag(1.0)
                }
                .glassRow()
                Picker("Party Exp share", selection: binding(\.partyShare)) {
                    Text("Off").tag(0.0); Text("10%").tag(0.1); Text("20%").tag(0.2); Text("50%").tag(0.5)
                }
                .glassRow()
                Stepper("Encounter every ~\(store.state.settings.encounterSteps) steps",
                        value: binding(\.encounterSteps), in: 100...2_000, step: 50).glassRow()
                Stepper("Ball every \(store.state.settings.ballSteps) steps", value: binding(\.ballSteps), in: 25...500, step: 25).glassRow()
                Stepper("Item every \(store.state.settings.itemSteps.formatted()) steps", value: binding(\.itemSteps), in: 250...5_000, step: 250).glassRow()
                Picker("Shiny chance", selection: binding(\.shinyOdds)) {
                    Text("1 in 4096").tag(4096); Text("1 in 1000").tag(1000); Text("1 in 512").tag(512); Text("1 in 128").tag(128)
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
                Button("Clear downloaded sprites") { SpriteStore.shared.clearDownloads() }.glassRow()
            } header: { Text("Sprites") } footer: {
                Text("Name Pokémon sprites by Pokédex number (25.gif) or name (pikachu.gif). Trainer sprites: red-walk.gif (walking), red-head.gif (map button), red-card.png (trainer card) — also leaf, gold, kris, brendan, may. Missing ones are downloaded.")
            }

            Section {
                Button("Start a new game", role: .destructive) { confirmReset = true }.glassRow()
            }
        }
        .navigationTitle("Settings")
        .glassScreen()
        .onAppear { name = store.state.trainer.name }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
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
