import SwiftUI
import UniformTypeIdentifiers

struct MainMenuView: View {
    @EnvironmentObject private var store: GameStore

    enum Dest: String, Hashable, CaseIterable {
        case pc = "Pokémon", dex = "Pokédex", bag = "Bag", journal = "Journal", trainer = "Trainer", settings = "Settings"
        var symbol: String {
            switch self {
            case .pc: return "square.grid.3x3.fill"
            case .dex: return "book.closed.fill"
            case .bag: return "bag.fill"
            case .journal: return "map.fill"
            case .trainer: return "person.text.rectangle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(Dest.allCases, id: \.self) { d in
                        NavigationLink(value: d) {
                            VStack(spacing: 10) {
                                Image(systemName: d.symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.tealDark)
                                Text(d.rawValue).font(.rounded(17, .black)).foregroundStyle(Theme.ink)
                            }
                            .frame(maxWidth: .infinity).frame(height: 120)
                            .background(.white, in: RoundedRectangle(cornerRadius: 22))
                            .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 2)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.ground)
            .navigationTitle("Menu")
            .navigationDestination(for: Dest.self) { d in
                switch d {
                case .pc: PCView()
                case .dex: PokedexView()
                case .bag: BagView()
                case .journal: JournalView()
                case .trainer: TrainerCardView()
                case .settings: SettingsView()
                }
            }
        }
    }
}

// MARK: - Pokédex

struct PokedexView: View {
    @EnvironmentObject private var store: GameStore
    @State private var filter = 0      // 0 all, 1 caught, 2 seen-not-caught
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
                                    AnimatedSprite(speciesID: sp.id, kind: .icons).frame(height: 34)
                                        .opacity(caught ? 1 : 0.45)
                                } else {
                                    Image(systemName: "questionmark").font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Theme.inkSoft.opacity(0.5)).frame(height: 34)
                                }
                                Text(String(format: "%03d", sp.id)).font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                                Text(seen ? sp.name : "???").font(.rounded(11, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Pokédex")
        .sheet(item: $selected) { sp in
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
                let owned = store.state.pokemon.filter { $0.speciesID == sp.id }
                if let first = owned.min(by: { $0.metDate < $1.metDate }) {
                    MetCard(mon: first)
                }
            }
            .padding()
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
                }
            }
            Section {
                let keys = store.state.bag.keys.sorted { Dex.itemName($0) < Dex.itemName($1) }
                if keys.isEmpty { Text("Nothing yet — keep walking!").foregroundStyle(Theme.inkSoft) }
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 12) {
                        ItemSprite(key: key).frame(width: 30, height: 30)
                        Text(Dex.itemName(key)).font(.rounded(16, .heavy))
                        Spacer()
                        Text("×\(store.state.bag[key] ?? 0)").font(.rounded(16, .heavy))
                    }
                }
            } header: { Text("Items") } footer: {
                Text("Balls: 1 every \(store.state.settings.ballSteps) steps (every 10th is a Great Ball, every 50th an Ultra Ball). Items: 1 every \(store.state.settings.itemSteps.formatted()) steps. Use items from a Pokémon's summary.")
            }
        }
        .navigationTitle("Bag")
    }
}

// MARK: - Trainer card

struct TrainerCardView: View {
    @EnvironmentObject private var store: GameStore
    @State private var totalKm: Double = 0

