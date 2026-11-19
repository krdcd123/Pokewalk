import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let pokemonID: UUID

    @State private var renaming = false
    @State private var newName = ""
    @State private var showItems = false
    @State private var message: String?
    @State private var confirmRelease = false
    @Environment(\.overMap) private var overMap

    private var mon: OwnedPokemon? { store.state.mon(pokemonID) }

    var body: some View {
        if let mon {
            let tint = Color(mon.species.primaryType)
            let isBuddy = mon.id == store.state.buddyID
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 130, height: 130)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(mon.name).font(.rounded(28, .black))
                            Text(mon.gender.symbol).font(.rounded(18, .heavy))
                                .foregroundStyle(mon.gender == .female ? Color(hex: 0xD6457A) : Color(hex: 0x3D7BE0))
                            Text("Lv \(mon.level)").font(.rounded(18, .heavy)).foregroundStyle(Theme.inkSoft)
                        }
                        Text("\(mon.species.dexNumber) \(mon.species.name)\(mon.isShiny ? " ✨" : "")")
                            .font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                        HStack { ForEach(mon.species.types, id: \.self) { TypeChip(type: $0) } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(mon.level < 100 ? "Exp to Lv \(mon.level + 1)" : "Max level").font(.rounded(13, .heavy))
                            Spacer()
                            Text(mon.expToNext.formatted()).font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                        ExpBar(progress: mon.levelProgress, tint: tint)
                        Text(evolutionText(mon)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .cardStyle().padding(.horizontal)

                    VStack(spacing: 0) {
                        row("OT", mon.otName)
                        row("ID No.", mon.otIDString)
                        row("Met", "\(mon.metDate.formatted(date: .abbreviated, time: .omitted)) at Lv \(mon.metLevel)")
                        row("Caught in", mon.ball.name)
                        row("Nature", mon.nature)
                        row("Characteristic", mon.characteristic)
                        row("Friendship", friendshipText(mon.friendship))
                        row("Steps walked", mon.stepsWalked.formatted())
                        row("Location", store.state.locationText(of: mon.id), last: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard(20)
                    .padding(.horizontal)

                    if !mon.heldItems.isEmpty {
                        HeldItemsCard(mon: mon) {
                            let taken = store.takeHeldItems(mon.id)
                            store.toast = "Took \(taken.count == 1 ? Dex.itemName(taken[0]) : "\(taken.count) Exp. Candies") from \(mon.name)."
                        }
                        .padding(.horizontal)
                    }

                    MetCard(mon: mon).padding(.horizontal)

                    VStack(spacing: 10) {
                        if let into = GameRules.pendingEvolution(for: mon, ignoringDecline: true) {
                            actionButton("Evolve into \(Dex.species(into).name)", "sparkles", filled: true) {
                                store.evolutionCandidate = .init(pokemonID: mon.id, into: into)
                            }
                        }
                        if !isBuddy {
                            actionButton("Walk with \(mon.name)", "figure.walk", filled: true) {
                                Task { await store.setBuddy(mon.id) }
                            }
                        } else {
                            Label("Your walking buddy", systemImage: "figure.walk.circle.fill")
                                .font(.rounded(15, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                        HStack(spacing: 10) {
                            actionButton("Rename", "pencil") { newName = mon.nickname ?? ""; renaming = true }
                            actionButton("Use item", "bag") { showItems = true }
                        }
                        if !isBuddy {
                            Button("Release", role: .destructive) { confirmRelease = true }
                                .font(.rounded(15, .heavy)).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 30)
                }
            }
            .navigationTitle(mon.name)
            .glassScreen(transparent: true)
            .onAppear { CryPlayer.shared.play(mon.speciesID) }
            .background {
                ZStack {
                    if !overMap { AppBackground() }
                    // Fades in from clear at the top, so there's no hard edge under the panel's handle.
                    LinearGradient(stops: [.init(color: tint.opacity(0), location: 0),
                                           .init(color: tint.opacity(0.42), location: 0.16),
                                           .init(color: tint.opacity(0.24), location: 0.38),
                                           .init(color: tint.opacity(0.07), location: 0.6),
                                           .init(color: .clear, location: 0.85)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Nickname", isPresented: $renaming) {
                TextField(mon.species.name, text: $newName)
                Button("Save") { store.rename(mon.id, to: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
            .confirmationDialog("Release \(mon.name)? This can't be undone.", isPresented: $confirmRelease, titleVisibility: .visible) {
                Button("Release", role: .destructive) { store.release(mon.id); dismiss() }
            }
            .sheet(isPresented: $showItems) {
                ItemPicker { item in
                    showItems = false
                    switch store.use(item, on: mon.id) {
                    case .noEffect: message = "It won't have any effect."
                    case .leveled(let l): message = "\(mon.name) is now Lv \(l)!"
                    case .evolves: break
                    }
                }
                .presentationDetents([.medium, .large])
            }
        } else {
            ContentUnavailableView("Pokémon not found", systemImage: "questionmark")
        }
    }

    private func row(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(k).font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 12)
                Text(v).font(.rounded(14, .heavy)).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
            if !last { Divider() }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.rounded(15, .heavy))
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(.white)
                .contentShape(Capsule())
                .glassCapsule(tint: filled ? Theme.teal : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func evolutionText(_ mon: OwnedPokemon) -> String {
        let evos = mon.species.evolutions
        guard !evos.isEmpty else { return "Fully evolved · \(mon.stepsWalked.formatted()) steps walked together" }
        return "Evolves: " + evos.map(\.summary).joined(separator: "; ")
    }

    private func friendshipText(_ f: Int) -> String {
        switch f {
        case 220...: return "Best friends (\(f))"
        case 150..<220: return "Very friendly (\(f))"
        case 70..<150: return "Friendly (\(f))"
        default: return "Getting to know you (\(f))"
        }
    }
}

struct ItemPicker: View {
    @EnvironmentObject private var store: GameStore
    let pick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                let keys = store.state.bag.keys.sorted { Dex.itemName($0) < Dex.itemName($1) }
                if keys.isEmpty {
                    ContentUnavailableView("Bag is empty", systemImage: "bag",
                                           description: Text("You find an item every \(store.state.settings.itemSteps.formatted()) steps."))
                }
                ForEach(keys, id: \.self) { key in
                    Button { pick(key) } label: {
                        HStack(spacing: 12) {
                            ItemSprite(key: key).frame(width: 30, height: 30)
                            Text(Dex.itemName(key)).font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("×\(store.state.bag[key] ?? 0)").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .glassRow()
                }
            }
            .navigationTitle("Use an item")
            .glassScreen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


/// Exp. Candies a Pokémon picked up on walks; "Take" moves them into the Bag.
private struct HeldItemsCard: View {
    let mon: OwnedPokemon
    var take: () -> Void

    var body: some View {
        let counts = Dictionary(grouping: mon.heldItems, by: { $0 }).mapValues(\.count)
        let order = ExpCandy.all.map(\.key).filter { counts[$0] != nil } + counts.keys.filter { ExpCandy.exp($0) == nil }.sorted()
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Holding").font(.rounded(15, .heavy))
                Spacer()
                Text("\(mon.heldItems.count)/\(ExpCandy.carryLimit)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(order, id: \.self) { key in
                HStack(spacing: 10) {
                    ItemSprite(key: key).frame(width: 26, height: 26)
                    Text(Dex.itemName(key)).font(.rounded(15, .heavy))
                    Spacer()
                    Text("×\(counts[key] ?? 0)").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                }
            }
            Button(action: take) {
                Label("Take items", systemImage: "arrow.down.to.line")
                    .font(.rounded(15, .heavy))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .glassCapsule(tint: Theme.teal, interactive: true)
            }
            .buttonStyle(.plain)
            if mon.heldItems.count >= ExpCandy.carryLimit {
                Text("\(mon.name)'s hands are full — take its candies so it can pick up more.")
                    .font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .glassCard(20)
    }
}