    var body: some View {
        let t = store.state.trainer
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRAINER CARD").font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.8))
                            Text(t.name).font(.rounded(30, .black)).foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ID No.").font(.rounded(12, .heavy)).foregroundStyle(.white.opacity(0.8))
                            Text(t.idString).font(.rounded(24, .black)).foregroundStyle(.white).monospacedDigit()
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(store.state.party) { mon in
                            AnimatedSprite(speciesID: mon.speciesID, kind: .icons).frame(width: 44, height: 34)
                                .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Text("Adventure started \(t.startedOn.formatted(date: .long, time: .omitted))")
                        .font(.rounded(13, .heavy)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(20)
                .background(LinearGradient(colors: [Theme.teal, Theme.tealDark], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 0) {
                    line("Pokédex", "\(store.state.dexCaught.count) caught · \(store.state.dexSeen.count) seen")
                    line("Pokémon owned", "\(store.state.pokemon.count)")
                    line("Shiny Pokémon", "\(store.state.pokemon.filter(\.isShiny).count)")
                    line("Lifetime steps", store.state.lifetimeSteps.formatted())
                    line("Distance tracked", String(format: "%.1f km", totalKm))
                    line("Balls in bag", "\(store.state.totalBalls)")
                }
                .padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Trainer")
        .task {
            let tracks = TrackStore.shared
            totalKm = tracks.daysWithTracks.reduce(0) { $0 + tracks.meters(on: $1) } / 1000
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            HStack { Text(k).foregroundStyle(Theme.inkSoft); Spacer(); Text(v).font(.rounded(15, .heavy)) }
                .font(.rounded(14)).padding(.vertical, 12)
            Divider()
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
    @State private var liveActivity = LiveActivityManager.shared.enabled

    var body: some View {
        Form {
            Section("Trainer") {
                TextField("Trainer name", text: $name).onSubmit { store.setTrainerName(name) }
                LabeledContent("ID No.", value: store.state.trainer.idString)
            }

            Section {
                Picker("Location tracking", selection: binding(\.trackingMode)) {
                    ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Live Activity (Lock Screen & Watch Smart Stack)", isOn: $liveActivity)
                    .onChange(of: liveActivity) { _, on in
                        LiveActivityManager.shared.enabled = on
                        if on { LiveActivityManager.shared.startIfNeeded(with: store) }
                    }
                Toggle("Encounter notifications", isOn: binding(\.notifyEncounters))
            } header: { Text("Walking") } footer: {
                Text("Adventure mode records where you walk all day and pauses automatically when you stop. Encounters pop up live while tracking runs; otherwise they're added the next time steps sync.")
            }

            Section("Game balance") {
                Stepper("Encounter every ~\(store.state.settings.encounterSteps) steps",
                        value: binding(\.encounterSteps), in: 100...2_000, step: 50)
                Stepper("Ball every \(store.state.settings.ballSteps) steps", value: binding(\.ballSteps), in: 25...500, step: 25)
                Stepper("Item every \(store.state.settings.itemSteps.formatted()) steps", value: binding(\.itemSteps), in: 250...5_000, step: 250)
                Picker("Exp per step", selection: binding(\.expMultiplier)) {
                    Text("1× (Pokéwalker)").tag(1); Text("2×").tag(2); Text("5×").tag(5); Text("10×").tag(10)
                }
                Picker("Shiny chance", selection: binding(\.shinyOdds)) {
                    Text("1 in 4096").tag(4096); Text("1 in 1000").tag(1000); Text("1 in 512").tag(512); Text("1 in 128").tag(128)
                }
            }

            Section {
                let pc = PhoneConnectivity.shared
                LabeledContent("Watch paired", value: pc.isWatchPaired ? "Yes" : "No")
                LabeledContent("PokéWalk on Watch", value: pc.isWatchAppInstalled ? "Installed" : "Not installed")
                LabeledContent("Complication on a face", value: pc.isComplicationOnFace ? "Yes" : "No")
            } header: { Text("Apple Watch") } footer: {
                Text("The Watch app comes inside this app, like Spotify's. If it hasn't appeared, open the Watch app on your iPhone › General › turn on Automatic App Install, or find PokéWalk under Available Apps and tap Install.")
            }

            Section {
                ForEach(SpriteStore.Kind.allCases, id: \.self) { kind in
                    Button("Import \(title(kind)) folder…") { importKind = kind; importing = true }
                }
                Button("Re-send party icons to Watch") {
                    PhoneConnectivity.shared.resetSentSprites(); store.pushOutward()
                }
                Button("Clear downloaded sprites") { SpriteStore.shared.clearDownloads() }
            } header: { Text("Sprites") } footer: {
                Text("Pick a folder of your sprites in Files (iCloud Drive, On My iPhone…). Name them by Pokédex number (25.gif / 025.gif) or name (pikachu.gif). You can also copy them straight into Files › On My iPhone › PokéWalk › Sprites. Missing ones are downloaded from PokeAPI.")
            }

            Section {
                Button("Start a new game", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Settings")
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
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: kp] }, set: { v in store.updateSettings { $0[keyPath: kp] = v } })
    }
}
